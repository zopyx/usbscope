import XCTest
@testable import UsbScopeCore
import UsbScopeUI

/// The interface level of the descriptor tree.
///
/// macOS publishes `IOUSBHostInterface` objects in the registry, which is readable
/// without an entitlement — so these are real descriptors, not a stand-in for the
/// endpoint view (which the registry does not publish at all).
final class USBInterfaceTests: XCTestCase {
    /// The captured interfaces of the fixture device (a composite keypad with two
    /// HID interfaces and one smart-card interface).
    func testFixtureInterfacesParse() throws {
        let entries = try Fixtures.plistValue("usb_interfaces.plist") as? [[String: Any]]
        let parsed = USBInterfaceSource.parse(try XCTUnwrap(entries))

        XCTAssertEqual(parsed.count, 1, "one device in the capture")
        let interfaces = try XCTUnwrap(parsed[17825792])
        XCTAssertEqual(interfaces.count, 3)

        XCTAssertEqual(interfaces.map(\.number), [0, 1, 2], "sorted by interface number")
        XCTAssertEqual(
            interfaces.map(\.classText),
            ["HID (3/1/1)", "HID (3/0/0)", "smart card (11/0/0)"]
        )
        XCTAssertEqual(interfaces.map(\.endpoints), [1, 2, 3], "bNumEndpoints, the count macOS publishes")
        XCTAssertEqual(interfaces.map(\.configuration), [1, 1, 1])
        XCTAssertEqual(interfaces.map(\.alternateSetting), [0, 0, 0])
    }

    /// The fixture snapshot must carry the interfaces through the builder, attached
    /// to the device they belong to.
    func testSnapshotAttachesInterfacesToTheDevice() throws {
        let snapshot = Fixtures.snapshot()
        let devices = snapshot.buses.flatMap(\.devices)
        let device = try XCTUnwrap(devices.first { $0.name.contains("OTP+FIDO+CCID") })
        XCTAssertEqual(device.interfaces.count, 3)
        XCTAssertEqual(device.interfaces.first?.classText, "HID (3/1/1)")
        // A device whose interfaces are unknown keeps an empty list rather than a guess.
        for other in devices where other.name != device.name {
            XCTAssertTrue(other.interfaces.isEmpty)
        }
    }

    /// An entry without a location or an interface number cannot be attached to a
    /// device, and is dropped instead of being invented.
    func testIncompleteEntriesAreDropped() {
        let parsed = USBInterfaceSource.parse([
            ["locationID": 42, "bInterfaceClass": 3],
            ["bInterfaceNumber": 0, "bInterfaceClass": 3],
            [:],
        ])
        XCTAssertTrue(parsed.isEmpty)
    }

    /// Alternates share the interface number; the sort puts them in a stable order so
    /// two runs cannot disagree (which would show up as a phantom baseline change).
    func testAlternateSettingsSortTogetherAndStably() throws {
        let parsed = USBInterfaceSource.parse([
            ["locationID": 7, "bInterfaceNumber": 1, "bAlternateSetting": 0],
            ["locationID": 7, "bInterfaceNumber": 0, "bAlternateSetting": 1],
            ["locationID": 7, "bInterfaceNumber": 0, "bAlternateSetting": 0],
        ])
        let labels = try XCTUnwrap(parsed[7]).map(\.label)
        XCTAssertEqual(labels, ["if 0", "if 0 alt 1", "if 1"])
    }

    /// A class the table does not know still reads as its numbers rather than as an
    /// empty string. The code is *derived* from the table so the test keeps testing
    /// the fallback when someone adds a name for it.
    func testUnknownClassFallsBackToItsNumbers() throws {
        let unknown = try XCTUnwrap((1...255).first { USBRegistry.classNames[$0] == nil })
        let parsed = USBInterfaceSource.parse([
            ["locationID": 9, "bInterfaceNumber": 0, "bInterfaceClass": unknown,
             "bInterfaceSubClass": 1, "bInterfaceProtocol": 2],
        ])
        XCTAssertEqual(
            try XCTUnwrap(parsed[9]).first?.classText,
            String(format: "0x%02x (%d/1/2)", unknown, unknown)
        )
    }

    /// A class the table *does* know is named rather than printed in hex.
    func testKnownClassIsNamed() throws {
        let parsed = USBInterfaceSource.parse([
            ["locationID": 11, "bInterfaceNumber": 0, "bInterfaceClass": 0xfe],
        ])
        XCTAssertEqual(try XCTUnwrap(parsed[11]).first?.classText, "application specific (254/?/?)")
    }

    /// The in-process backend is what a bundled app uses; it must find the interfaces
    /// of this machine too, not only the `ioreg` fallback. Skipped where the registry
    /// cannot be read — that is not a regression.
    func testInProcessBackendReadsTheLiveRegistry() throws {
        let source = USBInterfaceSource(backend: .inProcess)
        let (interfaces, warnings) = source.interfaces()
        if interfaces.isEmpty {
            throw XCTSkip("registry not readable here: \(warnings.joined(separator: "; "))")
        }
        let all = interfaces.values.flatMap { $0 }
        XCTAssertFalse(all.isEmpty)
        // Every interface carries a number; the rest may legitimately be missing.
        XCTAssertTrue(all.allSatisfy { $0.number >= 0 })
    }

    /// An unreadable backend must warn instead of quietly reporting "no interfaces".
    func testFailureIsReportedAsAWarning() {
        let failing: Runner = { argv in
            CommandResult(argv: argv, returncode: 1, error: "boom")
        }
        let (interfaces, warnings) = USBInterfaceSource(runner: failing, backend: .subprocess).interfaces()
        XCTAssertTrue(interfaces.isEmpty)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("boom"), warnings[0])
    }

    // MARK: - security rules now see the interface level

    /// A device that declares class `0` at the device level and carries a mass-storage
    /// interface is mass storage — before the interfaces were read, every rule keyed on
    /// `deviceClass` missed it entirely.
    func testCompositeStorageDeviceIsFlaggedThroughItsInterfaces() {
        var device = UsbDevice(name: "Flash+Keyboard", vendor: "Acme", locationID: 1)
        device.deviceClass = 0
        device.interfaces = [
            DeviceInterface(number: 0, classCode: 8, subclass: 6, protocolCode: 0x50, endpoints: 2),
            DeviceInterface(number: 1, classCode: 3, subclass: 1, protocolCode: 1, endpoints: 1),
        ]
        let rules = Security.deviceFindings(device).map(\.rule)
        XCTAssertTrue(rules.contains("mass-storage"), "\(rules)")
        XCTAssertTrue(rules.contains("hid-and-storage-on-device"), "a keyboard hidden in a stick")
        XCTAssertTrue(rules.contains("hid-without-serial"), "\(rules)")
    }

    /// A plain device without interfaces keeps the old behaviour: no invented findings.
    func testDeviceWithoutInterfacesIsUnchanged() {
        var device = UsbDevice(name: "Hub", vendor: "Acme", locationID: 2)
        device.deviceClass = 0x09
        XCTAssertTrue(Security.deviceFindings(device).isEmpty)
    }

    /// The composite note must name the interfaces when they are known and say what is
    /// missing when they are not — never claim knowledge it does not have.
    func testCompositeNoteExplainsItselfEitherWay() {
        var known = UsbDevice(name: "Key", locationID: 3)
        known.deviceClass = 0
        known.interfaces = [DeviceInterface(number: 0, classCode: 3, subclass: 1, protocolCode: 1)]
        let named = Security.compositePerInterfaceDetail(known)
        XCTAssertTrue(named.contains("if 0: HID (3/1/1)"), named)

        var unknown = UsbDevice(name: "Key", locationID: 4)
        unknown.deviceClass = 0
        let missing = Security.compositePerInterfaceDetail(unknown)
        XCTAssertTrue(missing.contains("published no interface objects"), missing)
    }

    /// The device detail sheet lists the interfaces.
    func testDeviceDetailsListInterfaces() {
        var device = UsbDevice(name: "Key", locationID: 5)
        device.interfaces = [
            DeviceInterface(number: 0, configuration: 1, classCode: 3, subclass: 1,
                            protocolCode: 1, endpoints: 1),
        ]
        let details = Presentation.deviceDetails(device)
        XCTAssertEqual(details.first { $0.0 == "Interfaces" }?.1, "1")
        XCTAssertEqual(details.first { $0.0 == "if 0" }?.1, "HID (3/1/1) · 1 endpoint(s) · config 1")
    }

    /// The honest-limits paragraph is the tool's promise: it must not still claim that
    /// the interfaces are invisible, and it must name the limit that remains.
    func testHonestLimitsMatchWhatTheToolCanSee() {
        let limits = SecurityPresentation.honestLimits
        XCTAssertFalse(
            limits.contains("are not exposed without a user client"),
            "the interfaces are read now — this claim is stale"
        )
        XCTAssertTrue(limits.contains("endpoint"), limits)
        // And the CLI prints exactly this text.
        XCTAssertTrue(limits.hasPrefix("honest limits: "))
    }
}
