import Foundation

public struct CompressionError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Shared by the UI and the worker. Cancelling also stops the current child process.
public final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?
    public init() {}
    public func cancel() {
        lock.lock()
        cancelled = true
        if let process, process.isRunning { process.terminate() }
        lock.unlock()
    }
    public func check() throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
    }
    fileprivate func launch(_ child: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        try child.run()
        process = child
    }
    fileprivate func clear() { lock.lock(); process = nil; lock.unlock() }
}

public struct Tools: Sendable {
    public let ffmpeg: URL
    public let ffprobe: URL
    public init(ffmpeg: URL, ffprobe: URL) { self.ffmpeg = ffmpeg; self.ffprobe = ffprobe }
    public static func discover() throws -> Tools {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("bin")
        let directories = [bundled?.path, "/opt/homebrew/bin", "/usr/local/bin", "/run/current-system/sw/bin", "/nix/var/nix/profiles/default/bin"]
            .compactMap { $0 } + (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        func find(_ name: String) throws -> URL {
            for directory in directories where !directory.isEmpty {
                let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: url.path) { return url }
            }
            throw CompressionError("FFmpeg is missing. Install ffmpeg and ffprobe (brew install ffmpeg), then try again.")
        }
        return try Tools(ffmpeg: find("ffmpeg"), ffprobe: find("ffprobe"))
    }
}

public struct MediaInfo: Decodable, Sendable {
    public struct Stream: Decodable, Sendable {
        public let index: Int
        public let codec_name: String?
        public let codec_type: String?
        public let pix_fmt: String?
        public let bit_rate: String?
        public let duration: String?
        public let width: Int?
        public let height: Int?
        public let avg_frame_rate: String?
        public let disposition: [String: Int]?
        public struct SideData: Decodable, Sendable { public let rotation: Double? }
        public let side_data_list: [SideData]?
        public let tags: [String: String]?
        public var hasRotation: Bool {
            side_data_list?.contains { ($0.rotation ?? 0).truncatingRemainder(dividingBy: 360) != 0 } == true
                || (Double(tags?["rotate"] ?? "") ?? 0).truncatingRemainder(dividingBy: 360) != 0
        }
    }
    public struct Format: Decodable, Sendable {
        public let duration: String?
        public let tags: [String: String]?
    }
    public let streams: [Stream]
    public let format: Format
    public var video: Stream? { streams.first { $0.codec_type == "video" && $0.disposition?["attached_pic"] != 1 } }
    public var duration: Double { Double(format.duration ?? "") ?? Double(video?.duration ?? "") ?? 0 }
}

public struct CompressionUpdate: Sendable {
    public let fraction: Double
    public let message: String
}

public final class Compressor: @unchecked Sendable {
    public let tools: Tools
    public init(tools: Tools) { self.tools = tools }

    @discardableResult
    private func run(_ executable: URL, _ args: [String], cancellation: Cancellation, workingDirectory: URL? = nil,
                     started: (() -> Void)? = nil, line: ((String) -> Void)? = nil) throws -> Data {
        try cancellation.check()
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        // A file prevents a full stderr pipe from deadlocking FFmpeg.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: log)
        process.standardError = errorHandle
        defer { try? errorHandle.close(); try? FileManager.default.removeItem(at: log); cancellation.clear() }
        try cancellation.launch(process)
        started?()
        var output = Data()
        var pending = ""
        while true {
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            if let line {
                pending += String(decoding: data, as: UTF8.self)
                while let end = pending.firstIndex(of: "\n") {
                    line(String(pending[..<end])); pending.removeSubrange(...end)
                }
            } else { output.append(data) }
        }
        process.waitUntilExit()
        try cancellation.check()
        guard process.terminationStatus == 0 else {
            let details = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            throw CompressionError("FFmpeg could not process this video.\n" + details.suffix(2400))
        }
        return output
    }

    public func probe(_ url: URL, cancellation: Cancellation = Cancellation()) throws -> MediaInfo {
        let data = try run(tools.ffprobe, ["-v", "error", "-show_streams", "-show_format", "-of", "json", url.path], cancellation: cancellation)
        let info = try JSONDecoder().decode(MediaInfo.self, from: data)
        guard info.video != nil, info.duration.isFinite, info.duration > 0 else {
            throw CompressionError("Choose a video file with a valid duration.")
        }
        return info
    }

    public static func targetBytes(megabytes: String) throws -> Int64 {
        let normalized = megabytes.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value > 0, value <= 1_000_000 else {
            throw CompressionError("Enter a size greater than 0 MB (up to 1,000,000 MB).")
        }
        let bytes = Int64((value * 1_000_000).rounded(.down))
        guard bytes >= 1000 else { throw CompressionError("Choose a target of at least 0.001 MB.") }
        return bytes
    }

    public func compress(source: URL, targetBytes: Int64, directory: URL,
                         cancellation: Cancellation = Cancellation(),
                         commandStarted: @escaping (CommandInvocation) -> Void = { _ in },
                         update: @escaping (CompressionUpdate) -> Void = { _ in }) throws -> URL {
        guard targetBytes >= 1000 else { throw CompressionError("The size limit is too small.") }
        try cancellation.check()
        update(.init(fraction: 0, message: "Reading video…"))
        let info = try probe(source, cancellation: cancellation)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        // Work stays hidden until size and stream verification succeeds.
        let work = directory.appendingPathComponent(".video-size-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: work) }
        let ext = source.pathExtension.isEmpty ? "mkv" : source.pathExtension
        let staged = work.appendingPathComponent("output").appendingPathExtension(ext)
        let originalSize = try size(source)
        if originalSize < targetBytes {
            update(.init(fraction: 0.9, message: "Already under the limit. Copying original…"))
            try fm.copyItem(at: source, to: staged)
        } else {
            let video = info.video!
            guard info.streams.filter({ $0.codec_type == "video" && $0.disposition?["attached_pic"] != 1 }).count == 1 else {
                throw CompressionError("This file has multiple video tracks. Choose a single-video-track file to preserve all tracks safely.")
            }
            let encoders = ["h264": "libx264", "hevc": "libx265", "vp9": "libvpx-vp9", "vp8": "libvpx", "av1": "libsvtav1", "mpeg4": "mpeg4", "mpeg2video": "mpeg2video"]
            guard let codec = video.codec_name, let encoder = encoders[codec] else {
                throw CompressionError("The \(video.codec_name ?? "unknown") codec does not support size-targeted compression in this app. The codec will not be changed.")
            }
            let retainedRate = info.streams.filter { $0.index != video.index }.reduce(0.0) {
                $0 + (Double($1.bit_rate ?? "") ?? ($1.codec_type == "audio" ? 192_000 : 0))
            }
            var bitrate = (Double(targetBytes) * 0.97 * 8 / info.duration) - retainedRate
            guard bitrate >= 1000 else { throw CompressionError("This target is too small while retaining the original audio and duration. Choose a larger size.") }
            let videoOrdinal = info.streams.filter { $0.codec_type == "video" }.firstIndex { $0.index == video.index } ?? 0
            let specifier = info.streams.filter { $0.codec_type == "video" }.count == 1 ? "v" : "v:\(videoOrdinal)"
            var succeeded = false
            for attempt in 0..<7 {
                try cancellation.check()
                try? fm.removeItem(at: staged)
                // Let FFmpeg choose its default preset and retain input format/metadata.
                // Only request options needed for preserving tracks/timing and controlling size.
                var args: [String] = []
                if video.hasRotation { args += ["-noautorotate"] }
                args += ["-i", source.path]
                if info.streams.count > 1 { args += ["-map", "0", "-c", "copy"] }
                args += ["-c:\(specifier)", encoder, "-b:\(specifier)", String(Int(bitrate)),
                         "-fps_mode:\(specifier)", "passthrough"]
                let twoPass = codec == "h264" || codec == "vp9" || codec == "vp8" || codec == "mpeg4"
                let passes = twoPass ? [1, 2] : [0]
                for pass in passes {
                    let description = attempt == 0 ? "Compressing" : "Refining size (attempt \(attempt + 1))"
                    let phase = pass == 0 ? "" : " · pass \(pass) of 2"
                    update(.init(fraction: 0, message: description + phase))
                    var passArgs = args
                    if twoPass { passArgs += ["-pass:\(specifier)", String(pass)] }
                    passArgs += ["-progress", "pipe:1"]
                    if pass == 1 { passArgs += ["-f", "null", "/dev/null"] }
                    else { passArgs += [staged.path] }
                    try run(tools.ffmpeg, passArgs, cancellation: cancellation, workingDirectory: work, started: {
                        commandStarted(CommandInvocation(executable: self.tools.ffmpeg.path, arguments: passArgs))
                    }) { line in
                        if line.hasPrefix("out_time_us="), let time = Double(line.dropFirst(12)) {
                            let fraction = min(1, max(0, time / 1_000_000 / info.duration))
                            let overall = twoPass ? (Double(pass - 1) + fraction) / 2 : fraction
                            update(.init(fraction: overall * 0.98, message: description + phase))
                        }
                    }
                }
                let actual = try size(staged)
                if actual < targetBytes { succeeded = true; break }
                // Use measured overshoot rather than trusting the encoder's requested rate.
                let overshootRate = Double(actual - targetBytes) * 8 / info.duration
                bitrate = min(bitrate * 0.90, bitrate - overshootRate * 1.15)
                guard bitrate >= 1000 else { break }
            }
            guard succeeded else { throw CompressionError("Cannot reach this size while preserving the codec and audio. Choose a larger target.") }
            update(.init(fraction: 0.99, message: "Verifying video…"))
            let result = try probe(staged, cancellation: cancellation)
            guard result.streams.count == info.streams.count,
                  zip(info.streams, result.streams).allSatisfy({ $0.codec_name == $1.codec_name && $0.codec_type == $1.codec_type }),
                  result.video?.width == video.width, result.video?.height == video.height,
                  result.video?.pix_fmt == video.pix_fmt,
                  abs(result.duration - info.duration) < max(0.5, info.duration * 0.005) else {
                throw CompressionError("The output could not preserve the source streams and image format. No result was saved.")
            }
        }
        try cancellation.check()
        guard try size(staged) < targetBytes else { throw CompressionError("Output exceeds the requested limit. No result was saved.") }
        let base = source.deletingPathExtension().lastPathComponent + "-compressed"
        var destination = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var suffix = 2
        // moveItem refuses to overwrite, including if a competing process creates the name.
        while fm.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(base)-\(suffix)").appendingPathExtension(ext); suffix += 1
        }
        try fm.moveItem(at: staged, to: destination)
        update(.init(fraction: 1, message: "Ready"))
        return destination
    }

    private func size(_ url: URL) throws -> Int64 {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
}
