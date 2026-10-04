import Foundation
import XCTest
@testable import UsbScopeCore
@testable import UsbScopeUI

/// The grouping helpers: pure functions, so they are verified without a window
/// server. The fixtures are the shared captures in `Fixtures`.
final class GroupingTests: XCTestCase {
    private func snapshot() -> Snapshot { Fixtures.snapshot() }

    // MARK: - Which fields a view offers

    func testGroupingFieldsPerView() {
        XCTAssertEqual(GroupField.fields(for: .ports), [.none, .bus, .deviceClass, .speed])
        XCTAssertEqual(GroupField.fields(for: .devices), [.none, .bus, .deviceClass, .speed])
        XCTAssertTrue(GroupField.fields(for: .cables).isEmpty)
        XCTAssertTrue(GroupField.fields(for: .thunderbolt).isEmpty)
        XCTAssertTrue(GroupField.fields(for: .power).isEmpty)
    }

    // MARK: - Bucket keys

    func testSpeedGroupLabelBuckets() {
        XCTAssertEqual(speedGroupLabel(0), "no link")
        XCTAssertEqual(speedGroupLabel(2), UsbMode.fullSpeed.label)
        XCTAssertEqual(speedGroupLabel(4), UsbMode.superSpeed.label)
        XCTAssertEqual(speedGroupLabel(8), UsbMode.usb4_80.label)
    }

    // MARK: - none keeps every row in one unnamed group

    func testNoGroupingKeepsAllRowsInOneGroup() {
        let rows = portRows(snapshot())
        let groups = groups(for: rows, by: .none)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "")
        XCTAssertEqual(groups[0].rows.map(\.id), rows.map(\.id))
    }

    // MARK: - Ports

    func testPortsGroupedByBusUseTheConnectorFamily() {
        let rows = portRows(snapshot())
        let grouped = groups(for: rows, by: .bus)
        // One bucket per distinct connector kind, and every row survives.
        XCTAssertEqual(Set(grouped.map(\.title)), Set(rows.map(\.kind.text)))
        XCTAssertEqual(grouped.flatMap(\.rows).count, rows.count)
        // Within a bucket the incoming order is preserved.
        for group in grouped {
            let original = rows.filter { $0.kind.text == group.title }.map(\.id)
            XCTAssertEqual(group.rows.map(\.id), original)
        }
    }

    func testPortsGroupedByClassUseTheAttachedDeviceClass() {
        let rows = portRows(snapshot())
        let grouped = groups(for: rows, by: .deviceClass)
        XCTAssertTrue(grouped.contains { $0.title == "no device" })
        let withDevice = grouped.first { $0.title != "no device" }
        XCTAssertEqual(withDevice?.rows.count, 1)
        XCTAssertEqual(withDevice?.rows.first?.id, "port:USB-C@3")
    }

    func testGroupOrderIsFastestSpeedFirst() {
        let slow = makePort("USB-C@1", kind: "USB-C", mbps: 480)   // High-Speed, rank 3
        let fast = makePort("USB-C@2", kind: "USB-C", mbps: 5_000) // SuperSpeed, rank 4
        let snapshot = Snapshot(host: "mac", osVersion: "27.0.1", seenAt: Date(), ports: [slow, fast])
        let grouped = groups(for: portRows(snapshot), by: .speed)
        XCTAssertEqual(grouped.map(\.title), [UsbMode.superSpeed.label, UsbMode.highSpeed.label])
        XCTAssertEqual(grouped[0].rows.map(\.id), ["port:USB-C@2"])
    }

    // MARK: - Devices

    func testDevicesGroupedByBus() {
        let rows = deviceRows(snapshot())
        let grouped = groups(for: rows, by: .bus)
        XCTAssertEqual(grouped.map(\.title), ["USB 3.1 Bus"])
        XCTAssertEqual(grouped[0].rows.count, rows.count)
    }

    func testDevicesGroupedByClassAndSpeed() {
        let rows = deviceRows(snapshot())
        XCTAssertEqual(groups(for: rows, by: .deviceClass).map(\.title), ["per-interface"])
        XCTAssertEqual(groups(for: rows, by: .speed).map(\.title), [UsbMode.fullSpeed.label])
    }

    // MARK: - Helpers

    private func makePort(_ name: String, kind: String, mbps: Double) -> UsbPort {
        var port = UsbPort(description: "Port-\(name)", kind: kind)
        port.connected = true
        port.number = Int(name.split(separator: "@").last ?? "1") ?? 1
        port.transports = [Transport(kind: "usb3", active: true, speedMbps: mbps)]
        return port
    }
}
