import Foundation

/// Cached host metadata used by repeated refreshes.
///
/// `SPHardwareDataType` is stable for the lifetime of a boot/session while the
/// USB connection, power, and restriction sources are dynamic. Keeping this
/// cache separate makes the invalidation policy explicit and keeps the cache
/// safe when snapshots are collected from detached tasks.
public final class StableMetadataCache: @unchecked Sendable {
    public static let shared = StableMetadataCache()
    public struct Value: Sendable, Equatable {
        public let model: String?
        public let chip: String?
        public let capturedAt: Date

        public init(model: String?, chip: String?, capturedAt: Date) {
            self.model = model
            self.chip = chip
            self.capturedAt = capturedAt
        }
    }

    private let lock = NSLock()
    private var values: [String: Value] = [:]
    public let lifetime: TimeInterval

    public init(lifetime: TimeInterval = 60 * 60) {
        self.lifetime = max(0, lifetime)
    }

    /// Return a non-expired entry for `key`, if one exists.
    public func value(for key: String, at now: Date = Date()) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = values[key] else { return nil }
        guard now.timeIntervalSince(value.capturedAt) <= lifetime else {
            values.removeValue(forKey: key)
            return nil
        }
        return value
    }

    public func insert(_ value: Value, for key: String) {
        lock.lock()
        values[key] = value
        lock.unlock()
    }

    /// Invalidate all stable metadata, for example after a system update or
    /// when a user explicitly requests a cold read.
    public func invalidate() {
        lock.lock()
        values.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
