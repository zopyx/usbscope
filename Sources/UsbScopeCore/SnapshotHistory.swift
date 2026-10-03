import Foundation

/// One timeline sample of the machine's power draw.
///
/// `watts` is the live power flowing into the machine (`Charging.systemPowerInMw`,
/// the value the Power view shows as "… W in") — a measurement, not the port
/// contract. A snapshot without charging telemetry still contributes a point
/// with `watts`/`stateOfCharge`/`charging` set to `nil`, so the timeline keeps
/// the gap instead of silently dropping the time.
public struct PowerPoint: Sendable, Equatable {
    public var at: Date
    public var watts: Double?
    public var stateOfCharge: Int?
    public var charging: Bool?

    public init(at: Date, watts: Double? = nil, stateOfCharge: Int? = nil, charging: Bool? = nil) {
        self.at = at
        self.watts = watts
        self.stateOfCharge = stateOfCharge
        self.charging = charging
    }

    /// Whether this point carries a measured power value.
    public var hasPower: Bool { watts != nil }
}

/// One recorded snapshot with its timestamp and the delta to its predecessor.
public struct HistoryEntry: Sendable {
    public var at: Date
    public var snapshot: Snapshot
    /// What changed against the previous entry; `nil` for the first entry (the
    /// first read of a session is not a plug event).
    public var changes: ChangeSet?

    public init(at: Date, snapshot: Snapshot, changes: ChangeSet? = nil) {
        self.at = at
        self.snapshot = snapshot
        self.changes = changes
    }
}

/// A bounded in-memory ring of snapshots/deltas, plus the power timeline.
///
/// This is the data a timeline view draws from: every recorded snapshot carries
/// its timestamp and the delta to the one before it, and `powerTimeline()`
/// projects the charging telemetry of the ring onto a watt-over-time series.
/// The ring drops the oldest entry once `capacity` is reached, so a long-running
/// app cannot grow without bound. Access is serialised — the watcher records
/// from its own queue while the UI reads.
///
/// The Python twin (`usbscope.history.PowerHistory`) keeps the same timeline
/// semantics but samples `Charging` values directly, because Python does not
/// run the IOKit watcher.
public final class SnapshotHistory: @unchecked Sendable {
    /// How many snapshots the ring keeps (at a 5 s cadence, 240 is 20 min).
    public static let defaultCapacity = 240

    public let capacity: Int

    private let lock = NSLock()
    private var storage: [HistoryEntry] = []

    public init(capacity: Int = SnapshotHistory.defaultCapacity) {
        self.capacity = max(capacity, 1)
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    public var isEmpty: Bool { count == 0 }

    /// The entries, oldest first.
    public var entries: [HistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// The most recent entry, if any.
    public var latest: HistoryEntry? {
        lock.lock()
        defer { lock.unlock() }
        return storage.last
    }

    /// Record a snapshot; returns the entry that was appended.
    ///
    /// Pass `changes` to store a known delta verbatim. With `nil` the delta is
    /// computed against the previous entry (`diffSnapshots`); the first entry
    /// keeps `changes == nil`, because the first read is not a plug event. The
    /// timestamp is `snapshot.seenAt`.
    @discardableResult
    public func record(_ snapshot: Snapshot, changes: ChangeSet? = nil) -> HistoryEntry {
        lock.lock()
        defer { lock.unlock() }
        let delta = changes ?? storage.last.map { diffSnapshots(previous: $0.snapshot, current: snapshot) }
        let entry = HistoryEntry(at: snapshot.seenAt, snapshot: snapshot, changes: delta)
        storage.append(entry)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
        return entry
    }

    /// The charging watts over time — one point per recorded snapshot.
    public func powerTimeline() -> [PowerPoint] {
        entries.map { entry in
            let charging = entry.snapshot.charging
            return PowerPoint(
                at: entry.at,
                watts: charging?.systemPowerInMw.map { Double($0) / 1000 },
                stateOfCharge: charging?.stateOfCharge,
                charging: charging?.charging
            )
        }
    }

    /// Only the points that carry a measured power value (for a chart's y axis).
    public func measuredPowerTimeline() -> [PowerPoint] {
        powerTimeline().filter(\.hasPower)
    }

    public func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}
