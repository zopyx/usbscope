import Foundation

/// Which backend produces the `IOPort` plane that a snapshot's ports come from.
///
/// The parsing is identical either way (`IOReg.parsePorts`); only the *reader*
/// differs. The default `automatic` prefers the in-process IOKit read, which
/// removes a subprocess from launch and is what a sandboxed App Store build
/// needs (`docs/app-store.md`, Plan B), and falls back to `/usr/sbin/ioreg`
/// whenever the in-process read is unavailable or reports no ports.
public enum IORegSourceBackend: Sendable {
    /// Prefer the in-process IOKit reader; fall back to `ioreg` if it fails or
    /// reports no port at all. This is the default.
    case automatic
    /// Always spawn `/usr/sbin/ioreg` — the historical path, kept for pinning.
    case subprocess
    /// Always read in-process; surface a warning instead of falling back.
    case inProcess
}

/// The steps `SnapshotBuilder.collect` walks, in the order it walks them.
///
/// The `progress` hook of `collect` reports one call per stage with the stage,
/// its 1-based position and the total stage count, so the app can drive a
/// per-step progress indicator instead of one opaque spinner.
public enum SnapshotStage: String, CaseIterable, Sendable {
    case ports
    case buses
    case interfaces
    case thunderbolt
    case hardware
    case charging
    case registry
}

/// Aggregation: turn the raw OS reports into one `Snapshot` — the twin of
/// `usbscope/snapshot.py`.
public enum SnapshotBuilder {
    static let orphanBus = "Port controller only (no bus entry)"

    /// Fill the gaps of `device` with values reported by `other`.
    static func merge(_ device: UsbDevice, with other: UsbDevice?) -> UsbDevice {
        guard let other else { return device }
        var merged = device
        if merged.vendor == nil { merged.vendor = other.vendor }
        if merged.serial == nil { merged.serial = other.serial }
        if merged.version == nil { merged.version = other.version }
        if merged.connection == nil { merged.connection = other.connection }
        if merged.bus == nil { merged.bus = other.bus }
        if merged.speedMbps == nil { merged.speedMbps = other.speedMbps }
        if merged.speedText == nil { merged.speedText = other.speedText }
        if merged.port == nil { merged.port = other.port }
        if merged.portType == nil { merged.portType = other.portType }
        if merged.transport == nil { merged.transport = other.transport }
        if merged.generation == nil { merged.generation = other.generation }
        if merged.restricted == nil { merged.restricted = other.restricted }
        // USB descriptor facts (`ioreg -p IOUSB`); the other sources do not
        // report them, so the registry fills them in.
        if merged.deviceClass == nil { merged.deviceClass = other.deviceClass }
        if merged.deviceSubclass == nil { merged.deviceSubclass = other.deviceSubclass }
        if merged.deviceProtocol == nil { merged.deviceProtocol = other.deviceProtocol }
        if merged.className == nil { merged.className = other.className }
        if merged.bcdUsb == nil { merged.bcdUsb = other.bcdUsb }
        if merged.maxPacketSize0 == nil { merged.maxPacketSize0 = other.maxPacketSize0 }
        if merged.numConfigurations == nil { merged.numConfigurations = other.numConfigurations }
        if merged.speedCode == nil { merged.speedCode = other.speedCode }
        if merged.tier == nil { merged.tier = other.tier }
        if merged.parent == nil { merged.parent = other.parent }
        if merged.address == nil { merged.address = other.address }
        return merged
    }

    static func index(_ devices: [UsbDevice]) -> [Int: UsbDevice] {
        var result: [Int: UsbDevice] = [:]
        for device in devices where device.locationID != nil {
            result[device.locationID!] = device
        }
        return result
    }

    static func indexWithWarnings(_ devices: [UsbDevice], source: String) -> ([Int: UsbDevice], [String]) {
        var result: [Int: UsbDevice] = [:]
        var warnings: [String] = []
        for device in devices {
            guard let locationID = device.locationID else { continue }
            if result[locationID] != nil {
                warnings.append("\(source): duplicate locationID \(locationID) for \(device.label); record retained with deterministic precedence")
            }
            result[locationID] = device
        }
        return (result, warnings)
    }

    static func identityWarnings(_ devices: [UsbDevice], source: String) -> [String] {
        let grouped = Dictionary(grouping: devices, by: deviceKey)
        return grouped.compactMap { key, records in
            guard records.count > 1, records.first.map({ deviceIdentity($0).isWeak }) == true else { return nil }
            return "\(source): ambiguous weak identity \(key) represents \(records.count) records; diff identity is read-local"
        }.sorted()
    }

    /// Read every source and merge the results into a single snapshot.
    ///
    /// Broken or missing sources never abort the collection: their message is kept
    /// in `Snapshot.warnings` so the UI can show it instead of a crash. The
    /// injectable `clock`, `host` and `osVersion` let tests pin a captured machine.
    /// `27.0.1` — `operatingSystemVersionString` carries the build too, which
    /// does not belong in the JSON (the Python side reports the plain version).
    ///
    /// `ioreg` is the `IOPort` reader. `nil` (the default) means “no reader was
    /// injected”, and then `ioregBackend` decides: `.automatic` reads the plane
    /// **in-process** through IOKit and only spawns `/usr/sbin/ioreg` when that
    /// fails or reports no port, `.subprocess` always spawns `ioreg`, and
    /// `.inProcess` always reads in-process. A non-`nil` `ioreg` is an explicit
    /// override — the fixture-backed source in the test suite, say — and is used
    /// as given, whatever the backend says. The JSON is identical on every path.
    ///
    /// `progress`, when given, is called once per `SnapshotStage` in order, with
    /// the stage, its 1-based index and the total stage count — additive and
    /// optional, so existing callers are untouched.
    public static func osVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// The plain network host name, matching Python's `platform.node()`.
    ///
    /// `ProcessInfo.processInfo.hostName` returns the Bonjour *local* name
    /// (`…-2.local`), not what `gethostname(3)` reports — so it would not match
    /// the Python side on the same machine.
    public static func hostName() -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count) == 0 else {
            return ProcessInfo.processInfo.hostName
        }
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty ? "this Mac" : name
    }

    /// The port records for `backend`, honouring an explicitly injected source.
    ///
    /// Split out so the selection is testable and the fallback is one obvious
    /// branch: `.automatic` keeps the subprocess result only as a backup, so the
    /// JSON it produces is byte-identical to `.subprocess` wherever the
    /// in-process read succeeds.
    static func readPorts(
        backend: IORegSourceBackend, explicit: IoregSource?
    ) -> ([UsbPort], [String]) {
        if let explicit { return explicit.ports() }
        switch backend {
        case .subprocess:
            return IoregSource().ports()
        case .inProcess:
            return IORegistryReader.ioregSource().ports()
        case .automatic:
            let (ports, warnings) = IORegistryReader.ioregSource().ports()
            if !ports.isEmpty { return (ports, warnings) }
            // The in-process read failed or found nothing: fall back to the
            // subprocess. Its result alone is reported, so the JSON stays
            // identical to the `.subprocess` path (no extra warning).
            return IoregSource().ports()
        }
    }

    public static func collect(
        profiler: SystemProfiler = SystemProfiler(),
        ioreg: IoregSource? = nil,
        ioregBackend: IORegSourceBackend = .automatic,
        charging: ChargingSource = ChargingSource(),
        usbregistry: USBRegistrySource = USBRegistrySource(),
        interfaces: USBInterfaceSource = USBInterfaceSource(),
        fabric: ThunderboltFabricSource = ThunderboltFabricSource(),
        clock: @Sendable () -> Date = { Date() },
        osVersion: String? = nil,
        host: String? = nil,
        includeConflictWarnings: Bool = false,
        progress: ((SnapshotStage, Int, Int) -> Void)? = nil
    ) -> Snapshot {
        let stages = SnapshotStage.allCases
        let total = stages.count
        func report(_ stage: SnapshotStage) {
            guard let progress else { return }
            progress(stage, (stages.firstIndex(of: stage) ?? 0) + 1, total)
        }

        var warnings: [String] = []
        let (ports, portWarnings) = readPorts(backend: ioregBackend, explicit: ioreg)
        warnings.append(contentsOf: portWarnings)
        report(.ports)
        let (buses, busWarnings) = profiler.usbBuses()
        warnings.append(contentsOf: busWarnings)
        report(.buses)
        let (interfaceMap, interfaceWarnings) = interfaces.interfaces()
        warnings.append(contentsOf: interfaceWarnings)
        report(.interfaces)
        let (thunderbolt, thunderboltWarnings) = profiler.thunderbolt()
        warnings.append(contentsOf: thunderboltWarnings)
        let (thunderboltFabric, fabricWarnings) = fabric.fabric()
        warnings.append(contentsOf: fabricWarnings)
        report(.thunderbolt)
        let hardware = profiler.hardware()
        warnings.append(contentsOf: hardware.warnings)
        report(.hardware)
        let (power, powerWarnings) = charging.charging()
        warnings.append(contentsOf: powerWarnings)
        report(.charging)
        let (registryDevices, registryWarnings) = usbregistry.devices()
        warnings.append(contentsOf: registryWarnings)
        report(.registry)

        let busIndexed = indexWithWarnings(buses.flatMap(\.devices), source: "buses")
        let portIndexed = indexWithWarnings(ports.flatMap(\.devices), source: "ports")
        let registryIndexed = indexWithWarnings(registryDevices, source: "registry")
        warnings.append(contentsOf: busIndexed.1 + portIndexed.1 + registryIndexed.1)
        warnings.append(contentsOf: identityWarnings(buses.flatMap(\.devices), source: "buses"))
        warnings.append(contentsOf: identityWarnings(ports.flatMap(\.devices), source: "ports"))
        warnings.append(contentsOf: identityWarnings(registryDevices, source: "registry"))
        let busIndex = busIndexed.0
        let portIndex = portIndexed.0
        let registryIndex = registryIndexed.0

        /// Fill a device from the other sources, in order.
        func merged(_ device: UsbDevice, _ sources: [Int: UsbDevice]...) -> UsbDevice {
            var result = device
            for source in sources {
                if let other = source[device.locationID ?? -1] {
                    let conflicts = SourcePrecedence.conflicts(result, other)
                    if includeConflictWarnings, !conflicts.isEmpty, let location = device.locationID {
                        let lhs = result.source.isEmpty ? "unknown" : result.source
                        let rhs = other.source.isEmpty ? "unknown" : other.source
                        warnings.append(
                            "source conflict at locationID \(location): \(conflicts.joined(separator: ", ")) (\(lhs) vs \(rhs)); precedence retained"
                        )
                    }
                    result = merge(result, with: other)
                }
            }
            return result
        }

        /// Attach the interface descriptors the registry published for this device.
        ///
        /// The join is `locationID`: the device records carry it and so does every
        /// `IOUSBHostInterface` object, so no guessing by name or port is needed.
        func withInterfaces(_ device: UsbDevice) -> UsbDevice {
            guard let location = device.locationID, let list = interfaceMap[location] else {
                return device
            }
            var copy = device
            copy.interfaces = list
            return copy
        }

        var mergedBuses = buses.map { bus in
            var copy = bus
            copy.devices = bus.devices.map { withInterfaces(merged($0, portIndex, registryIndex)) }
            return copy
        }
        var mergedPorts = ports.map { port in
            var copy = port
            copy.devices = port.devices.map { withInterfaces(merged($0, busIndex, registryIndex)) }
            return copy
        }
        let orphans = portIndex.merging(registryIndex) { current, _ in current }
            .filter { busIndex[$0.key] == nil }
            .map { withInterfaces($0.value) }
        if !orphans.isEmpty {
            mergedBuses.append(Bus(name: orphanBus, driver: "ioreg", devices: orphans))
        }
        // keep the ports in the controller's order
        mergedPorts.sort { ($0.kind, $0.number ?? 0) < ($1.kind, $1.number ?? 0) }

        return Snapshot(
            host: host ?? hostName(),
            osVersion: osVersion ?? osVersionString(),
            seenAt: clock(),
            model: hardware.model,
            chip: hardware.chip,
            ports: mergedPorts,
            buses: mergedBuses,
            thunderbolt: thunderbolt,
            thunderboltFabric: thunderboltFabric,
            charging: power,
            warnings: warnings
        )
    }
}
