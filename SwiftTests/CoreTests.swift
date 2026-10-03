import Foundation
import XCTest
@testable import UsbScopeCore

/// Unit tests of the pure core, mirroring `tests/test_format.py` and the mode
/// classification of `tests/test_models.py`.
final class CoreTests: XCTestCase {
    // MARK: - PlistValue (regression: the NSNumber→Bool bridge)

    /// On Darwin `NSNumber(0)`/`NSNumber(1)` bridge to `Bool`; a plain
    /// `value is Bool` would mistake them for booleans. This pins the guard the
    /// adapters rely on so the JSON keeps the integers `0` and `1`.
    func testIsBoolDistinguishesNumbersFromBooleans() {
        XCTAssertTrue(PlistValue.isBool(true))
        XCTAssertTrue(PlistValue.isBool(false))
        XCTAssertFalse(PlistValue.isBool(NSNumber(value: 0)))
        XCTAssertFalse(PlistValue.isBool(NSNumber(value: 1)))
        XCTAssertFalse(PlistValue.isBool(NSNumber(value: 2)))
        XCTAssertFalse(PlistValue.isBool("true"))

        // The same values as they arrive from a parsed plist/JSON payload.
        let json = try? JSONSerialization.jsonObject(
            with: Data(#"{"zero":0,"one":1,"two":2,"flag":true}"#.utf8)
        ) as? [String: Any]
        XCTAssertEqual(PlistValue.isBool(json?["zero"] as Any), false)
        XCTAssertEqual(PlistValue.isBool(json?["one"] as Any), false)
        XCTAssertEqual(PlistValue.isBool(json?["two"] as Any), false)
        XCTAssertEqual(PlistValue.isBool(json?["flag"] as Any), true)
    }

    func testIntKeepsZeroAndOne() {
        XCTAssertEqual(IOReg.int(0), 0)
        XCTAssertEqual(IOReg.int(1), 1)
        XCTAssertEqual(IOReg.int(NSNumber(value: 0)), 0)
        XCTAssertEqual(IOReg.int(NSNumber(value: 1)), 1)
        XCTAssertNil(IOReg.int(true))
        XCTAssertNil(IOReg.int(false))
    }

    func testTextDropsBooleansButKeepsNumbers() {
        XCTAssertNil(IOReg.text(true))
        XCTAssertEqual(IOReg.text(0), "0")
        XCTAssertEqual(IOReg.text(1), "1")
        XCTAssertEqual(IOReg.text("Idle"), "Idle")
        XCTAssertNil(IOReg.text("none"))
    }

    // MARK: - UsbMode

    func testModeClassificationFromText() {
        XCTAssertEqual(UsbMode.from(text: "12 Mbps (Full Speed)"), .fullSpeed)
        XCTAssertEqual(UsbMode.from(text: "480 Mbps"), .highSpeed)
        XCTAssertEqual(UsbMode.from(text: "5 Gbit/s"), .superSpeed)
        XCTAssertEqual(UsbMode.from(text: "SuperSpeed"), .superSpeed)
        XCTAssertEqual(UsbMode.from(text: "No Link"), .unknown)
        XCTAssertEqual(UsbMode.from(text: ""), .unknown)
        XCTAssertEqual(UsbMode.from(text: nil), .unknown)
    }

    func testModeClassificationFromRate() {
        XCTAssertEqual(UsbMode.from(mbps: 480), .highSpeed)
        XCTAssertEqual(UsbMode.from(mbps: 10_000), .superSpeedPlus)
        XCTAssertEqual(UsbMode.from(mbps: 480_000_000), .highSpeed)  // bit/s
        XCTAssertEqual(UsbMode.from(mbps: nil), .unknown)
    }

    func testModeLabelsAndRanks() {
        XCTAssertEqual(UsbMode.fullSpeed.label, "USB 1.1 Full-Speed · 12 Mbit/s")
        XCTAssertEqual(UsbMode.usb4_40.short, "USB4 40")
        XCTAssertGreaterThan(UsbMode.usb4_40.rank, UsbMode.superSpeed.rank)
        XCTAssertEqual(UsbMode.unknown.rank, 0)
    }

    // MARK: - Format (mirrors tests/test_format.py)

    func testUnitsAreRenderedFromTheRawValues() {
        XCTAssertNil(Format.watts(nil))
        XCTAssertEqual(Format.watts(27575), "27.6 W")
        XCTAssertEqual(Format.watts(70000, compact: true), "70 W")
        XCTAssertEqual(Format.volts(19478), "19.5 V")
        XCTAssertEqual(Format.volts(20000, compact: true), "20 V")
        XCTAssertEqual(Format.amps(1417), "1.42 A")
        XCTAssertEqual(Format.amps(3500, compact: true), "3.5 A")
    }

    func testPowerLineSkipsWhatIsUnknown() {
        XCTAssertEqual(Format.powerLine(powerMw: 27575, voltageMv: nil, currentMa: 1417), "27.6 W · 1.42 A")
        XCTAssertNil(Format.powerLine(powerMw: nil, voltageMv: nil, currentMa: nil))
    }

    func testChargingStateAndSummary() {
        var charging = Charging()
        charging.connected = true
        charging.charging = true
        charging.stateOfCharge = 42
        charging.timeRemainingMinutes = 17
        charging.systemPowerInMw = 35958
        charging.batteryPowerMw = 21773
        charging.systemLoadMw = 14185
        XCTAssertEqual(Format.chargingState(charging), "charging · 42 % · 17 min to full")
        XCTAssertEqual(Format.chargingSummary(charging), "36.0 W in · 21.8 W battery · 14.2 W system")
    }

    func testChargingStateOfEverySituation() {
        var full = Charging()
        full.connected = true
        full.fullyCharged = true
        full.stateOfCharge = 100
        full.timeRemainingMinutes = 14
        XCTAssertEqual(Format.chargingState(full), "fully charged · 100 %")

        var idle = Charging()
        idle.connected = true
        idle.charging = false
        idle.fullyCharged = false
        idle.stateOfCharge = 80
        XCTAssertEqual(Format.chargingState(idle), "plugged in, not charging · 80 %")

        var battery = Charging()
        battery.connected = false
        battery.stateOfCharge = 8
        battery.timeRemainingMinutes = 95
        XCTAssertEqual(Format.chargingState(battery), "on battery · 8 % · 95 min left")

        var half = Charging()
        half.stateOfCharge = 50
        XCTAssertEqual(Format.chargingState(half), "50 %")
        XCTAssertNil(Format.chargingState(Charging()))
        XCTAssertNil(Format.chargingSummary(Charging()))
    }

    func testChargerFlagsAreOnlyReportedWhenSet() {
        XCTAssertNil(Format.chargerFlags(Charging()))
        var slow = Charging()
        slow.slowChargingReason = 2
        XCTAssertEqual(Format.chargerFlags(slow), "slow charging: 2")
        var both = Charging()
        both.notChargingReason = 3
        both.thermallyLimitedSeconds = 90
        XCTAssertEqual(Format.chargerFlags(both), "not charging: 3, thermally limited 90 s")
    }

    // MARK: - model helpers

    func testDeviceIdStringAndLabel() {
        let device = UsbDevice(name: "YubiKey", vendor: "Yubico", vendorID: 0x1050, productID: 0x0407)
        XCTAssertEqual(device.idString, "0x1050:0x0407")
        XCTAssertEqual(device.label, "Yubico YubiKey")

        let suffixed = UsbDevice(name: "Yubico YubiKey", vendor: "Yubico")
        XCTAssertEqual(suffixed.label, "Yubico YubiKey")
    }

    func testCableKindAndPortName() {
        XCTAssertEqual(Cable().kind, "–")
        XCTAssertEqual(Cable(attached: true, emarker: true).kind, "e-marked")
        XCTAssertEqual(Cable(attached: true, active: true).kind, "active")
        XCTAssertEqual(Cable(attached: true, optical: true).kind, "optical")

        let port = UsbPort(description: "Port-USB-C@3", kind: "USB-C")
        XCTAssertEqual(port.name, "USB-C@3")
    }
}
