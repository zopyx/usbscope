import Foundation
import XCTest

@testable import UsbScopeCore

/// `usbscope baseline` — the twin of `tests/test_baseline.py`.
final class BaselineTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - helpers

    private func device(_ name: String = "Gadget", locationID: Int? = 1, port: String? = "USB-C@3") -> UsbDevice {
        UsbDevice(
            name: name, vendorID: 0x1050, productID: 0x0407, locationID: locationID, port: port
        )
    }

    private func port(_ name: String = "USB-C@3", connected: Bool = true) -> UsbPort {
        var value = UsbPort(description: "Port-\(name)", kind: "USB-C")
        value.number = 3
        value.connected = connected
        value.cable = Cable(attached: connected)
        if connected { value.devices = [device(port: name)] }
        return value
    }

    private func snapshot(ports: [UsbPort] = [], devices: [UsbDevice] = []) -> Snapshot {
        let buses = devices.isEmpty ? [] : [Bus(name: "USB 3.1 Bus", devices: devices)]
        return Snapshot(host: "mac", osVersion: "27.0.1", seenAt: when, ports: ports, buses: buses)
    }

    private func document(ports: [UsbPort] = [], devices: [UsbDevice] = []) -> [String: Any] {
        Serialize.dict(snapshot(ports: ports, devices: devices))
    }

    private func temporaryPath(_ name: String) -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent(name).path
    }

    // MARK: - save / load

    func testSaveAndLoadRoundTrip() throws {
        let path = temporaryPath("usbscope-baseline-roundtrip.json")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try Baseline.save(snapshot(ports: [port()]), to: path)
        let payload = try Baseline.load(path)
        XCTAssertEqual(payload["schema_version"] as? Int, 1)
        let ports = try XCTUnwrap(payload["ports"] as? [[String: Any]])
        XCTAssertEqual(ports.first?["name"] as? String, "USB-C@3")
    }

    func testSaveWritesTheSnapshotDocument() throws {
        let path = temporaryPath("usbscope-baseline-doc.json")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let value = snapshot(ports: [port()])
        try Baseline.save(value, to: path)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(decoded["schema_version"] as? Int, Serialize.dict(value)["schema_version"] as? Int)
    }

    func testLoadMissingFileThrows() {
        XCTAssertThrowsError(try Baseline.load(temporaryPath("usbscope-does-not-exist.json")))
    }

    func testLoadInvalidJSONThrows() throws {
        let path = temporaryPath("usbscope-baseline-bad.json")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try "{not json".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Baseline.load(path))
    }

    func testLoadNonSnapshotThrows() throws {
        let path = temporaryPath("usbscope-baseline-other.json")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try #"{"hello":"world"}"#.write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Baseline.load(path))
    }

    // MARK: - comparison

    func testIdenticalDocumentsReportNoDifference() {
        let doc = document(ports: [port()])
        let diff = Baseline.compare(previous: doc, current: doc)
        XCTAssertTrue(diff.identical)
        XCTAssertTrue(Baseline.render(diff, path: "base.json").hasSuffix("identical to baseline"))
    }

    func testSeenAtAloneIsIgnored() {
        var moved = document(ports: [port()])
        moved["seen_at"] = "2026-10-03T09:00:00"
        XCTAssertTrue(Baseline.compare(previous: document(ports: [port()]), current: moved).identical)
    }

    func testAppearedDisappearedAndChangedPorts() {
        let previous = document(ports: [port("USB-C@1"), port("USB-C@3")])
        let current = document(ports: [port("USB-C@3", connected: false), port("USB-C@4")])
        let diff = Baseline.compare(previous: previous, current: current)
        XCTAssertEqual(diff.appearedPorts, ["USB-C@4"])
        XCTAssertEqual(diff.disappearedPorts, ["USB-C@1"])
        XCTAssertEqual(diff.changedPorts, ["USB-C@3"])
        XCTAssertFalse(diff.identical)
    }

    func testDeviceAppearanceIsReported() {
        let previous = document(devices: [])
        let current = document(devices: [device("Stick", locationID: 7)])
        let diff = Baseline.compare(previous: previous, current: current)
        XCTAssertEqual(diff.appearedDevices, ["loc:7"])
        XCTAssertFalse(diff.identical)
    }

    func testDeviceIdentityFallsBackToNameWithoutLocation() {
        let current = document(devices: [device("Nameless", locationID: nil)])
        let diff = Baseline.compare(previous: document(), current: current)
        XCTAssertEqual(diff.appearedDevices, ["name:Nameless"])
    }

    func testRenderListsEachGroup() {
        let previous = document(ports: [port("USB-C@1")])
        let current = document(ports: [port("USB-C@2")])
        let text = Baseline.render(Baseline.compare(previous: previous, current: current), path: "base.json")
        XCTAssertTrue(text.contains("disappeared ports: USB-C@1"))
        XCTAssertTrue(text.contains("appeared ports: USB-C@2"))
        XCTAssertTrue(text.hasSuffix("differs from baseline"))
    }

    func testDiffJSONIsStable() {
        var diff = BaselineDiff()
        diff.appearedPorts = ["USB-C@4"]
        XCTAssertEqual(diff.dictionary["kind"] as? String, "baseline")
        XCTAssertEqual(diff.dictionary["identical"] as? Bool, false)
        XCTAssertEqual(diff.dictionary["appeared_ports"] as? [String], ["USB-C@4"])
    }
}
