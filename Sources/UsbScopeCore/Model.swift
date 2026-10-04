import Foundation

/// The domain model of the USB subsystem — the Swift twin of `usbscope/models.py`.
///
/// Deliberately free of any I/O: the adapters translate raw OS facts into these
/// values, the CLI and the SwiftUI app render them. Unknown facts stay `nil`
/// instead of being guessed.
public enum UsbMode: String, CaseIterable, Codable, Sendable {
    case unknown
    case lowSpeed = "low_speed"
    case fullSpeed = "full_speed"
    case highSpeed = "high_speed"
    case superSpeed = "super_speed"
    case superSpeedPlus = "super_speed_plus"
    case usb4_20 = "usb4_20"
    case usb4_40 = "usb4_40"
    case usb4_80 = "usb4_80"

    public var label: String {
        switch self {
        case .unknown: "unknown"
        case .lowSpeed: "USB 1.0 Low-Speed · 1.5 Mbit/s"
        case .fullSpeed: "USB 1.1 Full-Speed · 12 Mbit/s"
        case .highSpeed: "USB 2.0 High-Speed · 480 Mbit/s"
        case .superSpeed: "USB 3.2 Gen 1 · 5 Gbit/s"
        case .superSpeedPlus: "USB 3.2 Gen 2 · 10 Gbit/s"
        case .usb4_20: "USB 3.2 Gen 2x2 / USB4 · 20 Gbit/s"
        case .usb4_40: "USB4 · 40 Gbit/s"
        case .usb4_80: "USB4 v2 · 80 Gbit/s"
        }
    }

    public var short: String {
        switch self {
        case .unknown: "?"
        case .lowSpeed: "1.0 LS"
        case .fullSpeed: "1.1 FS"
        case .highSpeed: "2.0 HS"
        case .superSpeed: "3.2 G1"
        case .superSpeedPlus: "3.2 G2"
        case .usb4_20: "3.2 G2x2"
        case .usb4_40: "USB4 40"
        case .usb4_80: "USB4 80"
        }
    }

    /// Sort/compare helper: higher is faster, 0 for unknown.
    public var rank: Int {
        switch self {
        case .unknown: 0
        case .lowSpeed: 1
        case .fullSpeed: 2
        case .highSpeed: 3
        case .superSpeed: 4
        case .superSpeedPlus: 5
        case .usb4_20: 6
        case .usb4_40: 7
        case .usb4_80: 8
        }
    }

    private static let byMbps: [(Double, UsbMode)] = [
        (1.5, .lowSpeed), (12, .fullSpeed), (480, .highSpeed), (5_000, .superSpeed),
        (10_000, .superSpeedPlus), (20_000, .usb4_20), (40_000, .usb4_40), (80_000, .usb4_80),
    ]

    /// Classify a link rate in Mbit/s (values above 100000 are read as bit/s).
    public static func from(mbps: Double?) -> UsbMode {
        guard var value = mbps else { return .unknown }
        if value > 100_000 { value /= 1_000_000 }  // reported in bit/s
        for (known, mode) in byMbps where abs(value - known) <= known * 0.05 {
            return mode
        }
        return .unknown
    }

    /// Classify descriptive OS strings such as `12 Mbps (Full Speed)`.
    public static func from(text: String?) -> UsbMode {
        guard let text else { return .unknown }
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty { return .unknown }
        if ["none", "no link", "n/a", "-"].contains(stripped.lowercased()) { return .unknown }
        let lowered = stripped.lowercased()
        let keywords: [(String, UsbMode)] = [
            ("low speed", .lowSpeed), ("full speed", .fullSpeed), ("high speed", .highSpeed),
            ("superspeedplus", .superSpeedPlus), ("super speed plus", .superSpeedPlus),
            ("superspeed", .superSpeed), ("super speed", .superSpeed), ("usb4", .usb4_40),
        ]
        for (keyword, mode) in keywords where lowered.contains(keyword) { return mode }
        guard let regex = try? NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)\\s*(G|M)?(?:bit|b)", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)),
              let amountRange = Range(match.range(at: 1), in: stripped)
        else { return .unknown }
        let amount = Double(stripped[amountRange]) ?? 0
        let unit = match.range(at: 2).location == NSNotFound ? "M" : String(stripped[Range(match.range(at: 2), in: stripped)!]).uppercased()
        return .from(mbps: unit == "G" ? amount * 1000 : amount)
    }
}

/// One interface descriptor of a USB device.
///
/// macOS publishes these in the registry as `IOUSBHostInterface` objects — reading
/// them needs no entitlement, so the interface level of the descriptor tree is
/// available on a plain machine. What the registry gives is one object per
/// interface: its number, the alternate setting, the class triple, the
/// configuration it belongs to and **how many** endpoints it has.
///
/// The endpoint descriptors themselves (address, transfer type, max packet size,
/// interval) are *not* published; getting those means the IOUSBHost user-client API,
/// and that is what needs the entitlement. So `endpoints` here is a count, not a
/// list, and the docs say so.
public struct DeviceInterface: Equatable, Sendable {
    /// `bInterfaceNumber` — alternates share it.
    public var number: Int
    /// `bAlternateSetting`; together with `number` this identifies the interface.
    public var alternateSetting: Int
    /// `bConfigurationValue` the interface belongs to.
    public var configuration: Int?
    public var classCode: Int?
    public var subclass: Int?
    public var protocolCode: Int?
    /// `bNumEndpoints` — the count macOS publishes in place of the descriptors.
    public var endpoints: Int?
    /// The registry node name, e.g. `IOUSBHostInterface@0`.
    public var name: String?

    public init(
        number: Int, alternateSetting: Int = 0, configuration: Int? = nil,
        classCode: Int? = nil, subclass: Int? = nil, protocolCode: Int? = nil,
        endpoints: Int? = nil, name: String? = nil
    ) {
        self.number = number
        self.alternateSetting = alternateSetting
        self.configuration = configuration
        self.classCode = classCode
        self.subclass = subclass
        self.protocolCode = protocolCode
        self.endpoints = endpoints
        self.name = name
    }

    /// `HID (3/1/1)` — the registry class name plus the raw triple, so a class the
    /// table does not know still reads as its numbers.
    public var classText: String? {
        guard let classCode else { return nil }
        let base = USBRegistry.className(classCode) ?? String(format: "0x%02x", classCode)
        let sub = subclass.map(String.init) ?? "?"
        let proto = protocolCode.map(String.init) ?? "?"
        return "\(base) (\(classCode)/\(sub)/\(proto))"
    }

    /// `if 1 alt 0` — how the interface is addressed.
    public var label: String {
        alternateSetting == 0 ? "if \(number)" : "if \(number) alt \(alternateSetting)"
    }
}

/// A USB device as the sources describe it.
public struct UsbDevice: Equatable, Sendable {
    public var name: String
    public var vendor: String?
    public var vendorID: Int?
    public var productID: Int?
    public var serial: String?
    public var locationID: Int?
    public var speedText: String?
    public var speedMbps: Double?
    public var connection: String?
    public var version: String?
    public var bus: String?
    public var port: String?
    public var portType: String?
    public var transport: String?
    public var generation: String?
    public var restricted: Bool?
    public var source: String = "system_profiler"
    /// USB descriptor basics the device reports (`ioreg -p IOUSB`): the
    /// device-level class triple, the supported USB version, the control
    /// endpoint packet size, the configuration count, the enumeration speed code
    /// and — from the tree shape — the hub tier, the parent hub and the address.
    public var deviceClass: Int? = nil
    public var deviceSubclass: Int? = nil
    public var deviceProtocol: Int? = nil
    public var className: String? = nil
    public var bcdUsb: String? = nil
    public var maxPacketSize0: Int? = nil
    public var numConfigurations: Int? = nil
    public var speedCode: Int? = nil
    public var tier: Int? = nil
    public var parent: String? = nil
    public var address: Int? = nil
    /// The interface descriptors macOS publishes for this device
    /// (`IOUSBHostInterface`), in interface-number order. Empty when the device
    /// reports none (a hub, or a machine where the registry is unreadable).
    public var interfaces: [DeviceInterface] = []

    public init(
        name: String, vendor: String? = nil, vendorID: Int? = nil, productID: Int? = nil,
        serial: String? = nil, locationID: Int? = nil, speedText: String? = nil,
        speedMbps: Double? = nil, connection: String? = nil, version: String? = nil,
        bus: String? = nil, port: String? = nil, portType: String? = nil,
        transport: String? = nil, generation: String? = nil, restricted: Bool? = nil,
        source: String = "system_profiler",
        deviceClass: Int? = nil, deviceSubclass: Int? = nil, deviceProtocol: Int? = nil,
        className: String? = nil, bcdUsb: String? = nil, maxPacketSize0: Int? = nil,
        numConfigurations: Int? = nil, speedCode: Int? = nil, tier: Int? = nil,
        parent: String? = nil, address: Int? = nil
    ) {
        self.name = name
        self.vendor = vendor
        self.vendorID = vendorID
        self.productID = productID
        self.serial = serial
        self.locationID = locationID
        self.speedText = speedText
        self.speedMbps = speedMbps
        self.connection = connection
        self.version = version
        self.bus = bus
        self.port = port
        self.portType = portType
        self.transport = transport
        self.generation = generation
        self.restricted = restricted
        self.source = source
        self.deviceClass = deviceClass
        self.deviceSubclass = deviceSubclass
        self.deviceProtocol = deviceProtocol
        self.className = className
        self.bcdUsb = bcdUsb
        self.maxPacketSize0 = maxPacketSize0
        self.numConfigurations = numConfigurations
        self.speedCode = speedCode
        self.tier = tier
        self.parent = parent
        self.address = address
    }

    /// Negotiated link mode of this device.
    public var mode: UsbMode {
        if let speedMbps { return .from(mbps: speedMbps) }
        return .from(text: speedText)
    }

    /// Human form of the device class triple, e.g. `HID (3/1/1)`.
    ///
    /// A class of `0` means the class is declared per interface, which macOS only
    /// exposes through an `IOUSBHostDevice` user client — reported as
    /// `per-interface` instead of guessed.
    public var classText: String? {
        guard let deviceClass else { return nil }
        let base = className ?? String(format: "0x%02x", deviceClass)
        if deviceClass == 0 { return base }
        let sub = deviceSubclass.map(String.init) ?? "?"
        let proto = deviceProtocol.map(String.init) ?? "?"
        return "\(base) (\(deviceClass)/\(sub)/\(proto))"
    }

    /// `0x1050:0x0407` notation.
    public var idString: String {
        let vendor = vendorID.map { String(format: "0x%04x", $0) } ?? "?"
        let product = productID.map { String(format: "0x%04x", $0) } ?? "?"
        return "\(vendor):\(product)"
    }

    /// Name plus vendor, whichever are known.
    public var label: String {
        if let vendor, !name.lowercased().hasPrefix(vendor.lowercased()) {
            return "\(vendor) \(name)"
        }
        return name
    }
}

public struct Cable: Equatable, Sendable {
    public var attached = false
    /// Only true when the controller received an e-marker response (`SOP'`).
    public var emarker = false
    public var active = false
    public var optical = false
    public var authentication: String?
    public var hashStatus: String?
    public var pdSpecRevision: Int?

    public init() {}

    public init(
        attached: Bool = false, emarker: Bool = false, active: Bool = false, optical: Bool = false,
        authentication: String? = nil, hashStatus: String? = nil, pdSpecRevision: Int? = nil
    ) {
        self.attached = attached
        self.emarker = emarker
        self.active = active
        self.optical = optical
        self.authentication = authentication
        self.hashStatus = hashStatus
        self.pdSpecRevision = pdSpecRevision
    }

    /// Coarse cable class derived from the controller flags.
    public var kind: String {
        if !attached { return "–" }
        if optical { return "optical" }
        if active { return "active" }
        if emarker { return "e-marked" }
        return "unknown"
    }
}

/// One power source option (a PDO) as the port controller lists it.
///
/// `kind` is the PDO type from the option's `Class` key (`fixed`, `adjustable`
/// for a PPS/APDO, `variable`, `battery`); `uuid` is the controller's stable
/// identity for the option.
public struct PowerOption: Equatable, Sendable {
    public var maxPowerMw: Int?
    public var maxCurrentMa: Int?
    public var voltageMv: Int?
    public var kind: String?
    public var uuid: String?

    public init(
        maxPowerMw: Int? = nil, maxCurrentMa: Int? = nil, voltageMv: Int? = nil,
        kind: String? = nil, uuid: String? = nil
    ) {
        self.maxPowerMw = maxPowerMw
        self.maxCurrentMa = maxCurrentMa
        self.voltageMv = voltageMv
        self.kind = kind
        self.uuid = uuid
    }

    public var watts: Double? { maxPowerMw.map { Double($0) / 1000 } }

    /// Human name of the PDO type (`fixed`, `adjustable (PPS)` …).
    public var kindLabel: String? {
        guard let kind else { return nil }
        return POWER_OPTION_KINDS[kind] ?? kind
    }

    /// Compact `20 V · 3 A · 60 W` form, omitting what is unknown.
    public var label: String {
        var parts: [String] = []
        if let voltageMv { parts.append("\(Format.g(Double(voltageMv) / 1000)) V") }
        if let maxCurrentMa { parts.append("\(Format.g(Double(maxCurrentMa) / 1000)) A") }
        if let maxPowerMw { parts.append("\(Format.g(Double(maxPowerMw) / 1000)) W") }
        return parts.joined(separator: " · ")
    }
}

/// The controller's PDO classes (`IOPortFeaturePowerSourceOption*`) in human form.
public let POWER_OPTION_KINDS: [String: String] = [
    "fixed": "fixed",
    "adjustable": "adjustable (PPS)",
    "variable": "variable",
    "battery": "battery",
]

/// A power provider the port controller reports, and what it negotiated.
public struct PowerSource: Equatable, Sendable {
    public var name: String
    public var sourceType: Int?
    public var priority: Int?
    public var selected = false
    public var winning: PowerOption?
    public var options: [PowerOption] = []

    public init(
        name: String, sourceType: Int? = nil, priority: Int? = nil, selected: Bool = false,
        winning: PowerOption? = nil, options: [PowerOption] = []
    ) {
        self.name = name
        self.sourceType = sourceType
        self.priority = priority
        self.selected = selected
        self.winning = winning
        self.options = options
    }
}

public struct Transport: Equatable, Sendable {
    public var kind: String
    public var active: Bool
    public var rateText: String?
    public var speedMbps: Double?
    public var generation: String?
    public var signaling: String?
    public var dataRole: String?
    public var lanes: Int?
    public var restricted: Bool?
    public var trmState: String?
    public var trmProfile: String?
    public var hashStatus: String?

    public init(
        kind: String, active: Bool = false, rateText: String? = nil, speedMbps: Double? = nil,
        generation: String? = nil, signaling: String? = nil, dataRole: String? = nil,
        lanes: Int? = nil, restricted: Bool? = nil, trmState: String? = nil,
        trmProfile: String? = nil, hashStatus: String? = nil
    ) {
        self.kind = kind
        self.active = active
        self.rateText = rateText
        self.speedMbps = speedMbps
        self.generation = generation
        self.signaling = signaling
        self.dataRole = dataRole
        self.lanes = lanes
        self.restricted = restricted
        self.trmState = trmState
        self.trmProfile = trmProfile
        self.hashStatus = hashStatus
    }

    public var mode: UsbMode {
        if let speedMbps { return .from(mbps: speedMbps) }
        return .from(text: rateText)
    }
}

/// One entry of the receptacle's `Pin Configuration` map.
public struct PinAssignment: Equatable, Sendable {
    public var name: String
    public var value: Int

    public init(_ name: String, _ value: Int) {
        self.name = name
        self.value = value
    }
}

public struct UsbPort: Equatable, Sendable {
    public var description: String
    public var kind: String
    public var connected = false
    public var number: Int?
    public var connectType: String?
    public var superSpeedActive: Bool?
    public var plugOrientation: Int?
    public var displayPortPinAssignment: Int?
    public var liquidDetected: Bool?
    public var authorization: String?
    public var firmware: String?
    public var powerIn: [String] = []
    public var pinConfiguration: [PinAssignment] = []
    public var usbModeType: Int?
    public var accessoryMode: Int?
    public var powerMode: Int?
    public var activePowerMode: Int?
    public var supportedPowerModes: [Int] = []
    public var powerCurrentLimits: [Int] = []
    public var liquidState: String?
    public var liquidMeasurement: String?
    public var liquidPin: String?
    public var liquidMitigations: Bool?
    public var liquidOverride: Bool?
    public var powerSources: [PowerSource] = []
    public var cable = Cable()
    public var transports: [Transport] = []
    public var devices: [UsbDevice] = []

    public init(description: String, kind: String) {
        self.description = description
        self.kind = kind
    }

    /// `USB-C@3` style short name.
    public var name: String {
        let parts = description.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        let head = String(parts[0]).replacingOccurrences(of: "Port-", with: "")
        return parts.count > 1 ? "\(head)@\(parts[1])" : head
    }

    /// Non-zero USB-C pin assignment, e.g. `rx2=4, tx2=3`.
    public var pinsText: String {
        pinConfiguration.filter { $0.value != 0 }.map { "\($0.name)=\($0.value)" }.joined(separator: ", ")
    }

    /// Port-controller USB mode with the connect type it was paired with.
    public var usbModeText: String? {
        guard let usbModeType else { return nil }
        let connect = connectType?.trimmingCharacters(in: .whitespaces)
        if connect == nil || connect!.isEmpty || connect == "0" || connect == "None" {
            return String(usbModeType)
        }
        return "\(usbModeType) (\(connect!))"
    }

    /// The power option this port negotiated (`nil` when nothing is attached).
    public var powerContract: PowerOption? {
        powerSources.first { $0.selected && $0.winning != nil }?.winning
    }

    public func transport(_ kind: String) -> Transport? {
        transports.first { $0.kind.lowercased() == kind.lowercased() }
    }

    public var activeTransports: [Transport] { transports.filter(\.active) }

    /// The USB data transport of this port, preferring the faster one.
    public var usbTransport: Transport? {
        let candidates = transports.filter { ["usb2", "usb3", "usb4"].contains($0.kind.lowercased()) }
        guard !candidates.isEmpty else { return nil }
        return candidates.max { left, right in
            (left.active ? 1 : 0, left.mode.rank) < (right.active ? 1 : 0, right.mode.rank)
        }
    }

    public var mode: UsbMode { usbTransport?.mode ?? .unknown }
}

public struct Bus: Equatable, Sendable {
    public var name: String
    public var driver: String?
    public var locationID: Int?
    public var connection: String?
    public var protocolRevision: String?
    public var devices: [UsbDevice] = []

    public init(
        name: String, driver: String? = nil, locationID: Int? = nil, connection: String? = nil,
        protocolRevision: String? = nil, devices: [UsbDevice] = []
    ) {
        self.name = name
        self.driver = driver
        self.locationID = locationID
        self.connection = connection
        self.protocolRevision = protocolRevision
        self.devices = devices
    }
}

public struct ThunderboltPort: Equatable, Sendable {
    public var bus: String
    public var status: String?
    public var speed: String?
    public var receptacle: Int?
    public var device: String?
    public var vendor: String?

    public init(
        bus: String, status: String? = nil, speed: String? = nil, receptacle: Int? = nil,
        device: String? = nil, vendor: String? = nil
    ) {
        self.bus = bus
        self.status = status
        self.speed = speed
        self.receptacle = receptacle
        self.device = device
        self.vendor = vendor
    }

    public var connected: Bool {
        guard let status else { return false }
        return !status.contains("no_devices") && !status.contains("no devices")
    }
}

/// Live power and charging telemetry of the battery and the adapter.
///
/// macOS aggregates these numbers for the whole machine — they are *not* per
/// USB-C port. Per port the controller publishes the contract only.
public struct Charging: Equatable, Sendable {
    public var connected: Bool?
    public var charging: Bool?
    public var fullyCharged: Bool?
    public var stateOfCharge: Int?
    /// While charging this is the time to full, otherwise the runtime left.
    public var timeRemainingMinutes: Int?
    public var systemPowerInMw: Int?
    public var systemVoltageInMv: Int?
    public var systemCurrentInMa: Int?
    public var systemLoadMw: Int?
    public var batteryPowerMw: Int?
    public var batteryVoltageMv: Int?
    public var batteryCurrentMa: Int?
    public var adapterPowerMw: Int?
    public var adapterVoltageMv: Int?
    public var adapterCurrentMa: Int?
    public var adapterEfficiencyLossMw: Int?
    public var notChargingReason: Int?
    public var slowChargingReason: Int?
    public var thermallyLimitedSeconds: Int?

    public init() {}

    public var isEmpty: Bool { self == Charging() }
}

public struct Snapshot: Equatable, Sendable {
    public var host: String
    public var osVersion: String
    public var seenAt: Date
    public var model: String?
    public var chip: String?
    public var ports: [UsbPort] = []
    public var buses: [Bus] = []
    public var thunderbolt: [ThunderboltPort] = []
    public var thunderboltFabric = ThunderboltFabric()
    public var charging: Charging?
    public var warnings: [String] = []

    public init(
        host: String, osVersion: String, seenAt: Date, model: String? = nil, chip: String? = nil,
        ports: [UsbPort] = [], buses: [Bus] = [], thunderbolt: [ThunderboltPort] = [],
        thunderboltFabric: ThunderboltFabric = ThunderboltFabric(),
        charging: Charging? = nil, warnings: [String] = []
    ) {
        self.host = host
        self.osVersion = osVersion
        self.seenAt = seenAt
        self.model = model
        self.chip = chip
        self.ports = ports
        self.buses = buses
        self.thunderbolt = thunderbolt
        self.thunderboltFabric = thunderboltFabric
        self.charging = charging
        self.warnings = warnings
    }

    /// All known devices, deduplicated by location ID (or by name as fallback).
    public var devices: [UsbDevice] {
        var seen = Set<String>()
        var collected: [UsbDevice] = []
        let all = buses.flatMap(\.devices) + ports.flatMap(\.devices)
        for device in all {
            let key = device.locationID.map { "loc:\($0)" } ?? "name:\(device.name)"
            if seen.insert(key).inserted { collected.append(device) }
        }
        return collected
    }

    public var connectedPorts: [UsbPort] { ports.filter(\.connected) }
    public var emarkedCables: [UsbPort] { ports.filter(\.cable.emarker) }
}
