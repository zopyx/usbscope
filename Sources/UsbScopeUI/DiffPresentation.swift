import Foundation
import UsbScopeCore

/// What a diff row stands for, relative to the baseline snapshot.
public enum DiffChangeKind: String, Sendable, CaseIterable {
    /// Present on the live machine, absent from the baseline.
    case appeared
    /// Present in the baseline, gone from the live machine.
    case disappeared
    /// A port whose state differs from the baseline.
    case changed
}

/// One line of the baseline comparison.
public struct DiffRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: DiffChangeKind
    public let item: String
    public let detail: String
}

/// The "Compare with…" tab's presentation.
///
/// The baseline is an older snapshot (e.g. one written by `usbscope baseline
/// save`); `diffSnapshots(previous: baseline, current: live)` yields the edges.
/// "appeared" is what the live machine has and the baseline did not, so a device
/// plugged in since the baseline is `appeared`.
public enum DiffPresentation {
    /// The three counts of a change set, in display order.
    public static func counts(_ changes: ChangeSet) -> [(kind: DiffChangeKind, count: Int)] {
        [
            (.appeared, changes.added.count),
            (.disappeared, changes.removed.count),
            (.changed, changes.changedPorts.count),
        ]
    }

    /// Flatten a change set into rows: appeared, then disappeared, then the
    /// changed ports, each group sorted for a stable order.
    public static func rows(_ changes: ChangeSet) -> [DiffRow] {
        var rows: [DiffRow] = []
        let appeared = changes.added.sorted { deviceKey($0) < deviceKey($1) }
        for (index, device) in appeared.enumerated() {
            rows.append(
                DiffRow(
                    id: "appeared:\(index)",
                    kind: .appeared,
                    item: device.label,
                    detail: deviceDetail(device)
                )
            )
        }
        let disappeared = changes.removed.sorted { deviceKey($0) < deviceKey($1) }
        for (index, device) in disappeared.enumerated() {
            rows.append(
                DiffRow(
                    id: "disappeared:\(index)",
                    kind: .disappeared,
                    item: device.label,
                    detail: deviceDetail(device)
                )
            )
        }
        for (index, key) in changes.changedPorts.sorted().enumerated() {
            let name = key.hasPrefix("port:") ? String(key.dropFirst("port:".count)) : key
            rows.append(
                DiffRow(
                    id: "changed:\(index)",
                    kind: .changed,
                    item: name,
                    detail: "port state differs from the baseline"
                )
            )
        }
        return rows
    }

    private static func deviceDetail(_ device: UsbDevice) -> String {
        var parts: [String] = []
        if let vendor = device.vendor, !vendor.isEmpty { parts.append(vendor) }
        parts.append(device.idString)
        parts.append(device.mode.label)
        if let serial = device.serial, !serial.isEmpty { parts.append("serial \(serial)") }
        return parts.joined(separator: " · ")
    }

    /// `1 appeared · 0 disappeared · 2 changed` for the status line.
    public static func summary(_ changes: ChangeSet) -> String {
        counts(changes).map { "\($0.count) \($0.kind.rawValue)" }.joined(separator: " · ")
    }
}
