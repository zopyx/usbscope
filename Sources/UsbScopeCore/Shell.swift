import Foundation

/// Outcome of a command; a failure is data, never a thrown error.
public struct CommandResult: Sendable {
    public let argv: [String]
    public let returncode: Int32
    public let stdout: Data
    public let error: String?

    public init(argv: [String], returncode: Int32, stdout: Data = Data(), error: String? = nil) {
        self.argv = argv
        self.returncode = returncode
        self.stdout = stdout
        self.error = error
    }

    /// True when the command ran and exited with status 0.
    public var ok: Bool { error == nil && returncode == 0 }
}

/// A command runner, injectable so tests can serve captured payloads.
public typealias Runner = @Sendable ([String]) -> CommandResult

/// Small, dependency free command runner shared by the adapters.
public enum Shell {
    /// Absolute path of a system tool, falling back to the bare name.
    ///
    /// macOS keeps its CLI tools in `/usr/sbin` and `/usr/bin`. Calling them by
    /// name would fail with a minimal `PATH` (a bundled app launched from
    /// Finder, a launchd job), so the absolute path wins when it exists.
    public static func systemBinary(_ name: String, _ candidates: String...) -> String {
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return name
    }

    /// Run `argv` and capture stdout without ever throwing.
    ///
    /// The child process inherits no window; a missing binary and a non-zero
    /// exit are reported in the result instead of raising.
    public static func run(_ argv: [String]) -> CommandResult {
        guard let binary = argv.first else {
            return CommandResult(argv: argv, returncode: 127, error: "empty command")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = Array(argv.dropFirst())
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()  // diagnostics are not part of the data
        do {
            try process.run()
        } catch {
            return CommandResult(argv: argv, returncode: 127, error: "\(binary) not found")
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(argv: argv, returncode: process.terminationStatus, stdout: data)
    }
}
