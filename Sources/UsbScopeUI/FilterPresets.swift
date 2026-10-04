import Foundation

/// Rows that can answer the toolbar's quick filter presets.
///
/// The presets are a second, coarser filter *on top of* the free-text search:
/// the search keeps a row when every term appears somewhere in it, a preset
/// keeps only rows of a category. A row type that cannot answer a question says
/// `false` rather than guessing — so "HID only" on the Cables view is empty, not
/// wrong.
public protocol PresetFilterable {
    /// The row is a HID (class 3) device or carries one.
    var isHID: Bool { get }
    /// The row is a mass-storage (class 8) device or carries one.
    var isStorage: Bool { get }
    /// The row stands for something that is currently connected.
    var isConnected: Bool { get }
}

/// The quick filters offered in the toolbar.
///
/// `all` is the neutral element (every row passes). The app localises `label`
/// through its own typed string table; the logic stays English.
public enum FilterPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case all
    case hid
    case storage
    case connected

    public var id: String { rawValue }

    /// English label; the app localises it.
    public var label: String {
        switch self {
        case .all: "All"
        case .hid: "HID only"
        case .storage: "Storage only"
        case .connected: "Connected only"
        }
    }

    /// Whether a row passes this preset.
    public func matches(_ row: some PresetFilterable) -> Bool {
        switch self {
        case .all: true
        case .hid: row.isHID
        case .storage: row.isStorage
        case .connected: row.isConnected
        }
    }
}
