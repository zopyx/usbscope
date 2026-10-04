import Foundation

/// Human readable report (`usbscope report`) as Markdown or self-contained HTML —
/// the twin of `usbscope/report.py`.
///
/// The report is the artefact a person reads (or attaches to a ticket): machine,
/// port table, devices with class/tier, cables, the per-port power contract, the
/// live charging numbers, the security findings and the collection warnings.
///
/// Both formats are built from the same section list, so Markdown and HTML can
/// never disagree, and the exact wording is mirrored by the Python twin. The HTML
/// page carries an inline stylesheet only: no external assets, no network access.
public enum Report {
    static let absent = "–"
    static let none = "_none_"

    static let portHeaders = ["Port", "Type", "State", "Mode", "Cable", "Devices"]
    static let deviceHeaders = ["Device", "ID", "Class", "Tier", "Mode", "Port"]
    static let cableHeaders = ["Port", "Cable", "CC authentication", "PD spec", "Power in", "Contract"]
    static let findingHeaders = ["Severity", "Rule", "Subject", "Why"]
    static let storageHeaders = ["Device", "Name", "Capacity", "Mode", "Mount"]

    /// Human-readable report language. Schema keys, rule IDs, and raw values
    /// remain language-neutral; only presentation labels are translated.
    public enum Language: String, Codable, Sendable, CaseIterable {
        case english = "en"
        case german = "de"
    }

    private static func localized(_ text: String, _ language: Language) -> String {
        guard language == .german else { return text }
        let translations: [String: String] = [
            "usbscope report": "usbscope Bericht",
            "Machine": "Mac",
            "Host": "Rechner",
            "Read at": "Gelesen um",
            "Ports": "Anschlüsse",
            "Devices": "Geräte",
            "Cables": "Kabel",
            "Power": "Energie",
            "Security findings": "Sicherheitsbefunde",
            "USB mass storage": "USB-Massenspeicher",
            "Warnings": "Warnungen",
            "Port": "Anschluss",
            "Type": "Typ",
            "State": "Status",
            "Mode": "Modus",
            "Cable": "Kabel",
            "Device": "Gerät",
            "ID": "ID",
            "Class": "Klasse",
            "Tier": "Ebene",
            "CC authentication": "CC-Authentifizierung",
            "PD spec": "PD-Spezifikation",
            "Power in": "Eingangsleistung",
            "Contract": "Vertrag",
            "Severity": "Schweregrad",
            "Rule": "Regel",
            "Subject": "Objekt",
            "Why": "Warum",
            "Name": "Name",
            "Capacity": "Kapazität",
            "Mount": "Einhängepunkt",
            "connected": "verbunden",
            "free": "frei",
            "read-only": "schreibgeschützt",
            "read/write": "Lesen/Schreiben",
            "_no charging telemetry reported_": "_keine Lade-Telemetrie gemeldet_",
            "_no receptacles reported_": "_keine Anschlüsse gemeldet_",
            "_no USB devices attached_": "_keine USB-Geräte verbunden_",
            "_nothing stood out in what macOS reports_": "_in den macOS-Daten nichts Auffälliges_",
            "_no USB mass storage attached_": "_kein USB-Massenspeicher verbunden_",
            "_none_": "_keine_",
        ]
        return translations[text] ?? text
    }

    private static func localizedDocument(_ text: String, _ language: Language) -> String {
        guard language == .german else { return text }
        var result = text
        let phrases = [
            "usbscope report", "Security findings", "USB mass storage", "No changes against the baseline",
            "Machine", "Host", "Read at", "Ports", "Devices", "Cables", "Power", "Warnings",
            "Port", "Type", "State", "Mode", "Cable", "Device", "ID", "Class", "Tier", "CC authentication",
            "PD spec", "Power in", "Contract", "Severity", "Rule", "Subject", "Why", "Name", "Capacity", "Mount",
            "connected", "free", "read-only", "read/write", "_no charging telemetry reported_", "_no receptacles reported_",
            "_no USB devices attached_", "_nothing stood out in what macOS reports_", "_no USB mass storage attached_", "_none_",
        ]
        for phrase in phrases { result = result.replacingOccurrences(of: phrase, with: localized(phrase, language)) }
        return result
    }

    // MARK: - summary

    /// Naive local timestamp, matching the Python `isoformat(timespec: "seconds")`.
    static func timestamp(_ moment: Date) -> String {
        EventStream.timestampFormatter.string(from: moment)
    }

    static func machine(_ snapshot: Snapshot) -> String {
        let parts = [snapshot.model, snapshot.chip, "macOS \(snapshot.osVersion)"]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    // MARK: - rows

    static func modeCell(_ port: UsbPort) -> String {
        guard let transport = port.usbTransport, transport.active else { return absent }
        return transport.mode.label
    }

    static func devicesCell(_ port: UsbPort) -> String {
        port.devices.isEmpty ? absent : port.devices.map(\.name).joined(separator: ", ")
    }

    static func portRows(_ snapshot: Snapshot) -> [[String]] {
        snapshot.ports.map { port in
            [
                port.name, port.kind, port.connected ? "connected" : "free", modeCell(port),
                port.cable.kind, devicesCell(port),
            ]
        }
    }

    static func deviceRows(_ snapshot: Snapshot) -> [[String]] {
        snapshot.devices.map { device in
            [
                device.label, device.idString, device.classText ?? absent,
                device.tier.map { String($0) } ?? absent, device.mode.label, device.port ?? absent,
            ]
        }
    }

    static func cableRows(_ snapshot: Snapshot) -> [[String]] {
        snapshot.ports.map { port in
            let cable = port.cable
            return [
                port.name, cable.kind,
                cable.attached ? (cable.authentication ?? absent) : absent,
                cable.pdSpecRevision.map { String($0) } ?? absent,
                port.powerIn.isEmpty ? absent : port.powerIn.joined(separator: ", "),
                port.powerContract?.label ?? absent,
            ]
        }
    }

    static func chargingLines(_ snapshot: Snapshot) -> [String] {
        guard let charging = snapshot.charging else { return ["_no charging telemetry reported_"] }
        let entries: [(String, String?)] = [
            ("State", Format.chargingState(charging)),
            (
                "Adapter",
                Format.powerLine(
                    powerMw: charging.adapterPowerMw, voltageMv: charging.adapterVoltageMv,
                    currentMa: charging.adapterCurrentMa, compact: true
                )
            ),
            (
                "From adapter",
                Format.powerLine(
                    powerMw: charging.systemPowerInMw, voltageMv: charging.systemVoltageInMv,
                    currentMa: charging.systemCurrentInMa
                )
            ),
            ("System load", Format.watts(charging.systemLoadMw)),
            (
                "Battery",
                Format.powerLine(
                    powerMw: charging.batteryPowerMw, voltageMv: charging.batteryVoltageMv,
                    currentMa: charging.batteryCurrentMa
                )
            ),
            ("Adapter loss", Format.watts(charging.adapterEfficiencyLossMw)),
            ("Charger", Format.chargerFlags(charging)),
        ]
        return entries.compactMap { label, value in value.map { "- \(label): \($0)" } }
    }

    static func findingRows(_ report: SecurityReport) -> [[String]] {
        report.findings.map { [$0.severity.rawValue, $0.rule, $0.subject, $0.detail] }
    }

    static func storageRows(_ storage: [StorageDevice]) -> [[String]] {
        storage.map { device in
            [
                device.identifier, device.label, device.capacityText ?? absent,
                device.readOnly == true ? "read-only" : (device.readOnly == false ? "read/write" : absent),
                device.mountPoint ?? absent,
            ]
        }
    }

    // MARK: - sections

    struct Section {
        let title: String
        let headers: [String]?
        let rows: [[String]]
        let extra: [String]
    }

    static func sections(
        _ snapshot: Snapshot, _ report: SecurityReport, _ storage: [StorageDevice]
    ) -> [Section] {
        let findings = findingRows(report)
        let storageRowList = storageRows(storage)
        return [
            Section(
                title: "Ports", headers: portHeaders, rows: portRows(snapshot),
                extra: snapshot.ports.isEmpty ? ["_no receptacles reported_"] : []
            ),
            Section(
                title: "Devices", headers: deviceHeaders, rows: deviceRows(snapshot),
                extra: snapshot.devices.isEmpty ? ["_no USB devices attached_"] : []
            ),
            Section(title: "Cables", headers: cableHeaders, rows: cableRows(snapshot), extra: []),
            Section(
                title: "Power", headers: nil, rows: [], extra: chargingLines(snapshot)
            ),
            Section(
                title: "Security findings", headers: findingHeaders, rows: findings,
                extra: findings.isEmpty ? ["_nothing stood out in what macOS reports_"] : []
            ),
            Section(
                title: "USB mass storage", headers: storageHeaders, rows: storageRowList,
                extra: storageRowList.isEmpty ? ["_no USB mass storage attached_"] : []
            ),
            Section(
                title: "Warnings", headers: nil, rows: [],
                extra: snapshot.warnings.isEmpty ? [none] : snapshot.warnings.map { "- \($0)" }
            ),
        ]
    }

    // MARK: - markdown

    static func markdownCell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func markdownTable(_ headers: [String], _ rows: [[String]]) -> [String] {
        var out = [
            "| " + headers.joined(separator: " | ") + " |",
            "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |",
        ]
        for row in rows {
            out.append("| " + row.map(markdownCell).joined(separator: " | ") + " |")
        }
        return out
    }

    /// Render the report as a Markdown document (trailing newline included).
    public static func markdown(
        _ snapshot: Snapshot, report: SecurityReport? = nil, storage: [StorageDevice] = []
    ) -> String {
        let securityReport = report ?? Security.analyse(snapshot)
        var lines = ["# usbscope report", ""]
        lines.append("- Machine: \(machine(snapshot))")
        lines.append("- Host: \(snapshot.host)")
        lines.append("- Read at: \(timestamp(snapshot.seenAt))")
        lines.append(
            "- Ports: \(snapshot.ports.count) total · \(snapshot.connectedPorts.count) connected · "
                + "\(snapshot.emarkedCables.count) e-marked cable(s)"
        )
        lines.append("- Devices: \(snapshot.devices.count)")
        for section in sections(snapshot, securityReport, storage) {
            lines.append("")
            lines.append("## \(section.title)")
            lines.append("")
            if let headers = section.headers { lines.append(contentsOf: markdownTable(headers, section.rows)) }
            lines.append(contentsOf: section.extra)
        }
        var text = lines.joined(separator: "\n")
        while text.hasSuffix("\n") { text.removeLast() }
        return text + "\n"
    }

    public static func markdown(
        _ snapshot: Snapshot, report: SecurityReport? = nil, storage: [StorageDevice] = [],
        redactionPolicy: RedactionPolicy
    ) -> String {
        redactionPolicy.redactText(markdown(snapshot, report: report, storage: storage),
                                   snapshot: snapshot, storage: storage)
    }

    /// Localized presentation while retaining the stable default English API.
    public static func markdown(
        _ snapshot: Snapshot, report: SecurityReport? = nil, storage: [StorageDevice] = [],
        language: Language
    ) -> String {
        localizedDocument(markdown(snapshot, report: report, storage: storage), language)
    }

    // MARK: - html

    static func escape(_ value: String) -> String {
        var out = value.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        out = out.replacingOccurrences(of: "'", with: "&#x27;")
        return out
    }

    static func htmlTable(_ headers: [String], _ rows: [[String]]) -> [String] {
        var out = [
            "<table>",
            "<thead><tr>" + headers.map { "<th>\(escape($0))</th>" }.joined() + "</tr></thead>",
            "<tbody>",
        ]
        for row in rows {
            out.append("<tr>" + row.map { "<td>\(escape($0))</td>" }.joined() + "</tr>")
        }
        out.append("</tbody>")
        out.append("</table>")
        return out
    }

    /// Render the report as one self-contained HTML page (inline CSS, no assets).
    public static func html(
        _ snapshot: Snapshot, report: SecurityReport? = nil, storage: [StorageDevice] = []
    ) -> String {
        let securityReport = report ?? Security.analyse(snapshot)
        var lines = [
            "<!doctype html>",
            "<html lang=\"en\">",
            "<head>",
            "<meta charset=\"utf-8\">",
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
            "<title>usbscope report</title>",
            "<style>",
            ":root { color-scheme: light dark; }",
            "body { font: 15px/1.5 -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif; "
                + "margin: 2rem auto; max-width: 960px; padding: 0 1rem; "
                + "color: #1b1b1b; background: #fff; }",
            "h1 { font-size: 1.6rem; }",
            "h2 { font-size: 1.15rem; margin-top: 2rem; border-bottom: 1px solid #ddd; "
                + "padding-bottom: .25rem; }",
            "table { border-collapse: collapse; width: 100%; margin: .5rem 0 1rem; }",
            "th, td { text-align: left; padding: .35rem .6rem; "
                + "border-bottom: 1px solid #e5e5e5; vertical-align: top; }",
            "th { font-weight: 600; background: #f6f6f6; }",
            "ul { margin: .3rem 0 1rem 1.2rem; }",
            "</style>",
            "</head>",
            "<body>",
            "<h1>usbscope report</h1>",
            "<ul>",
            "<li><strong>Machine:</strong> \(escape(machine(snapshot)))</li>",
            "<li><strong>Host:</strong> \(escape(snapshot.host))</li>",
            "<li><strong>Read at:</strong> \(escape(timestamp(snapshot.seenAt)))</li>",
            "<li><strong>Ports:</strong> \(snapshot.ports.count) total · "
                + "\(snapshot.connectedPorts.count) connected · "
                + "\(snapshot.emarkedCables.count) e-marked cable(s)</li>",
            "<li><strong>Devices:</strong> \(snapshot.devices.count)</li>",
            "</ul>",
        ]
        for section in sections(snapshot, securityReport, storage) {
            lines.append("<h2>\(escape(section.title))</h2>")
            if let headers = section.headers { lines.append(contentsOf: htmlTable(headers, section.rows)) }
            for line in section.extra where !line.isEmpty {
                if line.hasPrefix("_"), line.hasSuffix("_") {
                    lines.append("<p class=\"muted\">\(escape(String(line.dropFirst().dropLast())))</p>")
                } else if line.hasPrefix("- ") {
                    lines.append("<p>\(escape(String(line.dropFirst(2))))</p>")
                } else {
                    lines.append("<p>\(escape(line))</p>")
                }
            }
        }
        lines.append("</body>")
        lines.append("</html>")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func html(
        _ snapshot: Snapshot, report: SecurityReport? = nil, storage: [StorageDevice] = [],
        redactionPolicy: RedactionPolicy
    ) -> String {
        redactionPolicy.redactText(html(snapshot, report: report, storage: storage),
                                   snapshot: snapshot, storage: storage)
    }

    /// Localized HTML report. The `lang` attribute is kept in sync with the
    /// selected presentation language; machine-readable values are unchanged.
    public static func html(
        _ snapshot: Snapshot, report: SecurityReport? = nil, storage: [StorageDevice] = [],
        language: Language
    ) -> String {
        let document = html(snapshot, report: report, storage: storage)
        let lang = language.rawValue
        return localizedDocument(document.replacingOccurrences(of: "<html lang=\"en\">",
                                                                with: "<html lang=\"\(lang)\">"), language)
    }
}
