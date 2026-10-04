import Foundation

/// The deterministic precedence used when the same device is reported by more
/// than one macOS source. The port controller is the primary live connection
/// source, followed by the bus report and finally the registry descriptor data.
/// Registry-only descriptor fields are merged separately and never overwrite a
/// value already supplied by a higher-precedence source.
public enum SourcePrecedence {
    public static let deviceSources = ["ioPort", "system_profiler", "ioUSB"]

    /// Fields whose disagreement can materially change the displayed result.
    /// Identity fields are deliberately excluded: a collision is handled by
    /// the duplicate-location warning instead of silently choosing a name.
    public static let conflictFields = [
        "serial", "speed_mbps", "speed_text", "connection", "transport", "restricted"
    ]

    public static func conflicts(_ first: UsbDevice, _ second: UsbDevice) -> [String] {
        var result: [String] = []
        if let lhs = first.serial, let rhs = second.serial, lhs != rhs { result.append("serial") }
        if let lhs = first.speedMbps, let rhs = second.speedMbps, lhs != rhs { result.append("speed_mbps") }
        if let lhs = first.speedText, let rhs = second.speedText, lhs != rhs { result.append("speed_text") }
        if let lhs = first.connection, let rhs = second.connection, lhs != rhs { result.append("connection") }
        if let lhs = first.transport, let rhs = second.transport, lhs != rhs { result.append("transport") }
        if let lhs = first.restricted, let rhs = second.restricted, lhs != rhs { result.append("restricted") }
        return result
    }
}
