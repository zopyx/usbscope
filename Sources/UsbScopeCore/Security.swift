import Foundation

/// Security posture analysis of a `Snapshot` — the twin of `usbscope/security.py`.
///
/// Pure and presentation free: `analyse` turns a snapshot into a ranked list of
/// findings, each with a severity (`info`/`attention`/`warning`) and a short
/// human reason. The Rich CLI and this Swift twin therefore print the same
/// findings. Every rule is derived from a fact macOS actually reported; a
/// signal that would need the interface descriptor tree (only reachable through
/// an `IOUSBHostDevice` user client) is deliberately *not* invented — the
/// `composite-per-interface` rule states that limit instead of guessing the
/// contained functions.
public enum FindingSeverity: String, Sendable, CaseIterable, Codable {
    case info
    case attention
    case warning

    /// Sort rank; higher is more severe.
    public var rank: Int {
        switch self {
        case .info: 0
        case .attention: 1
        case .warning: 2
        }
    }
}

/// One security-relevant observation about a device or a port.
///
/// `rule` is a stable identifier, `subject` names the device or port it is about
/// and `detail` is the short human reason. The optional identities let a UI jump
/// to the source row without re-deriving it.
public struct Finding: Equatable, Sendable {
    public let rule: String
    public let severity: FindingSeverity
    public let subject: String
    public let detail: String
    public let port: String?
    public let device: String?
    public let locationID: Int?

    public init(
        rule: String,
        severity: FindingSeverity,
        subject: String,
        detail: String,
        port: String? = nil,
        device: String? = nil,
        locationID: Int? = nil
    ) {
        self.rule = rule
        self.severity = severity
        self.subject = subject
        self.detail = detail
        self.port = port
        self.device = device
        self.locationID = locationID
    }
}

/// The findings of one snapshot, most severe first.
public struct SecurityReport: Equatable, Sendable {
    public let findings: [Finding]

    public init(findings: [Finding]) {
        self.findings = findings
    }

    /// True when nothing stood out.
    public var isEmpty: Bool { findings.isEmpty }

    /// Number of findings of a given severity.
    public func count(_ severity: FindingSeverity) -> Int {
        findings.filter { $0.severity == severity }.count
    }
}

/// The pure analyser — same rules and wording as `usbscope.security.analyse`.
public enum Security {
    /// macOS marks a receptacle that needs no user decision with one of these.
    public static let standardAuthorizations: Set<String> = ["Not Required", "No Action"]

    /// The transports that carry USB data; CC/SD/DisplayPort do not.
    static let usbTransportKinds: Set<String> = ["usb2", "usb3", "usb4"]

    // USB-IF base class codes this analyser keys on.
    static let classHID = 0x03
    static let classMassStorage = 0x08
    static let classPerInterface = 0x00
    static let classMisc = 0xEF  // Interface Association Descriptor (composite)

    static let massStorageDetail = "mass-storage device (class 8) — it presents a filesystem to the host"
    static let hidNoSerialDetail =
        "HID device without a serial number — an identical device cannot be told apart across reads"
    static let compositeIADDetailBase =
        "Interface Association Descriptor composite (0xEF/2/1)"
    static let deviceRestrictedDetail =
        "macOS reports the device as restricted (TRM) — it was not granted access without a prompt"
    static let transportRestrictedDetail = "an active transport of this port is restricted by macOS (TRM)"
    static let noUsbDataDetail =
        "a device is attached but the controller reports no active USB data transport "
        + "(charge/accessory only)"
    static let hidAndStorageDetail =
        "this port carries both a HID (class 3) and a mass-storage (class 8) device"
    static let hidAndStorageOnDeviceDetail =
        "one device declares both HID (class 3) and mass-storage (class 8) interfaces — it presents "
        + "a filesystem and a keyboard at the same time"
    /// What is *not* confirmed when macOS published no interface objects at all.
    static let noInterfacesDetail =
        " — macOS published no interface objects for this device, so the contained functions "
        + "(e.g. HID and mass storage) cannot be confirmed here"

    /// The classes a device declares — at the device level *and* per interface.
    ///
    /// A composite device reports class `0` at the device level and declares the real
    /// functions on its interfaces. Before the interface descriptors were read, such a
    /// device was invisible to every rule below: a mass-storage stick that also
    /// exposes a keyboard looked like nothing at all.
    public static func declaredClasses(_ device: UsbDevice) -> Set<Int> {
        var classes = Set(device.interfaces.compactMap(\.classCode))
        if let code = device.deviceClass { classes.insert(code) }
        return classes
    }

    /// `if 0: HID (3/1/1), if 1: HID (3/0/0), if 2: smart card (11/0/0)` — or `nil`
    /// when macOS published no interface objects.
    public static func interfaceSummary(_ device: UsbDevice) -> String? {
        guard !device.interfaces.isEmpty else { return nil }
        return device.interfaces
            .map { "\($0.label): \($0.classText ?? "class unknown")" }
            .joined(separator: ", ")
    }

    /// The `composite-per-interface` note, naming the interfaces when they are known.
    static func compositePerInterfaceDetail(_ device: UsbDevice) -> String {
        let base = "class declared per interface (composite)"
        guard let summary = interfaceSummary(device) else { return base + noInterfacesDetail }
        return base + " — macOS publishes the interfaces in the registry: \(summary)"
    }

    /// The `composite-iad` note, naming the interfaces when they are known.
    static func compositeIADDetail(_ device: UsbDevice) -> String {
        guard let summary = interfaceSummary(device) else {
            return compositeIADDetailBase + noInterfacesDetail
        }
        return compositeIADDetailBase + " — the interfaces macOS publishes are: \(summary)"
    }

    /// Turn a snapshot into a ranked security report.
    public static func analyse(_ snapshot: Snapshot) -> SecurityReport {
        var findings: [Finding] = []
        for device in snapshot.devices {
            findings.append(contentsOf: deviceFindings(device))
        }
        for port in snapshot.ports {
            findings.append(contentsOf: portFindings(port))
        }
        findings.sort { left, right in
            if left.severity.rank != right.severity.rank { return left.severity.rank > right.severity.rank }
            if left.rule != right.rule { return left.rule < right.rule }
            if left.subject != right.subject { return left.subject < right.subject }
            return (left.device ?? "") < (right.device ?? "")
        }
        return SecurityReport(findings: findings)
    }

    /// Device-level rules, keyed on the descriptor class triple macOS reports.
    static func deviceFindings(_ device: UsbDevice) -> [Finding] {
        var findings: [Finding] = []

        func add(_ rule: String, _ severity: FindingSeverity, _ detail: String) {
            findings.append(
                Finding(
                    rule: rule,
                    severity: severity,
                    subject: device.label,
                    detail: detail,
                    device: device.label,
                    locationID: device.locationID
                )
            )
        }

        let classes = declaredClasses(device)

        if classes.contains(classMassStorage) {
            add("mass-storage", .warning, massStorageDetail)
        }
        if classes.contains(classHID) && (device.serial ?? "").isEmpty {
            add("hid-without-serial", .attention, hidNoSerialDetail)
        }
        if classes.contains(classHID) && classes.contains(classMassStorage) {
            add("hid-and-storage-on-device", .warning, hidAndStorageOnDeviceDetail)
        }
        if device.deviceClass == classPerInterface {
            add("composite-per-interface", .info, compositePerInterfaceDetail(device))
        } else if device.deviceClass == classMisc
            && device.deviceSubclass == 0x02
            && device.deviceProtocol == 0x01
        {
            add("composite-iad", .info, compositeIADDetail(device))
        }
        if device.restricted == true {
            add("restricted-by-macos", .attention, deviceRestrictedDetail)
        }
        return findings
    }

    /// Port-level rules (authorization, restriction, no data transport, mix).
    static func portFindings(_ port: UsbPort) -> [Finding] {
        var findings: [Finding] = []

        func add(_ rule: String, _ severity: FindingSeverity, _ detail: String) {
            findings.append(
                Finding(rule: rule, severity: severity, subject: port.name, detail: detail, port: port.name)
            )
        }

        if let authorization = port.authorization, !standardAuthorizations.contains(authorization) {
            add(
                "authorization",
                .attention,
                "accessory authorization is '\(authorization)' — macOS neither reported "
                    + "'Not Required' nor 'No Action'"
            )
        }
        if port.transports.contains(where: { $0.active && $0.restricted == true }) {
            add("restricted-transport", .attention, transportRestrictedDetail)
        }
        if port.connected && !port.devices.isEmpty && !hasActiveUsbTransport(port) {
            add("no-usb-data", .attention, noUsbDataDetail)
        }
        // Interface aware: a composite device declares its classes per interface, so
        // both the device level and the interface level count.
        var classes: Set<Int> = []
        for device in port.devices { classes.formUnion(declaredClasses(device)) }
        if classes.contains(classHID) && classes.contains(classMassStorage) {
            add("hid-and-storage-on-port", .warning, hidAndStorageDetail)
        }
        return findings
    }

    /// True when at least one USB2/USB3/USB4 transport is carrying traffic.
    public static func hasActiveUsbTransport(_ port: UsbPort) -> Bool {
        port.transports.contains { usbTransportKinds.contains($0.kind.lowercased()) && $0.active }
    }
}
