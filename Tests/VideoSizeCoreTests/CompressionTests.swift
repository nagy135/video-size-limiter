import XCTest
@testable import VideoSizeCore

final class CompressionTests: XCTestCase {
    func testTargetParsing() throws {
        XCTAssertEqual(try Compressor.targetBytes(megabytes: " 25 "), 25_000_000)
        XCTAssertEqual(try Compressor.targetBytes(megabytes: "1,5"), 1_500_000)
        for input in ["", "nan", "inf", "0", "-2", "1000001", "0.00001"] {
            XCTAssertThrowsError(try Compressor.targetBytes(megabytes: input), input)
        }
    }

    func testRealCompressionAndPreservation() throws {
        let tools = try Tools.discover()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("video-size-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("sample with spaces.mp4")
        try execute(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=24:duration=4", "-f", "lavfi", "-i", "sine=frequency=440:duration=4", "-c:v", "libx264", "-crf", "12", "-c:a", "aac", "-b:a", "96k", "-metadata", "title=Keep this title", "-shortest", source.path])
        let engine = Compressor(tools: tools)
        let directory = root.appendingPathComponent("output")
        let result = try engine.compress(source: source, targetBytes: 220_000, directory: directory)
        let original = try engine.probe(source)
        let output = try engine.probe(result)
        XCTAssertEqual(output.video?.codec_name, "h264")
        XCTAssertEqual(output.video?.width, 640)
        XCTAssertEqual(output.video?.height, 360)
        XCTAssertEqual(output.video?.avg_frame_rate, original.video?.avg_frame_rate)
        XCTAssertEqual(output.streams.last?.codec_name, "aac")
        XCTAssertLessThan(try fileSize(result), 220_000)
        XCTAssertGreaterThan(try fileSize(result), 180_000)
        // Audio packets remain bit-for-bit identical, not merely the same codec.
        let audio1 = root.appendingPathComponent("source.aac")
        let audio2 = root.appendingPathComponent("output.aac")
        for (video, audio) in [(source, audio1), (result, audio2)] {
            try execute(tools.ffmpeg, ["-v", "error", "-i", video.path, "-map", "0:a", "-c", "copy", audio.path])
        }
        XCTAssertEqual(try Data(contentsOf: audio1), try Data(contentsOf: audio2))
        let copy = try engine.compress(source: result, targetBytes: 1_000_000, directory: directory)
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: result))
        let another = try engine.compress(source: result, targetBytes: 1_000_000, directory: directory)
        XCTAssertNotEqual(copy, another)
        XCTAssertThrowsError(try engine.compress(source: source, targetBytes: 1000, directory: directory))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".video-size-") })
    }

    func testHEVCAndSilentVideo() throws {
        let tools = try Tools.discover()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("silent.mp4")
        try execute(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24:duration=2", "-c:v", "libx265", "-x265-params", "log-level=error:pools=2", "-crf", "10", source.path])
        let engine = Compressor(tools: tools)
        let output = try engine.compress(source: source, targetBytes: 45_000, directory: root)
        XCTAssertLessThan(try fileSize(output), 45_000)
        XCTAssertEqual(try engine.probe(output).video?.codec_name, "hevc")
    }

    func testCancellationAndInvalidMedia() throws {
        let token = Cancellation(); token.cancel()
        let engine = try Compressor(tools: Tools.discover())
        XCTAssertThrowsError(try engine.probe(URL(fileURLWithPath: "/nonexistent"), cancellation: token)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertThrowsError(try engine.probe(URL(fileURLWithPath: "/nonexistent")))
    }

    func testCancellationDuringEncoding() throws {
        let tools = try Tools.discover()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("cancel.mp4")
        try execute(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=30:duration=5", "-c:v", "libx264", "-crf", "10", source.path])
        let token = Cancellation()
        let directory = root.appendingPathComponent("results")
        XCTAssertThrowsError(try Compressor(tools: tools).compress(source: source, targetBytes: 150_000, directory: directory, cancellation: token) { progress in
            if progress.fraction > 0 { token.cancel() }
        }) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! NSNumber).int64Value
    }
    private func execute(_ executable: URL, _ args: [String]) throws {
        let process = Process(); process.executableURL = executable; process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
