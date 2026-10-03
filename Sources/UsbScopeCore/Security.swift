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
    static let compositePerInterfaceDetail =
        "class declared per interface (composite) — macOS does not expose the interface classes "
        + "without a user client, so the contained functions (e.g. HID and mass storage) cannot be "
        + "confirmed here"
    static let compositeIADDetail =
        "Interface Association Descriptor composite (0xEF/2/1) — macOS does not expose the interface "
        + "classes without a user client, so the contained functions cannot be confirmed here"
    static let deviceRestrictedDetail =
        "macOS reports the device as restricted (TRM) — it was not granted access without a prompt"
    static let transportRestrictedDetail = "an active transport of this port is restricted by macOS (TRM)"
    static let noUsbDataDetail =
        "a device is attached but the controller reports no active USB data transport "
        + "(charge/accessory only)"
    static let hidAndStorageDetail =
        "this port carries both a HID (class 3) and a mass-storage (class 8) device"

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

        if device.deviceClass == classMassStorage {
            add("mass-storage", .warning, massStorageDetail)
        }
        if device.deviceClass == classHID && (device.serial ?? "").isEmpty {
            add("hid-without-serial", .attention, hidNoSerialDetail)
        }
        if device.deviceClass == classPerInterface {
            add("composite-per-interface", .info, compositePerInterfaceDetail)
        } else if device.deviceClass == classMisc
            && device.deviceSubclass == 0x02
            && device.deviceProtocol == 0x01
        {
            add("composite-iad", .info, compositeIADDetail)
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
        let classes = Set(port.devices.compactMap(\.deviceClass))
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
