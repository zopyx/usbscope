import Foundation
import XCTest
@testable import UsbScopeCore

/// The shape of the port/charging payload at the JSON level, mirroring the
/// assertions carried over from the original tool. These pin the
/// numbers the two implementations must agree on — including the integers `0`
/// and `1` that a naive `is Bool` test would drop.
final class PortPayloadTests: XCTestCase {
    private func ports() throws -> [String: [String: Any]] {
        let list = try XCTUnwrap(Fixtures.payload()["ports"] as? [[String: Any]])
        return Dictionary(uniqueKeysWithValues: list.compactMap { port in
            (port["name"] as? String).map { ($0, port) }
        })
    }

    func testUsbC3Payload() throws {
        let port = try XCTUnwrap(try ports()["USB-C@3"])
        XCTAssertEqual(port["connected"] as? Bool, true)
        XCTAssertEqual(port["mode"] as? String, "full_speed")
        XCTAssertEqual(port["mode_label"] as? String, "USB 1.1 Full-Speed · 12 Mbit/s")

        let cable = try XCTUnwrap(port["cable"] as? [String: Any])
        XCTAssertEqual(cable["emarker"] as? Bool, false)
        XCTAssertEqual(cable["hash_status"] as? String, "Not Set")
        XCTAssertEqual(port["power_in"] as? [String], [])

        let transports = try XCTUnwrap(port["transports"] as? [[String: Any]])
        let usb2 = try XCTUnwrap(transports.first { $0["kind"] as? String == "USB2" })
        XCTAssertEqual(usb2["active"] as? Bool, true)
        XCTAssertEqual(usb2["mode"] as? String, "full_speed")
        XCTAssertEqual(usb2["rate"] as? String, "12 Mbps (Full Speed)")
        XCTAssertEqual(usb2["trm_state"] as? String, "Limited")

        let devices = try XCTUnwrap(port["devices"] as? [[String: Any]])
        XCTAssertEqual(devices.first?["id"] as? String, "0x1050:0x0407")
    }

    /// The controller details include zeros and ones — the exact values the
    /// `NSNumber`→`Bool` bridge used to swallow.
    func testUsbC3ControllerDetailsKeepZeroAndOne() throws {
        let port = try XCTUnwrap(try ports()["USB-C@3"])
        XCTAssertEqual(
            port["pin_configuration"] as? [String: Int],
            ["rx1": 0, "rx2": 4, "tx1": 0, "tx2": 3, "sbu1": 0, "sbu2": 0]
        )
        XCTAssertEqual(port["usb_mode_type"] as? Int, 2)
        XCTAssertEqual(port["accessory_mode"] as? Int, 0)
        XCTAssertEqual(port["power_mode"] as? Int, 1)
        XCTAssertEqual(port["active_power_mode"] as? Int, 1)
        XCTAssertEqual(port["supported_power_modes"] as? [Int], [1, 3])
        XCTAssertEqual(port["power_current_limits"] as? [Int], [0, 0, 0, 0, 0])
        XCTAssertEqual(port["liquid_state"] as? String, "Idle")
        XCTAssertEqual(port["liquid_measurement"] as? String, "No Error")
        XCTAssertEqual(port["liquid_pin"] as? String, "Reference")
        XCTAssertEqual(port["liquid_mitigations"] as? Bool, false)
        XCTAssertEqual(port["liquid_override"] as? Bool, false)
    }

    func testReceptacleWithoutOptionalDataReportsEmptyNotNullGuesses() throws {
        let hdmi = try XCTUnwrap(try ports()["HDMI@1"])
        XCTAssertEqual(hdmi["pin_configuration"] as? [String: Int], [:])
        XCTAssertTrue(hdmi["usb_mode_type"] is NSNull)
        XCTAssertEqual(hdmi["supported_power_modes"] as? [Int], [])
        XCTAssertTrue(hdmi["liquid_state"] is NSNull)
    }

    func testPowerContractOfUsbC1() throws {
        let port = try XCTUnwrap(try ports()["USB-C@1"])
        let sources = try XCTUnwrap(port["power_sources"] as? [[String: Any]])
        XCTAssertEqual(sources.compactMap { $0["name"] as? String }, ["USB-PD", "Brick ID", "TypeC"])

        let usbPD = sources[0]
        XCTAssertEqual(usbPD["selected"] as? Bool, true)
        XCTAssertEqual(usbPD["type"] as? Int, 2)
        XCTAssertEqual(usbPD["priority"] as? Int, 1000)

        let winning = try XCTUnwrap(usbPD["winning"] as? [String: Any])
        XCTAssertEqual(winning["voltage_mv"] as? Int, 20000)
        XCTAssertEqual(winning["max_current_ma"] as? Int, 5000)
        XCTAssertEqual(winning["max_power_mw"] as? Int, 100000)
        XCTAssertEqual(winning["watts"] as? Double, 100.0)

        let options = try XCTUnwrap(usbPD["options"] as? [[String: Any]])
        XCTAssertEqual(options.compactMap { $0["max_power_mw"] as? Int }.sorted(), [15000, 27000, 45000, 100000])
        XCTAssertEqual((sources[2]["options"] as? [[String: Any]])?.first?["watts"] as? Double, 15.0)

        let c2 = try XCTUnwrap(try ports()["USB-C@2"])
        XCTAssertEqual((c2["power_sources"] as? [[String: Any]])?.count, 0)
    }

    func testChargingPayload() throws {
        let charging = try XCTUnwrap(Fixtures.payload()["charging"] as? [String: Any])
        XCTAssertEqual(charging["connected"] as? Bool, true)
        XCTAssertEqual(charging["charging"] as? Bool, true)
        XCTAssertEqual(charging["state_of_charge"] as? Int, 100)
        XCTAssertEqual(charging["system_power_in_mw"] as? Int, 27575)
        XCTAssertEqual(charging["adapter_power_mw"] as? Int, 70000)
        XCTAssertEqual(charging["battery_current_ma"] as? Int, 887)
    }

    func testDesktopSerialisesNoChargingBlock() {
        let without = Snapshot(host: "mac", osVersion: "27.0.1", seenAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(Serialize.dict(without)["charging"] is NSNull)
    }
}
