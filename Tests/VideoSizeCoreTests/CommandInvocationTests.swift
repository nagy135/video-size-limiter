import XCTest
@testable import VideoSizeCore

final class CommandInvocationTests: XCTestCase {
    func testRolesDistinguishSwitchesValuesAndOutputPath() {
        let command = CommandInvocation(executable: "/opt/homebrew/bin/ffmpeg", arguments: [
            "-hide_banner", "-y", "-i", "/tmp/a movie.mp4", "-map", "-0:a", "-c:v:0", "libx264", "-nostats", "/tmp/out.mp4"
        ])
        XCTAssertEqual(command.tokens.map(\.role), [.executable, .flag, .flag, .flag, .value, .flag, .value, .flag, .value, .flag, .path])
        XCTAssertEqual(command.tokens[6].text, "-0:a")
    }

    func testCopiedShellCommandRoundTripsSpecialCharacters() throws {
        let values = ["a movie.mp4", "Viktor's movie.mp4", "$(printf injected)", "semi;colon", "", "line\nbreak", "video🔥.mp4"]
        let command = CommandInvocation(executable: "printf", arguments: ["%s\\000"] + values)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command.shellCommand]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(data, Data((values.joined(separator: "\0") + "\0").utf8))
    }
}
