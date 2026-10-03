import Foundation

/// The five views of the app — the Swift twin of `usbscope.macapp.viewmodel.VIEWS`.
public enum AppView: String, CaseIterable, Identifiable, Codable, Sendable {
    case ports
    case cables
    case devices
    case thunderbolt
    case power

    public var id: String { rawValue }

    /// Toolbar label.
    public var title: String {
        switch self {
        case .ports: "Ports"
        case .cables: "Cables"
        case .devices: "Devices"
        case .thunderbolt: "Thunderbolt"
        case .power: "Power"
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
