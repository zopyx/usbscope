import Foundation
import XCTest
@testable import UsbScopeCore

/// Tests for the USB4/Thunderbolt fabric adapter (routers, ports, tunnels) —
/// the Swift twin of `tests/test_thunderbolt_fabric.py`.
///
/// The parser is pinned against the real `ioreg -r -c IOThunderboltSwitch`
/// capture (three host routers, 6 ports each) and against a synthetic daisy
/// chain, because this machine has no downstream router to capture.
final class ThunderboltFabricTests: XCTestCase {
    private func fabric(_ name: String = "tb_switch.plist") throws -> ThunderboltFabric {
        ThunderboltSwitch.parse(try Fixtures.plistValue(name))
    }

    // MARK: - real capture

    func testRealCaptureHasThreeHostRouters() throws {
        let fabric = try fabric()
        XCTAssertEqual(fabric.routers.count, 3)
        XCTAssertEqual(fabric.routers.compactMap(\.routerID), [0, 1, 2])
        XCTAssertEqual(Set(fabric.routers.compactMap(\.uid)).count, 3)
        XCTAssertEqual(Set(fabric.routers.compactMap(\.depth)), [0])
        XCTAssertEqual(Set(fabric.routers.compactMap(\.vendorName)), ["Apple Inc."])
        XCTAssertEqual(Set(fabric.routers.compactMap(\.vendorID)), [0x5AC])
        XCTAssertEqual(Set(fabric.routers.compactMap(\.thunderboltVersion)), [32])
        XCTAssertEqual(Set(fabric.routers.compactMap(\.maxPortNumber)), [7])
    }

    func testRealCapturePortsAndTunnels() throws {
        let fabric = try fabric()
        XCTAssertEqual(fabric.routers.map(\.ports.count), [6, 6, 6])
        XCTAssertEqual(fabric.routers.map(\.tunnels.count), [4, 4, 4])
        XCTAssertEqual(fabric.ports.count, 18)
        XCTAssertEqual(fabric.tunnels.count, 12)
    }

    func testRealCaptureProtocolTokens() throws {
        let router = try fabric().routers[0]
        XCTAssertEqual(router.ports.map(\.number), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(
            router.ports.map(\.protocolName),
            ["thunderbolt", "thunderbolt", "pcie", "usb", "displayport", "displayport"]
        )
        XCTAssertEqual(router.tunnels.map(\.protocolName), ["pcie", "usb", "displayport", "displayport"])
    }

    func testRealCaptureLinkFactsAreVerbatim() throws {
        let port = try fabric().routers[0].ports[0]
        XCTAssertEqual(port.label, "Thunderbolt Port")
        XCTAssertEqual(port.socketID, "1")
        XCTAssertEqual(port.adapterType, 1)
        XCTAssertEqual(port.currentLinkSpeed, 8)
        XCTAssertEqual(port.targetLinkSpeed, 12)
        XCTAssertEqual(port.supportedLinkSpeed, 12)
        XCTAssertEqual(port.currentLinkWidth, 1)
        XCTAssertEqual(port.targetLinkWidth, 1)
        XCTAssertEqual(port.supportedLinkWidth, 2)
        XCTAssertEqual(port.lane, 1)
        XCTAssertEqual(port.dualLinkPort, 2)
        XCTAssertEqual(port.linkBandwidth, 100)
        XCTAssertEqual(port.maxCredits, 174)
        XCTAssertEqual(port.maxInHopID, 22)
        XCTAssertEqual(port.maxOutHopID, 22)
        XCTAssertEqual(port.restricted, false)
        // macOS publishes the TRM restriction only on the dual-link port 1
        XCTAssertNil(try fabric().routers[0].ports[1].restricted)
    }

    func testRealCaptureTunnelDrivers() throws {
        let tunnels = Dictionary(
            uniqueKeysWithValues: try fabric().routers[0].tunnels.map { ($0.portNumber ?? 0, $0) }
        )
        let pcie = try XCTUnwrap(tunnels[3])
        XCTAssertEqual(pcie.protocolName, "pcie")
        XCTAssertEqual(pcie.label, "PCIe Adapter")
        XCTAssertEqual(pcie.adapterType, 1048833)
        XCTAssertEqual(pcie.driver, "com.apple.driver.AppleThunderboltPCIDownAdapter")
        XCTAssertEqual(pcie.driverClass, "AppleThunderboltPCIDownAdapterType5")
        XCTAssertEqual(pcie.deviceID, "0x00002000&0x0000ff00")
        // the USB adapter publishes no Device ID
        XCTAssertEqual(tunnels[4]?.driver, "com.apple.driver.AppleThunderboltUSBDownAdapter")
        XCTAssertNil(tunnels[4]?.deviceID)
    }

    // MARK: - synthetic daisy chain

    func testSyntheticDaisyChain() throws {
        let fabric = try fabric("tb_switch_synthetic.plist")
        XCTAssertEqual(fabric.routers.map(\.depth), [0, 1])
        XCTAssertEqual(fabric.routers.map(\.routerID), [0, 1])
        let downstream = fabric.routers[1]
        XCTAssertEqual(downstream.routeString, 256)
        XCTAssertEqual(downstream.maxPortNumber, 5)
        XCTAssertEqual(downstream.ports.count, 2)
        XCTAssertEqual(downstream.tunnels.map(\.protocolName), ["usb"])
    }

    func testSyntheticCoversRestrictionUnknownAndMissingFacts() throws {
        let router = try fabric("tb_switch_synthetic.plist").routers[0]
        XCTAssertEqual(router.ports[0].restricted, true)
        let vendor = router.ports[3]
        XCTAssertEqual(vendor.label, "Vendor Link Adapter")
        XCTAssertEqual(vendor.protocolName, "unknown")
        XCTAssertEqual(router.tunnels[1].protocolName, "unknown")
        // a port whose link facts the OS did not publish stays nil, never 0
        XCTAssertNil(vendor.currentLinkSpeed)
        XCTAssertNil(vendor.maxCredits)
        XCTAssertNil(vendor.lane)
    }

    func testProtocolKindMapping() {
        XCTAssertEqual(ThunderboltSwitch.protocolKind("Thunderbolt Port"), "thunderbolt")
        XCTAssertEqual(ThunderboltSwitch.protocolKind("PCIe Adapter"), "pcie")
        XCTAssertEqual(ThunderboltSwitch.protocolKind("USB Adapter"), "usb")
        XCTAssertEqual(ThunderboltSwitch.protocolKind("DP or HDMI Adapter"), "displayport")
        XCTAssertEqual(ThunderboltSwitch.protocolKind("  usb adapter  "), "usb")
        XCTAssertEqual(ThunderboltSwitch.protocolKind("Vendor Link Adapter"), "unknown")
        XCTAssertEqual(ThunderboltSwitch.protocolKind(""), "unknown")
        XCTAssertEqual(ThunderboltSwitch.protocolKind(nil), "unknown")
    }

    // MARK: - source

    func testSourceServesTheFixture() {
        let (fabric, warnings) = Fixtures.tbFabric.fabric()
        XCTAssertEqual(warnings, [])
        XCTAssertEqual(fabric.routers.count, 3)
    }

    func testEmptyPayloadIsNotAWarning() throws {
        // A Mac without Thunderbolt reports no switch — that is not a failure.
        let empty = try PropertyListSerialization.data(
            fromPropertyList: [String](), format: .xml, options: 0
        )
        let source = ThunderboltFabricSource(runner: { CommandResult(argv: $0, returncode: 0, stdout: empty) })
        let (fabric, warnings) = source.fabric()
        XCTAssertTrue(fabric.routers.isEmpty)
        XCTAssertEqual(warnings, [])
    }

    func testFailingCommandIsReportedNotRaised() {
        let source = ThunderboltFabricSource(
            runner: { CommandResult(argv: $0, returncode: 127, error: "ioreg not found") }
        )
        let (fabric, warnings) = source.fabric()
        XCTAssertTrue(fabric.routers.isEmpty)
        XCTAssertEqual(warnings, ["ioreg not found"])
    }

    func testUnparsableOutputIsReported() {
        let source = ThunderboltFabricSource(
            runner: { CommandResult(argv: $0, returncode: 0, stdout: Data("not a plist at all".utf8)) }
        )
        let (fabric, warnings) = source.fabric()
        XCTAssertTrue(fabric.routers.isEmpty)
        XCTAssertTrue(warnings.contains { $0.contains("unparsable") })
    }

    func testUnexpectedStructureIsReported() throws {
        let scalar = try PropertyListSerialization.data(
            fromPropertyList: "just a string", format: .xml, options: 0
        )
        let source = ThunderboltFabricSource(runner: { CommandResult(argv: $0, returncode: 0, stdout: scalar) })
        let (fabric, warnings) = source.fabric()
        XCTAssertTrue(fabric.routers.isEmpty)
        XCTAssertEqual(warnings, ["ioreg returned an unexpected structure"])
    }

    func testParseAcceptsASingleRouterDict() throws {
        // ioreg returns an array, but a lone switch must not be dropped.
        let payload = try Fixtures.plistValue("tb_switch.plist") as? [Any]
        let first = try XCTUnwrap(payload?.first)
        XCTAssertEqual(ThunderboltSwitch.parse(first).routers.count, 1)
    }

    // MARK: - snapshot wiring

    func testFabricIsPartOfTheSnapshotAndGolden() throws {
        let payload = Fixtures.payload()
        let block = try XCTUnwrap(payload["thunderbolt_fabric"] as? [String: Any])
        let routers = try XCTUnwrap(block["routers"] as? [[String: Any]])
        XCTAssertEqual(routers.count, 3)
        XCTAssertEqual(routers[0]["router_id"] as? Int, 0)
        XCTAssertEqual(routers[0]["uid"] as? Int, 408840496304102592)
        XCTAssertEqual(routers[0]["thunderbolt_version"] as? Int, 32)
        let ports = try XCTUnwrap(routers[0]["ports"] as? [[String: Any]])
        XCTAssertEqual(
            ports.map { $0["protocol"] as? String },
            ["thunderbolt", "thunderbolt", "pcie", "usb", "displayport", "displayport"]
        )
        XCTAssertEqual(ports[0]["current_link_speed"] as? Int, 8)
        XCTAssertEqual(ports[0]["restricted"] as? Bool, false)
        let tunnels = try XCTUnwrap(routers[0]["tunnels"] as? [[String: Any]])
        XCTAssertEqual(
            tunnels.map { $0["protocol"] as? String },
            ["pcie", "usb", "displayport", "displayport"]
        )
        XCTAssertEqual(tunnels[0]["driver"] as? String, "com.apple.driver.AppleThunderboltPCIDownAdapter")
    }
}
