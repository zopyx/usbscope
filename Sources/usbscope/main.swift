import Foundation
import UsbScopeCore
import UsbScopeUI

// usbscope — the CLI. One snapshot, one JSON schema, two front ends (this and the app).

let version = "0.4.0"

struct Options {
    var view = "overview"
    var verbose = false
    var json = false
    var noColor = false
    var watch: Double?
    var rest: [String] = []
    var expects: [String] = []
    var events = false
    var interval: Double = 2.0
    var format = "md"
    var out: String?
}

func usage() -> String {
    """
    usage: usbscope [view|command] [options]

    views:
      overview     ports, cables, devices and USB4 receptacles (default)
      ports        USB-C / Thunderbolt port table with negotiated modes
      devices      device tree with vendor/product IDs and link modes
      cables       cable, e-marker (SOP), CC authentication, power contract
      thunderbolt  Thunderbolt / USB4 receptacles
      usb4         USB4 fabric: routers, their ports and the tunnels on them
      security     security findings per device/port plus USB mass storage
      json         machine readable snapshot (same as --json)

    commands (for scripts and CI):
      check        evaluate --expect assertions, exit 0/3 (2 on a malformed expectation)
      watch        --events: one JSON line per attach/detach (IOKit, else polling)
      baseline     save <file> | check <file>: compare the live machine to a baseline
      report       --format md|html [--out file]: human readable report

    options:
      -v, --verbose   show additional details
      --json          print the snapshot as JSON (check/baseline: their own document)
      --watch S       redraw in place every S seconds until Ctrl-C
      --no-color      disable colours
      --expect EXPR   check: an expectation, e.g. device=0x1050:0x0407 (repeatable)
      --events        watch: stream attach/detach events
      --interval S    watch: poll interval in seconds (default 2)
      --format FMT    report: md (default) or html
      --out FILE      report: write to FILE instead of stdout
      --version       print the version
    """
}

let views = ["overview", "ports", "devices", "cables", "thunderbolt", "usb4", "security", "json"]
let commands = ["check", "watch", "baseline", "report"]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("usbscope: \(message)\n".utf8))
    exit(2)
}

func parse(_ argv: [String]) -> Options {
    var options = Options()
    var index = 0
    var hasPositional = false
    let arguments = Array(argv.dropFirst())

    func nextValue(_ option: String) -> String {
        guard index + 1 < arguments.count else { fail("\(option) needs a value") }
        index += 1
        return arguments[index]
    }

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "-v", "--verbose": options.verbose = true
        case "--json": options.json = true
        case "--no-color": options.noColor = true
        case "--events": options.events = true
        case "-h", "--help": print(usage()); exit(0)
        case "--version": print("usbscope \(version)"); exit(0)
        case "--watch":
            guard let seconds = Double(nextValue("--watch")) else { fail("--watch needs a number") }
            options.watch = seconds
        case "--interval":
            guard let seconds = Double(nextValue("--interval")) else {
                fail("--interval needs a number")
            }
            options.interval = seconds
        case "--expect": options.expects.append(nextValue("--expect"))
        case "--format":
            let value = nextValue("--format")
            guard value == "md" || value == "html" else { fail("--format must be md or html") }
            options.format = value
        case "--out": options.out = nextValue("--out")
        default:
            if !hasPositional {
                guard views.contains(argument) || commands.contains(argument) else {
                    fail("unknown argument \(argument)")
                }
                options.view = argument
                hasPositional = true
            } else {
                options.rest.append(argument)
            }
        }
        index += 1
    }
    return options
}

// MARK: - rendering

enum Style: String {
    case dim = "\u{1B}[2m"
    case bold = "\u{1B}[1m"
    case cyan = "\u{1B}[36m"
    case green = "\u{1B}[32m"
    case yellow = "\u{1B}[33m"
    case red = "\u{1B}[31m"
    case magenta = "\u{1B}[35m"
    case reset = "\u{1B}[0m"
}

/// Set once before rendering and only read afterwards, so the unsafe opt-out is
/// sound: the CLI is single threaded.
nonisolated(unsafe) var useColor = true

func paint(_ text: String, _ styles: Style...) -> String {
    guard useColor, !styles.isEmpty else { return text }
    return styles.map(\.rawValue).joined() + text + Style.reset.rawValue
}

/// Left-aligned padded cell (padding is applied before colouring).
func cell(_ text: String, width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

/// A minimal table: one header row, auto-sized columns, `|` separators.
func table(_ headers: [String], _ rows: [[String]]) -> String {
    guard !headers.isEmpty else { return "" }
    var widths = headers.map { $0.count }
    for row in rows {
        for (index, value) in row.enumerated() where index < widths.count {
            widths[index] = max(widths[index], value.count)
        }
    }
    func line(_ values: [String]) -> String {
        "│ " + values.enumerated()
            .map { cell($0.element, width: widths[$0.offset]) }
            .joined(separator: " │ ") + " │"
    }
    let rule = "├" + widths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: "┼") + "┤"
    var output = ["┌" + widths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: "┬") + "┐"]
    output.append(line(headers.map { paint($0, .bold) }))
    output.append(rule)
    output.append(contentsOf: rows.map { line($0) })
    output.append("└" + widths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: "┴") + "┘")
    return output.joined(separator: "\n")
}

func modeStyle(_ mode: UsbMode) -> Style {
    switch mode.rank {
    case 7...: .magenta
    case 4...: .cyan
    case 3: .green
    case 1...: .yellow
    default: .dim
    }
}

func stateText(_ port: UsbPort) -> String {
    port.connected ? paint("● connected", .green) : paint("○ free", .dim)
}

func modeText(_ port: UsbPort) -> String {
    guard let transport = port.usbTransport, transport.active else {
        return port.connected ? paint("no USB data", .yellow) : paint("–", .dim)
    }
    return paint(transport.mode.label, modeStyle(transport.mode))
}

func powerBrief(_ port: UsbPort) -> String? {
    guard !port.powerIn.isEmpty else { return nil }
    let names = port.powerIn.joined(separator: ", ")
    guard let contract = port.powerContract else { return names }
    return "\(names) (\(contract.label))"
}

func extraNotes(_ port: UsbPort) -> [String] {
    var notes: [String] = []
    if let mode = port.usbModeText { notes.append("USB mode: \(mode)") }
    if !port.pinsText.isEmpty { notes.append("pins: \(port.pinsText)") }
    if port.powerMode != nil || !port.supportedPowerModes.isEmpty {
        var parts = ["mode \(port.powerMode.map(String.init) ?? "–")"]
        if let active = port.activePowerMode { parts.append("active \(active)") }
        if !port.supportedPowerModes.isEmpty {
            parts.append("supported " + port.supportedPowerModes.map(String.init).joined(separator: "/"))
        }
        if port.powerCurrentLimits.contains(where: { $0 != 0 }) {
            parts.append("limits " + port.powerCurrentLimits.map(String.init).joined(separator: "/"))
        }
        notes.append("power contract: " + parts.joined(separator: ", "))
    }
    var liquid = [port.liquidState, port.liquidMeasurement, port.liquidPin].compactMap { $0 }
    if port.liquidMitigations == true { liquid.append("mitigations on") }
    if port.liquidOverride == true { liquid.append("override active") }
    if !liquid.isEmpty { notes.append("LDCM: " + liquid.joined(separator: " · ")) }
    if let accessory = port.accessoryMode, accessory != 0 { notes.append("accessory mode: \(accessory)") }
    return notes
}

func notesText(_ port: UsbPort, verbose: Bool) -> String {
    var notes: [String] = []
    if !port.devices.isEmpty {
        notes.append("\(port.devices.count) device(s): " + port.devices.map(\.name).joined(separator: ", "))
    }
    if let displayport = port.transport("DisplayPort"), displayport.active {
        notes.append("DP alt mode" + (displayport.rateText.map { ": \($0)" } ?? ""))
    }
    if let brief = powerBrief(port) { notes.append("power in: " + brief) }
    if port.connected && port.usbTransport == nil {
        notes.append("charge/accessory only, no USB data transport")
    }
    if port.liquidDetected == true { notes.append("liquid detected") }
    if let authorization = port.authorization, !["Not Required", "No Action"].contains(authorization) {
        notes.append("authorization: \(authorization)")
    }
    if port.transports.contains(where: { $0.restricted == true && $0.active }) {
        notes.append("restricted by macOS")
    }
    if verbose {
        if let superSpeed = port.superSpeedActive { notes.append("superspeed: \(superSpeed ? "yes" : "no")") }
        if let orientation = port.plugOrientation { notes.append("plug orientation: \(orientation)") }
        if let firmware = port.firmware { notes.append("controller fw \(firmware)") }
        for transport in port.transports where transport.active {
            if let state = transport.trmState {
                notes.append("TRM \(transport.kind): \(state)" + (transport.trmProfile.map { " (\($0))" } ?? ""))
            }
        }
        notes.append(contentsOf: extraNotes(port))
    }
    return notes.isEmpty ? paint("–", .dim) : notes.joined(separator: " · ")
}

let readAtFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

func summaryPanel(_ snapshot: Snapshot, verbose: Bool) -> String {
    var rows: [(String, String)] = []
    let machine = [snapshot.model, snapshot.chip, "macOS \(snapshot.osVersion)"].compactMap { $0 }.joined(separator: " · ")
    rows.append(("Machine", machine))
    rows.append(("Host", snapshot.host))
    rows.append(("Ports", "\(snapshot.ports.count) total · \(snapshot.connectedPorts.count) connected · \(snapshot.emarkedCables.count) e-marked cable(s)"))
    rows.append(("Devices", String(snapshot.devices.count)))
    if verbose, let charging = snapshot.charging {
        if let state = Format.chargingState(charging) { rows.append(("Charging", state)) }
        if let power = Format.chargingSummary(charging) { rows.append(("Power", power)) }
    }
    if !snapshot.thunderbolt.isEmpty {
        let connected = snapshot.thunderbolt.filter(\.connected).count
        rows.append(("USB4/TB", "\(snapshot.thunderbolt.count) receptacle(s) · \(connected) connected"))
    }
    rows.append(("Read at", readAtFormatter.string(from: snapshot.seenAt)))
    let width = rows.map(\.0.count).max() ?? 0
    let body = rows.map { cell($0.0, width: width) + "  " + $0.1 }.joined(separator: "\n")
    return "usbscope — macOS USB inspector\n" + body
}

func portsTable(_ snapshot: Snapshot, verbose: Bool) -> String {
    let rows = snapshot.ports.map { port -> [String] in
        [port.name, port.kind, stateText(port), modeText(port), notesText(port, verbose: verbose)]
    }
    return table(["Port", "Type", "State", "Mode", "Notes"], rows)
}

func devicesTree(_ snapshot: Snapshot, verbose: Bool) -> String {
    var lines = ["Devices (\(snapshot.devices.count))"]
    if snapshot.buses.isEmpty { return lines.joined(separator: "\n") + "\n└── no USB buses reported" }
    for bus in snapshot.buses {
        let head = [bus.name, bus.driver, bus.locationID.map { String(format: "@0x%08x", $0) }]
            .compactMap { $0 }.joined(separator: " · ")
        lines.append("├── \(paint(head, .bold))")
        if bus.devices.isEmpty {
            lines.append("│   └── no devices")
            continue
        }
        for device in bus.devices {
            var line = "│   └── \(paint(device.label, .bold)) · \(device.idString) · \(device.mode.label)"
            if verbose, let classText = device.classText { line += " · \(classText)" }
            if verbose, let tier = device.tier { line += " · tier \(tier)" }
            if let serial = device.serial { line += " · serial \(serial)" }
            if let port = device.port { line += " · → \(port)" }
            if verbose, let location = device.locationID { line += " · location=\(String(format: "0x%08x", location))" }
            lines.append(line)
        }
    }
    return lines.joined(separator: "\n")
}

func thunderboltTable(_ snapshot: Snapshot) -> String {
    let rows = snapshot.thunderbolt.map { port -> [String] in
        [
            port.bus,
            port.receptacle.map(String.init) ?? "–",
            port.connected ? paint("● connected", .green) : paint("○ free", .dim),
            port.speed ?? "–",
        ]
    }
    return table(["Bus", "Port", "State", "Link"], rows)
}

/// `usbscope usb4` — the USB4/Thunderbolt fabric as a tree.
///
/// The rows come from `FabricPresentation`, the same presentation the app's USB4
/// tab draws, so the two front ends cannot describe a router, a port or a tunnel
/// differently. The link speed/width enumerations are printed verbatim with the
/// note that explains why they are not converted to Gbit/s.
func usb4Tree(_ snapshot: Snapshot) -> String {
    let fabric = snapshot.thunderboltFabric
    guard !fabric.routers.isEmpty else { return "USB4 fabric: no routers reported" }
    var lines: [String] = []
    for row in FabricPresentation.rows(fabric) {
        let indent = String(repeating: "  ", count: row.depth)
        let marker: String
        switch row.kind {
        case .router: marker = paint("◆", .cyan) + " "
        case .port: marker = paint("•", .dim) + " "
        // A tunnel's title already carries its own "→ label" connector: a second
        // arrow would read as "→ → pcie: …".
        case .tunnel: marker = ""
        }
        var line = "\(indent)\(marker)\(row.title)"
        if !row.detail.isEmpty { line += "  " + paint(row.detail, .dim) }
        if let raw = row.rawLink { line += "\n\(indent)   " + paint(raw, .cyan) }
        lines.append(line)
    }
    lines.append("")
    lines.append(paint(FabricPresentation.rawLinkNote, .dim))
    return lines.joined(separator: "\n")
}

func cablesTable(_ snapshot: Snapshot, verbose: Bool) -> String {
    var headers = ["Port", "Cable", "CC authentication", "Hash (CC / USB)", "PD spec"]
    if verbose { headers.append(contentsOf: ["USB mode", "Power in", "Contract", "Liquid"]) }
    let rows = snapshot.ports.map { port -> [String] in
        let cable = port.cable
        let usbHash = port.transports.first { $0.kind.uppercased().hasPrefix("USB") && $0.hashStatus != nil }?.hashStatus
        var hashParts: [String] = []
        if cable.attached {
            hashParts = [cable.hashStatus, usbHash].compactMap { $0 }
            if cable.hashStatus == usbHash, !hashParts.isEmpty { hashParts = [hashParts[0]] }
        }
        var row = [
            port.name,
            cable.kind,
            cable.attached ? (cable.authentication ?? "–") : "–",
            hashParts.isEmpty ? "–" : hashParts.joined(separator: " / "),
            cable.pdSpecRevision.map(String.init) ?? "–",
        ]
        if verbose {
            row.append(port.usbModeText ?? "–")
            row.append(port.powerIn.joined(separator: ", "))
            row.append(port.powerContract?.label ?? "–")
            row.append((port.liquidDetected == true ? "detected" : "clean") + (port.liquidState.map { " · \($0)" } ?? ""))
        }
        return row
    }
    return table(headers, rows)
}

func chargingPanel(_ snapshot: Snapshot) -> String? {
    guard let charging = snapshot.charging else { return nil }
    var rows: [(String, String)] = []
    func add(_ label: String, _ value: String?) { if let value { rows.append((label, value)) } }
    add("State", Format.chargingState(charging))
    add("Adapter", Format.powerLine(powerMw: charging.adapterPowerMw, voltageMv: charging.adapterVoltageMv, currentMa: charging.adapterCurrentMa, compact: true))
    add("From adapter", Format.powerLine(powerMw: charging.systemPowerInMw, voltageMv: charging.systemVoltageInMv, currentMa: charging.systemCurrentInMa))
    add("System load", Format.watts(charging.systemLoadMw))
    add("Battery", Format.powerLine(powerMw: charging.batteryPowerMw, voltageMv: charging.batteryVoltageMv, currentMa: charging.batteryCurrentMa))
    add("Adapter loss", Format.watts(charging.adapterEfficiencyLossMw))
    add("Charger", Format.chargerFlags(charging))
    let width = rows.map(\.0.count).max() ?? 0
    let body = rows.map { cell($0.0, width: width) + "  " + $0.1 }.joined(separator: "\n")
    return "Charging & adapter — system wide, not per port\n" + body
}

func securityView(_ snapshot: Snapshot, report: SecurityReport, storage: [StorageDevice], verbose: Bool) -> String {
    var parts: [String] = [summaryPanel(snapshot, verbose: verbose)]
    if !snapshot.warnings.isEmpty {
        parts.append("notes\n" + snapshot.warnings.map { "• \(paint($0, .yellow))" }.joined(separator: "\n"))
    }
    parts.append("Security posture — heuristic, not a verdict")
    parts.append("  Warning    \(report.count(.warning))")
    parts.append("  Attention  \(report.count(.attention))")
    parts.append("  Info       \(report.count(.info))")
    if report.isEmpty {
        parts.append("  nothing stood out in what macOS reports")
    } else {
        let rows = report.findings.map { [$0.severity.rawValue, $0.rule, $0.subject, $0.detail] }
        parts.append(table(["Severity", "Rule", "Subject", "Why"], rows))
    }
    if storage.isEmpty {
        parts.append("no USB mass storage attached — a Mac without one is normal")
    } else {
        let rows = storage.map { device -> [String] in
            let mode = device.readOnly == true ? "read-only" : (device.readOnly == false ? "read/write" : "–")
            return [device.identifier, device.label, device.capacityText ?? "–", mode, device.mountPoint ?? "–"]
        }
        parts.append("USB mass storage\n" + table(["Device", "Name", "Capacity", "Mode", "Mount"], rows))
    }
    parts.append(
        "honest limits: the class triple is device level, so the interfaces of a composite device "
            + "(and therefore its HID/mass-storage mix) are not exposed without a user client; a missing "
            + "serial is a missing report, not proof there is none; storage covers only whole disks "
            + "whose diskutil BusProtocol is USB."
    )
    return parts.joined(separator: "\n")
}

func render(_ snapshot: Snapshot, options: Options) {
    if options.view == "security" {
        let report = Security.analyse(snapshot)
        let (storage, _) = StorageSource().inventory()
        if options.json {
            print(Serialize.securityJSON(report, storage: storage, generatedAt: snapshot.seenAt))
        } else {
            print(securityView(snapshot, report: report, storage: storage, verbose: options.verbose))
        }
        return
    }
    if options.json || options.view == "json" {
        print(Serialize.json(snapshot))
        return
    }
    var parts: [String] = [summaryPanel(snapshot, verbose: options.verbose)]
    if !snapshot.warnings.isEmpty {
        parts.append("notes\n" + snapshot.warnings.map { "• \(paint($0, .yellow))" }.joined(separator: "\n"))
    }
    if ["overview", "ports"].contains(options.view), !snapshot.ports.isEmpty {
        parts.append(portsTable(snapshot, verbose: options.verbose))
    }
    if options.view == "cables" {
        parts.append(cablesTable(snapshot, verbose: options.verbose))
        if options.verbose, let panel = chargingPanel(snapshot) { parts.append(panel) }
    }
    if ["overview", "devices"].contains(options.view) {
        parts.append(devicesTree(snapshot, verbose: options.verbose))
    }
    if ["overview", "thunderbolt"].contains(options.view), !snapshot.thunderbolt.isEmpty {
        parts.append(thunderboltTable(snapshot))
    }
    if options.view == "usb4" {
        parts.append(usb4Tree(snapshot))
    }
    print(parts.joined(separator: "\n"))
}

// MARK: - commands

/// `usbscope check --expect …` — exit 0 when every expectation holds, 3 when one
/// fails, 2 on a malformed expectation (a typo must not look like a failure).
func runCheck(_ options: Options) -> Never {
    guard !options.expects.isEmpty else {
        FileHandle.standardError.write(Data("usbscope check: no --expect given (nothing to check)\n".utf8))
        exit(2)
    }
    let expectations: [Expectation]
    do {
        expectations = try options.expects.map { try Assertions.parse($0) }
    } catch {
        FileHandle.standardError.write(Data("usbscope check: \(error)\n".utf8))
        exit(2)
    }
    let report = Assertions.evaluate(SnapshotBuilder.collect(), expectations)
    print(options.json ? Assertions.json(report) : Assertions.render(report))
    exit(report.passed ? 0 : 3)
}

/// `usbscope watch --events` — one flushed JSON line per attach/detach.
///
/// Builds on `UsbHotplugWatcher`: `.automatic` arms real IOKit notifications and
/// falls back to the watcher's polling differ when IOKit is unavailable, exactly
/// as the app does.
func runWatchEvents(_ options: Options) -> Never {
    let watcher = UsbHotplugWatcher(mode: .automatic, pollInterval: max(options.interval, 0.2))
    watcher.start { update in
        for line in EventStream.lines(update.changes, at: update.snapshot.seenAt) {
            FileHandle.standardOutput.write(Data((line + "\n").utf8))
        }
    }
    dispatchMain()
}

/// `usbscope baseline save <file>` / `usbscope baseline check <file>`.
func runBaseline(_ options: Options) -> Never {
    guard options.rest.count == 2, ["save", "check"].contains(options.rest[0]) else {
        FileHandle.standardError.write(
            Data("usage: usbscope baseline save <file> | usbscope baseline check <file>\n".utf8)
        )
        exit(2)
    }
    let action = options.rest[0]
    let path = options.rest[1]
    if action == "save" {
        do {
            try Baseline.save(SnapshotBuilder.collect(), to: path)
        } catch {
            FileHandle.standardError.write(Data("usbscope baseline: \(error)\n".utf8))
            exit(1)
        }
        print("baseline written: \(path)")
        exit(0)
    }
    let previous: [String: Any]
    do {
        previous = try Baseline.load(path)
    } catch {
        FileHandle.standardError.write(Data("usbscope baseline: \(error)\n".utf8))
        exit(2)
    }
    let diff = Baseline.compare(
        previous: previous, current: Serialize.dict(SnapshotBuilder.collect())
    )
    print(options.json ? Baseline.json(diff) : Baseline.render(diff, path: path))
    exit(diff.identical ? 0 : 3)
}

/// `usbscope report [--format md|html] [--out file]`.
func runReport(_ options: Options) -> Never {
    let snapshot = SnapshotBuilder.collect()
    let (storage, _) = StorageSource().inventory()
    let text = options.format == "html"
        ? Report.html(snapshot, storage: storage)
        : Report.markdown(snapshot, storage: storage)
    if let out = options.out {
        do {
            try text.write(toFile: out, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("usbscope report: cannot write \(out): \(error)\n".utf8))
            exit(1)
        }
        print("report written: \(out)")
        exit(0)
    }
    FileHandle.standardOutput.write(Data(text.utf8))
    exit(0)
}

// MARK: - main

/// Live mode: redraw on the spot until interrupted.
///
/// The escape sequence only makes sense on a terminal — when stdout is a pipe or a
/// file the frames are written one after the other instead, which is what makes
/// `usbscope --watch 1 | grep -c usbscope` a usable check. Ctrl-C ends the loop;
/// nothing is buffered across frames, so the last frame on screen is always a real
/// reading and never a mix of two.
func runWatch(_ options: Options, interval: Double) {
    let live = isatty(fileno(stdout)) == 1
    let seconds = max(interval, 0.2)
    var frames = 0
    while true {
        let snapshot = SnapshotBuilder.collect()
        if live {
            // Clear the screen and park the cursor at the top left, then draw.
            print("\u{1B}[2J\u{1B}[H", terminator: "")
        } else if frames > 0 {
            print("")
        }
        frames += 1
        print("usbscope — live · every \(Format.g(seconds)) s · frame \(frames) · Ctrl-C to stop")
        render(snapshot, options: options)
        fflush(stdout)
        Thread.sleep(forTimeInterval: seconds)
    }
}

let options = parse(CommandLine.arguments)
useColor = !options.noColor && isatty(fileno(stdout)) == 1
switch options.view {
case "check": runCheck(options)
case "watch": runWatchEvents(options)
case "baseline": runBaseline(options)
case "report": runReport(options)
default:
    if let interval = options.watch, !options.json {
        // JSON in a live loop makes no sense: a pipe wants one parseable document.
        runWatch(options, interval: interval)
    }
    let snapshot = SnapshotBuilder.collect()
    render(snapshot, options: options)
}
