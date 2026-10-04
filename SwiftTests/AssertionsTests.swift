import Foundation
import XCTest

@testable import UsbScopeCore

/// `usbscope check` — the assertion engine and its exit codes.
final class AssertionsTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - helpers

    private func device(
        _ name: String = "YubiKey",
        vendor: String? = nil,
        vendorID: Int? = 0x1050,
        productID: Int? = 0x0407,
        serial: String? = nil,
        locationID: Int? = 1,
        port: String? = nil
    ) -> UsbDevice {
        UsbDevice(
            name: name, vendor: vendor, vendorID: vendorID, productID: productID,
            serial: serial, locationID: locationID, port: port
        )
    }

    private func port(_ name: String = "USB-C@3", connected: Bool = true) -> UsbPort {
        var value = UsbPort(description: "Port-\(name)", kind: "USB-C")
        value.number = 3
        value.connected = connected
        return value
    }

    private func snapshot(
        devices: [UsbDevice] = [], ports: [UsbPort] = [], warnings: [String] = []
    ) -> Snapshot {
        let buses = devices.isEmpty ? [] : [Bus(name: "USB 3.1 Bus", devices: devices)]
        return Snapshot(
            host: "mac", osVersion: "27.0.1", seenAt: when, ports: ports, buses: buses,
            warnings: warnings
        )
    }

    // MARK: - parsing

    func testParseForms() throws {
        let id = try Assertions.parse("device=0x1050:0x0407")
        XCTAssertEqual([id.key, id.op, id.value], ["device", "=", "0x1050:0x0407"])
        XCTAssertNil(id.target)
        let named = try Assertions.parse("device=YubiKey")
        XCTAssertEqual(named.value, "YubiKey")
        let connected = try Assertions.parse("connected>=1")
        XCTAssertEqual(connected.target, 1)
        let warning = try Assertions.parse("warning=0")
        XCTAssertEqual(warning.target, 0)
        XCTAssertEqual(try Assertions.parse("warnings<=3").op, "<=")
    }

    func testMalformedExpressionsThrow() {
        for expression in ["", "connected", "nonsense=1", "device>=0x1050:0x0407", "connected>=many"] {
            XCTAssertThrowsError(try Assertions.parse(expression), expression)
        }
    }

    func testNormalizeUSBID() {
        XCTAssertEqual(Assertions.normalizeUSBID("0x1050:0x407"), "0x1050:0x0407")
        XCTAssertEqual(Assertions.normalizeUSBID("1050:0407"), "0x1050:0x0407")
        XCTAssertEqual(Assertions.normalizeUSBID("0XABCD:0X1"), "0xabcd:0x0001")
    }

    func testDeviceMatchesByIdAndName() {
        let value = device("YubiKey OTP", vendor: "Yubico")
        XCTAssertTrue(Assertions.deviceMatches(value, "0x1050:0x0407"))
        XCTAssertTrue(Assertions.deviceMatches(value, "yubikey"))
        XCTAssertTrue(Assertions.deviceMatches(value, "Yubico"))
        XCTAssertFalse(Assertions.deviceMatches(value, "0xdead:0xbeef"))
        XCTAssertFalse(Assertions.deviceMatches(value, "keyboard"))
    }

    // MARK: - evaluation

    func testCountsHold() throws {
        let report = Assertions.evaluate(
            snapshot(devices: [device()], ports: [port()]),
            [try Assertions.parse("connected>=1"), try Assertions.parse("devices>=1")]
        )
        XCTAssertTrue(report.passed)
        XCTAssertEqual(report.passedCount, 2)
        XCTAssertTrue(report.failed.isEmpty)
    }

    func testFailingExpectationIsReported() throws {
        let report = Assertions.evaluate(
            snapshot(devices: [device()], ports: [port()]),
            [try Assertions.parse("device=0xdead:0xbeef")]
        )
        XCTAssertFalse(report.passed)
        XCTAssertEqual(report.failed.count, 1)
        XCTAssertEqual(report.outcomes[0].actual, 0)
        XCTAssertEqual(report.outcomes[0].detail, "no matching device")
        XCTAssertNil(report.outcomes[0].target)
    }

    func testPortMatchIsCaseInsensitive() throws {
        let value = snapshot(ports: [port("USB-C@3")])
        XCTAssertTrue(Assertions.evaluate(value, [try Assertions.parse("port=usb-c@3")]).passed)
        XCTAssertFalse(Assertions.evaluate(value, [try Assertions.parse("port=USB-C@9")]).passed)
    }

    func testWarningZeroIsTheCIAssertion() throws {
        XCTAssertTrue(Assertions.evaluate(snapshot(), [try Assertions.parse("warning=0")]).passed)
        XCTAssertFalse(
            Assertions.evaluate(snapshot(warnings: ["ioreg failed"]), [try Assertions.parse("warning=0")])
                .passed
        )
    }

    func testNewDeviceTurnsAFailingCheckIntoAPassingOne() throws {
        let expectation = [try Assertions.parse("device=0x1050:0x0407")]
        XCTAssertFalse(Assertions.evaluate(snapshot(ports: [port(connected: false)]), expectation).passed)
        XCTAssertTrue(Assertions.evaluate(snapshot(devices: [device()], ports: [port()]), expectation).passed)
    }

    // MARK: - output

    func testJSONDocumentShape() throws {
        let report = Assertions.evaluate(
            snapshot(), [try Assertions.parse("connected>=1"), try Assertions.parse("warning=0")]
        )
        let data = try XCTUnwrap(Assertions.json(report).data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["kind"] as? String, "check")
        XCTAssertEqual(payload["passed"] as? Bool, false)
        XCTAssertEqual(payload["total"] as? Int, 2)
        XCTAssertEqual(payload["failed_count"] as? Int, 1)
        let expectations = try XCTUnwrap(payload["expectations"] as? [[String: Any]])
        XCTAssertEqual(expectations[0]["expression"] as? String, "connected>=1")
        XCTAssertEqual(expectations[0]["target"] as? Int, 1)
    }

    func testRenderMarksPassAndFail() throws {
        let passing = Assertions.evaluate(snapshot(ports: [port()]), [try Assertions.parse("connected>=1")])
        XCTAssertTrue(Assertions.render(passing).contains("✓ connected>=1"))
        let failing = Assertions.evaluate(snapshot(), [try Assertions.parse("connected>=1")])
        XCTAssertTrue(Assertions.render(failing).contains("✗ connected>=1"))
        XCTAssertTrue(Assertions.render(failing).contains("0/1 expectation(s) hold — 1 failed"))
    }

    func testEmptyReportPassesVacuously() {
        XCTAssertTrue(CheckReport(outcomes: []).passed)
        XCTAssertTrue(Assertions.render(CheckReport(outcomes: [])).contains("0/0 expectation(s) hold — ok"))
    }
}
