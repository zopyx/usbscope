import Foundation
import UsbScopeCore

/// How far a snapshot collection has got.
///
/// This is the value `SnapshotBuilder.collect(progress:)` reports: one callback per
/// stage, in `SnapshotStage` order, so a UI can show *which* source is being read
/// instead of an opaque spinner. One `collect` takes about 1.3 s on a MacBook Pro
/// (`system_profiler` dominates), which is long enough that "what is it doing?" is
/// a fair question.
public struct SnapshotProgress: Equatable, Sendable {
    public let stage: SnapshotStage
    /// 1-based, so the last stage reports `index == total`.
    public let index: Int
    public let total: Int

    public init(stage: SnapshotStage, index: Int, total: Int) {
        self.stage = stage
        self.index = index
        self.total = total
    }

    /// `0…1` for a determinate progress bar; `0` when the total is unknown.
    public var fraction: Double {
        total > 0 ? Double(index) / Double(total) : 0
    }
}

/// The wording of the loading line.
///
/// The stage name is the technical identifier from `SnapshotStage` (`Ports`,
/// `Buses`, …): it names the OS source being read, so it is not translated. The
/// verb is passed in, because the app takes its strings from the typed table.
public enum ProgressPresentation {
    /// `Ports`, `Charging`, … — `SnapshotStage`'s own name.
    public static func stageName(_ stage: SnapshotStage) -> String {
        stage.rawValue.capitalized
    }

    /// `collecting Charging · 5/6`, or `collecting …` before the first callback.
    public static func text(_ progress: SnapshotProgress?, verb: String) -> String {
        guard let progress else { return "\(verb) …" }
        return "\(verb) \(stageName(progress.stage)) · \(progress.index)/\(progress.total)"
    }
}
