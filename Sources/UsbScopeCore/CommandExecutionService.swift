import Foundation

/// Application-facing subprocess boundary.
///
/// UI code requests a command by argv and receives the bounded, structured
/// result from the injectable `CommandExecutor`; it never calls `Shell` or
/// owns a `Process` directly.
public struct CommandExecutionService: Sendable {
    private let executor: any CommandExecutor

    public init(executor: any CommandExecutor = ShellCommandExecutor()) {
        self.executor = executor
    }

    public func run(_ argv: [String]) async -> CommandResult {
        await Task.detached(priority: .userInitiated) {
            executor.run(argv)
        }.value
    }
}
