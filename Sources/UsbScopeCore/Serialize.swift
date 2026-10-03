import Foundation

/// Machine readable representation of a snapshot — the twin of
/// `usbscope/serialize.py`. The keys and the schema version are identical, so a
/// consumer cannot tell which implementation produced the JSON.
public enum Serialize {
    public static let schemaVersion = 1

    /// JSON has no optionals: an unknown value becomes `null`, like in Python.
    static func orNull(_ value: Any?) -> Any { value ?? NSNull() }

    private static let seenAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func device(_ device: UsbDevice) -> [String: Any] {
        [
            "name": device.name,
            "vendor": orNull(device.vendor),
            "vendor_id": orNull(device.vendorID),
            "product_id": orNull(device.productID),
            "id": device.idString,
            "serial": orNull(device.serial),
            "location_id": orNull(device.locationID),
            "speed_mbps": orNull(device.speedMbps),
            "mode": device.mode.rawValue,
            "mode_label": device.mode.label,
            "connection": orNull(device.connection),
            "version": orNull(device.version),
            "bus": orNull(device.bus),
            "port": orNull(device.port),
            "port_type": orNull(device.portType),
            "transport": orNull(device.transport),
            "generation": orNull(device.generation),
            "restricted": orNull(device.restricted),
            "source": device.source,
            "device_class": orNull(device.deviceClass),
            "device_subclass": orNull(device.deviceSubclass),
            "device_protocol": orNull(device.deviceProtocol),
            "class_name": orNull(device.className),
            "class_text": orNull(device.classText),
            "bcd_usb": orNull(device.bcdUsb),
            "max_packet_size0": orNull(device.maxPacketSize0),
            "num_configurations": orNull(device.numConfigurations),
            "speed_code": orNull(device.speedCode),
            "tier": orNull(device.tier),
            "parent": orNull(device.parent),
            "address": orNull(device.address),
        ]
    }

    static func cable(_ cable: Cable) -> [String: Any] {
        [
            "attached": cable.attached,
            "kind": cable.kind,
            "emarker": cable.emarker,
            "active": cable.active,
            "optical": cable.optical,
            "authentication": orNull(cable.authentication),
            "hash_status": orNull(cable.hashStatus),
            "pd_spec_revision": orNull(cable.pdSpecRevision),
        ]
    }

    static func powerOption(_ option: PowerOption?) -> Any {
        guard let option else { return NSNull() }
        return [
            "voltage_mv": orNull(option.voltageMv),
            "max_current_ma": orNull(option.maxCurrentMa),
            "max_power_mw": orNull(option.maxPowerMw),
            "watts": orNull(option.watts),
            "kind": orNull(option.kind),
            "kind_label": orNull(option.kindLabel),
            "uuid": orNull(option.uuid),
        ]
    }

    static func powerSource(_ source: PowerSource) -> [String: Any] {
        [
            "name": source.name,
            "type": orNull(source.sourceType),
            "priority": orNull(source.priority),
            "selected": source.selected,
            "winning": powerOption(source.winning),
            "options": source.options.map { powerOption($0) },
        ]
    }

    static func transport(_ transport: Transport) -> [String: Any] {
        [
            "kind": transport.kind,
            "active": transport.active,
            "rate": orNull(transport.rateText),
            "speed_mbps": orNull(transport.speedMbps),
            "mode": transport.mode.rawValue,
            "generation": orNull(transport.generation),
            "signaling": orNull(transport.signaling),
            "data_role": orNull(transport.dataRole),
            "lanes": orNull(transport.lanes),
            "restricted": orNull(transport.restricted),
            "trm_state": orNull(transport.trmState),
            "trm_profile": orNull(transport.trmProfile),
            "hash_status": orNull(transport.hashStatus),
        ]
    }

    static func port(_ port: UsbPort) -> [String: Any] {
        var pins: [String: Int] = [:]
        for assignment in port.pinConfiguration { pins[assignment.name] = assignment.value }
        var payload: [String: Any] = [:]
        payload["description"] = port.description
        payload["name"] = port.name
        payload["kind"] = port.kind
        payload["number"] = orNull(port.number)
        payload["connected"] = port.connected
        payload["mode"] = port.mode.rawValue
        payload["mode_label"] = port.mode.label
        payload["connect_type"] = orNull(port.connectType)
        payload["super_speed_active"] = orNull(port.superSpeedActive)
        payload["plug_orientation"] = orNull(port.plugOrientation)
        payload["displayport_pin_assignment"] = orNull(port.displayPortPinAssignment)
        payload["liquid_detected"] = orNull(port.liquidDetected)
        payload["authorization"] = orNull(port.authorization)
        payload["firmware"] = orNull(port.firmware)
        payload["power_in"] = port.powerIn
        payload["pin_configuration"] = pins
        payload["usb_mode_type"] = orNull(port.usbModeType)
        payload["accessory_mode"] = orNull(port.accessoryMode)
        payload["power_mode"] = orNull(port.powerMode)
        payload["active_power_mode"] = orNull(port.activePowerMode)
        payload["supported_power_modes"] = port.supportedPowerModes
        payload["power_current_limits"] = port.powerCurrentLimits
        payload["liquid_state"] = orNull(port.liquidState)
        payload["liquid_measurement"] = orNull(port.liquidMeasurement)
        payload["liquid_pin"] = orNull(port.liquidPin)
        payload["liquid_mitigations"] = orNull(port.liquidMitigations)
        payload["liquid_override"] = orNull(port.liquidOverride)
        payload["power_sources"] = port.powerSources.map { powerSource($0) }
        payload["cable"] = cable(port.cable)
        payload["transports"] = port.transports.map { transport($0) }
        payload["devices"] = port.devices.map { device($0) }
        return payload
    }

    static func bus(_ bus: Bus) -> [String: Any] {
        [
            "name": bus.name,
            "driver": orNull(bus.driver),
            "location_id": orNull(bus.locationID),
            "connection": orNull(bus.connection),
            "protocol": orNull(bus.protocolRevision),
            "devices": bus.devices.map { device($0) },
        ]
    }

    static func thunderbolt(_ port: ThunderboltPort) -> [String: Any] {
        [
            "bus": port.bus,
            "receptacle": orNull(port.receptacle),
            "status": orNull(port.status),
            "speed": orNull(port.speed),
            "connected": port.connected,
            "device": orNull(port.device),
            "vendor": orNull(port.vendor),
        ]
    }

    static func charging(_ charging: Charging?) -> Any {
        guard let charging else { return NSNull() }
        return [
            "connected": orNull(charging.connected),
            "charging": orNull(charging.charging),
            "fully_charged": orNull(charging.fullyCharged),
            "state_of_charge": orNull(charging.stateOfCharge),
            "time_remaining_minutes": orNull(charging.timeRemainingMinutes),
            "system_power_in_mw": orNull(charging.systemPowerInMw),
            "system_voltage_in_mv": orNull(charging.systemVoltageInMv),
            "system_current_in_ma": orNull(charging.systemCurrentInMa),
            "system_load_mw": orNull(charging.systemLoadMw),
            "battery_power_mw": orNull(charging.batteryPowerMw),
            "battery_voltage_mv": orNull(charging.batteryVoltageMv),
            "battery_current_ma": orNull(charging.batteryCurrentMa),
            "adapter_power_mw": orNull(charging.adapterPowerMw),
            "adapter_voltage_mv": orNull(charging.adapterVoltageMv),
            "adapter_current_ma": orNull(charging.adapterCurrentMa),
            "adapter_efficiency_loss_mw": orNull(charging.adapterEfficiencyLossMw),
            "not_charging_reason": orNull(charging.notChargingReason),
            "slow_charging_reason": orNull(charging.slowChargingReason),
            "thermally_limited_seconds": orNull(charging.thermallyLimitedSeconds),
        ]
    }

    /// Serialise a snapshot into plain JSON compatible types.
    public static func dict(_ snapshot: Snapshot) -> [String: Any] {
        [
            "schema_version": schemaVersion,
            "host": snapshot.host,
            "os_version": snapshot.osVersion,
            "model": orNull(snapshot.model),
            "chip": orNull(snapshot.chip),
            "seen_at": seenAtFormatter.string(from: snapshot.seenAt),
            "summary": [
                "ports": snapshot.ports.count,
                "connected_ports": snapshot.connectedPorts.count,
                "devices": snapshot.devices.count,
                "emarked_cables": snapshot.emarkedCables.count,
            ],
            "ports": snapshot.ports.map { port($0) },
            "buses": snapshot.buses.map { bus($0) },
            "thunderbolt": snapshot.thunderbolt.map { thunderbolt($0) },
            "charging": charging(snapshot.charging),
            "warnings": snapshot.warnings,
        ]
    }

    /// Serialise a snapshot as JSON text (`indent: nil` for one compact line).
    public static func json(_ snapshot: Snapshot, indent: Int? = 2) -> String {
        var options: JSONSerialization.WritingOptions = [.withoutEscapingSlashes]
        if indent != nil { options.insert(.prettyPrinted); options.insert(.sortedKeys) }
        guard let data = try? JSONSerialization.data(withJSONObject: dict(snapshot), options: options),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    // MARK: - security report (its own document, never the snapshot schema)

    public static let securitySchemaVersion = 1

    static func finding(_ finding: Finding) -> [String: Any] {
        [
            "rule": finding.rule,
            "severity": finding.severity.rawValue,
            "subject": finding.subject,
            "detail": finding.detail,
            "port": orNull(finding.port),
            "device": orNull(finding.device),
            "location_id": orNull(finding.locationID),
        ]
    }

    static func storageDevice(_ device: StorageDevice) -> [String: Any] {
        [
            "identifier": device.identifier,
            "name": orNull(device.name),
            "bus_protocol": orNull(device.busProtocol),
            "capacity_bytes": orNull(device.capacityBytes),
            "read_only": orNull(device.readOnly),
            "removable": orNull(device.removable),
            "mount_point": orNull(device.mountPoint),
            "content": orNull(device.content),
        ]
    }

    /// Serialise a security report plus the storage inventory.
    ///
    /// This is a document of its own (`kind: security`) — it never changes the
    /// `schema_version: 1` snapshot document.
    public static func securityDict(
        _ report: SecurityReport, storage: [StorageDevice] = [], generatedAt: Date
    ) -> [String: Any] {
        [
            "schema_version": securitySchemaVersion,
            "kind": "security",
            "generated_at": seenAtFormatter.string(from: generatedAt),
            "counts": [
                "info": report.count(.info),
                "attention": report.count(.attention),
                "warning": report.count(.warning),
                "total": report.findings.count,
            ],
            "findings": report.findings.map { finding($0) },
            "storage": storage.map { storageDevice($0) },
        ]
    }

    /// Serialise the security report as JSON text (pretty output sorts keys, like Python).
    public static func securityJSON(
        _ report: SecurityReport, storage: [StorageDevice] = [], generatedAt: Date, indent: Int? = 2
    ) -> String {
        var options: JSONSerialization.WritingOptions = [.withoutEscapingSlashes]
        if indent != nil { options.insert(.prettyPrinted); options.insert(.sortedKeys) }
        let payload = securityDict(report, storage: storage, generatedAt: generatedAt)
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: options),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
