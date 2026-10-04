import Foundation
import UsbScopeCore

/// Grouping of the Ports and Devices tables by bus / class / speed.
///
/// The whole logic lives here as pure functions so it is unit-testable without
/// a window server; the SwiftUI layer only renders the `RowGroup`s it returns.
/// A port has no bus of its own, so `.bus` groups ports by their connector
/// family (`kind`) and `.deviceClass` by the class of the attached device.

/// A grouping dimension offered by the toolbar toggle.
public enum GroupField: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case bus
    case deviceClass
    case speed

    public var id: String { rawValue }

    /// English label; the app localises it through its own strings table.
    public var label: String {
        switch self {
        case .none: "None"
        case .bus: "Bus"
        case .deviceClass: "Class"
        case .speed: "Speed"
        }
    }

    /// The fields a view offers; an empty array hides the toggle.
    public static func fields(for view: AppView) -> [GroupField] {
        switch view {
        case .ports, .devices: [.none, .bus, .deviceClass, .speed]
        case .cables, .thunderbolt, .power, .timeline, .security, .usb4, .diff, .warnings: []
        }
    }
}

/// One titled bucket of rows, in display order.
public struct RowGroup<Row: Identifiable>: Identifiable {
    public let id: String
    public let title: String
    public let rows: [Row]

    public init(id: String, title: String, rows: [Row]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}

/// The bucket a row belongs to: a title and a sort order (lower first).
public struct GroupSpec: Equatable, Sendable {
    public let title: String
    public let order: Int

    public init(title: String, order: Int = 0) {
        self.title = title
        self.order = order
    }
}

/// Bucket rows by `spec`, keeping the incoming order inside a bucket and
/// ordering the buckets by `order`, then case-insensitively by title.
///
/// A single `RowGroup` titled `""` is returned for `.none`, so callers can use
/// the grouped rendering unconditionally.
public func grouped<Row: Identifiable>(
    _ rows: [Row],
    by spec: (Row) -> GroupSpec
) -> [RowGroup<Row>] {
    var order: [String] = []
    var orders: [String: Int] = [:]
    var buckets: [String: [Row]] = [:]
    for row in rows {
        let key = spec(row)
        if buckets[key.title] == nil {
            order.append(key.title)
            orders[key.title] = key.order
        }
        buckets[key.title, default: []].append(row)
    }
    return order
        .sorted { lhs, rhs in
            let lo = orders[lhs] ?? 0
            let ro = orders[rhs] ?? 0
            if lo != ro { return lo < ro }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        .map { RowGroup(id: $0, title: $0, rows: buckets[$0] ?? []) }
}

/// Human bucket name for a `UsbMode` rank (`0` means no link).
public func speedGroupLabel(_ rank: Int) -> String {
    guard rank > 0, let mode = UsbMode.allCases.first(where: { $0.rank == rank }) else {
        return "no link"
    }
    return mode.label
}

/// The group a port row belongs to.
public func groupSpec(for row: PortRow, by field: GroupField) -> GroupSpec {
    switch field {
    case .none:
        GroupSpec(title: "")
    case .bus:
        GroupSpec(title: row.kind.text)
    case .deviceClass:
        GroupSpec(title: row.attachedClass.isEmpty ? "no device" : row.attachedClass)
    case .speed:
        GroupSpec(title: speedGroupLabel(row.modeSort), order: -row.modeSort)
    }
}

/// The group a device row belongs to.
public func groupSpec(for row: DeviceRow, by field: GroupField) -> GroupSpec {
    switch field {
    case .none:
        GroupSpec(title: "")
    case .bus:
        GroupSpec(title: row.bus.text)
    case .deviceClass:
        GroupSpec(title: row.deviceClass.text)
    case .speed:
        GroupSpec(title: speedGroupLabel(row.modeSort), order: -row.modeSort)
    }
}

public func groups(for rows: [PortRow], by field: GroupField) -> [RowGroup<PortRow>] {
    grouped(rows, by: { groupSpec(for: $0, by: field) })
}

public func groups(for rows: [DeviceRow], by field: GroupField) -> [RowGroup<DeviceRow>] {
    grouped(rows, by: { groupSpec(for: $0, by: field) })
}
