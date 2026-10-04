import Foundation
import XCTest
import UsbScopeCore
@testable import UsbScopeUI

/// The pure presentation logic of the app's new tabs: the filter presets, the
/// timeline scaling, the security findings/storage rows with their eject rules,
/// the USB4 fabric tree and the baseline diff. No window server is involved.
final class AppTabTests: XCTestCase {
    private func snapshot() -> Snapshot { Fixtures.snapshot() }

    // MARK: - Filter presets

    func testFilterPresetAllPassesEveryRow() {
        XCTAssertEqual(FilterPreset.all.filter(portRows(snapshot())).count, 6)
        XCTAssertEqual(FilterPreset.all.filter(deviceRows(snapshot())).count, 1)
    }

    func testConnectedPresetKeepsOnlyConnectedPorts() {
        let rows = portRows(snapshot())
        let connected = FilterPreset.connected.filter(rows)
        XCTAssertEqual(connected.count, 2)
        XCTAssertEqual(Set(connected.map(\.id)), ["port:USB-C@1", "port:USB-C@3"])
    }

    func testHIDPresetKeepsTheHIDPortAndDevice() {
        // The fixture's YubiKey is a per-interface composite (class 0), so HID is
        // not knowable at device level — a synthetic class-3 device is the case
        // where the preset must fire.
        let hid = synthetic(deviceClass: 3)
        XCTAssertEqual(FilterPreset.hid.filter(portRows(hid)).map(\.id), ["port:USB-C@1"])
        XCTAssertEqual(FilterPreset.hid.filter(deviceRows(hid)).count, 1)
        // And the fixture honestly yields nothing: class 0 says the functions are
        // declared per interface, which macOS does not expose without a user client.
        XCTAssertTrue(FilterPreset.hid.filter(portRows(snapshot())).isEmpty)
    }

    func testStoragePresetIsEmptyWithoutMassStorage() {
        XCTAssertTrue(FilterPreset.storage.filter(portRows(snapshot())).isEmpty)
        XCTAssertTrue(FilterPreset.storage.filter(deviceRows(snapshot())).isEmpty)
        // A class-8 device is the storage case.
        let storage = synthetic(deviceClass: 8)
        XCTAssertEqual(FilterPreset.storage.filter(portRows(storage)).count, 1)
        XCTAssertEqual(FilterPreset.storage.filter(deviceRows(storage)).count, 1)
    }

    /// A minimal snapshot whose single (connected) port and bus carry one device
    /// of the requested USB base class.
    private func synthetic(deviceClass: Int) -> Snapshot {
        var port = UsbPort(description: "USB-C@1", kind: "USB-C")
        port.connected = true
        port.number = 1
        let device = UsbDevice(
            name: "Synthetic", vendor: "Test", vendorID: 0x1234, productID: 0x5678,
            deviceClass: deviceClass, deviceSubclass: 1, deviceProtocol: 1,
            className: USBRegistry.className(deviceClass)
        )
        port.devices = [device]
        return Snapshot(
            host: "test", osVersion: "1.0", seenAt: Date(timeIntervalSince1970: 0),
            ports: [port], buses: [Bus(name: "Bus", devices: [device])]
        )
    }

    func testCableAndPowerRowsAnswerOnlyWhatTheyKnow() {
        let cables = cableRows(snapshot())
        // The cables table carries no USB class, so the class presets never match…
        XCTAssertTrue(FilterPreset.hid.filter(cables).isEmpty)
        XCTAssertTrue(FilterPreset.storage.filter(cables).isEmpty)
        // …but a cable that is attached (not the dash) is "connected".
        XCTAssertEqual(FilterPreset.connected.filter(cables).count, cables.filter { $0.cable.text != "–" }.count)
        // Charging metrics are live readings, all "connected".
        XCTAssertEqual(FilterPreset.connected.filter(powerRows(snapshot())).count, powerRows(snapshot()).count)
    }

    func testPresetAndSearchAreCombined() {
        // A class-3 HID device named "Synthetic": the preset passes it and the
        // search narrows to it; a term that matches nothing wins over the preset.
        let rows = portRows(synthetic(deviceClass: 3))
        XCTAssertEqual(rows.filter {
            FilterPreset.hid.matches($0) && $0.searchText.contains("synthetic")
        }.map(\.id), ["port:USB-C@1"])
        XCTAssertTrue(rows.filter {
            FilterPreset.hid.matches($0) && $0.searchText.contains("impossible")
        }.isEmpty)
    }

    // MARK: - Timeline scaling

    func testTimelineGeometryIsEmptyWithoutMeasuredPoints() {
        let geometry = TimelineGeometry([])
        XCTAssertTrue(geometry.isEmpty)
        XCTAssertNil(geometry.rangeText)
        XCTAssertEqual(geometry.x(Date()), 0)
        XCTAssertEqual(geometry.y(10), 0.5)
    }

    func testATimelineWithoutChargingTelemetryLeavesItsGaps() {
        let timeline = [
            PowerPoint(at: Date(timeIntervalSince1970: 0), watts: nil),
            PowerPoint(at: Date(timeIntervalSince1970: 10), watts: 20),
        ]
        let geometry = TimelineGeometry(timeline)
        XCTAssertEqual(geometry.points.count, 1)
        XCTAssertEqual(geometry.minWatts, 20)
        XCTAssertEqual(geometry.maxWatts, 20)
    }

    func testTimelineGeometryMapsTimeAndWattsOntoTheUnitSquare() {
        let start = Date(timeIntervalSince1970: 1_000)
        let timeline = [
            PowerPoint(at: start, watts: 10),
            PowerPoint(at: start.addingTimeInterval(30), watts: 20),
            PowerPoint(at: start.addingTimeInterval(60), watts: 30),
        ]
        let geometry = TimelineGeometry(timeline)
        XCTAssertEqual(geometry.minWatts, 10)
        XCTAssertEqual(geometry.maxWatts, 30)
        XCTAssertEqual(geometry.span, 60)
        XCTAssertEqual(geometry.x(start), 0)
        XCTAssertEqual(geometry.x(start.addingTimeInterval(60)), 1)
        XCTAssertEqual(geometry.y(10), 0)
        XCTAssertEqual(geometry.y(30), 1)
        XCTAssertEqual(geometry.y(20), 0.5, accuracy: 1e-9)
        XCTAssertEqual(geometry.unitPoints.count, 3)
        XCTAssertEqual(geometry.unitPoints.first?.x, 0)
        XCTAssertEqual(geometry.unitPoints.last?.x, 1)
    }

    func testASinglePointIsCentredInsteadOfDividingByZero() {
        let geometry = TimelineGeometry([PowerPoint(at: Date(timeIntervalSince1970: 5), watts: 42)])
        XCTAssertFalse(geometry.isEmpty)
        XCTAssertEqual(geometry.span, 0)
        XCTAssertEqual(geometry.x(Date(timeIntervalSince1970: 999)), 0.5)
        XCTAssertEqual(geometry.y(42), 0.5)
    }

    // MARK: - Hotplug event rows

    func testEventRowsAreNewestFirstAndLimited() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            UsbEvent(kind: .attached, seenAt: base, key: "device:a", name: "Old"),
            UsbEvent(kind: .detached, seenAt: base.addingTimeInterval(60), key: "device:b", name: "New"),
            UsbEvent(
                kind: .attached, seenAt: base.addingTimeInterval(30), key: "device:c",
                name: "YubiKey", vendor: "Yubico", vendorID: 0x1050, productID: 0x0407
            ),
        ]
        let rows = eventRows(events)
        XCTAssertEqual(rows.map(\.name), ["New", "YubiKey", "Old"])
        XCTAssertEqual(rows[0].kind, "detached")
        XCTAssertFalse(rows[0].isAttach)
        XCTAssertTrue(rows[1].isAttach)
        XCTAssertEqual(rows[1].detail, "Yubico · 0x1050:0x0407")
        XCTAssertEqual(rows[1].time, TimelineFormat.clock.string(from: base.addingTimeInterval(30)))

        let limited = eventRows(events, limit: 1)
        XCTAssertEqual(limited.map(\.name), ["New"])
    }

    // MARK: - Security presentation

    func testTheHonestLimitsWordingMatchesTheCLI() {
        XCTAssertTrue(SecurityPresentation.honestLimits.hasPrefix("honest limits: the class triple is device level"))
        XCTAssertTrue(SecurityPresentation.honestLimits.contains("storage covers only whole disks whose diskutil BusProtocol is USB."))
        XCTAssertEqual(SecurityPresentation.headline, "Security posture — heuristic, not a verdict")
        XCTAssertEqual(SecurityPresentation.emptyStorageText, "no USB mass storage attached — a Mac without one is normal")
    }

    func testSeverityCountsAndFindingRows() {
        let report = Security.analyse(snapshot())
        XCTAssertFalse(report.isEmpty)
        let counts = SecurityPresentation.counts(report)
        XCTAssertEqual(counts.map(\.label), ["Warning", "Attention", "Info"])
        XCTAssertEqual(counts.reduce(0) { $0 + $1.count }, report.findings.count)

        let rows = SecurityPresentation.findingRows(report)
        XCTAssertEqual(rows.count, report.findings.count)
        XCTAssertEqual(rows.first?.rule, report.findings.first?.rule)
        XCTAssertEqual(rows.first?.severity, report.findings.first?.severity.rawValue)
        XCTAssertEqual(rows.first?.severityStyle, SecurityPresentation.style(report.findings.first!.severity))
    }

    func testEjectIsRefusedOnlyForAnUnusableBSDName() {
        func device(_ identifier: String) -> StorageDevice { StorageDevice(identifier: identifier, name: "X") }
        XCTAssertNil(SecurityPresentation.ejectDisabledReason(device("disk4")))
        XCTAssertNil(SecurityPresentation.ejectDisabledReason(device("disk12")))
        XCTAssertNotNil(SecurityPresentation.ejectDisabledReason(device("")))
        XCTAssertNotNil(SecurityPresentation.ejectDisabledReason(device("disk")))
        XCTAssertNotNil(SecurityPresentation.ejectDisabledReason(device("rdisk4")))
        XCTAssertNotNil(SecurityPresentation.ejectDisabledReason(device("diskX")))
    }

    func testEjectCommandRunsDiskutilOnTheWholeDisk() {
        let command = SecurityPresentation.ejectCommand(StorageDevice(identifier: "disk7"))
        XCTAssertNotNil(command)
        XCTAssertEqual(command?.dropFirst(), ["eject", "disk7"])
        XCTAssertTrue(command?.first?.hasSuffix("diskutil") ?? false)
        XCTAssertNil(SecurityPresentation.ejectCommand(StorageDevice(identifier: "notadisk")))
    }

    func testStorageRowsCarryModeMountAndEjectState() {
        let devices = [
            StorageDevice(identifier: "disk3", name: "Stick", capacityBytes: 32_000_000_000, readOnly: false, mountPoint: "/Volumes/Stick"),
            StorageDevice(identifier: "disk4", name: "Frozen", capacityBytes: 1_000_000_000, readOnly: true, mountPoint: nil),
        ]
        let rows = SecurityPresentation.storageRows(devices)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].mode, "read/write")
        XCTAssertEqual(rows[0].mount, "/Volumes/Stick")
        XCTAssertTrue(rows[0].ejectEnabled)
        XCTAssertNotNil(rows[0].ejectCommand)
        XCTAssertEqual(rows[1].mode, "read-only")
        XCTAssertEqual(rows[1].mount, "–")
        XCTAssertTrue(rows[1].ejectEnabled)  // an unmounted disk can still be ejected
    }

    // MARK: - USB4 fabric tree

    func testFabricTreeNestsPortsAndTunnelsUnderRouters() {
        let fabric = snapshot().thunderboltFabric
        XCTAssertFalse(fabric.routers.isEmpty)
        let rows = FabricPresentation.rows(fabric)
        XCTAssertEqual(rows.first?.kind, .router)
        XCTAssertEqual(rows.first?.depth, 0)

        // Every router contributes at least one port row at depth 1.
        let routerIndices = fabric.routers.indices
        for index in routerIndices {
            XCTAssertTrue(rows.contains { $0.id.hasPrefix("router:\(index):port:") })
        }
        // A tunnel nested under a named port sits one level deeper.
        for row in rows where row.kind == .tunnel && row.id.split(separator: ":").count == 4 {
            XCTAssertGreaterThanOrEqual(row.depth, 1)
        }
        XCTAssertEqual(FabricPresentation.summary(fabric), "\(fabric.routers.count) router(s) · \(fabric.ports.count) port(s) · \(fabric.tunnels.count) tunnel(s)")
    }

    func testLinkTextKeepsTheRawLinkValuesVerbatim() {
        let port = ThunderboltFabricPort(
            label: "PCIe Adapter", protocolName: "pcie", number: 1,
            currentLinkSpeed: 2, targetLinkSpeed: 2, supportedLinkSpeed: 3,
            currentLinkWidth: 1, targetLinkWidth: 1, supportedLinkWidth: 1
        )
        XCTAssertEqual(FabricPresentation.linkText(port), "speed cur/tgt/sup 2/2/3 · width cur/tgt/sup 1/1/1")
        // Unknown values become the dash, never a guessed zero.
        let bare = ThunderboltFabricPort(label: "Thunderbolt Port", protocolName: "thunderbolt")
        XCTAssertEqual(FabricPresentation.linkText(bare), "–")
        XCTAssertTrue(FabricPresentation.rawLinkNote.contains("raw enumerations"))
    }

    // MARK: - Baseline diff

    func testDiffRowsOrderAppearedThenDisappearedThenChanged() {
        var changes = ChangeSet()
        changes.added = [UsbDevice(name: "Stick", vendor: "SanDisk", vendorID: 0x0781, productID: 0x5567)]
        changes.removed = [UsbDevice(name: "Mouse", vendor: "Logitech")]
        changes.changedPorts = ["port:USB-C@3"]
        let rows = DiffPresentation.rows(changes)
        XCTAssertEqual(rows.map(\.kind), [.appeared, .disappeared, .changed])
        XCTAssertEqual(rows[0].item, "SanDisk Stick")
        XCTAssertTrue(rows[0].detail.contains("0x0781:0x5567"))
        XCTAssertEqual(rows[2].item, "USB-C@3")
        XCTAssertEqual(DiffPresentation.summary(changes), "1 appeared · 1 disappeared · 1 changed")
        XCTAssertEqual(DiffPresentation.counts(changes).map(\.count), [1, 1, 1])
    }

    func testAnEmptyChangeSetHasNoRows() {
        XCTAssertTrue(DiffPresentation.rows(ChangeSet()).isEmpty)
        XCTAssertEqual(DiffPresentation.summary(ChangeSet()), "0 appeared · 0 disappeared · 0 changed")
    }
}

/// `filter` as a free helper so the tests read like production.
private extension FilterPreset {
    func filter<T: PresetFilterable>(_ rows: [T]) -> [T] { rows.filter { matches($0) } }
}
