import Foundation
import IOKit

/// Reads the `IOPort` registry plane **in-process** through IOKit.
///
/// This is *Plan B* from `docs/app-store.md`: a sandboxed build may not be able
/// to spawn `/usr/bin/ioreg`, so the very same tree `ioreg -a -l -w0 -p IOPort`
/// prints is collected through the public IOKit API instead —
///
///   * `IOServiceGetMatchingServices` finds the port-manager services,
///   * `IORegistryEntryCreateCFProperties` snapshots each node's property table,
///   * `IORegistryEntryCreateCFProperty` reads a node's `IOClass`,
///   * `IORegistryEntryCreateIterator` walks the children, which are assembled
///     under the same `IORegistryEntryChildren` key `ioreg` emits.
///
/// The resulting dictionary has the exact shape `IOReg.parsePorts` already
/// consumes, so the parser (and everything above it) stays untouched. `runner()`
/// wraps it as a `Runner`, which lets an `IoregSource` — and therefore the whole
/// `SnapshotBuilder` — be built on it without a subprocess at all.
///
/// Two deliberate differences from the `ioreg` subprocess are worth naming:
///
///   * Registry values that are an `OSSet` (e.g. `PowerSourceOptions`) are
///     emitted as an array sorted by a **canonical, process independent key**
///     (canonical JSON of the member), because `ioreg` gives no order guarantee
///     for a set and a stable snapshot is more useful. Sorting by the member's
///     `description` would *not* be stable: Swift renders a dictionary in the
///     process' random hash order, so the array would rotate between runs.
///   * Kernel `CFNumber`s stay numbers (`CFNumberGetTypeID`), so an integer `0`
///     or `1` is never mistaken for a `Bool` — the `NSNumber`→`Bool` bridge trap
///     the adapters already guard against with `PlistValue.isBool`.
public enum IORegistryReader {
    /// The registry plane `ioreg -p IOPort` reads.
    public static let plane = "IOPort"

    /// Port-manager service classes that expose receptacle nodes.
    ///
    /// `AppleHPMInterface` covers the USB-C/MagSafe ports, `AppleHDMIPortController`
    /// the HDMI receptacle and `AppleSDXCSlot` the SD card slot. They are the
    /// service classes whose nodes carry `PortDescription`/`PortTypeDescription`.
    public static let portManagerClasses = [
        "AppleHPMInterface",
        "AppleHDMIPortController",
        "AppleSDXCSlot",
    ]

    /// Recursion guard: the registry is a graph, a cycle must not hang the reader.
    static let maxDepth = 24

    // MARK: - public API

    /// The `IOPort` plane as the plist dictionary `IOReg.parsePorts` consumes.
    ///
    /// - Throws: `IORegistryReaderError` when the registry cannot be reached or
    ///   reports no port entry at all (e.g. under a restrictive sandbox).
    public static func ioportTree() throws -> [String: Any] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { throw IORegistryReaderError.mainPortUnavailable }
        defer { IOObjectRelease(root) }

        var seen: Set<UInt64> = [entryID(root)]
        var children: [[String: Any]] = []
        for className in portManagerClasses {
            guard let matching = IOServiceMatching(className) else { continue }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
                == KERN_SUCCESS
            else { continue }
            var entry = IOIteratorNext(iterator)
            while entry != 0 {
                let id = entryID(entry)
                if !seen.contains(id) {
                    seen.insert(id)
                    children.append(build(entry, depth: 0, seen: &seen))
                }
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }

        // Machines whose port nodes are not one of the classes above: walk the
        // plane itself, which is what `ioreg -p IOPort` does.
        if children.isEmpty {
            var iterator: io_iterator_t = 0
            if IORegistryEntryCreateIterator(root, plane, 0, &iterator) == KERN_SUCCESS {
                var entry = IOIteratorNext(iterator)
                while entry != 0 {
                    let id = entryID(entry)
                    if !seen.contains(id) {
                        seen.insert(id)
                        children.append(build(entry, depth: 0, seen: &seen))
                    }
                    IOObjectRelease(entry)
                    entry = IOIteratorNext(iterator)
                }
                IOObjectRelease(iterator)
            }
        }

        guard !children.isEmpty else { throw IORegistryReaderError.noPortEntries }
        return ["IORegistryEntryName": "Root", "IORegistryEntryChildren": children]
    }

    /// The registry tree as XML plist data — the payload `ioreg` would print.
    public static func plistData() throws -> Data {
        let tree = try ioportTree()
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: tree, format: .xml, options: 0
            )
        } catch {
            throw IORegistryReaderError.serializationFailed
        }
    }

    /// A `Runner` that ignores its arguments and serves the in-process plist.
    ///
    /// `IoregSource(runner: IORegistryReader.runner())` is a drop-in replacement
    /// for the subprocess-backed source: the parser and the snapshot builder do
    /// not change.
    public static func runner() -> Runner {
        { argv in
            do {
                return CommandResult(argv: argv, returncode: 0, stdout: try plistData())
            } catch {
                return CommandResult(
                    argv: argv, returncode: 1, error: "IORegistryReader: \(error)"
                )
            }
        }
    }

    /// An `IoregSource` backed by this reader instead of the `ioreg` binary.
    public static func ioregSource() -> IoregSource {
        IoregSource(runner: runner())
    }

    // MARK: - tree assembly

    static func build(
        _ entry: io_registry_entry_t, depth: Int, seen: inout Set<UInt64>
    ) -> [String: Any] {
        var node = sanitizedProperties(entry)
        node["IORegistryEntryName"] = entryName(entry)
        node["IORegistryEntryID"] = entryID(entry)
        if let name = entryClass(entry) { node["IORegistryEntryClass"] = name }
        guard depth < maxDepth else {
            node["IORegistryEntryChildren"] = [Any]()
            return node
        }
        var children: [[String: Any]] = []
        var iterator: io_iterator_t = 0
        if IORegistryEntryCreateIterator(entry, plane, 0, &iterator) == KERN_SUCCESS {
            var child = IOIteratorNext(iterator)
            while child != 0 {
                let id = entryID(child)
                if !seen.contains(id) {
                    seen.insert(id)
                    children.append(build(child, depth: depth + 1, seen: &seen))
                }
                IOObjectRelease(child)
                child = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        node["IORegistryEntryChildren"] = children
        return node
    }

    static func sanitizedProperties(_ entry: io_registry_entry_t) -> [String: Any] {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0)
            == KERN_SUCCESS,
            let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else { return [:] }
        var clean: [String: Any] = [:]
        for (key, value) in dictionary {
            if let sanitized = sanitize(value) { clean[key] = sanitized }
        }
        return clean
    }

    // MARK: - value coercion

    /// Make a registry value property-list compatible.
    ///
    /// Kernel objects bridge to `String`, `Data`, `[Any]`, `[String: Any]` and
    /// `NSNumber`; an `OSSet` has no plist equivalent, so its members are emitted
    /// as a sorted array. Anything else is rendered as text rather than dropped,
    /// so a surprise type is visible instead of silently missing.
    static func sanitize(_ value: Any) -> Any? {
        if let number = value as? NSNumber {
            // A CFBoolean and a CFNumber both bridge to NSNumber on Darwin.
            return PlistValue.isBool(number) ? number.boolValue : number
        }
        if let text = value as? String { return text }
        if let data = value as? Data { return data }
        if CFGetTypeID(value as CFTypeRef) == CFSetGetTypeID() {
            // `value` is an OSSet here (bridged happens to be empty otherwise).
            return sanitizeSet(value as! CFSet)
        }
        if let array = value as? [Any] { return array.compactMap { sanitize($0) } }
        if let dictionary = value as? [String: Any] {
            return dictionary.compactMapValues { sanitize($0) }
        }
        return String(describing: value)
    }

    private static func sanitizeSet(_ set: CFSet) -> [Any] {
        let count = CFSetGetCount(set)
        var values = [UnsafeRawPointer?](repeating: nil, count: count)
        CFSetGetValues(set, &values)
        let members = values.compactMap { pointer -> Any? in
            guard let pointer else { return nil }
            return sanitize(Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue())
        }
        return canonicalOrder(members)
    }

    /// The canonical order of already-sanitized set members.
    ///
    /// Split out from `sanitizeSet` so the guarantee is testable without a registry:
    /// the same members in *any* input order must produce the same sequence, which is
    /// what keeps two processes from disagreeing.
    static func canonicalOrder(_ members: [Any]) -> [Any] {
        members.sorted { canonicalKey($0) < canonicalKey($1) }
    }

    /// A key that orders two set members the same way in *every* process.
    ///
    /// An `OSSet` has no order, so the array built from it needs one. `String(describing:)`
    /// cannot supply it: for a dictionary Swift renders its pairs in the process' random
    /// hash order, so an array "sorted" that way rotates between runs. That is not
    /// cosmetic — two reads of an unchanged machine then differ, and `baseline check`
    /// reports a change that never happened. Canonical JSON (sorted keys, recursively)
    /// is stable across processes.
    private static func canonicalKey(_ member: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: member, options: [.sortedKeys]) {
            return String(decoding: data, as: UTF8.self)
        }
        return String(describing: member)
    }

    // MARK: - registry helpers

    private static func entryName(_ entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        IORegistryEntryGetName(entry, &buffer)
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func entryID(_ entry: io_registry_entry_t) -> UInt64 {
        var identifier: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(entry, &identifier)
        return identifier
    }

    private static func entryClass(_ entry: io_registry_entry_t) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(
            entry, "IOClass" as CFString, kCFAllocatorDefault, 0
        ) else { return nil }
        return value.takeRetainedValue() as? String
    }
}

/// Why the in-process registry read failed.
public enum IORegistryReaderError: Error, CustomStringConvertible {
    case mainPortUnavailable
    case noPortEntries
    case serializationFailed

    public var description: String {
        switch self {
        case .mainPortUnavailable:
            "the IORegistry root is not reachable"
        case .noPortEntries:
            "the IORegistry reports no port-manager entry"
        case .serializationFailed:
            "the IOPort tree is not property-list serialisable"
        }
    }
}
