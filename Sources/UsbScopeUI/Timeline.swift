import Foundation
import UsbScopeCore

/// The geometry of the power sparkline: it maps a `PowerPoint` onto the unit
/// square (x = time, y = watts) so the view only draws, it does not scale.
///
/// Only points that actually carry a measured watt value take part; a snapshot
/// without charging telemetry leaves a gap and must not drag the axis to zero.
/// A flat series (one point, or every point the same) maps to the middle, and a
/// single point sits centred — never a division by zero.
public struct TimelineGeometry: Equatable, Sendable {
    /// The measured points, oldest first (exactly what the chart draws).
    public let points: [PowerPoint]
    public let minWatts: Double
    public let maxWatts: Double
    public let minAt: Date
    public let maxAt: Date

    public init(_ timeline: [PowerPoint]) {
        let measured = timeline.filter(\.hasPower)
        points = measured
        let watts = measured.compactMap(\.watts)
        minWatts = watts.min() ?? 0
        maxWatts = watts.max() ?? 0
        minAt = measured.first?.at ?? Date(timeIntervalSince1970: 0)
        maxAt = measured.last?.at ?? minAt
    }

    public var isEmpty: Bool { points.isEmpty }

    /// Seconds between the first and the last measured point.
    public var span: TimeInterval { maxAt.timeIntervalSince(minAt) }

    /// Watts between the lowest and the highest measured value.
    public var wattsSpan: Double { maxWatts - minWatts }

    /// x in `0…1` for a point in time (a degenerate span centres the point).
    public func x(_ at: Date) -> Double {
        guard !points.isEmpty else { return 0 }
        guard span > 0 else { return 0.5 }
        return min(max(at.timeIntervalSince(minAt) / span, 0), 1)
    }

    /// y in `0…1`, `0` at the bottom of the plot (a flat series is centred).
    public func y(_ watts: Double) -> Double {
        guard wattsSpan > 0 else { return 0.5 }
        return min(max((watts - minWatts) / wattsSpan, 0), 1)
    }

    /// The points as `(x, y)` pairs ready to be wired into a `Path`.
    public var unitPoints: [(x: Double, y: Double)] {
        points.compactMap { point in
            guard let watts = point.watts else { return nil }
            return (x(point.at), y(watts))
        }
    }

    /// `17.6 – 35.9 W` over the measured points, or `nil` when there are none.
    public var rangeText: String? {
        guard !points.isEmpty else { return nil }
        return "\(Format.watts(Int((minWatts * 1000).rounded())) ?? "–") – "
            + "\(Format.watts(Int((maxWatts * 1000).rounded())) ?? "–")"
    }

    /// `HH:mm:ss – HH:mm:ss` covering the measured points.
    public func timeRangeText(formatter: DateFormatter = TimelineFormat.clock) -> String? {
        guard !points.isEmpty else { return nil }
        return "\(formatter.string(from: minAt)) – \(formatter.string(from: maxAt))"
    }
}

/// One row of the hotplug event list (the `EventLog` tail).
public struct EventRow: Identifiable, Hashable, Sendable {
    public let id: String
    /// `HH:mm:ss` of the event.
    public let time: String
    /// `attached` / `detached`.
    public let kind: String
    public let name: String
    /// Vendor, VID:PID and serial, whichever are known.
    public let detail: String
    /// True for an attach edge (the view tints the row).
    public let isAttach: Bool
}

/// Formatting shared by the timeline view and its tests.
public enum TimelineFormat {
    /// Fixed `HH:mm:ss` so the output does not depend on the user's locale.
    public static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

/// Turn recorded hotplug events into rows, newest first.
///
/// The log is append-only and grows without bound, so the view asks for a `limit`
/// (the newest N) instead of the whole history. Events with the same timestamp
/// keep a stable order by device key, so the list does not reshuffle between
/// renders.
public func eventRows(
    _ events: [UsbEvent],
    limit: Int = 200,
    formatter: DateFormatter = TimelineFormat.clock
) -> [EventRow] {
    events
        .sorted { left, right in
            if left.seenAt != right.seenAt { return left.seenAt > right.seenAt }
            return left.key < right.key
        }
        .prefix(max(limit, 0))
        .enumerated()
        .map { index, event in
            var parts: [String] = []
            if let vendor = event.vendor, !vendor.isEmpty { parts.append(vendor) }
            if let vendorID = event.vendorID, let productID = event.productID {
                parts.append(String(format: "0x%04x:0x%04x", vendorID, productID))
            }
            if let serial = event.serial, !serial.isEmpty { parts.append("serial \(serial)") }
            return EventRow(
                id: "\(event.key)#\(index)",
                time: formatter.string(from: event.seenAt),
                kind: event.kind.rawValue,
                name: event.name,
                detail: parts.joined(separator: " · "),
                isAttach: event.kind == .attached
            )
        }
}
