import Foundation

/// The exact executable and argument vector passed to Process, suitable for display or copying.
public struct CommandInvocation: Sendable, Equatable {
    public enum Role: Sendable { case executable, flag, value, path }
    public struct Token: Sendable, Equatable {
        public let text: String
        public let role: Role
    }
    public let executable: String
    public let arguments: [String]
    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
    public var tokens: [Token] {
        let switches: Set<String> = ["-hide_banner", "-nostdin", "-y", "-noautorotate", "-nostats"]
        var result = [Token(text: executable, role: .executable)]
        var expectsValue = false
        for argument in arguments {
            if expectsValue {
                result.append(Token(text: argument, role: .value))
                expectsValue = false
            } else if argument.hasPrefix("-") {
                result.append(Token(text: argument, role: .flag))
                expectsValue = !switches.contains(argument)
            } else {
                result.append(Token(text: argument, role: .path))
            }
        }
        return result
    }
    public var shellCommand: String {
        ([executable] + arguments).map(Self.shellQuote).joined(separator: " ")
    }
    public static func shellQuote(_ argument: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:=+,-@%")
        if !argument.isEmpty && argument.unicodeScalars.allSatisfy({ safe.contains($0) }) { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
