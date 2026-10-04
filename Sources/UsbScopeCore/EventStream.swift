import Foundation

/// Attach/detach event stream (`usbscope watch --events`) — the twin of
/// `usbscope/events.py`.
///
/// One compact JSON object per line per USB edge, flushed immediately so a shell
/// script can pipe it. This builds on `UsbEvents.swift`: `usbEvents(_:at:)`
/// already turns a `ChangeSet` into attach/detach `UsbEvent`s with the identity
/// the app uses; this file adds the `port` field and the exact JSON line shape.
///
/// **Identity and order are shared with the Python twin.** A device is keyed by
/// its `location_id` when it has one (else its name); detaches are emitted before
/// attaches and each group is sorted by that key. `usbEvents` sorts by
/// `deviceKey` instead, so the order is re-established here — otherwise a
/// multi-device change would stream in a language-specific order.
///
/// The live trigger is `UsbHotplugWatcher` (real IOKit notifications, falling
/// back to its documented polling differ); the Python side polls because it has
/// no IOKit bridge — see `usbscope/events.py`.
public enum EventStream {
    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Stable identity of an event's device (location ID, else name).
    public static func identity(_ event: UsbEvent) -> String {
        if let location = event.locationID { return "loc:\(location)" }
        return "name:\(event.name)"
    }

    /// The `port` an event's device sits on, resolved from the change lists.
    ///
    /// A terminating device no longer exposes its properties, which is why the
    /// identity came from the diff — the removed device in the change set still
    /// carries the `port` it had.
    public static func port(of event: UsbEvent, in changes: ChangeSet) -> String? {
        let candidates = changes.added + changes.removed
        return candidates.first { deviceKey($0) == event.key }?.port
    }

    /// One compact, sorted JSON line (no spaces).
    public static func line(_ event: UsbEvent, port: String?) -> String {
        let payload: [String: Any] = [
            "timestamp": timestampFormatter.string(from: event.seenAt),
            "kind": event.kind.rawValue,
            "name": event.name,
            "vendor_id": Serialize.orNull(event.vendorID),
            "product_id": Serialize.orNull(event.productID),
            "serial": Serialize.orNull(event.serial),
            "location_id": Serialize.orNull(event.locationID),
            "port": Serialize.orNull(port),
        ]
        return sortedJSONText(payload, pretty: false)
    }

    /// Every event of a change set as JSON lines, in the shared deterministic order.
    public static func lines(_ changes: ChangeSet, at: Date) -> [String] {
        let events = usbEvents(changes, at: at)
        let detached = events.filter { $0.kind == .detached }.sorted { identity($0) < identity($1) }
        let attached = events.filter { $0.kind == .attached }.sorted { identity($0) < identity($1) }
        return (detached + attached).map { line($0, port: port(of: $0, in: changes)) }
    }
}
