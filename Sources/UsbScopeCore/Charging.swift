import Foundation

/// Adapter for the battery/charger telemetry — the twin of
/// `usbscope/sources/charging.py`.
///
/// Two sources are merged: `system_profiler SPPowerDataType -json` names the
/// adapter (watt, connected, charging state, state of charge), and
/// `ioreg -r -n AppleSmartBattery -a -l -w0` carries the live SMC numbers
/// (adapter input, system load, battery flow, adapter PD menu).
public enum ChargingParser {
    static let batteryClass = "AppleSmartBattery"
    static let adapterEntry = "sppower_ac_charger_information"
    static let batteryEntry = "spbattery_information"

    static func int(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if PlistValue.isBool(value) { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return PlistValue.int(text) }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.intValue != 0 }
        if let text = value as? String {
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "yes", "true", "y": return true
            case "no", "false", "n": return false
            default: return nil
            }
        }
        return nil
    }

    /// The first value that is not `nil`.
    static func first(_ values: Any?...) -> Any? {
        for value in values where value != nil { return value }
        return nil
    }

    /// A minute value, with the `0`/`65535` placeholders of macOS as unknown.
    static func minutes(_ value: Any?) -> Int? {
        guard let number = int(value), number > 0, number < 65535 else { return nil }
        return number
    }

    static func wattsToMw(_ value: Any?) -> Int? {
        guard let number = int(value) else { return nil }
        return number * 1000
    }

    /// Find the `AppleSmartBattery` node inside a parsed ioreg plist.
    static func batteryNode(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if (dict["IOObjectClass"] as? String) == batteryClass || dict["InstantAmperage"] != nil {
                return dict
            }
            for child in dict.values {
                if let found = batteryNode(child) { return found }
            }
        } else if let list = value as? [Any] {
            for child in list {
                if let found = batteryNode(child) { return found }
            }
        }
        return nil
    }

    static func group(_ node: [String: Any], _ key: String) -> [String: Any] {
        (node[key] as? [String: Any]) ?? [:]
    }

    /// The adapter row macOS reports, whichever of its two keys is present.
    static func adapter(_ node: [String: Any]) -> [String: Any] {
        for key in ["AdapterDetails", "AppleRawAdapterDetails"] {
            let value = node[key]
            let entries = (value as? [Any]) ?? [value as Any]
            for entry in entries where entry is [String: Any] {
                if let dict = entry as? [String: Any] { return dict }
            }
        }
        return [:]
    }
}

/// Reads the live power and charging telemetry of the machine.
public struct ChargingSource: Sendable {
    private let run: Runner

    public init(runner: Runner? = nil) {
        self.run = runner ?? { Shell.run($0) }
    }

    public static let binary = Shell.systemBinary("ioreg", "/usr/sbin/ioreg", "/usr/bin/ioreg")

    /// The adapter entry, the charge info and an optional warning.
    func powerReport() -> ([String: Any], [String: Any], String?) {
        let result = run([SystemProfiler.binary, "SPPowerDataType", "-json"])
        guard result.ok else {
            return ([:], [:], result.error ?? "system_profiler SPPowerDataType failed")
        }
        guard let payload = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] else {
            return ([:], [:], "system_profiler SPPowerDataType returned unparsable output")
        }
        var entries = payload["SPPowerDataType"] as? [Any] ?? []
        if let single = payload["SPPowerDataType"] as? [String: Any] { entries = [single] }
        var adapter: [String: Any] = [:]
        var charge: [String: Any] = [:]
        for case let entry as [String: Any] in entries {
            switch entry["_name"] as? String {
            case ChargingParser.adapterEntry: adapter = entry
            case ChargingParser.batteryEntry:
                charge = (entry["sppower_battery_charge_info"] as? [String: Any]) ?? [:]
            default: continue
            }
        }
        return (adapter, charge, nil)
    }

    func batteryNode() -> ([String: Any]?, String?) {
        let result = run([Self.binary, "-r", "-n", ChargingParser.batteryClass, "-a", "-l", "-w0"])
        guard result.ok else { return (nil, result.error ?? "ioreg failed") }
        guard !result.stdout.isEmpty else { return (nil, nil) }  // no such class: nothing to report
        guard let plist = try? PropertyListSerialization.propertyList(
            from: result.stdout, options: [], format: nil
        ) else {
            return (nil, "ioreg returned unparsable output")
        }
        return (ChargingParser.batteryNode(plist), nil)
    }

    /// The live charging telemetry plus any non-fatal warnings.
    ///
    /// A desktop without a battery reports neither source and stays silent:
    /// that is a normal state, not a problem.
    public func charging() -> (Charging?, [String]) {
        var warnings: [String] = []
        let (adapterEntry, charge, powerWarning) = powerReport()
        if let powerWarning { warnings.append(powerWarning) }
        let (node, batteryWarning) = batteryNode()
        if let batteryWarning { warnings.append(batteryWarning) }
        if node == nil && adapterEntry.isEmpty && charge.isEmpty {
            return (nil, Array(Set(warnings)).sorted())
        }

        let data = node ?? [:]
        let telemetry = ChargingParser.group(data, "PowerTelemetryData")
        let chargerData = ChargingParser.group(data, "ChargerData")
        let adapter = ChargingParser.adapter(data)
        var charging = Charging()
        charging.connected = ChargingParser.bool(
            ChargingParser.first(adapterEntry["sppower_battery_charger_connected"], data["ExternalConnected"])
        )
        charging.charging = ChargingParser.bool(
            ChargingParser.first(
                charge["sppower_battery_is_charging"],
                adapterEntry["sppower_battery_is_charging"],
                data["IsCharging"],
                chargerData["IsCharging"]
            )
        )
        charging.fullyCharged = ChargingParser.bool(
            ChargingParser.first(charge["sppower_battery_fully_charged"], data["FullyCharged"])
        )
        charging.stateOfCharge = ChargingParser.int(charge["sppower_battery_state_of_charge"])
        charging.timeRemainingMinutes = ChargingParser.minutes(data["TimeRemaining"])
        charging.systemPowerInMw = ChargingParser.int(telemetry["SystemPowerIn"])
        charging.systemVoltageInMv = ChargingParser.int(telemetry["SystemVoltageIn"])
        charging.systemCurrentInMa = ChargingParser.int(telemetry["SystemCurrentIn"])
        charging.systemLoadMw = ChargingParser.int(telemetry["SystemLoad"])
        charging.batteryPowerMw = ChargingParser.int(telemetry["BatteryPower"])
        charging.batteryVoltageMv = ChargingParser.int(data["Voltage"])
        charging.batteryCurrentMa = ChargingParser.int(
            ChargingParser.first(data["InstantAmperage"], data["Amperage"])
        )
        charging.adapterPowerMw = ChargingParser.first(
            ChargingParser.wattsToMw(adapter["Watts"]),
            ChargingParser.wattsToMw(adapterEntry["sppower_ac_charger_watts"])
        ) as? Int
        charging.adapterVoltageMv = ChargingParser.int(adapter["AdapterVoltage"])
        charging.adapterCurrentMa = ChargingParser.int(adapter["Current"])
        charging.adapterEfficiencyLossMw = ChargingParser.int(telemetry["AdapterEfficiencyLoss"])
        charging.notChargingReason = ChargingParser.int(chargerData["NotChargingReason"])
        charging.slowChargingReason = ChargingParser.int(chargerData["SlowChargingReason"])
        charging.thermallyLimitedSeconds = ChargingParser.int(chargerData["TimeChargingThermallyLimited"])

        var unique: [String] = []
        for warning in warnings where !unique.contains(warning) { unique.append(warning) }
        return charging.isEmpty ? (nil, unique) : (charging, unique)
    }
}
