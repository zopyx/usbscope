import Foundation

/// Adapter for `system_profiler` — the twin of `usbscope/sources/profiler.py`.
public enum Profiler {
    /// Keys of the modern `SPUSBHostDataType` JSON output.
    static let hostKeys: [String: String] = [
        "vendor_id": "USBDeviceKeyVendorID",
        "product_id": "USBDeviceKeyProductID",
        "vendor": "USBDeviceKeyVendorName",
        "serial": "USBDeviceKeySerialNumber",
        "version": "USBDeviceKeyProductVersion",
        "location": "USBKeyLocationID",
        "speed": "USBDeviceKeyLinkSpeed",
        "connection": "USBKeyHardwareType",
    ]

    /// Keys of the legacy `SPUSBDataType` JSON output (Intel Macs, older macOS).
    static let legacyKeys: [String: String] = [
        "vendor_id": "vendor_id",
        "product_id": "product_id",
        "vendor": "manufacturer",
        "serial": "serial_num",
        "version": "bcd_device",
        "location": "location_id",
        "speed": "device_speed",
        "connection": "host_info",
    ]

    static func text(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let described = String(describing: value)
        return described.isEmpty ? nil : described
    }

    /// Parse decimal, `0x…` and `0x… (decimal)` style integers.
    static func toInt(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if PlistValue.isBool(value) { return nil }
        if let number = value as? NSNumber { return number.intValue }
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || ["not provided", "n/a", "none"].contains(trimmed.lowercased()) { return nil }
        let head = String(trimmed.split(separator: " ").first ?? "").replacingOccurrences(of: ",", with: "")
        if head.lowercased().hasPrefix("0x") {
            return Int(head.dropFirst(2), radix: 16) ?? PlistValue.int(head)
        }
        return Int(head, radix: 10)
    }

    /// Convert a `12 Mb/s` style string or a raw bit/s number into Mbit/s.
    static func speedMbps(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if PlistValue.isBool(value) { return nil }
        if let number = value as? NSNumber {
            let amount = number.doubleValue
            return amount > 100_000 ? (amount / 1_000_000).rounded() : amount
        }
        guard let raw = value as? String else { return nil }
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if text.isEmpty || ["not provided", "unknown"].contains(text) { return nil }
        var digits = ""
        for character in text {
            if character.isNumber || character == "." { digits.append(character) } else if !digits.isEmpty { break }
        }
        guard var amount = Double(digits) else { return nil }
        if amount <= 1000 && text.contains("gb") { amount *= 1000 }
        if amount >= 1000 { return amount.rounded() }
        return amount == amount.rounded() ? amount.rounded() : amount
    }

    /// Depth first walk over the `_items` tree of a system_profiler report.
    static func iterate(_ node: [String: Any], _ body: ([String: Any]) -> Void) {
        body(node)
        for child in (node["_items"] as? [Any])?.compactMap({ $0 as? [String: Any] }) ?? [] {
            iterate(child, body)
        }
    }

    static func first(_ node: [String: Any], _ keys: String...) -> Any? {
        for key in keys where node[key] != nil { return node[key] }
        return nil
    }

    /// True when a node of the report carries device identity, not bus data.
    static func looksLikeDevice(_ node: [String: Any], keys: [String: String]) -> Bool {
        let markers = [keys["product_id"] ?? "", keys["vendor_id"] ?? "", "idProduct", "idVendor"]
        return markers.contains { !$0.isEmpty && node[$0] != nil }
    }

    static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        return ["not provided", "unknown"].contains(value.lowercased()) ? nil : value
    }

    static func parseDevice(_ node: [String: Any], keys: [String: String], bus: String) -> UsbDevice {
        let speed = first(node, keys["speed"] ?? "", "device_speed")
        return UsbDevice(
            name: text(first(node, "USB Product Name", "_name")) ?? "unknown device",
            vendor: clean(text(first(node, keys["vendor"] ?? "", "USB Vendor Name"))),
            vendorID: toInt(first(node, keys["vendor_id"] ?? "", "idVendor")),
            productID: toInt(first(node, keys["product_id"] ?? "", "idProduct")),
            serial: clean(text(first(node, keys["serial"] ?? "", "serial_num"))),
            locationID: toInt(first(node, keys["location"] ?? "", "locationID")),
            speedText: text(speed),
            speedMbps: speedMbps(speed),
            connection: text(first(node, keys["connection"] ?? "", "USBKeyHardwareType")) ?? "bus",
            version: text(first(node, keys["version"] ?? "", "bcd_device")),
            bus: bus,
            source: "system_profiler"
        )
    }

    static func parseBus(_ entry: [String: Any], legacy: Bool) -> Bus {
        let keys = legacy ? legacyKeys : hostKeys
        var devices: [UsbDevice] = []
        // devices may sit behind hubs, so walk the whole _items subtree
        for child in (entry["_items"] as? [Any])?.compactMap({ $0 as? [String: Any] }) ?? [] {
            iterate(child) { node in
                if looksLikeDevice(node, keys: keys) {
                    devices.append(parseDevice(node, keys: keys, bus: text(entry["_name"]) ?? "USB bus"))
                }
            }
        }
        return Bus(
            name: text(entry["_name"]) ?? "USB bus",
            driver: text(first(entry, "Driver", "driver")),
            locationID: toInt(first(entry, "USBKeyLocationID", "location_id")),
            connection: text(first(entry, "USBKeyHardwareType", "host_info")),
            protocolRevision: text(first(entry, "USBDeviceKeyProtocolRevision", "protocol")),
            devices: devices
        )
    }
}

/// Reads USB and Thunderbolt facts from `system_profiler`.
public struct SystemProfiler: Sendable {
    private let run: Runner

    public init(runner: Runner? = nil) {
        self.run = runner ?? { Shell.run($0) }
    }

    public static let binary = Shell.systemBinary(
        "system_profiler", "/usr/sbin/system_profiler", "/usr/bin/system_profiler"
    )

    private func report(_ dataType: String) -> ([[String: Any]], String?) {
        let result = run([Self.binary, dataType, "-json"])
        guard result.ok else { return ([], result.error ?? "system_profiler \(dataType) failed") }
        guard let payload = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] else {
            return ([], "system_profiler \(dataType) returned unparsable output")
        }
        var entries = payload[dataType] as? [Any] ?? []
        if let single = payload[dataType] as? [String: Any] { entries = [single] }
        return (entries.compactMap { $0 as? [String: Any] }, nil)
    }

    /// The USB bus tree plus any non-fatal warnings.
    public func usbBuses() -> ([Bus], [String]) {
        var warnings: [String] = []
        let (hostEntries, hostError) = report("SPUSBHostDataType")
        let (legacyEntries, legacyError) = report("SPUSBDataType")
        let entries = hostEntries.isEmpty ? legacyEntries : hostEntries
        guard !entries.isEmpty else {
            if let error = hostError ?? legacyError { warnings.append(error) }
            return ([], warnings)
        }
        let legacy = hostEntries.isEmpty
        return (entries.map { Profiler.parseBus($0, legacy: legacy) }, warnings)
    }

    /// Model/chip facts for the header (best effort).
    public func hardware() -> (model: String?, chip: String?, warnings: [String]) {
        let (entries, error) = report("SPHardwareDataType")
        guard let entry = entries.first else {
            return (nil, nil, error.map { [$0] } ?? [])
        }
        return (
            Profiler.text(Profiler.first(entry, "machine_name", "model_name")),
            Profiler.text(entry["chip_type"]),
            []
        )
    }

    /// Thunderbolt/USB4 receptacles plus any non-fatal warnings.
    public func thunderbolt() -> ([ThunderboltPort], [String]) {
        let (entries, error) = report("SPThunderboltDataType")
        if entries.isEmpty, let error { return ([], [error]) }
        var ports: [ThunderboltPort] = []
        for entry in entries {
            for index in 1...6 {
                guard let tag = entry["receptacle_\(index)_tag"] as? [String: Any] else { continue }
                ports.append(
                    ThunderboltPort(
                        bus: Profiler.text(Profiler.first(entry, "_name")) ?? "thunderbolt",
                        status: Profiler.text(tag["receptacle_status_key"]),
                        speed: Profiler.text(tag["current_speed_key"]),
                        receptacle: Profiler.toInt(tag["receptacle_id_key"]),
                        device: Profiler.text(entry["device_name_key"]),
                        vendor: Profiler.text(entry["vendor_name_key"])
                    )
                )
            }
        }
        return (ports, [])
    }
}
