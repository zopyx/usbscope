import Foundation
import UsbScopeUI

/// Stable names for SwiftUI table sort descriptors. `KeyPathComparator` itself
/// is not Codable, so the preference stores a small per-view key and direction.
enum TableSortPersistence {
    static func ports(_ preference: (key: String?, ascending: Bool)) -> [KeyPathComparator<PortRow>] {
        switch preference.key {
        case "kind": return [KeyPathComparator(\.kindSort, order: preference.ascending ? .forward : .reverse)]
        case "state": return [KeyPathComparator(\.stateSort, order: preference.ascending ? .forward : .reverse)]
        case "mode": return [KeyPathComparator(\.modeSort, order: preference.ascending ? .forward : .reverse)]
        case "transports": return [KeyPathComparator(\.transportsSort, order: preference.ascending ? .forward : .reverse)]
        case "cable": return [KeyPathComparator(\.cableSort, order: preference.ascending ? .forward : .reverse)]
        case "notes": return [KeyPathComparator(\.notesSort, order: preference.ascending ? .forward : .reverse)]
        default: return [KeyPathComparator(\.nameSort, order: preference.key == "name" && !preference.ascending ? .reverse : .forward)]
        }
    }

    static func portKey(_ comparator: KeyPathComparator<PortRow>) -> String {
        if comparator.keyPath == \PortRow.kindSort { return "kind" }
        if comparator.keyPath == \PortRow.stateSort { return "state" }
        if comparator.keyPath == \PortRow.modeSort { return "mode" }
        if comparator.keyPath == \PortRow.transportsSort { return "transports" }
        if comparator.keyPath == \PortRow.cableSort { return "cable" }
        if comparator.keyPath == \PortRow.notesSort { return "notes" }
        return "name"
    }

    static func cables(_ preference: (key: String?, ascending: Bool)) -> [KeyPathComparator<CableRow>] {
        switch preference.key {
        case "cable": return [KeyPathComparator(\.cableSort, order: preference.ascending ? .forward : .reverse)]
        case "authentication": return [KeyPathComparator(\.authenticationSort, order: preference.ascending ? .forward : .reverse)]
        case "hash": return [KeyPathComparator(\.hashSort, order: preference.ascending ? .forward : .reverse)]
        case "spec": return [KeyPathComparator(\.specSort, order: preference.ascending ? .forward : .reverse)]
        case "power": return [KeyPathComparator(\.powerSort, order: preference.ascending ? .forward : .reverse)]
        case "contract": return [KeyPathComparator(\.contractSort, order: preference.ascending ? .forward : .reverse)]
        case "liquid": return [KeyPathComparator(\.liquidSort, order: preference.ascending ? .forward : .reverse)]
        case "firmware": return [KeyPathComparator(\.firmwareSort, order: preference.ascending ? .forward : .reverse)]
        default: return [KeyPathComparator(\.portSort, order: preference.key == "port" && !preference.ascending ? .reverse : .forward)]
        }
    }

    static func cableKey(_ comparator: KeyPathComparator<CableRow>) -> String {
        if comparator.keyPath == \CableRow.cableSort { return "cable" }
        if comparator.keyPath == \CableRow.authenticationSort { return "authentication" }
        if comparator.keyPath == \CableRow.hashSort { return "hash" }
        if comparator.keyPath == \CableRow.specSort { return "spec" }
        if comparator.keyPath == \CableRow.powerSort { return "power" }
        if comparator.keyPath == \CableRow.contractSort { return "contract" }
        if comparator.keyPath == \CableRow.liquidSort { return "liquid" }
        if comparator.keyPath == \CableRow.firmwareSort { return "firmware" }
        return "port"
    }

    static func devices(_ preference: (key: String?, ascending: Bool)) -> [KeyPathComparator<DeviceRow>] {
        switch preference.key {
        case "vendor": return [KeyPathComparator(\.vendorSort, order: preference.ascending ? .forward : .reverse)]
        case "id": return [KeyPathComparator(\.idSort, order: preference.ascending ? .forward : .reverse)]
        case "mode": return [KeyPathComparator(\.modeSort, order: preference.ascending ? .forward : .reverse)]
        case "class": return [KeyPathComparator(\.classSort, order: preference.ascending ? .forward : .reverse)]
        case "tier": return [KeyPathComparator(\.tierSort, order: preference.ascending ? .forward : .reverse)]
        case "port": return [KeyPathComparator(\.portSort, order: preference.ascending ? .forward : .reverse)]
        case "transport": return [KeyPathComparator(\.transportSort, order: preference.ascending ? .forward : .reverse)]
        case "serial": return [KeyPathComparator(\.serialSort, order: preference.ascending ? .forward : .reverse)]
        case "restricted": return [KeyPathComparator(\.restrictedSort, order: preference.ascending ? .forward : .reverse)]
        default: return [KeyPathComparator(\.nameSort, order: preference.key == "name" && !preference.ascending ? .reverse : .forward)]
        }
    }

    static func deviceKey(_ comparator: KeyPathComparator<DeviceRow>) -> String {
        if comparator.keyPath == \DeviceRow.vendorSort { return "vendor" }
        if comparator.keyPath == \DeviceRow.idSort { return "id" }
        if comparator.keyPath == \DeviceRow.modeSort { return "mode" }
        if comparator.keyPath == \DeviceRow.classSort { return "class" }
        if comparator.keyPath == \DeviceRow.tierSort { return "tier" }
        if comparator.keyPath == \DeviceRow.portSort { return "port" }
        if comparator.keyPath == \DeviceRow.transportSort { return "transport" }
        if comparator.keyPath == \DeviceRow.serialSort { return "serial" }
        if comparator.keyPath == \DeviceRow.restrictedSort { return "restricted" }
        return "name"
    }

    static func thunderbolt(_ preference: (key: String?, ascending: Bool)) -> [KeyPathComparator<ThunderboltRow>] {
        switch preference.key {
        case "receptacle": return [KeyPathComparator(\.receptacleSort, order: preference.ascending ? .forward : .reverse)]
        case "state": return [KeyPathComparator(\.stateSort, order: preference.ascending ? .forward : .reverse)]
        case "link": return [KeyPathComparator(\.linkSort, order: preference.ascending ? .forward : .reverse)]
        case "host": return [KeyPathComparator(\.hostSort, order: preference.ascending ? .forward : .reverse)]
        default: return [KeyPathComparator(\.busSort, order: preference.key == "bus" && !preference.ascending ? .reverse : .forward)]
        }
    }

    static func thunderboltKey(_ comparator: KeyPathComparator<ThunderboltRow>) -> String {
        if comparator.keyPath == \ThunderboltRow.receptacleSort { return "receptacle" }
        if comparator.keyPath == \ThunderboltRow.stateSort { return "state" }
        if comparator.keyPath == \ThunderboltRow.linkSort { return "link" }
        if comparator.keyPath == \ThunderboltRow.hostSort { return "host" }
        return "bus"
    }

    static func power(_ preference: (key: String?, ascending: Bool)) -> [KeyPathComparator<PowerRow>] {
        switch preference.key {
        case "value": return [KeyPathComparator(\.valueSort, order: preference.ascending ? .forward : .reverse)]
        default: return [KeyPathComparator(\.metricSort, order: preference.key == "metric" && !preference.ascending ? .reverse : .forward)]
        }
    }

    static func powerKey(_ comparator: KeyPathComparator<PowerRow>) -> String {
        comparator.keyPath == \PowerRow.valueSort ? "value" : "metric"
    }
}
