import Foundation

/// The views of the app — the Swift twin of `usbscope.macapp.viewmodel.VIEWS`
/// plus the four tabs the Swift app adds on top of the port tables
/// (`timeline`, `security`, `usb4`, `diff`).
///
/// `tableViews` is the original five, in the order the Python `VIEWS` uses: the
/// headless `--print-rows` self test iterates exactly those, so its output did
/// not change when the extra tabs were added.
public enum AppView: String, CaseIterable, Identifiable, Codable, Sendable {
    case ports
    case cables
    case devices
    case thunderbolt
    case power
    case timeline
    case security
    case usb4
    case diff

    public var id: String { rawValue }

    /// The five table views, in the Python app's order.
    public static let tableViews: [AppView] = [.ports, .cables, .devices, .thunderbolt, .power]

    /// Toolbar label.
    public var title: String {
        switch self {
        case .ports: "Ports"
        case .cables: "Cables"
        case .devices: "Devices"
        case .thunderbolt: "Thunderbolt"
        case .power: "Power"
        case .timeline: "Timeline"
        case .security: "Security"
        case .usb4: "USB4"
        case .diff: "Diff"
        }
    }

    /// SF Symbol for the segmented control / menu.
    public var systemImage: String {
        switch self {
        case .ports: "cable.connector"
        case .cables: "link"
        case .devices: "externaldrive.connected.to.line.below"
        case .thunderbolt: "bolt.horizontal"
        case .power: "bolt.fill"
        case .timeline: "chart.xyaxis.line"
        case .security: "lock.shield"
        case .usb4: "point.3.connected.trianglepath.dotted"
        case .diff: "arrow.left.arrow.right"
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
    /// The number of the `⌘n` shortcut this view answers to (1-based).
    public var shortcutNumber: Int {
        (AppView.allCases.firstIndex(of: self) ?? 0) + 1
    }

    /// `Security (⌘7)` — the view's own label plus its shortcut, for a tooltip.
    ///
    /// The label is passed in because the app takes its strings from the typed table;
    /// this type stays language-free.
    public func helpText(_ label: String) -> String {
        "\(label) (⌘\(shortcutNumber))"
    }
}
