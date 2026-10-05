import Foundation
import IOKit

/// Which backend supplied the interface descriptors.
public enum InterfaceSourceBackend: String, Sendable {
    case automatic
    case inProcess
    case subprocess
}

/// The interface descriptors of every attached device.
///
/// macOS publishes one `IOUSBHostInterface` object per interface in the registry.
/// Reading them needs **no entitlement** — unlike the IOUSBHost user-client API that
/// would hand out the endpoint descriptors — so this source works on a plain machine
/// and in a sandbox that may read the registry.
///
/// Like the `IOPort` reader this prefers the in-process IOKit read (no subprocess to
/// spawn, no `ioreg` on disk to trust) and falls back to `ioreg` when that yields
/// nothing, so a plain process and a bundled one get the same answer.
public struct USBInterfaceSource: Sendable {
    /// The registry class of an interface object.
    public static let serviceClass = "IOUSBHostInterface"
    /// The subprocess used by the fallback, resolved the same way `IOReg` resolves it.
    public static let binary = Shell.systemBinary("ioreg", "/usr/sbin/ioreg", "/usr/bin/ioreg")

    private let run: Runner
    private let backend: InterfaceSourceBackend

    public init(runner: Runner? = nil, backend: InterfaceSourceBackend = .automatic) {
        self.run = runner ?? { Shell.run($0) }
        self.backend = backend
    }

    /// The interfaces of every device, keyed by the device's `locationID`, plus any
    /// warning worth showing.
    ///
    /// An empty result is not an error: a hub has no interfaces, and a machine whose
    /// registry cannot be read reports a warning instead of pretending the devices
    /// have none.
    public func interfaces() -> ([Int: [DeviceInterface]], [String]) {
        switch backend {
        case .inProcess:
            do {
                return (Self.parse(try Self.inProcessEntries()), [])
            } catch {
                return ([:], ["USB interfaces unavailable: \(error)"])
            }
        case .subprocess:
            do {
                return (Self.parse(try subprocessEntries()), [])
            } catch {
                return ([:], ["USB interfaces unavailable: \(error)"])
            }
        case .automatic:
            if let entries = try? Self.inProcessEntries(), !entries.isEmpty {
                return (Self.parse(entries), [])
            }
            do {
                return (Self.parse(try subprocessEntries()), [])
            } catch {
                return ([:], ["USB interfaces unavailable: \(error)"])
            }
        }
    }

    // MARK: - backends

    /// Read the interface objects in-process through IOKit.
    static func inProcessEntries() throws -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching(serviceClass) else {
            throw USBInterfaceSourceError.matchingFailed
        }
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard status == KERN_SUCCESS else {
            throw USBInterfaceSourceError.registryUnreadable(status)
        }
        defer { IOObjectRelease(iterator) }
        var entries: [[String: Any]] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            let properties = IORegistryReader.sanitizedProperties(service)
            if !properties.isEmpty { entries.append(properties) }
        }
        return entries
    }

    /// Ask `ioreg` for the same objects — `-r` limits the output to the matches, so
    /// the answer is a flat list of interfaces rather than a tree.
    func subprocessEntries() throws -> [[String: Any]] {
        let result = run([Self.binary, "-a", "-c", Self.serviceClass, "-r", "-l", "-w0"])
        guard result.ok else {
            throw USBInterfaceSourceError.commandFailed(result.error ?? "ioreg failed")
        }
        // An empty match prints an empty document; treat that as "no interfaces".
        guard !result.stdout.isEmpty else { return [] }
        let plist = try PropertyListSerialization.propertyList(from: result.stdout, format: nil)
        if let list = plist as? [[String: Any]] { return list }
        if let single = plist as? [String: Any] { return [single] }
        throw USBInterfaceSourceError.unexpectedShape
    }

    // MARK: - parsing

    /// Group raw registry entries by the device they belong to.
    ///
    /// `locationID` is the device's location identifier, which the device records
    /// already carry — that is the join key. Entries without it cannot be attached to
    /// a device and are dropped rather than guessed at.
    public static func parse(_ entries: [[String: Any]]) -> [Int: [DeviceInterface]] {
        var result: [Int: [DeviceInterface]] = [:]
        for entry in entries {
            guard let location = integer(entry["locationID"]),
                  let number = integer(entry["bInterfaceNumber"])
            else { continue }
            let interface = DeviceInterface(
                number: number,
                alternateSetting: integer(entry["bAlternateSetting"]) ?? 0,
                configuration: integer(entry["bConfigurationValue"]),
                classCode: integer(entry["bInterfaceClass"]),
                subclass: integer(entry["bInterfaceSubClass"]),
                protocolCode: integer(entry["bInterfaceProtocol"]),
                endpoints: integer(entry["bNumEndpoints"]),
                name: entry["IORegistryEntryName"] as? String
            )
            result[location, default: []].append(interface)
        }
        // The registry order is not contractual; interface number then alternate
        // setting is, and it is what a reader expects to see.
        for location in result.keys {
            result[location]?.sort { ($0.number, $0.alternateSetting) < ($1.number, $1.alternateSetting) }
        }
        return result
    }

    /// A registry integer: `CFNumber` bridges to `NSNumber`, plists hand back `Int`.
    static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        return nil
    }
}

/// Why the interface descriptors could not be read.
public enum USBInterfaceSourceError: Error, CustomStringConvertible {
    case matchingFailed
    case registryUnreadable(kern_return_t)
    case commandFailed(String)
    case unexpectedShape

    public var description: String {
        switch self {
        case .matchingFailed:
            return "\(USBInterfaceSource.serviceClass) could not be matched"
        case let .registryUnreadable(status):
            return "the registry could not be read (status \(status))"
        case let .commandFailed(message):
            return "\(USBInterfaceSource.binary) failed: \(message)"
        case .unexpectedShape:
            return "\(USBInterfaceSource.binary) did not return a list of interfaces"
        }
    }
}
