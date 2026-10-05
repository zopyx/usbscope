import Foundation
import XCTest
@testable import UsbScopeCore
@testable import UsbScopeUI

/// Phase 4: the append-only event log, the snapshot ring buffer with its power
/// timeline and the hotplug watcher. The watcher is exercised with the polling
/// path and with real IOKit notifications; no test needs a device to be plugged.
final class HistoryTests: XCTestCase {
    // MARK: - Builders

    private func device(_ name: String, location: Int, serial: String? = nil) -> UsbDevice {
        UsbDevice(
            name: name, vendor: "Acme", vendorID: 0x1234, productID: 0x0001,
            serial: serial, locationID: location
        )
    }

    private func snapshot(
        _ devices: [UsbDevice], at seconds: TimeInterval = 0, charging: Charging? = nil
    ) -> Snapshot {
        Snapshot(
            host: "mac", osVersion: "27.0.1", seenAt: Date(timeIntervalSince1970: seconds),
            buses: [Bus(name: "USB 3.1 Bus", devices: devices)], charging: charging
        )
    }

    private func charging(systemPowerInMw: Int?, stateOfCharge: Int?, charging: Bool?) -> Charging {
        var value = Charging()
        value.systemPowerInMw = systemPowerInMw
        value.stateOfCharge = stateOfCharge
        value.charging = charging
        return value
    }

    // MARK: - Ring buffer

    func testRingKeepsOnlyTheCapacityMostRecentSnapshots() {
        let history = SnapshotHistory(capacity: 2)
        let first = device("First", location: 0x01)
        let second = device("Second", location: 0x02)
        let third = device("Third", location: 0x03)

        history.record(snapshot([first], at: 1))
        history.record(snapshot([second], at: 2))
        history.record(snapshot([third], at: 3))

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.entries.map(\.snapshot.seenAt.timeIntervalSince1970), [2, 3])
        XCTAssertEqual(history.entries.first?.snapshot.devices.map(\.name), ["Second"])
        XCTAssertEqual(history.latest?.snapshot.devices.map(\.name), ["Third"])
        XCTAssertEqual(history.capacity, 2)
    }

    func testCapacityIsAtLeastOne() {
        XCTAssertEqual(SnapshotHistory(capacity: 0).capacity, 1)
        XCTAssertEqual(SnapshotHistory(capacity: -5).capacity, 1)
    }

    func testEntriesAreOldestFirst() {
        let history = SnapshotHistory(capacity: 8)
        for step in 1...3 {
            history.record(snapshot([device("D", location: 1)], at: TimeInterval(step)))
        }
        XCTAssertEqual(history.entries.map(\.at.timeIntervalSince1970), [1, 2, 3])
        XCTAssertFalse(history.isEmpty)
    }

    func testFirstEntryHasNoDeltaAndLaterEntriesDo() {
        let first = device("First", location: 0x01)
        let second = device("Second", location: 0x02)
        let history = SnapshotHistory(capacity: 8)

        let entry = history.record(snapshot([first], at: 1))
        XCTAssertNil(entry.changes)  // the first read is not a plug event

        let grown = history.record(snapshot([first, second], at: 2))
        XCTAssertEqual(grown.changes?.added.map(\.name), ["Second"])
        XCTAssertEqual(grown.changes?.removed.count, 0)
        XCTAssertEqual(grown.at.timeIntervalSince1970, 2)
    }

    func testExplicitChangesAreStoredVerbatim() {
        let history = SnapshotHistory(capacity: 8)
        history.record(snapshot([device("A", location: 1)], at: 1))
        var explicit = ChangeSet()
        explicit.changedPorts = ["port:USB-C@3"]
        let entry = history.record(snapshot([device("A", location: 1)], at: 2), changes: explicit)
        XCTAssertEqual(entry.changes?.changedPorts, ["port:USB-C@3"])
    }

    func testClearEmptiesTheRing() {
        let history = SnapshotHistory(capacity: 4)
        history.record(snapshot([device("A", location: 1)], at: 1))
        history.clear()
        XCTAssertEqual(history.count, 0)
        XCTAssertNil(history.latest)
    }

    // MARK: - Power timeline

    func testPowerTimelineMapsTheLiveSystemPower() {
        let history = SnapshotHistory(capacity: 8)
        history.record(snapshot([], at: 10, charging: charging(systemPowerInMw: 27575, stateOfCharge: 100, charging: true)))
        history.record(snapshot([], at: 20, charging: charging(systemPowerInMw: 16084, stateOfCharge: 90, charging: false)))

        let timeline = history.powerTimeline()
        XCTAssertEqual(timeline.count, 2)
        XCTAssertEqual(timeline[0].at.timeIntervalSince1970, 10)
        XCTAssertEqual(timeline[0].watts, 27.575)
        XCTAssertEqual(timeline[0].stateOfCharge, 100)
        XCTAssertEqual(timeline[0].charging, true)
        XCTAssertEqual(timeline[1].watts, 16.084)
    }

    func testPowerTimelineKeepsSnapshotsWithoutChargingAsGaps() {
        let history = SnapshotHistory(capacity: 8)
        history.record(snapshot([], at: 1, charging: nil))
        history.record(snapshot([], at: 2, charging: charging(systemPowerInMw: 5000, stateOfCharge: 50, charging: nil)))

        let timeline = history.powerTimeline()
        XCTAssertEqual(timeline.count, 2)
        XCTAssertNil(timeline[0].watts)
        XCTAssertFalse(timeline[0].hasPower)
        XCTAssertEqual(timeline[1].watts, 5.0)
        XCTAssertTrue(timeline[1].hasPower)
    }

    func testMeasuredTimelineDropsTheGaps() {
        let history = SnapshotHistory(capacity: 8)
        history.record(snapshot([], at: 1, charging: nil))
        history.record(snapshot([], at: 2, charging: charging(systemPowerInMw: 5000, stateOfCharge: nil, charging: nil)))
        XCTAssertEqual(history.measuredPowerTimeline().map(\.watts), [5.0])
    }

    // MARK: - Event derivation

    func testEventFromADeviceUsesTheSharedDeviceKey() {
        let device = device("Portable SSD", location: 0x01100000, serial: "ABC123")
        let event = UsbEvent(kind: .attached, seenAt: Date(timeIntervalSince1970: 0), device: device)
        XCTAssertEqual(event.key, deviceKey(device))
        XCTAssertEqual(event.key, "device:serial:ABC123")
        XCTAssertEqual(event.name, "Portable SSD")
        XCTAssertEqual(event.vendorID, 0x1234)
        XCTAssertEqual(event.locationID, 0x01100000)
        XCTAssertEqual(event.serial, "ABC123")
    }

    func testEventsAreDetachedFirstThenAttachedEachSortedByKey() {
        let a = device("Alpha", location: 0x03)
        let b = device("Beta", location: 0x01)
        let gone = device("Gone", location: 0x02)
        var changes = ChangeSet()
        changes.added = [a, b]
        changes.removed = [gone]

        let events = usbEvents(changes, at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(events.map(\.kind), [.detached, .attached, .attached])
        XCTAssertEqual(events.map(\.name), ["Gone", "Beta", "Alpha"])  // sorted by key, not by name
    }

    func testEventsFromTwoSnapshots() {
        let first = device("A", location: 1)
        let second = device("B", location: 2)
        let events = usbEvents(from: snapshot([first], at: 1), to: snapshot([second], at: 2), at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(events.map(\.name).sorted(), ["A", "B"])
        XCTAssertEqual(events.map(\.kind).sorted { $0.rawValue < $1.rawValue }, [.attached, .detached])
    }

    // MARK: - Event log

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("usbscope-events-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func logURL() -> URL { directory.appendingPathComponent("events.jsonl") }

    func testEventLogCreatesItsDirectoryAndRoundTrips() throws {
        let log = try EventLog(url: logURL())
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))

        let device = device("YubiKey", location: 0x01100000, serial: "ABC")
        let attached = UsbEvent(
            kind: .attached, seenAt: Date(timeIntervalSince1970: 1_790_000_000), device: device
        )
        let detached = UsbEvent(
            kind: .detached, seenAt: Date(timeIntervalSince1970: 1_790_000_100), device: device
        )
        try log.append(attached)
        try log.append([detached])

        let events = try log.read()
        XCTAssertEqual(events, [attached, detached])
        XCTAssertEqual(events.first?.key, "device:serial:ABC")
        XCTAssertEqual(events.first?.kind, .attached)
    }

    func testEventLogIsOneJsonObjectPerLineWithAnIsoTimestamp() throws {
        let log = try EventLog(url: logURL())
        let device = device("Stick", location: 2)
        try log.append(UsbEvent(kind: .attached, seenAt: Date(timeIntervalSince1970: 1_790_000_000), device: device))
        try log.append(UsbEvent(kind: .detached, seenAt: Date(timeIntervalSince1970: 1_790_000_001), device: device))

        let raw = try String(contentsOf: logURL(), encoding: .utf8)
        let lines = raw.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(raw.hasSuffix("\n"))
        for line in lines { XCTAssertTrue(line.hasPrefix("{")) }

        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any]
        )
        XCTAssertEqual(payload["kind"] as? String, "attached")
        XCTAssertEqual(payload["key"] as? String, deviceKey(device))
        let seenAt = try XCTUnwrap(payload["seen_at"] as? String)
        XCTAssertTrue(seenAt.hasSuffix("Z"), seenAt)
        XCTAssertNotNil(seenAt.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"#, options: .regularExpression))
    }

    func testEventLogIsAppendOnly() throws {
        let log = try EventLog(url: logURL())
        let device = device("Stick", location: 2)
        try log.append(UsbEvent(kind: .attached, seenAt: Date(timeIntervalSince1970: 1), device: device))
        let sizeAfterFirst = try Data(contentsOf: logURL()).count
        try log.append(UsbEvent(kind: .detached, seenAt: Date(timeIntervalSince1970: 2), device: device))
        let sizeAfterSecond = try Data(contentsOf: logURL()).count

        XCTAssertGreaterThan(sizeAfterSecond, sizeAfterFirst)
        XCTAssertEqual(try log.read().map(\.kind), [.attached, .detached])
    }

    func testEventLogSkipsMalformedLines() throws {
        let log = try EventLog(url: logURL())
        let device = device("Stick", location: 2)
        try log.append(UsbEvent(kind: .attached, seenAt: Date(timeIntervalSince1970: 1), device: device))

        let handle = try FileHandle(forWritingTo: logURL())
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("this is not json\n\n".utf8))
        try handle.close()

        XCTAssertEqual(try log.read().count, 1)
    }

    func testEventLogReadsAMissingFileAsEmpty() throws {
        let log = try EventLog(url: logURL())
        XCTAssertEqual(try log.read().count, 0)
        try log.remove()
        XCTAssertEqual(try log.read().count, 0)
    }

    func testEventLogRotationAdvancesExistingArchives() throws {
        let log = try EventLog(url: logURL(), maximumBytes: 1_024, maximumAge: 0, retainedRotations: 2)
        for index in 0..<40 {
            let event = UsbEvent(
                kind: .attached,
                seenAt: Date(timeIntervalSince1970: TimeInterval(index + 1)),
                key: "device:\(index)",
                name: "Device \(index)",
                vendorID: 0x1050,
                productID: 0x0407,
                locationID: index,
                serial: String(repeating: "S", count: 48)
            )
            try log.append(event)
        }

        let current = try log.read()
        let firstRotation = try EventLog(
            url: directory.appendingPathComponent("events.1.jsonl"),
            maximumBytes: 1_024,
            maximumAge: 0,
            retainedRotations: 2
        ).read()
        let secondRotation = try EventLog(
            url: directory.appendingPathComponent("events.2.jsonl"),
            maximumBytes: 1_024,
            maximumAge: 0,
            retainedRotations: 2
        ).read()

        XCTAssertFalse(current.isEmpty)
        XCTAssertFalse(firstRotation.isEmpty)
        XCTAssertFalse(secondRotation.isEmpty)
        XCTAssertGreaterThan(current.map(\.seenAt).max()!, firstRotation.map(\.seenAt).max()!)
        XCTAssertGreaterThan(firstRotation.map(\.seenAt).max()!, secondRotation.map(\.seenAt).max()!)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("events.3.jsonl").path))
    }

    func testDefaultLogLivesInApplicationSupport() {
        let url = EventLog.defaultURL()
        XCTAssertTrue(
            url.path.hasSuffix("/Library/Application Support/usbscope/events.jsonl"),
            url.path
        )
        XCTAssertEqual(url.lastPathComponent, "events.jsonl")
    }

    // MARK: - Watcher

    /// A thread-safe, repeating sequence of snapshots for the injectable collector.
    private final class SnapshotSource: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Snapshot]
        init(_ items: [Snapshot]) { self.items = items }
        func next() -> Snapshot {
            lock.lock()
            defer { lock.unlock() }
            if items.count > 1 { return items.removeFirst() }
            return items.first!
        }
    }

    private final class EventSink: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [UsbEvent] = []
        var all: [UsbEvent] { lock.lock(); defer { lock.unlock() }; return events }
        func add(_ new: [UsbEvent]) { lock.lock(); events.append(contentsOf: new); lock.unlock() }
    }

    func testPollingWatcherReportsAnAttachmentAndUsesThePollingFallback() {
        let first = device("First", location: 1)
        let second = device("Second", location: 2)
        let base = snapshot([first], at: 1)
        let grown = snapshot([first, second], at: 2)
        // The watcher's baseline read consumes the first element; the first timer
        // tick then sees the grown snapshot and reports the attachment.
        let source = SnapshotSource([base, grown, grown, grown, grown, grown, grown])
        let watcher = UsbHotplugWatcher(
            mode: .polling, pollInterval: 0.02, debounce: 0,
            collect: { source.next() },
            clock: { Date(timeIntervalSince1970: 2) }
        )

        let sink = EventSink()
        let arrived = expectation(description: "attachment reported")
        watcher.start { update in
            sink.add(update.events)
            if update.events.contains(where: { $0.kind == .attached && $0.name == "Second" }) {
                arrived.fulfill()
            }
        }
        XCTAssertFalse(watcher.isEventDriven)
        XCTAssertTrue(watcher.status.contains("polling"), watcher.status)
        wait(for: [arrived], timeout: 3)
        watcher.stop()

        let events = sink.all
        XCTAssertTrue(events.contains { $0.kind == .attached && $0.name == "Second" })
        XCTAssertEqual(events.first { $0.name == "Second" }?.key, deviceKey(second))
    }

    func testIOKitWatcherIsEventDriven() {
        let watcher = UsbHotplugWatcher(mode: .ioKit, collect: { Fixtures.snapshot() })
        watcher.start { _ in }
        XCTAssertTrue(
            watcher.isEventDriven,
            "IOKit notifications on \(UsbHotplugWatcher.deviceClass) unavailable: \(watcher.status)"
        )
        XCTAssertTrue(watcher.status.contains("IOKit"), watcher.status)
        XCTAssertTrue(watcher.isRunning)
        watcher.stop()
        XCTAssertFalse(watcher.isRunning)
        XCTAssertFalse(watcher.isEventDriven)
    }

    func testStoppingWithoutStartingIsANoOp() {
        let watcher = UsbHotplugWatcher(mode: .ioKit, collect: { Fixtures.snapshot() })
        watcher.stop()
        XCTAssertFalse(watcher.isRunning)
    }
}
