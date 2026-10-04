import Foundation

/// Baseline: save a snapshot and tell whether the live machine still matches —
/// the twin of `usbscope/baseline.py`.
///
/// `usbscope baseline save <file>` writes the current `schema_version: 1`
/// snapshot document (the same JSON `usbscope --json` prints), so a baseline is
/// interchangeable with any other snapshot a script keeps. `usbscope baseline
/// check <file>` compares that file against a fresh read and reports which
/// receptacles appeared, disappeared or changed state, plus the devices that
/// came and went.
///
/// The comparison runs on the *JSON documents*, not on two live objects: a
/// baseline may have been written by the Python twin, and the snapshot schema is
/// the only contract between the implementations. `seen_at` is the one field
/// that always differs and is therefore ignored.
///
/// Identity rules (mirrored in the Python twin so both agree): a port is keyed
/// by its `name`, a device by its `location_id` when it has one, else by name.
public enum BaselineError: Error, CustomStringConvertible, Equatable {
    case unreadable(String)
    case notJSON(String)
    case notASnapshot(String)

    public var description: String {
        switch self {
        case let .unreadable(message), let .notJSON(message), let .notASnapshot(message): message
        }
    }
}

/// What differs between a saved baseline and the live snapshot.
public struct BaselineDiff: Equatable, Sendable {
    public var appearedPorts: [String] = []
    public var disappearedPorts: [String] = []
    public var changedPorts: [String] = []
    public var appearedDevices: [String] = []
    public var disappearedDevices: [String] = []

    public init() {}

    /// True when nothing differs (ignoring `seen_at`).
    public var identical: Bool {
        appearedPorts.isEmpty && disappearedPorts.isEmpty && changedPorts.isEmpty
            && appearedDevices.isEmpty && disappearedDevices.isEmpty
    }

    /// Machine readable form (`kind: baseline`).
    public var dictionary: [String: Any] {
        [
            "kind": "baseline",
            "identical": identical,
            "appeared_ports": appearedPorts,
            "disappeared_ports": disappearedPorts,
            "changed_ports": changedPorts,
            "appeared_devices": appearedDevices,
            "disappeared_devices": disappearedDevices,
        ]
    }
}

public enum Baseline {
    /// Write the current snapshot as a baseline JSON document.
    public static func save(_ snapshot: Snapshot, to path: String) throws {
        try (Serialize.json(snapshot) + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Read and validate a baseline document.
    public static func load(_ path: String) throws -> [String: Any] {
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw BaselineError.unreadable("cannot read baseline \(path): \(error.localizedDescription)")
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw BaselineError.notJSON("\(path) is not valid JSON: \(error.localizedDescription)")
        }
        guard let document = object as? [String: Any], document["ports"] != nil,
              document["schema_version"] != nil
        else {
            throw BaselineError.notASnapshot("\(path) is not a usbscope snapshot document")
        }
        return document
    }

    // MARK: - diffing

    static func portSignatures(_ port: [String: Any]) -> String {
        let connected = jsonBool(port["connected"]).map(String.init) ?? "nil"
        let mode = port["mode"] as? String ?? "nil"
        let cableKind = (port["cable"] as? [String: Any])?["kind"] as? String ?? "nil"
        let liquid = jsonBool(port["liquid_detected"]).map(String.init) ?? "nil"
        let devices = (port["devices"] as? [Any])?.count ?? 0
        return "\(connected)|\(mode)|\(cableKind)|\(liquid)|\(devices)"
    }

    static func deviceKey(_ device: [String: Any]) -> String {
        if let location = device["location_id"] as? Int { return "loc:\(location)" }
        return "name:\(device["name"] as? String ?? "")"
    }

    static func ports(_ document: [String: Any]) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for port in document["ports"] as? [[String: Any]] ?? [] {
            if let name = port["name"] as? String { result[name] = port }
        }
        return result
    }

    /// Every device of the document: on a bus and on a port, by identity.
    static func devices(_ document: [String: Any]) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        func add(_ device: [String: Any]) {
            guard device["name"] is String else { return }
            let key = deviceKey(device)
            if result[key] == nil { result[key] = device }
        }
        for bus in document["buses"] as? [[String: Any]] ?? [] {
            for device in bus["devices"] as? [[String: Any]] ?? [] { add(device) }
        }
        for port in document["ports"] as? [[String: Any]] ?? [] {
            for device in port["devices"] as? [[String: Any]] ?? [] { add(device) }
        }
        return result
    }

    /// Diff two snapshot documents, ignoring only `seen_at`.
    public static func compare(previous: [String: Any], current: [String: Any]) -> BaselineDiff {
        let before = ports(previous)
        let after = ports(current)
        var diff = BaselineDiff()
        diff.appearedPorts = after.keys.filter { before[$0] == nil }.sorted()
        diff.disappearedPorts = before.keys.filter { after[$0] == nil }.sorted()
        diff.changedPorts = after.keys.filter { name in
            guard let old = before[name], let new = after[name] else { return false }
            return portSignatures(old) != portSignatures(new)
        }.sorted()
        let beforeDevices = devices(previous)
        let afterDevices = devices(current)
        diff.appearedDevices = afterDevices.keys.filter { beforeDevices[$0] == nil }.sorted()
        diff.disappearedDevices = beforeDevices.keys.filter { afterDevices[$0] == nil }.sorted()
        return diff
    }

    /// JSON text of a diff (sorted keys, so a consumer sees a stable document).
    public static func json(_ diff: BaselineDiff) -> String {
        sortedJSONText(diff.dictionary, pretty: true)
    }

    /// Plain-text report of a baseline comparison.
    public static func render(_ diff: BaselineDiff, path: String) -> String {
        var lines = ["baseline: \(path)"]
        let groups: [(String, [String])] = [
            ("appeared ports", diff.appearedPorts),
            ("disappeared ports", diff.disappearedPorts),
            ("changed ports", diff.changedPorts),
            ("appeared devices", diff.appearedDevices),
            ("disappeared devices", diff.disappearedDevices),
        ]
        for (label, names) in groups where !names.isEmpty {
            lines.append("  \(label): " + names.joined(separator: ", "))
        }
        lines.append(diff.identical ? "identical to baseline" : "differs from baseline")
        return lines.joined(separator: "\n")
    }
}

/// A JSON boolean, tolerating the `NSNumber` bridging pitfall the project knows
/// about: on Darwin a `0`/`1` bridges to `Bool`, so this checks the CF type
/// (`CFBooleanGetTypeID`) instead of `as? Bool` alone.
func jsonBool(_ value: Any?) -> Bool? {
    guard let value, !(value is NSNull) else { return nil }
    guard CFGetTypeID(value as AnyObject) == CFBooleanGetTypeID() else { return nil }
    return (value as AnyObject) as? Bool
}
