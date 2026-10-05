import Foundation
import XCTest
@testable import UsbScopeCore

/// The USB device tree adapter (`ioreg -p IOUSB`) — the twin of
/// `tests/test_usbregistry.py`. Same fixtures, same expectations.
final class USBRegistryTests: XCTestCase {
    func testClassNamesCoverTheUSBIFBaseClasses() {
        XCTAssertEqual(USBRegistry.className(0), "per-interface")
        XCTAssertEqual(USBRegistry.className(3), "HID")
        XCTAssertEqual(USBRegistry.className(8), "mass storage")
        XCTAssertEqual(USBRegistry.className(9), "hub")
        XCTAssertEqual(USBRegistry.className(0xFF), "vendor specific")
        XCTAssertEqual(USBRegistry.className(0x42), "0x42")  // unknown stays explicit
        XCTAssertNil(USBRegistry.className(nil))
        XCTAssertGreaterThanOrEqual(USBRegistry.classNames.count, 20)
    }

    func testBcdUsbIsTheSpecificationVersion() {
        XCTAssertEqual(USBRegistry.bcdUsb(512), "2.00")  // 0x0200
        XCTAssertEqual(USBRegistry.bcdUsb(528), "2.10")  // 0x0210
        XCTAssertEqual(USBRegistry.bcdUsb(768), "3.00")  // 0x0300
        XCTAssertNil(USBRegistry.bcdUsb(0))
        XCTAssertNil(USBRegistry.bcdUsb(nil))
    }

    func testSpeedCodes() {
        XCTAssertEqual(USBRegistry.speedCodeName(1), "full_speed")
        XCTAssertEqual(USBRegistry.speedCodeName(3), "super_speed")
        XCTAssertEqual(USBRegistry.speedCodeName(9), "code 9")
        XCTAssertNil(USBRegistry.speedCodeName(nil))
    }

    func testParseTheCapturedUsbPlane() throws {
        let devices = USBRegistry.devices(in: try Fixtures.plist("usbplane.plist"))
        XCTAssertEqual(devices.count, 1)
        let device = try XCTUnwrap(devices.first)
        XCTAssertEqual(device.name, "YubiKey OTP+FIDO+CCID")
        XCTAssertEqual(device.vendor, "Yubico")
        XCTAssertEqual(device.vendorID, 0x1050)
        XCTAssertEqual(device.productID, 0x0407)
        XCTAssertEqual(device.locationID, 0x01100000)
        XCTAssertEqual(device.deviceClass, 0)
        XCTAssertEqual(device.classText, "per-interface")
        XCTAssertEqual(device.bcdUsb, "2.00")
        XCTAssertEqual(device.maxPacketSize0, 64)
        XCTAssertEqual(device.numConfigurations, 1)
        XCTAssertEqual(device.speedCode, 1)
        XCTAssertEqual(device.speedMbps, 12)
        XCTAssertEqual(device.tier, 1)
        XCTAssertNil(device.parent)
        XCTAssertEqual(device.address, 1)
        XCTAssertEqual(device.source, "ioreg-usb")
    }

    func testHubChainSetsTierAndParent() throws {
        let devices = USBRegistry.devices(in: try Fixtures.plist("usbplane_hub_synthetic.plist"))
        let byName = Dictionary(uniqueKeysWithValues: devices.map { ($0.name, $0) })
        XCTAssertEqual(Set(byName.keys), ["USB3.0 Hub", "USB Keyboard", "USB Flash Drive"])

        let hub = try XCTUnwrap(byName["USB3.0 Hub"])
        XCTAssertEqual(hub.tier, 1)
        XCTAssertNil(hub.parent)
        XCTAssertEqual(hub.deviceClass, 9)
        XCTAssertEqual(hub.classText, "hub (9/0/1)")

        let keyboard = try XCTUnwrap(byName["USB Keyboard"])
        XCTAssertEqual(keyboard.tier, 2)
        XCTAssertEqual(keyboard.parent, "USB3.0 Hub")
        XCTAssertEqual(keyboard.classText, "HID (3/1/1)")

        let drive = try XCTUnwrap(byName["USB Flash Drive"])
        XCTAssertEqual(drive.tier, 2)
        XCTAssertEqual(drive.parent, "USB3.0 Hub")
        XCTAssertEqual(drive.classText, "mass storage (8/6/80)")
        XCTAssertEqual(drive.speedMbps, 5000)
    }

    func testSourceServesTheFixture() {
        let (devices, warnings) = Fixtures.usbregistry.devices()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(warnings, [])
    }

    func testAFailingCommandIsAWarningNotACrash() {
        let source = USBRegistrySource(runner: { argv in
            CommandResult(argv: argv, returncode: 1, error: "ioreg not found")
        })
        let (devices, warnings) = source.devices()
        XCTAssertEqual(devices.count, 0)
        XCTAssertEqual(warnings, ["ioreg not found"])
    }

    func testDescriptorFactsAreMergedIntoTheSnapshot() throws {
        let snapshot = Fixtures.snapshot()
        let device = try XCTUnwrap(snapshot.devices.first { $0.name.hasPrefix("YubiKey") })
        XCTAssertEqual(device.classText, "per-interface")
        XCTAssertEqual(device.bcdUsb, "2.00")
        XCTAssertEqual(device.tier, 1)
        XCTAssertEqual(device.address, 1)
        XCTAssertEqual(device.numConfigurations, 1)
    }
}
