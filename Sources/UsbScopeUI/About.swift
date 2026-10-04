import Foundation
import UsbScopeCore

/// One label/value line of the About window.
public struct AboutFact: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

/// The content of the About window, kept out of the view so the Swift suite can
/// assert it (the project never ships untested logic).
///
/// The product copy (name, tagline, licence, copyright) stays English on
/// purpose — an About box is a product surface, not chrome; only the
/// interactive labels are localised through the app's string table.
public enum AboutInfo {
    public static let name = "usbscope"
    public static let tagline = "See what macOS knows about your USB ports, cables and link modes."
    public static let license = "MIT licensed"
    public static let copyright = "© 2026 Andreas Jung / ZOPYX"
    public static let dataNote = "Everything is read locally. Nothing leaves this Mac."
    public static let repositoryURL = "https://github.com/zopyx/usbscope"
    public static let documentationURL = "https://github.com/zopyx/usbscope/blob/main/docs/index.md"

    /// Used when the process has no bundle (`swift run`); a bundled app reports
    /// `CFBundleShortVersionString` instead.
    public static let fallbackVersion = "0.9.0"

    /// The live facts of this Mac, or an empty list before the first read.
    public static func facts(_ snapshot: Snapshot?) -> [AboutFact] {
        guard let snapshot else { return [] }
        var facts: [AboutFact] = []
        let machine = [snapshot.model, snapshot.chip].compactMap { $0 }.joined(separator: " · ")
        if !machine.isEmpty { facts.append(AboutFact("Machine", machine)) }
        if !snapshot.osVersion.isEmpty { facts.append(AboutFact("macOS", snapshot.osVersion)) }
        facts.append(
            AboutFact(
                "Ports",
                "\(snapshot.ports.count) total, \(snapshot.connectedPorts.count) connected"
            )
        )
        facts.append(AboutFact("Devices", "\(snapshot.devices.count)"))
        facts.append(AboutFact("Cables", "\(snapshot.emarkedCables.count) e-marked"))
        facts.append(AboutFact("USB4 / Thunderbolt", "\(snapshot.thunderbolt.count) receptacle(s)"))
        facts.append(AboutFact("Data sources", "\(snapshot.warnings.count) warning(s)"))
        facts.append(AboutFact("Snapshot schema", "version \(Serialize.schemaVersion)"))
        return facts
    }

    /// The copyable diagnostics block behind the About window's copy button.
    public static func diagnostics(version: String, snapshot: Snapshot?) -> String {
        var lines = [
            "\(name) \(version)",
            "\(license) · \(copyright)",
            repositoryURL,
        ]
        for fact in facts(snapshot) {
            lines.append("\(fact.label): \(fact.value)")
        }
        if let snapshot {
            lines.append("Host: \(snapshot.host)")
            lines.append("Read at: \(snapshot.seenAt.formatted(date: .abbreviated, time: .standard))")
            if !snapshot.warnings.isEmpty {
                lines.append("Warnings: \(snapshot.warnings.joined(separator: " · "))")
            }
        }
        return lines.joined(separator: "\n")
    }
}
