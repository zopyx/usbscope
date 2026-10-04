import Foundation

/// Serial owner for manual, timer, and hotplug snapshot requests.
///
/// Requests arriving while a collection is active share that collection instead
/// of spawning concurrent system-tool reads. The strongest reason is retained
/// for diagnostics and every result carries a monotonic generation.
public actor SnapshotCoordinator {
    public enum Reason: String, Sendable, CaseIterable {
        case initial, timer, hotplug, manual

        fileprivate var priority: Int {
            switch self { case .initial: 0; case .timer: 1; case .hotplug: 2; case .manual: 3 }
        }
    }

    public struct Result: Sendable {
        public let generation: UInt64
        public let reason: Reason
        public let snapshot: Snapshot
        public let capturedAt: Date
        public let duration: TimeInterval
        public let stageTimings: [String: TimeInterval]
    }

    public typealias Collector = @Sendable (@escaping @Sendable (SnapshotStage, Int, Int) -> Void) async -> Snapshot

    private let collect: Collector
    private struct Collected: Sendable {
        let snapshot: Snapshot
        let stageTimings: [String: TimeInterval]
    }

    private final class TimingState: @unchecked Sendable {
        var timings: [String: TimeInterval] = [:]
        var lastStage: SnapshotStage?
        var stageStarted: Date

        init(started: Date) { stageStarted = started }
    }

    private var active: Task<Collected, Never>?
    private var activeReason: Reason?
    private var nextGeneration: UInt64 = 0
    private var stopped = false

    public init(collect: @escaping Collector = { progress in
        await Task.detached(priority: .userInitiated) {
            SnapshotBuilder.collect(includeConflictWarnings: true, progress: progress)
        }.value
    }) {
        self.collect = collect
    }

    public func request(_ reason: Reason, collector override: Collector? = nil,
                        progress: @escaping @Sendable (SnapshotStage, Int, Int) -> Void = { _, _, _ in }) async -> Result? {
        guard !stopped else { return nil }
        if let active {
            if activeReason == nil || reason.priority > activeReason!.priority { activeReason = reason }
            let started = Date()
            let collected = await active.value
            return makeResult(collected, started: started, reason: activeReason ?? reason)
        }
        let chosen = reason
        activeReason = chosen
        let started = Date()
        let collector = override ?? collect
        let task = Task { () -> Collected in
            let timing = TimingState(started: started)
            let snapshot = await collector { stage, index, total in
                let now = Date()
                if let lastStage = timing.lastStage {
                    timing.timings[lastStage.rawValue] = now.timeIntervalSince(timing.stageStarted)
                }
                timing.lastStage = stage
                timing.stageStarted = now
                progress(stage, index, total)
            }
            if let lastStage = timing.lastStage {
                timing.timings[lastStage.rawValue] = Date().timeIntervalSince(timing.stageStarted)
            }
            return Collected(snapshot: snapshot, stageTimings: timing.timings)
        }
        active = task
        let collected = await task.value
        active = nil
        let finalReason = activeReason ?? chosen
        activeReason = nil
        return makeResult(collected, started: started, reason: finalReason)
    }

    public func stop() {
        stopped = true
        active?.cancel()
        active = nil
        activeReason = nil
    }

    public func resume() { stopped = false }

    private func makeResult(_ collected: Collected, started: Date, reason: Reason) -> Result {
        nextGeneration &+= 1
        return Result(generation: nextGeneration, reason: reason, snapshot: collected.snapshot,
                      capturedAt: Date(), duration: Date().timeIntervalSince(started),
                      stageTimings: collected.stageTimings)
    }
}
