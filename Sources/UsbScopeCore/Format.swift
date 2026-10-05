import Foundation

/// Human readable formatting of the raw power numbers — the twin of
/// `usbscope/format.py`. Both frontends (CLI and SwiftUI app) print these
/// strings, so they are built once here. The model keeps mV/mA/mW untouched.
public enum Format {
    /// Shortest form of a decimal, like Python's `%g` (`20`, `3.5`, `7.5`).
    public static func g(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// A byte count as `GB`/`MB`/`kB`/`B` (SI, not GiB), like Python's `format_bytes`.
    public static func bytes(_ value: Int?) -> String? {
        guard let value else { return nil }
        if value >= 1_000_000_000 { return String(format: "%.1f GB", Double(value) / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.0f MB", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0f kB", Double(value) / 1_000) }
        return "\(value) B"
    }

    /// Milliwatts as watt: `35.9 W`, or `36 W` when asked compactly.
    public static func watts(_ mw: Int?, compact: Bool = false) -> String? {
        guard let mw else { return nil }
        let value = Double(mw) / 1000
        return compact ? "\(g(value)) W" : String(format: "%.1f W", value)
    }

    /// Millivolts as volt: `19.5 V`, or `20 V` when asked compactly.
    public static func volts(_ mv: Int?, compact: Bool = false) -> String? {
        guard let mv else { return nil }
        let value = Double(mv) / 1000
        return compact ? "\(g(value)) V" : String(format: "%.1f V", value)
    }

    /// Milliamps as ampere: `1.42 A`, or `3.5 A` when asked compactly.
    public static func amps(_ ma: Int?, compact: Bool = false) -> String? {
        guard let ma else { return nil }
        let value = Double(ma) / 1000
        return compact ? "\(g(value)) A" : String(format: "%.2f A", value)
    }

    /// `36.0 W · 19.4 V · 1.86 A` — only the parts that are known.
    public static func powerLine(
        powerMw: Int?, voltageMv: Int?, currentMa: Int?, compact: Bool = false
    ) -> String? {
        let parts = [
            watts(powerMw, compact: compact),
            volts(voltageMv, compact: compact),
            amps(currentMa, compact: compact),
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The charger problems macOS would act on (`0` means it sees none).
    public static func chargerFlags(_ charging: Charging) -> String? {
        var flags: [String] = []
        if let reason = charging.notChargingReason, reason != 0 { flags.append("not charging: \(reason)") }
        if let reason = charging.slowChargingReason, reason != 0 { flags.append("slow charging: \(reason)") }
        if let seconds = charging.thermallyLimitedSeconds, seconds != 0 {
            flags.append("thermally limited \(seconds) s")
        }
        return flags.isEmpty ? nil : flags.joined(separator: ", ")
    }

    /// `charging · 42 % · 17 min to full` — state, charge and remaining time.
    public static func chargingState(_ charging: Charging) -> String? {
        let state: String?
        if charging.charging == true {
            state = "charging"
        } else if charging.fullyCharged == true {
            state = "fully charged"
        } else if charging.connected == true {
            state = "plugged in, not charging"
        } else if charging.connected == false {
            state = "on battery"
        } else {
            state = nil
        }
        var parts: [String] = state.map { [$0] } ?? []
        if let charge = charging.stateOfCharge { parts.append("\(charge) %") }
        // macOS reports one value for both directions and none when it is full
        if let minutes = charging.timeRemainingMinutes, minutes > 0, charging.fullyCharged != true {
            parts.append("\(minutes) min \(charging.charging == true ? "to full" : "left")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `35.9 W in · 21.8 W battery · 14.2 W system` — only what is known.
    public static func chargingSummary(_ charging: Charging) -> String? {
        var parts: [String] = []
        if let text = watts(charging.systemPowerInMw) { parts.append("\(text) in") }
        if let text = watts(charging.batteryPowerMw) { parts.append("\(text) battery") }
        if let text = watts(charging.systemLoadMw) { parts.append("\(text) system") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
