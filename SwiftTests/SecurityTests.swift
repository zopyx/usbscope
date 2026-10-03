import Foundation
import XCTest

@testable import UsbScopeCore

/// The security posture analyser and the storage inventory — the twin of
/// `tests/test_security.py` and `tests/test_storage.py`.
final class SecurityTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - helpers

    private func device(
        _ name: String,
        deviceClass: Int? = nil,
        subclass: Int? = nil,
        proto: Int? = nil,
        serial: String? = nil,
        restricted: Bool? = nil,
        locationID: Int? = 1
    ) -> UsbDevice {
        UsbDevice(
            name: name,
            serial: serial,
            locationID: locationID,
            restricted: restricted,
            deviceClass: deviceClass,
            deviceSubclass: subclass,
            deviceProtocol: proto
        )
    }

    private func port(
        _ name: String = "USB-C@1",
        connected: Bool = false,
        authorization: String? = nil,
        transports: [Transport] = [],
        devices: [UsbDevice] = []
    ) -> UsbPort {
        var value = UsbPort(description: "Port-\(name)", kind: "USB-C")
        value.number = 1
        value.connected = connected
        value.authorization = authorization
        value.transports = transports
        value.devices = devices
        return value
    }

    private func snapshot(devices: [UsbDevice] = [], ports: [UsbPort] = []) -> Snapshot {
        let buses = devices.isEmpty ? [] : [Bus(name: "USB 3.1 Bus", devices: devices)]
        return Snapshot(
            host: "mac", osVersion: "27.0.1", seenAt: when, ports: ports, buses: buses
        )
    }

    private func rules(_ report: SecurityReport) -> [String] { report.findings.map(\.rule) }
    private func find(_ report: SecurityReport, _ rule: String) -> [Finding] {
        report.findings.filter { $0.rule == rule }
    }

    // MARK: - device rules

    func testMassStorageIsAWarning() {
        let report = Security.analyse(snapshot(devices: [device("Stick", deviceClass: 0x08)]))
        let finding = find(report, "mass-storage")[0]
        XCTAssertEqual(finding.severity, .warning)
        XCTAssertEqual(finding.subject, "Stick")
        XCTAssertTrue(finding.detail.contains("class 8"))
    }

    func testHIDWithoutSerialIsAttention() {
        let report = Security.analyse(snapshot(devices: [device("Keyboard", deviceClass: 0x03)]))
        XCTAssertEqual(find(report, "hid-without-serial")[0].severity, .attention)
    }

    func testHIDWithASerialIsNotFlagged() {
        let report = Security.analyse(
            snapshot(devices: [device("Keyboard", deviceClass: 0x03, serial: "ABC123")])
        )
        XCTAssertTrue(find(report, "hid-without-serial").isEmpty)
    }

    func testCompositeClassZeroIsOnlyAnInfo() {
        let report = Security.analyse(snapshot(devices: [device("Hub-ish", deviceClass: 0x00)]))
        let finding = find(report, "composite-per-interface")[0]
        XCTAssertEqual(finding.severity, .info)
        XCTAssertTrue(finding.detail.contains("cannot be confirmed"))
        XCTAssertTrue(finding.detail.contains("HID and mass storage"))
    }

    func testIADCompositeIsReportedAsInfo() {
        let report = Security.analyse(
            snapshot(devices: [device("Combo", deviceClass: 0xEF, subclass: 0x02, proto: 0x01)])
        )
        XCTAssertEqual(rules(report), ["composite-iad"])
    }

    func testRestrictedDeviceIsAttention() {
        let report = Security.analyse(snapshot(devices: [device("Odd", restricted: true)]))
        XCTAssertEqual(find(report, "restricted-by-macos")[0].severity, .attention)
    }

    func testADeviceWithoutAClassIsNotFlagged() {
        XCTAssertTrue(Security.analyse(snapshot(devices: [device("Anonymous")])).isEmpty)
    }

    // MARK: - port rules

    func testNonStandardAuthorizationIsAttention() {
        let report = Security.analyse(snapshot(ports: [port(authorization: "Denied")]))
        let finding = find(report, "authorization")[0]
        XCTAssertEqual(finding.severity, .attention)
        XCTAssertTrue(finding.detail.contains("Denied"))
    }

    func testStandardAuthorizationsAreNotFlagged() {
        for value in ["Not Required", "No Action", nil] {
            let report = Security.analyse(snapshot(ports: [port(authorization: value)]))
            XCTAssertTrue(find(report, "authorization").isEmpty)
        }
    }

    func testAnActiveRestrictedTransportIsAttention() {
        let transport = Transport(kind: "USB3", active: true, restricted: true)
        let report = Security.analyse(snapshot(ports: [port(transports: [transport])]))
        XCTAssertEqual(find(report, "restricted-transport").count, 1)
    }

    func testAnIdleRestrictedTransportIsNotFlagged() {
        let transport = Transport(kind: "USB3", active: false, restricted: true)
        let report = Security.analyse(snapshot(ports: [port(transports: [transport])]))
        XCTAssertTrue(find(report, "restricted-transport").isEmpty)
    }

    func testADeviceWithoutAnActiveUsbTransportIsAttention() {
        let value = port(
            connected: true,
            transports: [Transport(kind: "CC", active: true)],
            devices: [device("Ghost", deviceClass: 0x00)]
        )
        let report = Security.analyse(snapshot(ports: [value]))
        XCTAssertEqual(find(report, "no-usb-data").count, 1)
    }

    func testAnActiveUsbTransportSilencesTheNoDataRule() {
        let value = port(
            connected: true,
            transports: [Transport(kind: "USB2", active: true)],
            devices: [device("Real", deviceClass: 0x00)]
        )
        let report = Security.analyse(snapshot(ports: [value]))
        XCTAssertTrue(find(report, "no-usb-data").isEmpty)
    }

    func testAPortWithHIDAndStorageIsAWarning() {
        let value = port(devices: [
            device("Keyboard", deviceClass: 0x03, locationID: 2),
            device("Stick", deviceClass: 0x08, locationID: 3),
        ])
        let report = Security.analyse(snapshot(ports: [value]))
        let finding = find(report, "hid-and-storage-on-port")[0]
        XCTAssertEqual(finding.severity, .warning)
        XCTAssertEqual(finding.subject, "USB-C@1")
    }

    // MARK: - ordering, counts, fixtures

    func testFindingsAreSortedMostSevereFirst() {
        let report = Security.analyse(snapshot(devices: [
            device("Stick", deviceClass: 0x08, locationID: 1),
            device("Keyboard", deviceClass: 0x03, locationID: 2),
            device("Combo", deviceClass: 0x00, locationID: 3),
        ]))
        XCTAssertEqual(report.findings.map(\.severity), [.warning, .attention, .info])
        XCTAssertEqual(rules(report), ["mass-storage", "hid-without-serial", "composite-per-interface"])
    }

    func testCountsAreStable() {
        let report = Security.analyse(snapshot(devices: [
            device("Stick", deviceClass: 0x08, locationID: 1),
            device("Combo", deviceClass: 0x00, locationID: 2),
        ]))
        XCTAssertEqual(report.count(.warning), 1)
        XCTAssertEqual(report.count(.info), 1)
        XCTAssertEqual(report.count(.attention), 0)
        XCTAssertEqual(report.findings.count, 2)
    }

    func testAnEmptySnapshotHasNoFindings() {
        XCTAssertTrue(Security.analyse(snapshot()).isEmpty)
    }

    func testTheFixtureSnapshotReportsTheYubiKeyAsPerInterface() {
        let report = Security.analyse(Fixtures.snapshot())
        let composites = find(report, "composite-per-interface")
        XCTAssertEqual(composites.count, 1)
        XCTAssertTrue(composites[0].subject.hasPrefix("Yubico YubiKey"))
    }

    // MARK: - JSON document

    func testTheSecurityJSONDocumentShape() throws {
        let report = Security.analyse(snapshot(devices: [device("Stick", deviceClass: 0x08)]))
        let dict = Serialize.securityDict(report, storage: [], generatedAt: when)
        XCTAssertEqual(dict["kind"] as? String, "security")
        XCTAssertEqual(dict["schema_version"] as? Int, 1)
        let findings = try XCTUnwrap(dict["findings"] as? [[String: Any]])
        XCTAssertEqual(findings.first?["rule"] as? String, "mass-storage")
        XCTAssertEqual(findings.first?["severity"] as? String, "warning")
    }

    // MARK: - storage inventory

    private func listing(_ identifiers: String...) -> [String: Any] {
        ["WholeDisks": identifiers, "AllDisksAndPartitions": []]
    }

    private func usbInfo() -> [String: Any] {
        [
            "DeviceIdentifier": "disk4",
            "BusProtocol": "USB",
            "MediaName": "USB DISK 3.0",
            "VolumeName": "STICK",
            "TotalSize": 32_000_000_000,
            "Writable": true,
            "Removable": true,
            "MountPoint": "/Volumes/STICK",
            "Content": "DOS_FAT_32",
        ]
    }

    private func internalInfo() -> [String: Any] {
        [
            "DeviceIdentifier": "disk0",
            "BusProtocol": "Apple Fabric",
            "MediaName": "APPLE SSD AP1024Z",
            "TotalSize": 1_000_555_581_440,
            "Writable": true,
            "Removable": false,
        ]
    }

    func testOnlyUsbDisksAreKept() {
        let devices = Storage.parse(
            listing: listing("disk0", "disk4"),
            infos: ["disk0": internalInfo(), "disk4": usbInfo()]
        )
        XCTAssertEqual(devices.map(\.identifier), ["disk4"])
    }

    func testVolumeNameWinsOverMediaName() {
        let devices = Storage.parse(listing: listing("disk4"), infos: ["disk4": usbInfo()])
        XCTAssertEqual(devices[0].name, "STICK")
    }

    func testReadOnlyComesFromWritable() {
        var info = usbInfo()
        info["Writable"] = false
        let devices = Storage.parse(listing: listing("disk4"), infos: ["disk4": info])
        XCTAssertEqual(devices[0].readOnly, true)
    }

    func testReadOnlyFallsBackToMediaReadOnly() {
        var info = usbInfo()
        info.removeValue(forKey: "Writable")
        info["MediaReadOnly"] = true
        let devices = Storage.parse(listing: listing("disk4"), infos: ["disk4": info])
        XCTAssertEqual(devices[0].readOnly, true)
    }

    func testCapacityPrefersTotalSizeThenSize() {
        var info = usbInfo()
        info.removeValue(forKey: "TotalSize")
        info["Size"] = 16_000_000_000
        let devices = Storage.parse(listing: listing("disk4"), infos: ["disk4": info])
        XCTAssertEqual(devices[0].capacityBytes, 16_000_000_000)
    }

    func testRemovableFallsBackToRemovableMedia() {
        var info = usbInfo()
        info.removeValue(forKey: "Removable")
        info["RemovableMedia"] = true
        let devices = Storage.parse(listing: listing("disk4"), infos: ["disk4": info])
        XCTAssertEqual(devices[0].removable, true)
    }

    func testADiskWithoutInfoIsSkipped() {
        let devices = Storage.parse(
            listing: listing("disk4", "disk5"),
            infos: ["disk5": ["DeviceIdentifier": "disk5", "BusProtocol": "USB"]]
        )
        XCTAssertEqual(devices.map(\.identifier), ["disk5"])
    }

    func testOrderFollowsTheDiskList() {
        var disk4 = usbInfo()
        disk4["DeviceIdentifier"] = "disk4"
        var disk5 = usbInfo()
        disk5["DeviceIdentifier"] = "disk5"
        let devices = Storage.parse(
            listing: listing("disk5", "disk4"),
            infos: ["disk4": disk4, "disk5": disk5]
        )
        XCTAssertEqual(devices.map(\.identifier), ["disk5", "disk4"])
    }

    func testCapacityTextIsHumanReadable() {
        XCTAssertEqual(Format.bytes(32_000_000_000), "32.0 GB")
        XCTAssertEqual(Format.bytes(16_000_000), "16 MB")
        XCTAssertEqual(Format.bytes(4_000), "4 kB")
        XCTAssertEqual(Format.bytes(512), "512 B")
        XCTAssertNil(Format.bytes(nil))
        XCTAssertEqual(StorageDevice(identifier: "disk4", capacityBytes: 32_000_000_000).capacityText, "32.0 GB")
    }

    func testAStorageSourceWithAFailingRunnerIsEmpty() {
        let source = StorageSource(runner: { argv in
            CommandResult(argv: argv, returncode: 127, error: "diskutil not found")
        })
        let (devices, warnings) = source.inventory()
        XCTAssertTrue(devices.isEmpty)
        XCTAssertTrue(warnings.isEmpty)
    }
}
