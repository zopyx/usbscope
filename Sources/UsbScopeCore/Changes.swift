import Foundation

/// Diffing two snapshots: what appeared, what disappeared, what changed.
///
/// This is the canonical differ of the Swift port and the twin of
/// `usbscope.macapp.changes`. It lives in the core (headless) layer rather than
/// in `UsbScopeUI` because the hotplug watcher (`UsbEvents.swift`) and the
/// snapshot history (`SnapshotHistory.swift`) build on it too — the UI only adds
/// the `Highlight` mapping (`UsbScopeUI.highlight(for:)`).
public enum ChangeKind: String, Sendable {
    case added
    case removed
    case changed
}

public enum DeviceIdentityStrength: String, Codable, Sendable, CaseIterable {
    case locationID
    case serial
    case busPortPath
    case vendorProductName
    case readLocal
}

public struct DeviceIdentity: Equatable, Sendable {
    public let key: String
    public let strength: DeviceIdentityStrength
    public let isWeak: Bool

    public init(key: String, strength: DeviceIdentityStrength) {
        self.key = key
        self.strength = strength
        self.isWeak = strength == .vendorProductName || strength == .readLocal
    }
}

/// Explain which available identity facts support a diff key. The legacy key
/// format remains unchanged for compatibility with existing event logs and
/// snapshot consumers.
public func deviceIdentity(_ device: UsbDevice) -> DeviceIdentity {
    if let locationID = device.locationID {
        return DeviceIdentity(key: "device:location:\(String(format: "%08x", locationID))", strength: .locationID)
    }
    if let serial = device.serial, !serial.isEmpty {
        return DeviceIdentity(key: "device:serial:\(serial)", strength: .serial)
    }
    if let bus = device.bus, !bus.isEmpty, let port = device.port, !port.isEmpty {
        return DeviceIdentity(key: "device:path:\(bus):\(port)", strength: .busPortPath)
    }
    let vendor = device.vendorID.map { String(format: "%04x", $0) } ?? "????"
    let product = device.productID.map { String(format: "%04x", $0) } ?? "????"
    return DeviceIdentity(key: "device:\(vendor):\(product):\(device.name.lowercased())", strength: .vendorProductName)
}

/// A stable identity for a device across reads.
///
/// A serial number identifies a device best; without one the vendor/product ID
/// plus the location ID is used, and the name is appended as a last resort so
/// two identical models on different ports are not merged.
public func deviceKey(_ device: UsbDevice) -> String {
    if let serial = device.serial {
        return "device:serial:\(serial)"
    }
    let vendor = device.vendorID.map { String(format: "%04x", $0) } ?? "????"
    let product = device.productID.map { String(format: "%04x", $0) } ?? "????"
    let location = device.locationID.map { String(format: "%08x", $0) } ?? "????????"
    return "device:\(vendor):\(product):\(location):\(device.name.lowercased())"
}

/// The key a port row is addressed by.
public func portKey(_ port: UsbPort) -> String { "port:\(port.name)" }

/// The key a Thunderbolt receptacle is addressed by.
public func thunderboltKey(_ port: ThunderboltPort) -> String {
    "tb:\(port.bus):\(port.receptacle.map(String.init) ?? "-")"
}

/// The key a charging metric is addressed by.
public func powerKey(_ label: String) -> String { "power:\(label)" }

/// The part of a port's state that counts as a change.
private func portSignature(_ port: UsbPort) -> [String?] {
    let mode = port.usbTransport?.mode.label
    return [
        String(port.connected),
        mode,
        port.cable.kind,
        port.liquidDetected.map(String.init),
        String(port.devices.count),
    ]
}

/// What changed between two reads.
public struct ChangeSet: Sendable {
    public var added: [UsbDevice] = []
    public var removed: [UsbDevice] = []
    public var changedPorts: [String] = []

    public init() {}

    public var count: Int { added.count + removed.count + changedPorts.count }
    public var isEmpty: Bool { count == 0 }
    public var deviceCount: Int { added.count + removed.count }

    /// Short human readable description, e.g. `1 added · 1 removed`.
    public var summary: String {
        if isEmpty { return "no changes" }
        var parts: [String] = []
        if !added.isEmpty { parts.append("\(added.count) added") }
        if !removed.isEmpty { parts.append("\(removed.count) removed") }
        if !changedPorts.isEmpty { parts.append("\(changedPorts.count) port state changed") }
        return parts.joined(separator: " · ")
    }

    /// Classify a row key as added / removed / changed.
    public func tag(_ key: String) -> ChangeKind? {
        if added.contains(where: { deviceKey($0) == key }) { return .added }
        if removed.contains(where: { deviceKey($0) == key }) { return .removed }
        if changedPorts.contains(key) { return .changed }
        return nil
    }
}

/// Compare two snapshots.
///
/// Without a `previous` snapshot nothing is reported as added — the first read
/// of a session is not a plug event.
public func diffSnapshots(previous: Snapshot?, current: Snapshot) -> ChangeSet {
    guard let previous else { return ChangeSet() }
    let before = Dictionary(previous.devices.map { (deviceKey($0), $0) }, uniquingKeysWith: { first, _ in first })
    let after = Dictionary(current.devices.map { (deviceKey($0), $0) }, uniquingKeysWith: { first, _ in first })
    var changes = ChangeSet()
    changes.added = after.keys.filter { before[$0] == nil }.map { after[$0]! }
    changes.removed = before.keys.filter { after[$0] == nil }.map { before[$0]! }
    let previousPorts = Dictionary(
        previous.ports.map { (portKey($0), portSignature($0)) }, uniquingKeysWith: { first, _ in first }
    )
    changes.changedPorts = current.ports.compactMap { port in
        let key = portKey(port)
        guard let old = previousPorts[key], old != portSignature(port) else { return nil }
        return key
    }
    return changes
}
