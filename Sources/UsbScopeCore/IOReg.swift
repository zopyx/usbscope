import Foundation

/// Adapter for the IORegistry — the twin of `usbscope/sources/ioreg.py`.
///
/// `ioreg -a -l -w0 -p IOPort` returns the hardware port manager view of every
/// receptacle: the negotiated transports, the cable/CC data, the power contract,
/// liquid detection and the accessory restrictions of macOS. The plist is parsed
/// from stdout — no entitlements, no private framework, no sudo.
public enum IOReg {
    static let pinOrder = ["rx1", "rx2", "tx1", "tx2", "sbu1", "sbu2"]
    static let deviceMarkers = ["UsbLinkSpeed", "idVendor", "USB Product Name", "UsbDeviceSignature"]
    static let transportKinds: Set<String> = ["CC", "USB2", "USB3", "USB4", "DisplayPort", "SD"]

    // MARK: - plist helpers

    static func children(_ node: [String: Any]) -> [[String: Any]] {
        (node["IORegistryEntryChildren"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    /// Coerce a plist value to text, dropping the "none"/"null" placeholders.
    static func text(_ value: Any?) -> String? {
        guard let value else { return nil }
        if PlistValue.isBool(value) { return nil }
        if let data = value as? Data { return data.isEmpty ? nil : data.map { String(format: "%02x", $0) }.joined() }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || ["none", "null", "<null>"].contains(text.lowercased()) { return nil }
        return text
    }

    static func int(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if PlistValue.isBool(value) { return nil }
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return PlistValue.int(text) }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.intValue != 0 }
        if let text = value as? String {
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "yes", "true": return true
            case "no", "false": return false
            default: return nil
            }
        }
        return nil
    }

    static func label(_ node: [String: Any]) -> String {
        (node["IORegistryEntryName"] as? String) ?? (node["Description"] as? String) ?? "?"
    }

    /// Find a direct child by `IORegistryEntryName`.
    static func find(_ node: [String: Any], _ name: String) -> [String: Any]? {
        children(node).first { ($0["IORegistryEntryName"] as? String) == name }
    }

    static func formatBcd(_ value: Any?) -> String? {
        guard let number = int(value) else { return nil }
        return String(format: "0x%04x", number)
    }

    /// Render the raw firmware blob of the port controller as a hex version.
    static func firmware(_ raw: Any?) -> String? {
        if let data = raw as? Data, !data.isEmpty {
            var bytes = [UInt8](data.prefix(4))
            while bytes.count < 4 { bytes.append(0) }
            let number = bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            return String(format: "0x%08x", number)
        }
        return text(raw)
    }

    // MARK: - ports

    static func isPortNode(_ node: [String: Any]) -> Bool {
        node["PortDescription"] is String && node["PortTypeDescription"] is String
    }

    static func isDeviceNode(_ node: [String: Any]) -> Bool {
        deviceMarkers.contains { node[$0] != nil }
    }

    private static func iterate(_ node: [String: Any], _ body: ([String: Any]) -> Void) {
        body(node)
        for child in children(node) { iterate(child, body) }
    }

    /// The USB-C pin assignment of the receptacle (`Pin Configuration`).
    static func pins(_ node: [String: Any]) -> [PinAssignment] {
        guard let raw = node["Pin Configuration"] as? [String: Any] else { return [] }
        return pinOrder.compactMap { name in int(raw[name]).map { PinAssignment(name, $0) } }
    }

    static func intList(_ value: Any?) -> [Int] {
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { int($0) }
    }

    /// Decode the controller's PDO class (`IOPortFeaturePowerSourceOptionFixed`).
    ///
    /// `Fixed` is a normal PDO, `Adjustable` a PPS/APDO, `Variable` and
    /// `Battery` the rarer types; unknown classes are lower-cased verbatim.
    static func powerOptionKind(_ raw: Any?) -> String? {
        guard let text = raw as? String, !text.isEmpty else { return nil }
        let prefix = "IOPortFeaturePowerSourceOption"
        let name = text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : text
        guard let first = name.first else { return nil }
        return first.lowercased() + name.dropFirst()
    }

    static func powerOption(_ raw: Any?) -> PowerOption? {
        guard let dict = raw as? [String: Any] else { return nil }
        let option = PowerOption(
            maxPowerMw: int(dict["Max Power (mW)"]),
            maxCurrentMa: int(dict["Max Current (mA)"]),
            voltageMv: int(dict["Voltage (mV)"]),
            kind: powerOptionKind(dict["Class"]),
            uuid: dict["UUID"] as? String
        )
        if option.maxPowerMw == nil && option.maxCurrentMa == nil && option.voltageMv == nil {
            return nil
        }
        return option
    }

    /// Power providers of a port, including the option they negotiated.
    ///
    /// macOS marks the winning provider with `[*]` in the registry name and stores
    /// the agreed option only on that node.
    static func powerSources(_ node: [String: Any]) -> [PowerSource] {
        guard let feature = find(node, "Power In") else { return [] }
        return children(feature).compactMap { child in
            let rawName = label(child)
            let winner = powerOption(child["WinningPowerSourceOption"])
            let name = rawName.replacingOccurrences(of: "[*]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let options = (child["PowerSourceOptions"] as? [Any] ?? []).compactMap { powerOption($0) }
            return PowerSource(
                name: name,
                sourceType: int(child["PowerSourceType"]),
                priority: int(child["Priority"]),
                selected: rawName.contains("[*]") || winner != nil,
                winning: winner,
                options: options
            )
        }
    }

    static func powerSourceNames(_ node: [String: Any]) -> [String] {
        guard let feature = find(node, "Power In") else { return [] }
        return children(feature).compactMap { text($0["PowerSourceName"]) }
    }

    static func cable(_ node: [String: Any]) -> Cable {
        let cc = find(node, "CC")
        let partners = cc.map { children($0) } ?? []
        let plugs = partners.filter { isCablePlug($0) }
        let connected = bool(node["ConnectionActive"]) == true || bool(node["IOAccessoryDetect"]) == true
        let partner = partners.first { isPartner($0) }
        return Cable(
            attached: connected,
            emarker: !plugs.isEmpty,
            active: bool(node["ActiveCable"]) == true,
            optical: bool(node["OpticalCable"]) == true,
            authentication: cc.flatMap { text($0["AuthenticationStatusDescription"]) },
            hashStatus: cc.flatMap { text($0["HashStatusDescription"]) },
            pdSpecRevision: partner.flatMap { int($0["Specification Revision"]) }
        )
    }

    static func isPartner(_ node: [String: Any]) -> Bool {
        let name = (node["IORegistryEntryName"] as? String) ?? (node["AddressDescription"] as? String) ?? ""
        return name.trimmingCharacters(in: .whitespaces).uppercased() == "SOP"
    }

    /// Only e-marked cables answer to the `SOP'`/`SOP''` ordered sets.
    static func isCablePlug(_ node: [String: Any]) -> Bool {
        let name = (node["IORegistryEntryName"] as? String) ?? (node["AddressDescription"] as? String) ?? ""
        let values: Set<String> = ["SOP'", "SOP''", "SOPP", "SOPPP", "SOP'S", "SOP''S"]
        return values.contains(name.trimmingCharacters(in: .whitespaces).uppercased())
    }

    /// Map the enumeration values Apple uses on the USB2/USB3 transports.
    static func speedFromIndex(_ index: Int?, kind: String) -> Double? {
        guard let index, index > 0 else { return nil }
        if kind.uppercased().hasPrefix("USB3") {
            return [1: 5000.0, 2: 10000.0, 3: 20000.0][index]
        }
        return [1: 1.5, 2: 12.0, 3: 480.0][index]
    }

    static func parseDevice(_ node: [String: Any], port: UsbPort, transport: Transport) -> UsbDevice {
        let bits = int(node["UsbLinkSpeed"])
        let speedMbps = (bits != nil && bits! > 100_000) ? Double(bits!) / 1_000_000 : nil
        let rounded = speedMbps.map { $0.rounded() }
        return UsbDevice(
            name: (node["USB Product Name"] as? String) ?? (node["kUSBProductString"] as? String) ?? label(node),
            vendor: text(node["USB Vendor Name"]) ?? text(node["kUSBVendorString"]),
            vendorID: int(node["idVendor"]),
            productID: int(node["idProduct"]),
            locationID: int(node["locationID"]),
            speedText: rounded.map { "\(Int($0)) Mbit/s" },
            speedMbps: rounded,
            connection: "Removable",
            version: formatBcd(node["bcdDevice"]),
            port: port.name,
            portType: port.kind,
            transport: transport.kind,
            generation: transport.generation,
            restricted: transport.restricted,
            source: "ioreg"
        )
    }

    static func parseTransport(_ node: [String: Any], port: UsbPort) -> (Transport, [UsbDevice]) {
        let kind = (node["TransportTypeDescription"] as? String) ?? label(node)
        var deviceNodes: [[String: Any]] = []
        iterate(node) { child in
            if !(child as NSDictionary === node as NSDictionary) && isDeviceNode(child) {
                deviceNodes.append(child)
            }
        }
        let speeds = deviceNodes.compactMap { int($0["UsbLinkSpeed"]) }.filter { $0 > 100_000 }
            .map { (Double($0) / 1_000_000).rounded() }
        let speedMbps = speeds.max() ?? speedFromIndex(int(node["DataRate"]), kind: kind)
        let transport = Transport(
            kind: kind,
            active: bool(node["Active"]) == true,
            rateText: text(node["DataRateDescription"]) ?? text(node["LinkRateDescription"]),
            speedMbps: speedMbps,
            generation: text(node["GenerationDescription"]),
            signaling: text(node["SuperSpeedSignalingDescription"]),
            dataRole: text(node["DataRoleDescription"]) ?? text(node["RoleDescription"]),
            lanes: int(node["LaneCount"]),
            restricted: bool(node["TRM_TransportRestricted"]),
            trmState: text(node["TRM_StateDescription"]),
            trmProfile: text(node["TRM_ProfileDescription"]),
            hashStatus: text(node["HashStatusDescription"])
        )
        return (transport, deviceNodes.map { parseDevice($0, port: port, transport: transport) })
    }

    static func parsePort(_ node: [String: Any]) -> UsbPort {
        let liquid = find(node, "LDCM")
        var liquidDetected = bool(node["LDCM_LiquidDetected"])
        if liquidDetected == nil, let liquid { liquidDetected = bool(liquid["LiquidDetected"]) }
        var port = UsbPort(
            description: (node["PortDescription"] as? String) ?? (node["Description"] as? String) ?? "port",
            kind: (node["PortTypeDescription"] as? String) ?? "unknown"
        )
        port.connected = bool(node["ConnectionActive"]) == true
        port.number = int(node["PortNumber"])
        port.connectType = text(node["IOAccessoryUSBConnectString"]) ?? text(node["IOAccessoryUSBConnectType"])
        port.superSpeedActive = bool(node["IOAccessoryUSBSuperSpeedActive"])
        port.plugOrientation = int(node["PlugOrientation"])
        port.displayPortPinAssignment = int(node["DisplayPortPinAssignment"])
        port.liquidDetected = liquidDetected
        port.authorization = text(node["UserAuthorizationStatusDescription"])
        port.firmware = firmware(node["FW Version"])
        port.powerIn = powerSourceNames(node)
        port.pinConfiguration = pins(node)
        port.usbModeType = int(node["IOAccessoryUSBModeType"])
        port.accessoryMode = int(node["AccessoryMode"])
        port.powerMode = int(node["IOAccessoryPowerMode"])
        port.activePowerMode = int(node["IOAccessoryActivePowerMode"])
        port.supportedPowerModes = intList(node["IOAccessorySupportedPowerModes"])
        port.powerCurrentLimits = intList(node["IOAccessoryPowerCurrentLimits"])
        port.liquidState = text(node["LDCM_StateDescription"])
        port.liquidMeasurement = text(node["LDCM_MeasurementStatusDescription"])
        port.liquidPin = text(node["LDCMPinDescription"])
        port.liquidMitigations = bool(node["LDCM_MitigationsEnabled"])
        port.liquidOverride = bool(node["LDCM_UserOverrideActive"])
        port.powerSources = powerSources(node)
        port.cable = cable(node)

        var transports: [Transport] = []
        var devices: [UsbDevice] = []
        for child in children(node) {
            let kind = (child["TransportTypeDescription"] as? String) ?? ""
            guard transportKinds.contains(kind) else { continue }
            let (transport, found) = parseTransport(child, port: port)
            transports.append(transport)
            devices.append(contentsOf: found)
        }
        port.transports = transports
        port.devices = devices
        return port
    }

    /// Translate a parsed `-p IOPort` plist into ports, without duplicates.
    public static func parsePorts(_ tree: [String: Any]) -> [UsbPort] {
        var ports: [String: UsbPort] = [:]
        iterate(tree) { node in
            guard isPortNode(node) else { return }
            let port = parsePort(node)
            if let existing = ports[port.description] {
                if port.connected && !existing.connected { ports[port.description] = port }
            } else {
                ports[port.description] = port
            }
        }
        return ports.values.sorted { left, right in
            (left.kind, left.number ?? 0) < (right.kind, right.number ?? 0)
        }
    }

    public static let binary = Shell.systemBinary("ioreg", "/usr/sbin/ioreg", "/usr/bin/ioreg")
}

/// Reads the IORegistry port tree.
public struct IoregSource: Sendable {
    private let run: Runner

    public init(runner: Runner? = nil) {
        self.run = runner ?? { Shell.run($0) }
    }

    /// The parsed `IOPort` plane and an optional warning.
    public func ioportTree() -> ([String: Any]?, String?) {
        let result = run([IOReg.binary, "-a", "-l", "-w0", "-p", "IOPort"])
        guard result.ok else { return (nil, result.error ?? "ioreg failed") }
        guard let plist = try? PropertyListSerialization.propertyList(
            from: result.stdout, options: [], format: nil
        ) as? [String: Any] else {
            return (nil, "ioreg returned unparsable output")
        }
        return (plist, nil)
    }

    /// The ports of the machine plus any non-fatal warnings.
    public func ports() -> ([UsbPort], [String]) {
        let (tree, warning) = ioportTree()
        guard let tree else { return ([], warning.map { [$0] } ?? []) }
        let ports = IOReg.parsePorts(tree)
        guard !ports.isEmpty else {
            return ([], ["no port data reported by the hardware port manager"])
        }
        return (ports, [])
    }
}
