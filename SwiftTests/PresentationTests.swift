import Foundation
import XCTest
@testable import UsbScopeCore
@testable import UsbScopeUI

/// The presentation layer (the twin of `macapp/viewmodel.py` + `changes.py` +
/// `tableops.py`), verified against the same fixtures.
final class PresentationTests: XCTestCase {
    private func snapshot() -> Snapshot { Fixtures.snapshot() }

    // MARK: - Columns (must match the column titles the CLI prints)

    func testColumnTitlesMatchTheCLITables() {
        XCTAssertEqual(Presentation.headers(for: .ports), ["Port", "Type", "State", "Mode", "Transports", "Cable", "Notes"])
        XCTAssertEqual(
            Presentation.headers(for: .cables),
            ["Port", "Cable", "CC authentication", "Hash (CC / USB)", "PD spec", "Power in", "Contract", "Liquid", "Controller fw"]
        )
        XCTAssertEqual(
            Presentation.headers(for: .devices),
            ["Device", "Vendor", "VID:PID", "Mode", "Class", "Tier", "Port", "Transport", "Serial", "Restricted"]
        )
        XCTAssertEqual(Presentation.headers(for: .thunderbolt), ["Bus", "Receptacle", "State", "Link", "Host / vendor"])
        XCTAssertEqual(Presentation.headers(for: .power), ["Metric", "Value"])
    }

    func testEveryRowCarriesTheSameNumberOfCellsAsColumns() {
        let snapshot = snapshot()
        for view in AppView.allCases {
            let headers = Presentation.headers(for: view)
            for row in Presentation.tableRows(for: view, snapshot: snapshot) {
                XCTAssertEqual(row.cells.count, headers.count, "\(view) row \(row.id)")
            }
        }
    }

    // MARK: - Ports

    func testPortRows() {
        let rows = portRows(snapshot())
        XCTAssertEqual(rows.count, 6)
        let usbC3 = try? XCTUnwrap(rows.first { $0.id == "port:USB-C@3" })
        XCTAssertEqual(usbC3?.state.text, "● connected")
        XCTAssertEqual(usbC3?.state.style, .green)
        XCTAssertEqual(usbC3?.mode.text, "USB 1.1 Full-Speed · 12 Mbit/s")
        XCTAssertEqual(usbC3?.mode.style, .yellow)  // rank 2 → yellow, like the Python viewmodel
        XCTAssertEqual(usbC3?.cable.text, "unknown")
        XCTAssertTrue(usbC3?.notes.text.contains("1 device(s): YubiKey OTP+FIDO+CCID") ?? false)
        XCTAssertEqual(usbC3?.nameSort, 3)

        // a free port is dim, has no USB data and sorts below the connected one
        let hdmi = try? XCTUnwrap(rows.first { $0.id == "port:HDMI@1" })
        XCTAssertEqual(hdmi?.state.text, "○ free")
        XCTAssertEqual(hdmi?.kind.style, .dim)
    }

    func testCommonTableStatesCanBeLocalizedWithoutChangingDefaultCLIText() throws {
        let germanPorts = portRows(snapshot(), language: .de)
        let connected = try XCTUnwrap(germanPorts.first { $0.id == "port:USB-C@3" })
        XCTAssertEqual(connected.state.text, "● verbunden")
        XCTAssertTrue(connected.notes.text.contains("Gerät(e)"))

        let germanCables = cableRows(snapshot(), language: .de)
        let cable = try XCTUnwrap(germanCables.first { $0.id == "port:USB-C@3" })
        XCTAssertEqual(cable.liquid.text, "sauber")

        let germanDevices = deviceRows(snapshot(), language: .de)
        XCTAssertEqual(germanDevices.first?.restricted.text, "nein")
    }

    // MARK: - Cables

    func testCableRows() {
        let rows = cableRows(snapshot())
        XCTAssertEqual(rows.count, 6)
        let usbC3 = try? XCTUnwrap(rows.first { $0.id == "port:USB-C@3" })
        XCTAssertEqual(usbC3?.cable.text, "unknown")
        XCTAssertEqual(usbC3?.authentication.text, "Idle")
        XCTAssertEqual(usbC3?.hash.text, "Not Set")
        XCTAssertEqual(usbC3?.liquid.text, "clean")
        XCTAssertNotNil(usbC3?.firmware.text)

        let usbC1 = try? XCTUnwrap(rows.first { $0.id == "port:USB-C@1" })
        XCTAssertEqual(usbC1?.contract.text, "20 V · 5 A · 100 W")
        XCTAssertEqual(usbC1?.contract.style, .cyan)
    }

    // MARK: - Devices

    func testDeviceRows() {
        let rows = deviceRows(snapshot())
        XCTAssertEqual(rows.count, 1)
        let device = rows[0]
        XCTAssertEqual(device.idString.text, "0x1050:0x0407")
        XCTAssertEqual(device.mode.text, "USB 1.1 Full-Speed · 12 Mbit/s")
        XCTAssertEqual(device.deviceClass.text, "per-interface")
        XCTAssertEqual(device.tier.text, "1")
        XCTAssertEqual(device.port.text, "USB-C@3")
        XCTAssertEqual(device.restricted.text, "no")
    }

    /// HID and storage get the attention colours of the security check.
    func testDeviceClassStyles() {
        XCTAssertEqual(deviceClassStyle("HID (3/1/1)"), .cyan)
        XCTAssertEqual(deviceClassStyle("mass storage (8/6/80)"), .magenta)
        XCTAssertEqual(deviceClassStyle("hub (9/0/1)"), .dim)
        XCTAssertEqual(deviceClassStyle("per-interface"), .dim)
        XCTAssertEqual(deviceClassStyle("audio (1/0/0)"), .default)
    }

    // MARK: - Thunderbolt & power

    func testThunderboltRows() {
        let rows = thunderboltRows(snapshot())
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.state.text == "○ free" })
    }

    func testPowerRows() {
        let rows = powerRows(snapshot())
        let labels = rows.map(\.metric.text)
        // "Charger" is dropped while macOS reports no charger problem (0 flags),
        // exactly like `viewmodel._pair` drops an empty value.
        XCTAssertEqual(labels, ["Status", "Adapter", "From adapter", "System load", "Battery", "Adapter loss"])
        // the live status of a charging machine is green
        XCTAssertEqual(rows.first?.value.style, .green)
    }

    // MARK: - Details

    func testPortDetailsAndCableDetails() throws {
        let port = try XCTUnwrap(snapshot().ports.first { $0.name == "USB-C@3" })
        let pairs = Dictionary(uniqueKeysWithValues: Presentation.portDetails(port))
        XCTAssertEqual(pairs["Type"], "USB-C")
        XCTAssertEqual(pairs["Connected"], "yes")
        XCTAssertEqual(pairs["Pin assignment"], "rx2=4, tx2=3")
        XCTAssertEqual(pairs["Power mode"], "1")
        XCTAssertEqual(pairs["Supported power modes"], "1, 3")
        XCTAssertEqual(pairs["Liquid state"], "Idle")

        let cablePairs = Dictionary(uniqueKeysWithValues: Presentation.cableDetails(port))
        XCTAssertEqual(cablePairs["Cable"], "unknown")
        XCTAssertEqual(cablePairs["USB link"], "USB 1.1 Full-Speed · 12 Mbit/s")
    }

    func testDeviceDetails() throws {
        let device = try XCTUnwrap(snapshot().devices.first)
        let pairs = Dictionary(uniqueKeysWithValues: Presentation.deviceDetails(device))
        XCTAssertEqual(pairs["VID:PID"], "0x1050:0x0407")
        XCTAssertEqual(pairs["Port"], "USB-C@3")
        XCTAssertEqual(pairs["Location ID"], "0x01100000")
    }

    func testDetailsForARowKey() {
        let snapshot = snapshot()
        XCTAssertFalse(Presentation.details(snapshot, view: .ports, rowKey: "port:USB-C@3").isEmpty)
        XCTAssertEqual(Presentation.details(snapshot, view: .power, rowKey: "power:Status").count, 1)
        XCTAssertTrue(Presentation.details(snapshot, view: .ports, rowKey: "port:nope").isEmpty)
    }

    // MARK: - Header / status

    func testHeaderAndSummary() {
        let snapshot = snapshot()
        XCTAssertEqual(Presentation.headerText(snapshot), "usbscope — MacBook Pro · Apple M3 Pro · macOS 27.0.1")
        XCTAssertEqual(
            Presentation.summaryText(snapshot),
            "6 ports · 2 connected · 1 device(s) · 0 e-marked cable(s) · 3 USB4 receptacle(s)"
        )
        XCTAssertTrue(Presentation.statusText(snapshot, interval: 5, reads: 1, changes: nil).contains("auto-refresh 5s"))
        XCTAssertTrue(Presentation.statusText(snapshot, interval: nil, reads: 2, changes: nil).contains("auto-refresh off"))
    }

    // MARK: - Text exports

    func testTSVAndCSV() {
        let snapshot = snapshot()
        let tsv = Presentation.tsv(for: .ports, snapshot: snapshot)
        let lines = tsv.split(separator: "\n")
        XCTAssertEqual(lines.count, 7)  // header + 6 ports
        XCTAssertEqual(lines[0], "Port\tType\tState\tMode\tTransports\tCable\tNotes")

        let csv = Presentation.csv(for: .devices, snapshot: snapshot)
        XCTAssertTrue(csv.hasPrefix("Device,Vendor,VID:PID,Mode,Class,Tier,Port,Transport,Serial,Restricted"))
        XCTAssertTrue(csv.contains("YubiKey OTP+FIDO+CCID"))
    }

    // MARK: - Diffing

    private func makePort(_ name: String, connected: Bool, devices: [UsbDevice]) -> UsbPort {
        var port = UsbPort(description: "Port-\(name)", kind: "USB-C")
        port.connected = connected
        port.number = 1
        port.devices = devices
        return port
    }

    func testDiffSnapshotsDetectsAddedAndRemovedDevices() {
        let yubikey = UsbDevice(name: "YubiKey", vendor: "Yubico", vendorID: 0x1050, productID: 0x0407, locationID: 0x01100000)
        let keyboard = UsbDevice(name: "Keyboard", vendor: "Acme", vendorID: 0x1234, productID: 0x0001, locationID: 0x01200000)

        let previous = Snapshot(
            host: "mac", osVersion: "27.0.1", seenAt: Date(timeIntervalSince1970: 0),
            ports: [makePort("USB-C@1", connected: false, devices: [yubikey])]
        )
        let current = Snapshot(
            host: "mac", osVersion: "27.0.1", seenAt: Date(timeIntervalSince1970: 1),
            ports: [makePort("USB-C@1", connected: true, devices: [keyboard])]
        )
        let changes = diffSnapshots(previous: previous, current: current)
        XCTAssertEqual(changes.added.map(\.name), ["Keyboard"])
        XCTAssertEqual(changes.removed.map(\.name), ["YubiKey"])
        XCTAssertEqual(changes.changedPorts, ["port:USB-C@1"])
        XCTAssertEqual(changes.summary, "1 added · 1 removed · 1 port state changed")
        XCTAssertEqual(highlight(for: changes.tag("port:USB-C@1")), .changed)
        XCTAssertEqual(highlight(for: changes.tag(deviceKey(keyboard))), .added)
    }

    func testFirstReadIsNotAPlugEvent() {
        XCTAssertTrue(diffSnapshots(previous: nil, current: snapshot()).isEmpty)
    }

    func testRowHighlightIsAppliedToMatchingRows() {
        var changes = ChangeSet()
        changes.changedPorts = ["port:USB-C@3"]
        let rows = portRows(snapshot(), changes: changes)
        XCTAssertEqual(rows.first { $0.id == "port:USB-C@3" }?.highlight, .changed)
        XCTAssertNil(rows.first { $0.id == "port:HDMI@1" }?.highlight)
    }

    // MARK: - Search

    func testSearchTextCoversEveryCell() {
        let device = deviceRows(snapshot())[0]
        XCTAssertTrue(device.searchText.contains("yubico"))
        XCTAssertTrue(device.searchText.contains("0x1050:0x0407"))
    }
}
