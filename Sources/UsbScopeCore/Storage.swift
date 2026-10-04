import Foundation

/// A whole disk macOS reports over the USB bus — the twin of
/// `usbscope/sources/storage.py`.
public struct StorageDevice: Equatable, Sendable {
    public var identifier: String
    public var name: String?
    public var busProtocol: String?
    public var capacityBytes: Int?
    public var readOnly: Bool?
    public var removable: Bool?
    public var mountPoint: String?
    public var content: String?

    public init(
        identifier: String,
        name: String? = nil,
        busProtocol: String? = nil,
        capacityBytes: Int? = nil,
        readOnly: Bool? = nil,
        removable: Bool? = nil,
        mountPoint: String? = nil,
        content: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.busProtocol = busProtocol
        self.capacityBytes = capacityBytes
        self.readOnly = readOnly
        self.removable = removable
        self.mountPoint = mountPoint
        self.content = content
    }

    /// Volume/media name when known, otherwise the BSD device.
    public var label: String { name ?? identifier }

    /// Human capacity such as `32.0 GB` (`nil` when unknown).
    public var capacityText: String? { Format.bytes(capacityBytes) }
}

/// Mapping of `diskutil` output to USB mass storage — the twin of the pure
/// `usbscope.sources.storage` helpers.
///
/// `diskutil list -plist` names the whole disks; `diskutil info -plist <device>`
/// carries the one fact that says a disk hangs off USB — its `BusProtocol`. Only
/// whole disks whose bus protocol is `USB` are kept.
public enum Storage {
    /// The whole-disk identifiers of `diskutil list -plist`, in its order.
    public static func wholeDisks(_ listing: [String: Any]) -> [String] {
        if let identifiers = listing["WholeDisks"] as? [String] { return identifiers }
        guard let entries = listing["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }
        return entries.compactMap { $0["DeviceIdentifier"] as? String }
    }

    /// Read-only state from `Writable`, falling back to `MediaReadOnly`.
    static func readOnly(_ info: [String: Any]) -> Bool? {
        if let writable = IOReg.bool(info["Writable"]) { return !writable }
        return IOReg.bool(info["MediaReadOnly"])
    }

    static func capacity(_ info: [String: Any]) -> Int? {
        IOReg.int(info["TotalSize"]) ?? IOReg.int(info["Size"])
    }

    /// Build the USB storage devices from a disk list and per-disk info dicts.
    public static func parse(listing: [String: Any], infos: [String: [String: Any]]) -> [StorageDevice] {
        var devices: [StorageDevice] = []
        for identifier in wholeDisks(listing) {
            guard let info = infos[identifier] else { continue }
            guard let protocolName = IOReg.text(info["BusProtocol"]),
                  protocolName.uppercased() == "USB"
            else { continue }
            var removable = IOReg.bool(info["Removable"])
            if removable == nil { removable = IOReg.bool(info["RemovableMedia"]) }
            devices.append(
                StorageDevice(
                    identifier: identifier,
                    name: IOReg.text(info["VolumeName"]) ?? IOReg.text(info["MediaName"]),
                    busProtocol: protocolName,
                    capacityBytes: capacity(info),
                    readOnly: readOnly(info),
                    removable: removable,
                    mountPoint: IOReg.text(info["MountPoint"]),
                    content: IOReg.text(info["Content"])
                )
            )
        }
        return devices
    }
}

public enum SourceHealth: String, Codable, Sendable {
    case healthy, partial, failed, stale, unsupported, notApplicable
}

/// Explicit storage collection outcome. An empty device list is not by itself
/// evidence that diskutil worked and found no disks.
public struct StorageInventory: Sendable, Equatable {
    public let devices: [StorageDevice]
    public let warnings: [String]
    public let errors: [SourceError]
    public let status: SourceHealth
    public let capturedAt: Date

    public init(devices: [StorageDevice], warnings: [String] = [], errors: [SourceError] = [],
                status: SourceHealth, capturedAt: Date = Date()) {
        self.devices = devices
        self.warnings = warnings
        self.errors = errors
        self.status = status
        self.capturedAt = capturedAt
    }
}

/// Reads the USB mass-storage inventory through `diskutil`.
///
/// Absence is normal, not an error: a Mac with no USB storage reports no
/// matching disk and the inventory is empty. A missing or failing `diskutil`
/// degrades to the same empty inventory — and without a warning, because there
/// is nothing to say about a machine that has no USB storage.
public struct StorageSource: Sendable {
    private let run: Runner

    public init(runner: Runner? = nil) {
        self.run = runner ?? { Shell.run($0) }
    }

    public static let binary = Shell.systemBinary("diskutil", "/usr/sbin/diskutil", "/usr/bin/diskutil")

    func plist(_ argv: [String]) -> [String: Any]? {
        let result = run(argv)
        guard result.ok else { return nil }
        return (try? PropertyListSerialization.propertyList(
            from: result.stdout, options: [], format: nil
        )) as? [String: Any]
    }

    public func inventoryResult(clock: @Sendable () -> Date = { Date() }) -> StorageInventory {
        let listingResult = run([StorageSource.binary, "list", "-plist"])
        guard listingResult.ok else {
            let reason = listingResult.error ?? "exit \(listingResult.returncode)"
            return StorageInventory(devices: [], warnings: ["storage: diskutil list failed: \(reason)"],
                                    errors: [listingResult.sourceError(source: "diskutil", operation: "list",
                                                                        recoveryAction: "Retry the refresh or inspect diskutil permissions.")].compactMap { $0 },
                                    status: .failed, capturedAt: clock())
        }
        guard let listing = (try? PropertyListSerialization.propertyList(
            from: listingResult.stdout, options: [], format: nil
        )) as? [String: Any] else {
            return StorageInventory(devices: [], warnings: ["storage: diskutil list returned invalid plist"],
                                    errors: [SourceError(code: .sourceMalformed, source: "diskutil", operation: "list",
                                                         userMessage: "Storage information was malformed.",
                                                         technicalMessage: "diskutil list returned invalid plist",
                                                         recoveryAction: "Retry the refresh.")],
                                    status: .failed, capturedAt: clock())
        }
        var infos: [String: [String: Any]] = [:]
        var warnings: [String] = []
        var errors: [SourceError] = []
        for identifier in Storage.wholeDisks(listing) {
            let result = run([StorageSource.binary, "info", "-plist", identifier])
            guard result.ok,
                  let info = (try? PropertyListSerialization.propertyList(
                    from: result.stdout, options: [], format: nil
            )) as? [String: Any] else {
                warnings.append("storage: diskutil info failed for \(identifier)")
                errors.append(result.sourceError(source: "diskutil", operation: "info \(identifier)",
                                                 recoveryAction: "Retry the refresh or inspect the disk connection.") ??
                               SourceError(code: .sourceMalformed, source: "diskutil", operation: "info \(identifier)",
                                           userMessage: "Storage information was malformed.",
                                           technicalMessage: "diskutil info returned invalid plist",
                                           recoveryAction: "Retry the refresh."))
                continue
            }
            infos[identifier] = info
        }
        let devices = Storage.parse(listing: listing, infos: infos)
        return StorageInventory(devices: devices, warnings: warnings,
                                errors: errors,
                                status: warnings.isEmpty ? .healthy : .partial,
                                capturedAt: clock())
    }

    /// USB mass-storage devices plus the (always empty) warnings list.
    public func inventory() -> ([StorageDevice], [String]) {
        let result = inventoryResult()
        // Keep the tuple API source-compatible for existing callers. New code
        // must use inventoryResult() to preserve explicit failure state.
        return (result.devices, [])
    }
}
