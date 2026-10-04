import Foundation
import UsbScopeCore

/// A cell's text plus its semantic style — the Swift twin of `viewmodel.Cell`.
public struct StyledText: Hashable, Sendable {
    public let text: String
    public let style: CellStyle

    public init(_ text: String, _ style: CellStyle = .default) {
        self.text = text
        self.style = style
    }
}

private let dash = StyledText("–", .dim)

private func modeStyle(_ mode: UsbMode) -> CellStyle {
    switch mode.rank {
    case 7...: .magenta
    case 4...: .cyan
    case 3: .green
    case 1...: .yellow
    default: .dim
    }
}

private func stateCell(connected: Bool, language: AppLanguage = .en) -> (StyledText, Int) {
    if connected {
        return (StyledText(language == .de ? "● verbunden" : "● connected", .green), 1)
    }
    return (StyledText(language == .de ? "○ frei" : "○ free", .dim), 0)
}

private func modeCell(_ port: UsbPort, language: AppLanguage = .en) -> (StyledText, Int) {
    guard let transport = port.usbTransport, transport.active else {
        return port.connected
            ? (StyledText(language == .de ? "keine USB-Daten" : "no USB data", .yellow), -1)
            : (dash, -2)
    }
    return (StyledText(transport.mode.label, modeStyle(transport.mode)), transport.mode.rank)
}

private func transportsCell(_ port: UsbPort, language: AppLanguage = .en) -> StyledText {
    guard !port.transports.isEmpty else { return dash }
    let active = port.transports.filter(\.active).map { "\($0.kind) ●" }
    let idle = port.transports.filter { !$0.active }.map(\.kind)
    let idleLabel = language == .de ? "inaktiv" : "idle"
    var text = active.isEmpty ? idleLabel : active.joined(separator: " · ")
    if !idle.isEmpty { text += language == .de ? "  (\(idle.joined(separator: ", ")) inaktiv)" : "  (\(idle.joined(separator: ", ")) idle)" }
    return StyledText(text, active.isEmpty ? .dim : .cyan)
}

private func cableCell(_ port: UsbPort) -> (StyledText, Int) {
    let cable = port.cable
    guard cable.attached else { return (dash, 0) }
    return (StyledText(cable.kind, cable.emarker ? .cyan : .dim), cable.emarker ? 2 : 1)
}

private func notesCell(_ port: UsbPort, language: AppLanguage = .en) -> StyledText {
    var notes: [(String, CellStyle)] = []
    if !port.devices.isEmpty {
        let names = port.devices.map(\.name).joined(separator: ", ")
        notes.append((language == .de ? "\(port.devices.count) Gerät(e): \(names)" : "\(port.devices.count) device(s): \(names)", .default))
    }
    if let displayport = port.transport("DisplayPort"), displayport.active {
        let detail = displayport.rateText ?? ""
        notes.append(((language == .de ? "DP-Alternativmodus" : "DP alt mode") + (detail.isEmpty ? "" : " \(detail)"), .cyan))
    }
    if !port.powerIn.isEmpty {
        notes.append(((language == .de ? "Eingangsleistung: " : "power in: ") + port.powerIn.joined(separator: ", "), .cyan))
    }
    if port.connected && port.usbTransport == nil {
        notes.append((language == .de ? "nur Ladegerät/Zubehör" : "charger/accessory only", .yellow))
    }
    if port.liquidDetected == true {
        notes.append((language == .de ? "Flüssigkeit erkannt" : "liquid detected", .red))
    }
    if port.transports.contains(where: { $0.restricted == true && $0.active }) {
        notes.append((language == .de ? "von macOS eingeschränkt" : "restricted by macOS", .yellow))
    }
    if notes.isEmpty { return dash }
    let styles = Set(notes.map(\.1))
    let severity: CellStyle = styles.contains(.red) ? .red : (styles.contains(.yellow) ? .yellow : .default)
    return StyledText(notes.map(\.0).joined(separator: " · "), severity)
}

// MARK: - Ports

public struct PortRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: StyledText
    public let kind: StyledText
    public let state: StyledText
    public let mode: StyledText
    public let transports: StyledText
    public let cable: StyledText
    public let notes: StyledText
    /// Class of the first attached device (`classText`), empty when the port is
    /// free. A port has no bus of its own, so the grouping layer uses the
    /// connector family for "bus" and this for "class".
    public let attachedClass: String
    public let highlight: Highlight?

    public let nameSort: Int
    public let kindSort: String
    public let stateSort: Int
    public let modeSort: Int
    public let transportsSort: String
    public let cableSort: Int
    public let notesSort: String
}

public func portRows(_ snapshot: Snapshot, changes: ChangeSet? = nil,
                     language: AppLanguage = .en) -> [PortRow] {
    snapshot.ports.map { port in
        let state = stateCell(connected: port.connected, language: language)
        let mode = modeCell(port, language: language)
        let cable = cableCell(port)
        let notes = notesCell(port, language: language)
        return PortRow(
            id: portKey(port),
            name: StyledText(port.name, .bold),
            kind: StyledText(port.kind, ["HDMI", "SD Card"].contains(port.kind) ? .dim : .default),
            state: state.0,
            mode: mode.0,
            transports: transportsCell(port, language: language),
            cable: cable.0,
            notes: notes,
            attachedClass: port.devices.first?.classText ?? "",
            highlight: changes.flatMap { highlight(for: $0.tag(portKey(port))) },
            nameSort: port.number ?? 999,
            kindSort: port.kind.lowercased(),
            stateSort: state.1,
            modeSort: mode.1,
            transportsSort: transportsCell(port, language: language).text.lowercased(),
            cableSort: cable.1,
            notesSort: notes.text.lowercased()
        )
    }
}

// MARK: - Cables

public struct CableRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let port: StyledText
    public let cable: StyledText
    public let authentication: StyledText
    public let hash: StyledText
    public let spec: StyledText
    public let powerIn: StyledText
    public let contract: StyledText
    public let liquid: StyledText
    public let firmware: StyledText
    public let highlight: Highlight?

    public let portSort: Int
    public let cableSort: Int
    public let authenticationSort: Int
    public let hashSort: String
    public let specSort: Int
    public let powerSort: String
    public let contractSort: Double
    public let liquidSort: Int
    public let firmwareSort: String
}

private func contractCell(_ port: UsbPort) -> (StyledText, Double) {
    guard let contract = port.powerContract else { return (dash, 0) }
    return (StyledText(contract.label, .cyan), contract.watts ?? 0)
}

private func hashCell(_ port: UsbPort) -> StyledText {
    let cable = port.cable
    guard cable.attached else { return dash }
    let usbHash = port.transports
        .first { $0.kind.uppercased().hasPrefix("USB") && $0.hashStatus != nil }?.hashStatus
    var parts = [cable.hashStatus, usbHash].compactMap { $0 }
    if cable.hashStatus == usbHash { parts = Array(parts.prefix(1)) }
    return StyledText(parts.isEmpty ? "–" : parts.joined(separator: " / "), .dim)
}

public func cableRows(_ snapshot: Snapshot, changes: ChangeSet? = nil,
                      language: AppLanguage = .en) -> [CableRow] {
    snapshot.ports.map { port in
        let cable = port.cable
        let contract = contractCell(port)
        let hasAuth = cable.attached && cable.authentication != nil
        let power = port.powerIn
        let liquidDetected = port.liquidDetected == true
        return CableRow(
            id: portKey(port),
            port: StyledText(port.name, .bold),
            cable: cableCell(port).0,
            authentication: hasAuth ? StyledText(cable.authentication!, .green) : dash,
            hash: hashCell(port),
            spec: cable.pdSpecRevision.map { StyledText(String($0), .default) } ?? dash,
            powerIn: power.isEmpty ? dash : StyledText(power.joined(separator: ", "), .cyan),
            contract: contract.0,
            liquid: liquidDetected
                ? StyledText(language == .de ? "erkannt" : "detected", .red)
                : StyledText(language == .de ? "sauber" : "clean", .dim),
            firmware: port.firmware.map { StyledText($0, .dim) } ?? dash,
            highlight: changes.flatMap { highlight(for: $0.tag(portKey(port))) },
            portSort: port.number ?? 999,
            cableSort: cableCell(port).1,
            authenticationSort: hasAuth ? 1 : 0,
            hashSort: hashCell(port).text.lowercased(),
            specSort: cable.pdSpecRevision ?? 0,
            powerSort: power.joined(separator: ", ").lowercased(),
            contractSort: contract.1,
            liquidSort: liquidDetected ? 1 : 0,
            firmwareSort: (port.firmware ?? "").lowercased()
        )
    }
}

// MARK: - Devices

public struct DeviceRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: StyledText
    public let vendor: StyledText
    public let idString: StyledText
    public let mode: StyledText
    public let deviceClass: StyledText
    public let tier: StyledText
    public let port: StyledText
    public let transport: StyledText
    /// The bus the device hangs off (`device.bus`), for the grouping toggle.
    public let bus: StyledText
    public let serial: StyledText
    public let restricted: StyledText
    public let highlight: Highlight?

    public let nameSort: String
    public let vendorSort: String
    public let idSort: String
    public let modeSort: Int
    public let classSort: String
    public let tierSort: Int
    public let portSort: String
    public let transportSort: String
    public let serialSort: String
    public let restrictedSort: Int
}

public func deviceRows(_ snapshot: Snapshot, changes: ChangeSet? = nil,
                       language: AppLanguage = .en) -> [DeviceRow] {
    snapshot.devices.map { device in
        let restricted = device.restricted == true
        return DeviceRow(
            id: deviceKey(device),
            name: StyledText(device.name, .bold),
            vendor: device.vendor.map { StyledText($0, .default) } ?? dash,
            idString: StyledText(device.idString, .dim),
            mode: StyledText(device.mode.label, modeStyle(device.mode)),
            deviceClass: device.classText.map { StyledText($0, deviceClassStyle($0)) } ?? dash,
            tier: device.tier.map { StyledText(String($0), .dim) } ?? dash,
            port: device.port.map { StyledText($0, .cyan) } ?? dash,
            transport: device.transport.map { StyledText($0, .cyan) } ?? dash,
            bus: device.bus.map { StyledText($0, .dim) } ?? dash,
            serial: device.serial.map { StyledText($0, .dim) } ?? dash,
            restricted: restricted
                ? StyledText(language == .de ? "ja" : "yes", .yellow)
                : StyledText(language == .de ? "nein" : "no", .dim),
            highlight: changes.flatMap { highlight(for: $0.tag(deviceKey(device))) },
            nameSort: device.name.lowercased(),
            vendorSort: (device.vendor ?? "").lowercased(),
            idSort: device.idString,
            modeSort: device.mode.rank,
            classSort: (device.classText ?? "").lowercased(),
            tierSort: device.tier ?? 0,
            portSort: (device.port ?? "").lowercased(),
            transportSort: (device.transport ?? "").lowercased(),
            serialSort: (device.serial ?? "").lowercased(),
            restrictedSort: restricted ? 1 : 0
        )
    }
}

/// HID and storage devices get attention colours: the classes a bad-USB or data
/// exfiltration scenario cares about.
func deviceClassStyle(_ classText: String) -> CellStyle {
    if classText.hasPrefix("HID") { return .cyan }
    if classText.hasPrefix("mass storage") { return .magenta }
    if classText.hasPrefix("hub") { return .dim }
    if classText.hasPrefix("per-interface") { return .dim }
    return .default
}

// MARK: - Thunderbolt

public struct ThunderboltRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let bus: StyledText
    public let receptacle: StyledText
    public let state: StyledText
    public let link: StyledText
    public let host: StyledText

    public let busSort: String
    public let receptacleSort: Int
    public let stateSort: Int
    public let linkSort: String
    public let hostSort: String
}

public func thunderboltRows(_ snapshot: Snapshot, language: AppLanguage = .en) -> [ThunderboltRow] {
    snapshot.thunderbolt.map { port in
        let state = stateCell(connected: port.connected, language: language)
        let host = [port.device, port.vendor].compactMap { $0 }.joined(separator: " · ")
        return ThunderboltRow(
            id: thunderboltKey(port),
            bus: StyledText(port.bus, .bold),
            receptacle: (port.receptacle.flatMap { $0 != 0 ? String($0) : nil })
                .map { StyledText($0, .default) } ?? dash,
            state: state.0,
            link: port.speed.map { StyledText($0, .cyan) } ?? dash,
            host: host.isEmpty ? dash : StyledText(host, .dim),
            busSort: port.bus.lowercased(),
            receptacleSort: port.receptacle ?? 0,
            stateSort: state.1,
            linkSort: (port.speed ?? "").lowercased(),
            hostSort: host.lowercased()
        )
    }
}

// MARK: - Power

public struct PowerRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let metric: StyledText
    public let value: StyledText
    public let metricSort: String
    public let valueSort: String
}

private func chargingStateText(_ charging: Charging, language: AppLanguage) -> String? {
    guard language == .de else { return Format.chargingState(charging) }

    let state: String?
    if charging.charging == true {
        state = "lädt"
    } else if charging.fullyCharged == true {
        state = "voll geladen"
    } else if charging.connected == true {
        state = "angeschlossen, lädt nicht"
    } else if charging.connected == false {
        state = "Akkubetrieb"
    } else {
        state = nil
    }
    var parts: [String] = state.map { [$0] } ?? []
    if let charge = charging.stateOfCharge { parts.append("\(charge) %") }
    if let minutes = charging.timeRemainingMinutes, minutes > 0, charging.fullyCharged != true {
        parts.append("\(minutes) Min. \(charging.charging == true ? "bis voll" : "verbleibend")")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

private func chargerFlagsText(_ charging: Charging, language: AppLanguage) -> String? {
    guard language == .de else { return Format.chargerFlags(charging) }

    var flags: [String] = []
    if let reason = charging.notChargingReason, reason != 0 { flags.append("lädt nicht: \(reason)") }
    if let reason = charging.slowChargingReason, reason != 0 { flags.append("langsames Laden: \(reason)") }
    if let seconds = charging.thermallyLimitedSeconds, seconds != 0 {
        flags.append("thermisch begrenzt \(seconds) s")
    }
    return flags.isEmpty ? nil : flags.joined(separator: ", ")
}

/// The live charging metrics as one row each (`viewmodel._charging_pairs`).
public func chargingPairs(_ charging: Charging, language: AppLanguage = .en) -> [(String, String)] {
    let labels = language == .de
        ? (status: "Status", adapter: "Adapter", fromAdapter: "Vom Adapter", load: "Systemlast", battery: "Batterie", loss: "Adapterverlust", charger: "Ladegerät")
        : (status: "Status", adapter: "Adapter", fromAdapter: "From adapter", load: "System load", battery: "Battery", loss: "Adapter loss", charger: "Charger")
    var items: [(String, String?)] = []
    items.append((labels.status, chargingStateText(charging, language: language)))
    items.append((
        labels.adapter,
        Format.powerLine(
            powerMw: charging.adapterPowerMw, voltageMv: charging.adapterVoltageMv,
            currentMa: charging.adapterCurrentMa, compact: true
        )
    ))
    items.append((
        labels.fromAdapter,
        Format.powerLine(
            powerMw: charging.systemPowerInMw, voltageMv: charging.systemVoltageInMv,
            currentMa: charging.systemCurrentInMa
        )
    ))
    items.append((labels.load, Format.watts(charging.systemLoadMw)))
    items.append((
        labels.battery,
        Format.powerLine(
            powerMw: charging.batteryPowerMw, voltageMv: charging.batteryVoltageMv,
            currentMa: charging.batteryCurrentMa
        )
    ))
    items.append((labels.loss, Format.watts(charging.adapterEfficiencyLossMw)))
    items.append((labels.charger, chargerFlagsText(charging, language: language)))
    return items.compactMap { label, value in
        guard let value, !value.isEmpty else { return nil }
        return (label, value)
    }
}

public func powerRows(_ snapshot: Snapshot, language: AppLanguage = .en) -> [PowerRow] {
    guard let charging = snapshot.charging else { return [] }
    return chargingPairs(charging, language: language).map { label, value in
        let live = label == "Status" && charging.charging == true
        return PowerRow(
            id: powerKey(label),
            metric: StyledText(label, .dim),
            value: StyledText(value, live ? .green : .default),
            metricSort: label.lowercased(), valueSort: value.lowercased()
        )
    }
}

// MARK: - Dispatch

/// The empty-state message of a view (`viewmodel` `empty_message`).
public func emptyMessage(for view: AppView) -> String {
    switch view {
    case .ports: "No ports reported by the port controller."
    case .cables: "No cable or port controller data."
    case .devices: "No USB device attached — plug one in, the table refreshes itself."
    case .thunderbolt: "No Thunderbolt/USB4 receptacle reported."
    case .power: "No battery or charger reported — a desktop Mac has none."
    case .timeline: "No power history yet — the graph fills in as the app reads the machine."
    case .security: "No security findings — macOS reported nothing that stood out."
    case .usb4: "No Thunderbolt/USB4 router reported."
    case .diff: "No baseline loaded — use 'Compare with…' to pick a snapshot JSON."
    case .warnings: "No source warnings were reported for the current snapshot."
    }
}

// MARK: - Quick filter presets

/// Conformances for the toolbar's quick filters (`FilterPreset`). A row answers
/// only what it can know: the Cables/Power rows carry no USB class, so their
/// `isHID`/`isStorage` are `false` instead of guessed from the free text.

extension PortRow: PresetFilterable {
    public var isHID: Bool { attachedClass.hasPrefix("HID") }
    public var isStorage: Bool { attachedClass.hasPrefix("mass storage") }
    public var isConnected: Bool { stateSort == 1 }
}

extension CableRow: PresetFilterable {
    public var isHID: Bool { false }
    public var isStorage: Bool { false }
    public var isConnected: Bool { cable.text != "–" }
}

extension DeviceRow: PresetFilterable {
    public var isHID: Bool { deviceClass.text.hasPrefix("HID") }
    public var isStorage: Bool { deviceClass.text.hasPrefix("mass storage") }
    /// A device row is by construction an attached device.
    public var isConnected: Bool { true }
}

extension ThunderboltRow: PresetFilterable {
    public var isHID: Bool { false }
    public var isStorage: Bool { false }
    public var isConnected: Bool { stateSort == 1 }
}

extension PowerRow: PresetFilterable {
    public var isHID: Bool { false }
    public var isStorage: Bool { false }
    /// Charging metrics are live readings, not objects that plug in.
    public var isConnected: Bool { true }
}
