import Foundation

private final class BoundedOutput: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private(set) var data = Data()
    private(set) var truncated = false

    init(limit: Int) { self.limit = max(0, limit) }

    func drain(_ handle: FileHandle) {
        defer { try? handle.close() }
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            lock.lock()
            let remaining = max(0, limit - data.count)
            if remaining > 0 { data.append(chunk.prefix(remaining)) }
            if chunk.count > remaining { truncated = true }
            lock.unlock()
        }
    }
}

/// Outcome of a command; a failure is data, never a thrown error.
public struct CommandResult: Sendable {
    public let argv: [String]
    public let returncode: Int32
    public let stdout: Data
    public let error: String?
    public let stderr: Data
    public let timedOut: Bool
    public let truncated: Bool

    public init(argv: [String], returncode: Int32, stdout: Data = Data(), error: String? = nil,
                stderr: Data = Data(), timedOut: Bool = false, truncated: Bool = false) {
        self.argv = argv
        self.returncode = returncode
        self.stdout = stdout
        self.error = error
        self.stderr = stderr
        self.timedOut = timedOut
        self.truncated = truncated
    }

    /// True when the command ran and exited with status 0.
    public var ok: Bool { error == nil && returncode == 0 }

    /// Convert a process failure into the stable error model used by UI and
    /// diagnostics. Callers may still retain stderr separately for debugging.
    public func sourceError(source: String, operation: String,
                            recoveryAction: String? = nil) -> SourceError? {
        guard !ok else { return nil }
        let code: AppErrorCode = timedOut ? .commandTimedOut :
            (error == "cancelled" ? .cancelled : .commandFailed)
        let technical = error ?? "exit \(returncode)"
        let user = timedOut ? "\(source) did not respond before the timeout." :
            "\(source) could not complete \(operation)."
        return SourceError(code: code, source: source, operation: operation,
                           userMessage: user, technicalMessage: technical,
                           recoveryAction: recoveryAction)
    }
}

/// A command runner, injectable so tests can serve captured payloads.
public typealias Runner = @Sendable ([String]) -> CommandResult

/// Small, dependency free command runner shared by the adapters.
public enum Shell {
    public struct Limits: Sendable, Equatable {
        public var timeout: TimeInterval
        public var maximumStdoutBytes: Int
        public var maximumStderrBytes: Int

        public init(timeout: TimeInterval = 30, maximumStdoutBytes: Int = 8 * 1024 * 1024,
                    maximumStderrBytes: Int = 256 * 1024) {
            self.timeout = timeout
            self.maximumStdoutBytes = maximumStdoutBytes
            self.maximumStderrBytes = maximumStderrBytes
        }
    }

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
        run(argv, limits: Limits())
    }

    /// Run a command with bounded output and a cancellation-safe timeout.
    /// stderr is drained concurrently, preventing a noisy child from blocking
    /// stdout. The legacy `run(_:)` API uses conservative production defaults.
    public static func run(_ argv: [String], limits: Limits,
                           cancellation: (@Sendable () -> Bool)? = nil) -> CommandResult {
        guard let binary = argv.first else {
            return CommandResult(argv: argv, returncode: 127, error: "empty command")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = Array(argv.dropFirst())
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return CommandResult(argv: argv, returncode: 127, error: "\(binary) not found")
        }

        // One reader per pipe is essential: Process can block if either pipe's
        // kernel buffer fills while the parent waits on the other one.
        let group = DispatchGroup()
        let out = BoundedOutput(limit: limits.maximumStdoutBytes)
        let err = BoundedOutput(limit: limits.maximumStderrBytes)
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            out.drain(stdout.fileHandleForReading)
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            err.drain(stderr.fileHandleForReading)
            group.leave()
        }

        let deadline = Date().addingTimeInterval(max(0.01, limits.timeout))
        var timedOut = false
        while process.isRunning {
            if cancellation?() == true || Date() >= deadline {
                timedOut = true
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        process.waitUntilExit()
        group.wait()
        let diagnostic = String(data: err.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let error: String? = timedOut ? "\(binary) timed out after \(limits.timeout)s" :
            (process.terminationStatus == 0 ? nil : (diagnostic ?? "exit \(process.terminationStatus)"))
        return CommandResult(argv: argv, returncode: process.terminationStatus, stdout: out.data,
                             error: error, stderr: err.data, timedOut: timedOut,
                             truncated: out.truncated || err.truncated)
    }
}
