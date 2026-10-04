import Foundation
import UsbScopeCore

/// Header, status bar, detail pairs and the text exports — the twin of the
/// `viewmodel`/`tableops` helpers that the app layer uses.
public enum Presentation {
    // MARK: - Header & status

    /// Window title: model, chip and macOS version.
    public static func headerText(_ snapshot: Snapshot, language: AppLanguage = .en) -> String {
        var parts = [snapshot.model, snapshot.chip].compactMap { $0 }
        if !snapshot.osVersion.isEmpty { parts.append("macOS \(snapshot.osVersion)") }
        let tail = parts.isEmpty ? snapshot.host : parts.joined(separator: " · ")
        return "usbscope — \(tail)"
    }

    /// One line of headline facts below the toolbar.
    public static func summaryText(_ snapshot: Snapshot, language: AppLanguage = .en) -> String {
        if language == .de {
            return "\(snapshot.ports.count) Anschlüsse · \(snapshot.connectedPorts.count) verbunden · "
                + "\(snapshot.devices.count) Gerät(e) · \(snapshot.emarkedCables.count) e-markierte Kabel · "
                + "\(snapshot.thunderbolt.count) USB4-Anschlüsse"
        }
        return "\(snapshot.ports.count) ports · \(snapshot.connectedPorts.count) connected · "
            + "\(snapshot.devices.count) device(s) · \(snapshot.emarkedCables.count) e-marked cable(s) · "
            + "\(snapshot.thunderbolt.count) USB4 receptacle(s)"
    }

    /// Status bar line: last read, cadence, changes and source problems.
    public static func statusText(
        _ snapshot: Snapshot,
        interval: Double?,
        reads: Int,
        changes: ChangeSet?,
        filterQuery: String = "",
        language: AppLanguage = .en
    ) -> String {
        let time = timeFormatter.string(from: snapshot.seenAt)
        if language == .de {
            var parts = ["Gelesen um \(time) (Lesevorgang Nr. \(reads))"]
            parts.append(interval.map { "automatisch \(Format.g($0)) s" } ?? "automatisch aus")
            parts.append("system_profiler + ioreg (IOPort, AppleSmartBattery)")
            if let changes, !changes.isEmpty { parts.append("geändert: \(changes.summary)") }
            if !filterQuery.isEmpty { parts.append("Filter: '\(filterQuery)'") }
            if !snapshot.warnings.isEmpty {
                parts.append("\(snapshot.warnings.count) Warnung(en): \(snapshot.warnings[0])")
            }
            return parts.joined(separator: "  ·  ")
        }

        var parts = ["Read at \(time) (read #\(reads))"]
        parts.append(interval.map { "auto-refresh \(Format.g($0))s" } ?? "auto-refresh off")
        parts.append("system_profiler + ioreg (IOPort, AppleSmartBattery)")
        if let changes, !changes.isEmpty { parts.append("changed: \(changes.summary)") }
        if !filterQuery.isEmpty { parts.append("filter: '\(filterQuery)'") }
        if !snapshot.warnings.isEmpty {
            parts.append("\(snapshot.warnings.count) warning(s): \(snapshot.warnings[0])")
        }
        return parts.joined(separator: "  ·  ")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - Detail pairs

    private static func pair(_ label: String, _ value: String?) -> (String, String)? {
        guard let value, !value.isEmpty else { return nil }
        return (label, value)
    }

    private static func pair(_ label: String, _ value: Int?) -> (String, String)? {
        value.map { (label, String($0)) }
    }

    private static func pair(_ label: String, _ value: Bool?) -> (String, String)? {
        value.map { (label, $0 ? "yes" : "no") }
    }

    private static func pairs(_ items: [(String, String)?]) -> [(String, String)] {
        items.compactMap { $0 }
    }

    private static func list(_ values: [Int]) -> String {
        values.map(String.init).joined(separator: ", ")
    }

    /// `3 / 1 / 1` for a device whose class is declared at device level.
    private static func classTriple(_ device: UsbDevice) -> String? {
        guard let value = device.deviceClass, value != 0 else { return nil }
        let sub = device.deviceSubclass.map(String.init) ?? "?"
        let proto = device.deviceProtocol.map(String.init) ?? "?"
        return "\(value) / \(sub) / \(proto)"
    }

    /// Summary of a provider's PD menu: count, voltage range, ceiling, PDO types.
    static func powerMenuPair(_ source: PowerSource) -> (String, String)? {
        guard !source.options.isEmpty else { return nil }
        let volts = source.options.compactMap(\.voltageMv)
        let watts = source.options.compactMap(\.watts)
        let kinds = Set(source.options.compactMap(\.kindLabel)).sorted()
        var parts = ["\(source.options.count) option(s)"]
        if let low = volts.min(), let high = volts.max() {
            parts.append("\(low / 1000)–\(high / 1000) V")
        }
        if let top = watts.max() { parts.append("up to \(Format.g(top)) W") }
        if !kinds.isEmpty { parts.append(kinds.joined(separator: ", ")) }
        return ("PD menu", parts.joined(separator: " · "))
    }

    private static func extraPairs(_ port: UsbPort) -> [(String, String)] {
        let contract = port.powerContract
        let limits = port.powerCurrentLimits
        var items: [(String, String)?] = [
            pair("USB mode", port.usbModeText),
            pair("Pin assignment", port.pinsText.isEmpty ? nil : port.pinsText),
            pair("Accessory mode", port.accessoryMode.flatMap { $0 != 0 ? $0 : nil }),
            pair("Power contract", contract?.label),
            pair("Power mode", port.powerMode),
            pair("Active power mode", port.activePowerMode),
            pair("Supported power modes", port.supportedPowerModes.isEmpty ? nil : list(port.supportedPowerModes)),
            pair("Power current limits", limits.contains(where: { $0 != 0 }) ? list(limits) : nil),
        ]
        if !port.powerSources.isEmpty {
            items.append(pair("Power sources", port.powerSources.map(\.name).joined(separator: ", ")))
            items.append(pair("Selected source", port.powerSources.first { $0.selected }?.name))
            if let selected = port.powerSources.first(where: { $0.selected }) {
                items.append(powerMenuPair(selected))
            }
            for source in port.powerSources {
                for (index, option) in source.options.enumerated() {
                    let kind = option.kindLabel
                    let suffix = (kind != nil && kind != "fixed") ? " (\(kind!))" : ""
                    items.append(pair("\(source.name) option \(index + 1)", option.label + suffix))
                }
            }
        }
        items.append(pair("Liquid state", port.liquidState))
        items.append(pair("Liquid measurement", port.liquidMeasurement))
        items.append(pair("Liquid pin", port.liquidPin))
        items.append(pair("Liquid mitigations", port.liquidMitigations))
        items.append(pair("Liquid override", port.liquidOverride))
        return pairs(items)
    }

    /// Every known fact about a port, as label/value pairs.
    public static func portDetails(_ port: UsbPort) -> [(String, String)] {
        let transport = port.usbTransport
        let cable = port.cable
        let transfers = port.transports
            .map { "\($0.kind) \($0.active ? "active" : "idle")" }
            .joined(separator: " · ")
        var items: [(String, String)?] = [
            pair("Port", port.name),
            pair("Description", port.description),
            pair("Type", port.kind),
            pair("Connected", port.connected),
            pair("Number", port.number),
            pair("Connect type", port.connectType),
            pair("USB link", transport?.mode.label),
            pair("Advertised modes", port.advertisedModes.map(\.label).joined(separator: " · ")),
            pair("Negotiated mode", port.negotiatedMode.label),
            pair("Maximum observed rate", port.maximumObservedRate.map { Format.g($0) + " Mbit/s" }),
            pair("USB link active", transport?.active),
            pair("USB speed", transport?.rateText),
            pair("Super speed active", port.superSpeedActive),
            pair("Transports", transfers),
            pair("Cable", cable.attached ? cable.kind : nil),
            pair("e-marker", cable.attached ? cable.emarker : nil),
            pair("Cable authentication", cable.authentication),
            pair("Cable hash", cable.hashStatus),
            pair("PD specification", cable.pdSpecRevision),
            pair("Power in", port.powerIn.joined(separator: ", ")),
            pair("Liquid detected", port.liquidDetected),
            pair("Authorization", port.authorization),
            pair("Controller firmware", port.firmware),
            pair("DisplayPort pin assignment", port.displayPortPinAssignment),
            pair("Plug orientation", port.plugOrientation),
            pair("Devices", port.devices.map { "\($0.name) (\($0.idString))" }.joined(separator: ", ")),
        ]
        items.append(contentsOf: extraPairs(port).map { Optional($0) })
        return pairs(items)
    }

    /// Cable/port-controller facts (the cables view) as label/value pairs.
    public static func cableDetails(_ port: UsbPort) -> [(String, String)] {
        let cable = port.cable
        let usb = port.usbTransport
        var items: [(String, String)?] = [
            pair("Port", port.name),
            pair("Cable", cable.attached ? cable.kind : nil),
            pair("e-marker", cable.attached ? cable.emarker : nil),
            pair("Active cable", cable.attached ? cable.active : nil),
            pair("Optical", cable.attached ? cable.optical : nil),
            pair("CC authentication", cable.authentication),
            pair("Cable hash", cable.hashStatus),
            pair("USB3 hash", usb?.hashStatus),
            pair("PD specification", cable.pdSpecRevision),
            pair("Power in", port.powerIn.joined(separator: ", ")),
            pair("Liquid detected", port.liquidDetected),
            pair("Authorization", port.authorization),
            pair("Controller firmware", port.firmware),
            pair("USB link", usb?.mode.label),
        ]
        items.append(contentsOf: extraPairs(port).map { Optional($0) })
        return pairs(items)
    }

    /// Every known fact about a device as label/value pairs.
    public static func deviceDetails(_ device: UsbDevice) -> [(String, String)] {
        var details = pairs([
            pair("Device", device.label),
            pair("Vendor", device.vendor),
            pair("VID:PID", device.idString),
            pair("USB link", device.mode.label),
            pair("Device class", device.classText),
            pair("Class / subclass / protocol", classTriple(device)),
            pair("USB specification", device.bcdUsb),
            pair("Control packet size", device.maxPacketSize0),
            pair("Configurations", device.numConfigurations),
            pair("Enumeration speed", USBRegistry.speedCodeName(device.speedCode)),
            pair("Hub tier", device.tier),
            pair("Parent hub", device.parent),
            pair("Device address", device.address),
            pair("Speed", device.speedText),
            pair("Mode (bit/s)", device.speedMbps.map { Format.g($0) }),
            pair("Port", device.port),
            pair("Port type", device.portType),
            pair("Transport", device.transport),
            pair("Bus", device.bus),
            pair("Connection", device.connection),
            pair("Device version", device.version),
            pair("Generation", device.generation),
            pair("Serial", device.serial),
            pair("Location ID", device.locationID.flatMap { $0 != 0 ? String(format: "0x%08x", $0) : nil }),
            pair("Restricted by macOS", device.restricted),
            pair("Source", device.source),
            pair("Provenance", device.fieldProvenance
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value.rawValue)" }
                .joined(separator: ", ")),
        ])
        // The interface level: one row per interface, since a composite device
        // declares its functions there and `endpoints` is the count macOS publishes.
        if !device.interfaces.isEmpty {
            details.append(("Interfaces", "\(device.interfaces.count)"))
            for interface in device.interfaces {
                details.append((interface.label, interfaceDetail(interface)))
            }
        }
        return details
    }

    /// `HID (3/1/1) · 2 endpoint(s) · config 1` — how one interface reads.
    public static func interfaceDetail(_ interface: DeviceInterface) -> String {
        var parts = [interface.classText ?? "class unknown"]
        if let endpoints = interface.endpoints { parts.append("\(endpoints) endpoint(s)") }
        if let configuration = interface.configuration { parts.append("config \(configuration)") }
        return parts.joined(separator: " · ")
    }

    /// Thunderbolt receptacle facts as label/value pairs.
    public static func thunderboltDetails(_ port: ThunderboltPort) -> [(String, String)] {
        pairs([
            pair("Bus", port.bus),
            pair("Receptacle", port.receptacle),
            pair("Connected", port.connected),
            pair("Status", port.status),
            pair("Link", port.speed),
            pair("Device", port.device),
            pair("Vendor", port.vendor),
        ])
    }

    /// Detail pairs for the object a table row stands for (keyed by the row id).
    public static func details(_ snapshot: Snapshot, view: AppView, rowKey: String,
                               language: AppLanguage = .en) -> [(String, String)] {
        switch view {
        case .cables:
            let name = String(rowKey.dropFirst("port:".count))
            guard let port = snapshot.ports.first(where: { $0.name == name }) else { return [] }
            return cableDetails(port)
        case .power:
            let label = String(rowKey.dropFirst("power:".count))
            guard let charging = snapshot.charging else { return [] }
            return chargingPairs(charging, language: language).filter { $0.0 == label }.map { ($0.0, $0.1) }
        default:
            if rowKey.hasPrefix("device:") {
                return snapshot.devices.first { deviceKey($0) == rowKey }.map(deviceDetails) ?? []
            }
            if rowKey.hasPrefix("tb:") {
                return snapshot.thunderbolt.first { thunderboltKey($0) == rowKey }.map(thunderboltDetails) ?? []
            }
            if rowKey.hasPrefix("port:") {
                let name = String(rowKey.dropFirst("port:".count))
                return snapshot.ports.first { $0.name == name }.map(portDetails) ?? []
            }
            return []
        }
    }

    // MARK: - Text exports

    /// Column titles of a view, matching the table columns.
    public static func headers(for view: AppView) -> [String] {
        switch view {
        case .ports: ["Port", "Type", "State", "Mode", "Transports", "Cable", "Notes"]
        case .cables: ["Port", "Cable", "CC authentication", "Hash (CC / USB)", "PD spec", "Power in", "Contract", "Liquid", "Controller fw"]
        case .devices: ["Device", "Vendor", "VID:PID", "Mode", "Class", "Tier", "Port", "Transport", "Serial", "Restricted"]
        case .thunderbolt: ["Bus", "Receptacle", "State", "Link", "Host / vendor"]
        case .power: ["Metric", "Value"]
        case .timeline: []          // a graph, not a table — nothing to export
        case .security: ["Severity", "Rule", "Subject", "Why"]
        case .usb4: ["Kind", "Level", "Item", "Detail"]
        case .diff: []              // depends on the loaded baseline, not the snapshot
        case .warnings: ["Source", "Severity", "Field", "Message", "Remediation"]
        }
    }

    /// Every row of a view as `(row id, cell texts)`.
    public static func tableRows(for view: AppView, snapshot: Snapshot) -> [(id: String, cells: [String])] {
        switch view {
        case .ports:
            return portRows(snapshot).map { ($0.id, [$0.name.text, $0.kind.text, $0.state.text, $0.mode.text, $0.transports.text, $0.cable.text, $0.notes.text]) }
        case .cables:
            return cableRows(snapshot).map { ($0.id, [$0.port.text, $0.cable.text, $0.authentication.text, $0.hash.text, $0.spec.text, $0.powerIn.text, $0.contract.text, $0.liquid.text, $0.firmware.text]) }
        case .devices:
            return deviceRows(snapshot).map { ($0.id, [$0.name.text, $0.vendor.text, $0.idString.text, $0.mode.text, $0.deviceClass.text, $0.tier.text, $0.port.text, $0.transport.text, $0.serial.text, $0.restricted.text]) }
        case .thunderbolt:
            return thunderboltRows(snapshot).map { ($0.id, [$0.bus.text, $0.receptacle.text, $0.state.text, $0.link.text, $0.host.text]) }
        case .power:
            return powerRows(snapshot).map { ($0.id, [$0.metric.text, $0.value.text]) }
        case .security:
            return SecurityPresentation.findingRows(Security.analyse(snapshot)).map {
                ($0.id, [$0.severity, $0.rule, $0.subject, $0.detail])
            }
        case .usb4:
            return FabricPresentation.rows(snapshot.thunderboltFabric).map {
                ($0.id, [$0.kind.rawValue, String($0.depth), $0.title, [$0.detail, $0.rawLink].compactMap { $0 }.joined(separator: " · ")])
            }
        case .warnings:
            return WarningPresentation.rows(snapshot.warnings).map {
                ($0.id, [$0.source, $0.severity, $0.field, $0.message, $0.remediation])
            }
        case .timeline, .diff:
            return []
        }
    }

    /// Column titles and cell texts per view, matching the table columns.
    public static func tableText(for view: AppView, snapshot: Snapshot) -> (headers: [String], rows: [[String]]) {
        (headers(for: view), tableRows(for: view, snapshot: snapshot).map(\.cells))
    }

    /// Tab separated text for the clipboard.
    public static func tsv(for view: AppView, snapshot: Snapshot, header: Bool = true) -> String {
        let table = tableText(for: view, snapshot: snapshot)
        var lines: [String] = []
        if header { lines.append(table.headers.joined(separator: "\t")) }
        lines.append(contentsOf: table.rows.map { $0.map(clean).joined(separator: "\t") })
        return lines.joined(separator: "\n")
    }

    /// CSV (RFC 4180 quoting) for the export menu.
    public static func csv(for view: AppView, snapshot: Snapshot, header: Bool = true) -> String {
        let table = tableText(for: view, snapshot: snapshot)
        var lines: [String] = []
        if header { lines.append(table.headers.map(quote).joined(separator: ",")) }
        lines.append(contentsOf: table.rows.map { $0.map { quote(clean($0)) }.joined(separator: ",") })
        return lines.joined(separator: "\n")
    }

    /// Make a cell safe for a single line.
    private static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func quote(_ text: String) -> String {
        text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
            ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : text
    }
}

// MARK: - Search

/// A row that can be searched by text.
public protocol Searchable {
    var searchText: String { get }
}

extension PortRow: Searchable {
    /// Every cell's text, lowercased — the haystack for the search field.
    public var searchText: String {
        [name.text, kind.text, state.text, mode.text, transports.text, cable.text, notes.text]
            .joined(separator: " ").lowercased()
    }
}

extension CableRow: Searchable {
    public var searchText: String {
        [port.text, cable.text, authentication.text, hash.text, spec.text, powerIn.text, contract.text, liquid.text, firmware.text]
            .joined(separator: " ").lowercased()
    }
}

extension DeviceRow: Searchable {
    public var searchText: String {
        [name.text, vendor.text, idString.text, mode.text, deviceClass.text, tier.text, port.text, transport.text, serial.text, restricted.text]
            .joined(separator: " ").lowercased()
    }
}

extension ThunderboltRow: Searchable {
    public var searchText: String {
        [bus.text, receptacle.text, state.text, link.text, host.text].joined(separator: " ").lowercased()
    }
}

extension PowerRow: Searchable {
    public var searchText: String {
        [metric.text, value.text].joined(separator: " ").lowercased()
    }
}
