import Foundation

/// The views of the app — the Swift twin of `usbscope.macapp.viewmodel.VIEWS`,
/// with a diagnostic Overview plus the port tables and additional history,
/// security, USB4 and diff routes.
///
/// `tableViews` is the original five, in the order the Python `VIEWS` uses: the
/// headless `--print-rows` self test iterates exactly those, so its output did
/// not change when the extra tabs were added.
public enum AppView: String, CaseIterable, Identifiable, Codable, Sendable {
    case overview
    case ports
    case cables
    case devices
    case thunderbolt
    case power
    case timeline
    case security
    case usb4
    case diff
    case warnings

    public var id: String { rawValue }

    /// The five table views, in the Python app's order.
    public static let tableViews: [AppView] = [.ports, .cables, .devices, .thunderbolt, .power, .warnings]

    /// Toolbar label.
    public var title: String {
        switch self {
        case .overview: "Overview"
        case .ports: "Ports"
        case .cables: "Cables"
        case .devices: "Devices"
        case .thunderbolt: "Thunderbolt"
        case .power: "Power"
        case .timeline: "Timeline"
        case .security: "Security"
        case .usb4: "USB4"
        case .diff: "Diff"
        case .warnings: "Warnings"
        }
    }

    /// SF Symbol for the segmented control / menu.
    public var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .ports: "cable.connector"
        case .cables: "link"
        case .devices: "externaldrive.connected.to.line.below"
        case .thunderbolt: "bolt.horizontal"
        case .power: "bolt.fill"
        case .timeline: "chart.xyaxis.line"
        case .security: "lock.shield"
        case .usb4: "point.3.connected.trianglepath.dotted"
        case .diff: "arrow.left.arrow.right"
        case .warnings: "exclamationmark.triangle"
        }
    }
}

/// Semantic cell style, mapped to a colour by the SwiftUI layer.
public enum CellStyle: String, Sendable {
    case `default`
    case dim
    case bold
    case green
    case yellow
    case red
    case cyan
    case magenta
}

/// How a row is marked after a refresh (appeared / disappeared / changed).
public enum Highlight: String, Sendable {
    case added
    case removed
    case changed
}

/// The `⌘n` shortcut and the tooltip of a view.
///
/// Both read the view's position in `allCases`, so the toolbar tooltip, the View menu
/// item and the keyboard shortcut cannot disagree about which number a view answers to.
extension AppView {
    /// The 1-based menu position. The first nine positions receive `⌘1`–`⌘9`;
    /// later views remain reachable through the menu and command palette because
    /// macOS has no single-key `⌘10` equivalent.
    public var shortcutNumber: Int {
        if self == .overview { return 0 }
        let numbered = AppView.allCases.filter { $0 != .overview }
        return (numbered.firstIndex(of: self) ?? 0) + 1
    }

    /// The view's own label plus its shortcut, for a tooltip. Overview is the
    /// landing page and intentionally has no single-key shortcut.
    ///
    /// The label is passed in because the app takes its strings from the typed table;
    /// this type stays language-free.
    public func helpText(_ label: String) -> String {
        shortcutNumber == 0 ? label : "\(label) (⌘\(shortcutNumber))"
    }
}
