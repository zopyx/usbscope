import Foundation
import XCTest
import UsbScopeCore
@testable import UsbScopeUI

/// `SnapshotLoading` turns the JSON `usbscope json` / `usbscope baseline save`
/// writes back into a `Snapshot`, which is what the "Compare with…" tab diffs
/// against the live machine. It is verified by round-tripping the shared
/// fixtures through `Serialize`.
final class SnapshotLoadingTests: XCTestCase {
    private func snapshot() -> Snapshot { Fixtures.snapshot() }

    private func load(_ dict: [String: Any]) throws -> Snapshot {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return try SnapshotLoading.snapshot(from: data)
    }

    func testRoundTripPreservesTheIdentityAndCounts() throws {
        let original = snapshot()
        let data = try XCTUnwrap(Serialize.json(original).data(using: .utf8))
        let loaded = try SnapshotLoading.snapshot(from: data)

        XCTAssertEqual(loaded.host, original.host)
        XCTAssertEqual(loaded.osVersion, original.osVersion)
        XCTAssertEqual(loaded.model, original.model)
        XCTAssertEqual(loaded.chip, original.chip)
        XCTAssertEqual(loaded.seenAt, original.seenAt)
        XCTAssertEqual(loaded.ports.count, original.ports.count)
        XCTAssertEqual(loaded.devices.count, original.devices.count)
        XCTAssertEqual(loaded.ports.map(\.name), original.ports.map(\.name))
        XCTAssertEqual(loaded.warnings, original.warnings)
    }

    func testARoundTrippedSnapshotDiffsCleanAgainstItself() throws {
        let original = snapshot()
        let data = try XCTUnwrap(Serialize.json(original).data(using: .utf8))
        let loaded = try SnapshotLoading.snapshot(from: data)
        let changes = diffSnapshots(previous: loaded, current: original)
        XCTAssertTrue(changes.isEmpty, "round trip changed the diff: \(changes.summary)")
        // The port signature (connected, mode, cable, liquid, device count) survives too.
        XCTAssertTrue(changes.changedPorts.isEmpty)
    }

    func testADeviceMissingFromTheBaselineAppears() throws {
        let original = snapshot()
        var dict = Serialize.dict(original)
        // Strip every device from both carriers, so the one fixture device is new.
        dict["ports"] = (dict["ports"] as? [[String: Any]] ?? []).map { port -> [String: Any] in
            var copy = port
            copy["devices"] = [[String: Any]]()
            return copy
        }
        dict["buses"] = (dict["buses"] as? [[String: Any]] ?? []).map { bus -> [String: Any] in
            var copy = bus
            copy["devices"] = [[String: Any]]()
            return copy
        }
        let baseline = try load(dict)
        XCTAssertEqual(baseline.devices.count, 0)

        let changes = diffSnapshots(previous: baseline, current: original)
        XCTAssertEqual(changes.added.count, original.devices.count)
        XCTAssertTrue(changes.removed.isEmpty)
        XCTAssertEqual(DiffPresentation.rows(changes).filter { $0.kind == .appeared }.count, original.devices.count)
    }

    func testADeviceOnlyInTheBaselineDisappears() throws {
        let original = snapshot()
        let changes = diffSnapshots(previous: original, current: try load(Serialize.dict(original)))
        XCTAssertTrue(changes.isEmpty)

        // Baseline = original; live = a snapshot with no devices.
        var dict = Serialize.dict(original)
        dict["ports"] = (dict["ports"] as? [[String: Any]] ?? []).map { port -> [String: Any] in
            var copy = port
            copy["devices"] = [[String: Any]]()
            return copy
        }
        dict["buses"] = (dict["buses"] as? [[String: Any]] ?? []).map { bus -> [String: Any] in
            var copy = bus
            copy["devices"] = [[String: Any]]()
            return copy
        }
        let live = try load(dict)
        let removed = diffSnapshots(previous: original, current: live)
        XCTAssertEqual(removed.removed.count, original.devices.count)
        XCTAssertTrue(removed.added.isEmpty)
    }

    func testAnArrayInsteadOfAnObjectIsRejected() {
        XCTAssertThrowsError(try SnapshotLoading.snapshot(from: Data("[]".utf8))) { error in
            XCTAssertEqual(error as? SnapshotLoadingError, .notAnObject)
        }
    }

    func testAnEmptyObjectLoadsAsAnEmptySnapshot() throws {
        let loaded = try load([:])
        XCTAssertEqual(loaded.host, "")
        XCTAssertEqual(loaded.ports.count, 0)
        XCTAssertEqual(loaded.seenAt, Date(timeIntervalSince1970: 0))
    }
}
