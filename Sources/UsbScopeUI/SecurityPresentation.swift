import Foundation
import UsbScopeCore

/// One line of the security findings table.
public struct FindingRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let severity: String
    public let severityStyle: CellStyle
    public let rule: String
    public let subject: String
    public let detail: String
}

/// One USB storage device with the state the Eject button needs.
public struct StorageRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let identifier: String
    public let name: String
    public let capacity: String
    /// `read-only` / `read/write` / `–`.
    public let mode: String
    /// Mount point, or `–` when unmounted.
    public let mount: String
    /// Whether the Eject button is enabled.
    public let ejectEnabled: Bool
    /// Why the button is disabled (shown as the button's help/tooltip).
    public let ejectReason: String?
    /// The argv to run (absolute `diskutil` path, `nil` when not ejectable).
    public let ejectCommand: [String]?
}

/// The security tab's presentation: the CLI's wording and the rules, kept out
/// of the view so the suite can assert them.
///
/// The headline, the "what this is NOT" note and the empty-state wording are
/// copied verbatim from the Rich CLI (`securityView` in `Sources/usbscope/main.swift`),
/// so the app and the CLI say exactly the same thing. They stay English on
/// purpose: they are the tool's honest-limits statement, not chrome.
public enum SecurityPresentation {
    public static let headline = "Security posture — heuristic, not a verdict"

    /// The exact honest-limits paragraph the CLI prints (the CLI reads this constant,
    /// so the two cannot drift).
    public static let honestLimits =
        "honest limits: the class triple is device level, but the interfaces macOS publishes in "
        + "the registry are read too, so a composite device's HID/mass-storage mix is visible — the "
        + "endpoint descriptors, however, are not published at all; a missing serial is a missing "
        + "report, not proof there is none; storage covers only whole disks whose diskutil "
        + "BusProtocol is USB."

    public static let emptyReportText = "nothing stood out in what macOS reports"
    public static let emptyStorageText = "no USB mass storage attached — a Mac without one is normal"

    /// The colour a severity gets.
    public static func style(_ severity: FindingSeverity) -> CellStyle {
        switch severity {
        case .warning: .red
        case .attention: .yellow
        case .info: .cyan
        }
    }

    /// The three count lines the CLI prints, most severe first.
    public static func counts(_ report: SecurityReport) -> [(label: String, count: Int, style: CellStyle)] {
        [
            ("Warning", report.count(.warning), .red),
            ("Attention", report.count(.attention), .yellow),
            ("Info", report.count(.info), .cyan),
        ]
    }

    /// The findings as table rows (the report already ranks them).
    public static func findingRows(_ report: SecurityReport) -> [FindingRow] {
        report.findings.enumerated().map { index, finding in
            FindingRow(
                id: "finding:\(index):\(finding.rule)",
                severity: finding.severity.rawValue,
                severityStyle: style(finding.severity),
                rule: finding.rule,
                subject: finding.subject,
                detail: finding.detail
            )
        }
    }

    /// Read-only state as the CLI words it (`–` when the controller did not say).
    ///
    /// Matched as `.some(true)` / `.some(false)` / `.none` rather than `true` /
    /// `false` / `nil`: over an `Optional<Bool>` an older toolchain (Swift 6.1.2,
    /// Xcode 16.4) does not treat the bare `true`/`false` patterns as covering the
    /// optional, and rejects the switch as non-exhaustive.
    public static func modeText(_ device: StorageDevice) -> String {
        switch device.readOnly {
        case .some(true): "read-only"
        case .some(false): "read/write"
        case .none: "–"
        }
    }

    /// Why a device cannot be ejected, or `nil` when it can.
    ///
    /// `diskutil eject` unmounts and powers off a whole disk, so it is possible
    /// for a mounted *and* an unmounted disk. It is impossible (and therefore
    /// disabled) for a disk without a BSD whole-disk name, or with a name that is
    /// not one (`diskutil` only accepts `disk<number>`).
    public static func ejectDisabledReason(_ device: StorageDevice) -> String? {
        let identifier = device.identifier.trimmingCharacters(in: .whitespaces)
        if identifier.isEmpty { return "no BSD device reported" }
        guard identifier.hasPrefix("disk") else {
            return "'\(identifier)' is not a whole-disk BSD name (disk* required)"
        }
        guard identifier.dropFirst(4).allSatisfy(\.isNumber), identifier.count > 4 else {
            return "'\(identifier)' is not a valid BSD disk name"
        }
        return nil
    }

    /// The `diskutil eject` argv for a device, or `nil` when it is not ejectable.
    public static func ejectCommand(_ device: StorageDevice) -> [String]? {
        guard ejectDisabledReason(device) == nil else { return nil }
        return [Shell.systemBinary("diskutil", "/usr/sbin/diskutil", "/usr/bin/diskutil"), "eject", device.identifier]
    }

    /// The storage inventory as rows.
    public static func storageRows(_ devices: [StorageDevice]) -> [StorageRow] {
        devices.map { device in
            let reason = ejectDisabledReason(device)
            return StorageRow(
                id: device.identifier,
                identifier: device.identifier,
                name: device.label,
                capacity: device.capacityText ?? "–",
                mode: modeText(device),
                mount: device.mountPoint ?? "–",
                ejectEnabled: reason == nil,
                ejectReason: reason,
                ejectCommand: reason == nil ? ejectCommand(device) : nil
            )
        }
    }
}
