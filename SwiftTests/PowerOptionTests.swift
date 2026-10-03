import Foundation
import XCTest
@testable import UsbScopeCore
@testable import UsbScopeUI

/// Power-delivery depth: PDO types, option identity and the PD menu summary —
/// the twin of `tests/test_power_options.py`.
final class PowerOptionTests: XCTestCase {
    func testPdoClassesAreDecoded() {
        XCTAssertEqual(IOReg.powerOptionKind("IOPortFeaturePowerSourceOptionFixed"), "fixed")
        XCTAssertEqual(IOReg.powerOptionKind("IOPortFeaturePowerSourceOptionAdjustable"), "adjustable")
        XCTAssertEqual(IOReg.powerOptionKind("IOPortFeaturePowerSourceOptionVariable"), "variable")
        XCTAssertEqual(IOReg.powerOptionKind("IOPortFeaturePowerSourceOptionBattery"), "battery")
        XCTAssertEqual(IOReg.powerOptionKind("SomethingElse"), "somethingElse")
        XCTAssertNil(IOReg.powerOptionKind(nil))
        XCTAssertNil(IOReg.powerOptionKind("IOPortFeaturePowerSourceOption"))
    }

    func testKindLabelNamesThePpsApdo() {
        XCTAssertEqual(PowerOption(kind: "fixed").kindLabel, "fixed")
        XCTAssertEqual(PowerOption(kind: "adjustable").kindLabel, "adjustable (PPS)")
        XCTAssertEqual(PowerOption(kind: "battery").kindLabel, "battery")
        XCTAssertEqual(PowerOption(kind: "mystery").kindLabel, "mystery")
        XCTAssertNil(PowerOption().kindLabel)
    }

    func testTheCapturedContractCarriesItsPdoTypeAndUuid() throws {
        let snapshot = Fixtures.snapshot()
        let port = try XCTUnwrap(snapshot.ports.first { $0.name == "USB-C@1" })
        let usbPD = try XCTUnwrap(port.powerSources.first { $0.name == "USB-PD" })
        XCTAssertTrue(usbPD.selected)
        let winning = try XCTUnwrap(usbPD.winning)
        XCTAssertEqual(winning.kind, "fixed")
        XCTAssertEqual(winning.uuid, "BAC8D9DA-DC62-4A85-8590-D9037ACB133B")
        XCTAssertEqual(Set(usbPD.options.compactMap(\.kind)), ["fixed"])
        XCTAssertEqual(Set(usbPD.options.compactMap(\.uuid)).count, usbPD.options.count)
    }

    func testThePdMenuIsSummarisedInTheDetails() throws {
        let snapshot = Fixtures.snapshot()
        let port = try XCTUnwrap(snapshot.ports.first { $0.name == "USB-C@1" })
        let detail = Dictionary(
            Presentation.portDetails(port), uniquingKeysWith: { first, _ in first }
        )
        XCTAssertEqual(detail["Selected source"], "USB-PD")
        XCTAssertEqual(detail["PD menu"], "4 option(s) · 5–20 V · up to 100 W · fixed")
    }

    func testANonFixedOptionIsMarkedInTheDetails() {
        let pps = PowerOption(maxCurrentMa: 3000, voltageMv: 9000, kind: "adjustable")
        let source = PowerSource(name: "USB-PD", selected: true, winning: pps, options: [pps])
        var port = UsbPort(description: "Port-USB-C@1", kind: "USB-C")
        port.powerSources = [source]
        let detail = Dictionary(
            Presentation.portDetails(port), uniquingKeysWith: { first, _ in first }
        )
        XCTAssertTrue(detail["USB-PD option 1"]?.hasSuffix("(adjustable (PPS))") ?? false)

        let fixed = PowerOption(maxCurrentMa: 3000, voltageMv: 5000, kind: "fixed")
        let fixedSource = PowerSource(name: "USB-PD", selected: true, winning: fixed, options: [fixed])
        var fixedPort = UsbPort(description: "Port-USB-C@1", kind: "USB-C")
        fixedPort.powerSources = [fixedSource]
        let fixedDetail = Dictionary(
            Presentation.portDetails(fixedPort), uniquingKeysWith: { first, _ in first }
        )
        XCTAssertFalse(fixedDetail["USB-PD option 1"]?.contains("(fixed)") ?? true)
    }
}
