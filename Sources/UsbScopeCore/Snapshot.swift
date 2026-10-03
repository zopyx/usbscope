import Foundation

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

    /// Read every source and merge the results into a single snapshot.
    ///
    /// Broken or missing sources never abort the collection: their message is kept
    /// in `Snapshot.warnings` so the UI can show it instead of a crash. The
    /// injectable `clock`, `host` and `osVersion` let tests pin a captured machine.
    /// `27.0.1` — `operatingSystemVersionString` carries the build too, which
    /// does not belong in the JSON (the Python side reports the plain version).
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

    public static func collect(
        profiler: SystemProfiler = SystemProfiler(),
        ioreg: IoregSource = IoregSource(),
        charging: ChargingSource = ChargingSource(),
        usbregistry: USBRegistrySource = USBRegistrySource(),
        fabric: ThunderboltFabricSource = ThunderboltFabricSource(),
        clock: @Sendable () -> Date = { Date() },
        osVersion: String? = nil,
        host: String? = nil
    ) -> Snapshot {
        var warnings: [String] = []
        let (ports, portWarnings) = ioreg.ports()
        warnings.append(contentsOf: portWarnings)
        let (buses, busWarnings) = profiler.usbBuses()
        warnings.append(contentsOf: busWarnings)
        let (thunderbolt, thunderboltWarnings) = profiler.thunderbolt()
        warnings.append(contentsOf: thunderboltWarnings)
        let (thunderboltFabric, fabricWarnings) = fabric.fabric()
        warnings.append(contentsOf: fabricWarnings)
        let hardware = profiler.hardware()
        warnings.append(contentsOf: hardware.warnings)
        let (power, powerWarnings) = charging.charging()
        warnings.append(contentsOf: powerWarnings)
        let (registryDevices, registryWarnings) = usbregistry.devices()
        warnings.append(contentsOf: registryWarnings)

        let busIndex = index(buses.flatMap(\.devices))
        let portIndex = index(ports.flatMap(\.devices))
        let registryIndex = index(registryDevices)

        /// Fill a device from the other sources, in order.
        func merged(_ device: UsbDevice, _ sources: [Int: UsbDevice]...) -> UsbDevice {
            var result = device
            for source in sources {
                result = merge(result, with: source[device.locationID ?? -1])
            }
            return result
        }

        var mergedBuses = buses.map { bus in
            var copy = bus
            copy.devices = bus.devices.map { merged($0, portIndex, registryIndex) }
            return copy
        }
        var mergedPorts = ports.map { port in
            var copy = port
            copy.devices = port.devices.map { merged($0, busIndex, registryIndex) }
            return copy
        }
        let orphans = portIndex.merging(registryIndex) { current, _ in current }
            .filter { busIndex[$0.key] == nil }
            .map(\.value)
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
