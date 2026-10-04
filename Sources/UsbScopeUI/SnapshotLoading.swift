import Foundation
import UsbScopeCore

/// Why a snapshot JSON could not be read.
public enum SnapshotLoadingError: Error, Equatable {
    case notAnObject
}

/// Load a `Snapshot` back from the JSON `usbscope json` / `usbscope baseline
/// save` writes (`Serialize.json`).
///
/// This is what the "Compare with…" tab needs: it reads a baseline file, turns it
/// back into a `Snapshot` and diffs it against the live machine with
/// `diffSnapshots`. Only the fields the comparison uses are decoded (ports and
/// their devices, the identity, the warnings); unknown keys are ignored, so a
/// newer baseline still loads. A missing field becomes `nil`/absent, never a
/// crash — an unreadable *shape* is the only error.
public enum SnapshotLoading {
    static let seenAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public static func snapshot(from url: URL) throws -> Snapshot {
        try snapshot(from: Data(contentsOf: url))
    }

    public static func snapshot(from data: Data) throws -> Snapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SnapshotLoadingError.notAnObject
        }
        return snapshot(fromObject: object)
    }

    static func snapshot(fromObject object: [String: Any]) -> Snapshot {
        let seenAt = object["seen_at"] as? String ?? ""
        let date = seenAtFormatter.date(from: seenAt) ?? Date(timeIntervalSince1970: 0)
        let ports = (object["ports"] as? [[String: Any]] ?? []).map(port)
        let buses = (object["buses"] as? [[String: Any]] ?? []).map(bus)
        let thunderbolt = (object["thunderbolt"] as? [[String: Any]] ?? []).map(receptacle)
        return Snapshot(
            host: object["host"] as? String ?? "",
            osVersion: object["os_version"] as? String ?? "",
            seenAt: date,
            model: object["model"] as? String,
            chip: object["chip"] as? String,
            ports: ports,
            buses: buses,
            thunderbolt: thunderbolt,
            charging: charging(object["charging"]),
            warnings: object["warnings"] as? [String] ?? []
        )
    }

    // MARK: - Field helpers

    private static func text(_ dict: [String: Any], _ key: String) -> String? {
        guard let value = dict[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    private static func int(_ dict: [String: Any], _ key: String) -> Int? {
        (dict[key] as? NSNumber)?.intValue
    }

    private static func double(_ dict: [String: Any], _ key: String) -> Double? {
        (dict[key] as? NSNumber)?.doubleValue
    }

    private static func bool(_ dict: [String: Any], _ key: String) -> Bool? {
        (dict[key] as? NSNumber)?.boolValue
    }

    // MARK: - Model decoding

    static func device(_ dict: [String: Any]) -> UsbDevice {
        UsbDevice(
            name: text(dict, "name") ?? "?",
            vendor: text(dict, "vendor"),
            vendorID: int(dict, "vendor_id"),
            productID: int(dict, "product_id"),
            serial: text(dict, "serial"),
            locationID: int(dict, "location_id"),
            speedMbps: double(dict, "speed_mbps"),
            connection: text(dict, "connection"),
            version: text(dict, "version"),
            bus: text(dict, "bus"),
            port: text(dict, "port"),
            portType: text(dict, "port_type"),
            transport: text(dict, "transport"),
            generation: text(dict, "generation"),
            restricted: bool(dict, "restricted"),
            source: text(dict, "source") ?? "baseline",
            deviceClass: int(dict, "device_class"),
            deviceSubclass: int(dict, "device_subclass"),
            deviceProtocol: int(dict, "device_protocol"),
            className: text(dict, "class_name"),
            bcdUsb: text(dict, "bcd_usb"),
            maxPacketSize0: int(dict, "max_packet_size0"),
            numConfigurations: int(dict, "num_configurations"),
            speedCode: int(dict, "speed_code"),
            tier: int(dict, "tier"),
            parent: text(dict, "parent"),
            address: int(dict, "address")
        )
    }

    static func cable(_ dict: [String: Any]?) -> Cable {
        guard let dict else { return Cable() }
        return Cable(
            attached: bool(dict, "attached") ?? false,
            emarker: bool(dict, "emarker") ?? false,
            active: bool(dict, "active") ?? false,
            optical: bool(dict, "optical") ?? false,
            authentication: text(dict, "authentication"),
            hashStatus: text(dict, "hash_status"),
            pdSpecRevision: int(dict, "pd_spec_revision")
        )
    }

    static func transport(_ dict: [String: Any]) -> Transport {
        Transport(
            kind: text(dict, "kind") ?? "?",
            active: bool(dict, "active") ?? false,
            rateText: text(dict, "rate"),
            speedMbps: double(dict, "speed_mbps"),
            generation: text(dict, "generation"),
            signaling: text(dict, "signaling"),
            dataRole: text(dict, "data_role"),
            lanes: int(dict, "lanes"),
            restricted: bool(dict, "restricted"),
            trmState: text(dict, "trm_state"),
            trmProfile: text(dict, "trm_profile"),
            hashStatus: text(dict, "hash_status")
        )
    }

    static func port(_ dict: [String: Any]) -> UsbPort {
        var port = UsbPort(
            description: text(dict, "description") ?? text(dict, "name") ?? "?",
            kind: text(dict, "kind") ?? "?"
        )
        port.connected = bool(dict, "connected") ?? false
        port.number = int(dict, "number")
        port.connectType = text(dict, "connect_type")
        port.superSpeedActive = bool(dict, "super_speed_active")
        port.plugOrientation = int(dict, "plug_orientation")
        port.displayPortPinAssignment = int(dict, "displayport_pin_assignment")
        port.liquidDetected = bool(dict, "liquid_detected")
        port.authorization = text(dict, "authorization")
        port.firmware = text(dict, "firmware")
        port.powerIn = dict["power_in"] as? [String] ?? []
        port.usbModeType = int(dict, "usb_mode_type")
        port.accessoryMode = int(dict, "accessory_mode")
        port.powerMode = int(dict, "power_mode")
        port.activePowerMode = int(dict, "active_power_mode")
        port.supportedPowerModes = dict["supported_power_modes"] as? [Int] ?? []
        port.cable = cable(dict["cable"] as? [String: Any])
        port.transports = (dict["transports"] as? [[String: Any]] ?? []).map(transport)
        port.devices = (dict["devices"] as? [[String: Any]] ?? []).map(device)
        return port
    }

    static func bus(_ dict: [String: Any]) -> Bus {
        Bus(
            name: text(dict, "name") ?? "?",
            driver: text(dict, "driver"),
            locationID: int(dict, "location_id"),
            connection: text(dict, "connection"),
            protocolRevision: text(dict, "protocol"),
            devices: (dict["devices"] as? [[String: Any]] ?? []).map(device)
        )
    }

    static func receptacle(_ dict: [String: Any]) -> ThunderboltPort {
        ThunderboltPort(
            bus: text(dict, "bus") ?? "?",
            status: text(dict, "status"),
            speed: text(dict, "speed"),
            receptacle: int(dict, "receptacle"),
            device: text(dict, "device"),
            vendor: text(dict, "vendor")
        )
    }

    static func charging(_ value: Any?) -> Charging? {
        guard let dict = value as? [String: Any] else { return nil }
        var charging = Charging()
        charging.connected = bool(dict, "connected")
        charging.charging = bool(dict, "charging")
        charging.fullyCharged = bool(dict, "fully_charged")
        charging.stateOfCharge = int(dict, "state_of_charge")
        charging.timeRemainingMinutes = int(dict, "time_remaining_minutes")
        charging.systemPowerInMw = int(dict, "system_power_in_mw")
        charging.systemVoltageInMv = int(dict, "system_voltage_in_mv")
        charging.systemCurrentInMa = int(dict, "system_current_in_ma")
        charging.systemLoadMw = int(dict, "system_load_mw")
        charging.batteryPowerMw = int(dict, "battery_power_mw")
        charging.batteryVoltageMv = int(dict, "battery_voltage_mv")
        charging.batteryCurrentMa = int(dict, "battery_current_ma")
        charging.adapterPowerMw = int(dict, "adapter_power_mw")
        charging.adapterVoltageMv = int(dict, "adapter_voltage_mv")
        charging.adapterCurrentMa = int(dict, "adapter_current_ma")
        charging.adapterEfficiencyLossMw = int(dict, "adapter_efficiency_loss_mw")
        charging.notChargingReason = int(dict, "not_charging_reason")
        charging.slowChargingReason = int(dict, "slow_charging_reason")
        charging.thermallyLimitedSeconds = int(dict, "thermally_limited_seconds")
        return charging
    }
}
