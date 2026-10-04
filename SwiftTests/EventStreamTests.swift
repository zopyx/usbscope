import Foundation
import XCTest

@testable import UsbScopeCore

/// `usbscope watch --events` — the twin of `tests/test_events.py`.
final class EventStreamTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_790_000_000)
    private let later = Date(timeIntervalSince1970: 1_790_000_002)

    // MARK: - helpers

    private func device(
        _ name: String = "YubiKey",
        vendorID: Int? = 0x1050,
        productID: Int? = 0x0407,
        serial: String? = nil,
        locationID: Int? = 0x0010_0000,
        port: String? = "USB-C@3"
    ) -> UsbDevice {
        UsbDevice(
            name: name, vendorID: vendorID, productID: productID, serial: serial,
            locationID: locationID, port: port
        )
    }

    private func snapshot(_ devices: [UsbDevice], at date: Date) -> Snapshot {
        let buses = devices.isEmpty ? [] : [Bus(name: "USB 3.1 Bus", devices: devices)]
        return Snapshot(host: "mac", osVersion: "27.0.1", seenAt: date, buses: buses)
    }

    private func parse(_ line: String) throws -> [String: Any] {
        let data = try XCTUnwrap(line.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - diffing

    func testAttachLineCarriesTheDeviceFacts() throws {
        let changes = diffSnapshots(
            previous: snapshot([], at: when), current: snapshot([device(serial: "ABC")], at: later)
        )
        let lines = EventStream.lines(changes, at: later)
        XCTAssertEqual(lines.count, 1)
        let payload = try parse(lines[0])
        XCTAssertEqual(payload["kind"] as? String, "attached")
        XCTAssertEqual(payload["name"] as? String, "YubiKey")
        XCTAssertEqual(payload["vendor_id"] as? Int, 0x1050)
        XCTAssertEqual(payload["product_id"] as? Int, 0x0407)
        XCTAssertEqual(payload["serial"] as? String, "ABC")
        XCTAssertEqual(payload["location_id"] as? Int, 0x0010_0000)
        XCTAssertEqual(payload["port"] as? String, "USB-C@3")
    }

    func testDetachLineIsEmittedForARemovedDevice() throws {
        let changes = diffSnapshots(
            previous: snapshot([device()], at: when), current: snapshot([], at: later)
        )
        let payload = try parse(EventStream.lines(changes, at: later)[0])
        XCTAssertEqual(payload["kind"] as? String, "detached")
        XCTAssertEqual(payload["port"] as? String, "USB-C@3")
    }

    func testDetachesComeBeforeAttachesAndAreSorted() throws {
        let previous = snapshot(
            [device("B", locationID: 2), device("A", locationID: 1)], at: when
        )
        let current = snapshot([device("D", locationID: 4), device("C", locationID: 3)], at: later)
        let lines = EventStream.lines(diffSnapshots(previous: previous, current: current), at: later)
        let pairs = try lines.map { line -> String in
            let payload = try parse(line)
            return "\(payload["kind"] as? String ?? "")/\(payload["name"] as? String ?? "")"
        }
        XCTAssertEqual(pairs, ["detached/A", "detached/B", "attached/C", "attached/D"])
    }

    func testAnUnchangedSnapshotProducesNoLines() {
        let same = snapshot([device()], at: when)
        let changes = diffSnapshots(previous: same, current: snapshot([device()], at: later))
        XCTAssertTrue(EventStream.lines(changes, at: later).isEmpty)
    }

    func testIdentityPrefersLocationOverName() {
        let byLocation = UsbEvent(kind: .attached, seenAt: when, device: device(locationID: 42))
        XCTAssertEqual(EventStream.identity(byLocation), "loc:42")
        let byName = UsbEvent(kind: .attached, seenAt: when, device: device(locationID: nil))
        XCTAssertEqual(EventStream.identity(byName), "name:YubiKey")
    }

    func testLineIsCompactSortedJSON() throws {
        let event = UsbEvent(
            kind: .attached, seenAt: when, key: "k", name: "YubiKey", vendorID: 0x1050,
            productID: 0x0407, locationID: 1_048_576, serial: nil
        )
        let line = EventStream.line(event, port: "USB-C@3")
        XCTAssertFalse(line.contains(" "))
        XCTAssertTrue(line.hasPrefix("{\"kind\":\"attached\""))
        let payload = try parse(line)
        XCTAssertTrue(payload["serial"] is NSNull)
        XCTAssertEqual(payload["port"] as? String, "USB-C@3")
        XCTAssertEqual(payload["location_id"] as? Int, 1_048_576)
    }
}
