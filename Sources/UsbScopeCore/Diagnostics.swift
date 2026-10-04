import Foundation

public enum DataState: String, Codable, Sendable, CaseIterable {
    case absent, unknown, unavailable, unsupported, stale, present
}

public enum DataFreshness: String, Codable, Sendable, CaseIterable {
    case current, stale, unavailable, loading
}

public enum FactCertainty: String, Codable, Sendable, CaseIterable {
    case observed, derived, unavailable, stale
}

public enum FactSource: String, Codable, Sendable, CaseIterable {
    case systemProfiler, ioPort, ioUSB, interfaceRegistry, diskutil, heuristic
}

public struct Fact<T: Sendable>: Sendable {
    public let value: T?
    public let certainty: FactCertainty
    public let source: FactSource?
    public let explanation: String?

    public init(_ value: T?, certainty: FactCertainty = .observed,
                source: FactSource? = nil, explanation: String? = nil) {
        self.value = value
        self.certainty = certainty
        self.source = source
        self.explanation = explanation
    }
}

public struct SourceTiming: Codable, Sendable, Equatable {
    public let source: String
    public let startedAt: Date
    public let endedAt: Date
    public let result: SourceHealth
    public let warning: String?
    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    public init(source: String, startedAt: Date, endedAt: Date,
                result: SourceHealth, warning: String? = nil) {
        self.source = source; self.startedAt = startedAt; self.endedAt = endedAt
        self.result = result; self.warning = warning
    }
}

public enum AppErrorCode: String, Codable, Sendable, CaseIterable {
    case sourceUnavailable, sourceMalformed, commandFailed, commandTimedOut
    case exportFailed, cancelled, unsupported, schemaMismatch, permissionDenied
}

public struct SourceError: Error, Codable, Sendable, Equatable, LocalizedError {
    public let code: AppErrorCode
    public let source: String
    public let operation: String
    public let severity: String
    public let userMessage: String
    public let technicalMessage: String
    public let recoveryAction: String?

    public init(code: AppErrorCode, source: String, operation: String,
                severity: String = "warning", userMessage: String,
                technicalMessage: String, recoveryAction: String? = nil) {
        self.code = code; self.source = source; self.operation = operation
        self.severity = severity; self.userMessage = userMessage
        self.technicalMessage = technicalMessage; self.recoveryAction = recoveryAction
    }

    public var errorDescription: String? { userMessage }
}

/// Privacy policy shared by every support/export path.
public struct RedactionPolicy: Sendable, Equatable {
    public var redactSerials: Bool
    public var redactHost: Bool
    public var redactLocationIDs: Bool
    public var redactPaths: Bool
    public var redactEventIdentities: Bool

    public init(redactSerials: Bool = true, redactHost: Bool = true,
                redactLocationIDs: Bool = true, redactPaths: Bool = true,
                redactEventIdentities: Bool = true) {
        self.redactSerials = redactSerials
        self.redactHost = redactHost
        self.redactLocationIDs = redactLocationIDs
        self.redactPaths = redactPaths
        self.redactEventIdentities = redactEventIdentities
    }

    /// Redact sensitive values from a human-readable export without changing
    /// its format. Values are replaced longest-first to avoid partial leaks.
    public func redactText(_ text: String, snapshot: Snapshot,
                           storage: [StorageDevice] = []) -> String {
        var values: [String] = []
        if redactHost { values.append(snapshot.host) }
        if redactSerials {
            values += snapshot.devices.compactMap(\.serial)
            values += snapshot.ports.flatMap { $0.devices.compactMap(\.serial) }
        }
        if redactLocationIDs {
            values += snapshot.devices.compactMap { $0.locationID.map(String.init) }
        }
        if redactPaths { values += storage.compactMap(\.mountPoint) }
        var result = text
        for value in Set(values).filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: value, with: "[REDACTED]")
        }
        return result
    }
}

public enum DiagnosticBundle {
    public static let formatVersion = 1
    private static let architecture: String = {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }()

    /// Writes a complete, redacted support bundle to a new directory. The
    /// temporary directory is renamed only after all files are complete.
    @discardableResult
    public static func write(to destination: URL, snapshot: Snapshot?, warnings: [String],
                             timings: [String: Double] = [:], events: [UsbEvent] = [],
                             errors: [SourceError] = [],
                             policy: RedactionPolicy = RedactionPolicy()) throws -> URL {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".diagnostics-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        do {
            let safeWarnings = snapshot.map { current in
                warnings.map { policy.redactText($0, snapshot: current) }
            } ?? warnings
            let payload: [String: Any] = [
                "format_version": formatVersion,
                "generated_at": ISO8601DateFormatter().string(from: Date()),
                "app": "usbscope",
                "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
                "architecture": architecture,
                "warnings": safeWarnings,
                "errors": errors,
                "timings": timings,
                "redaction": [
                    "serials": policy.redactSerials, "host": policy.redactHost,
                    "location_ids": policy.redactLocationIDs, "paths": policy.redactPaths,
                    "event_identities": policy.redactEventIdentities,
                ],
            ]
            try json(payload).write(to: temporary.appendingPathComponent("metadata.json"), atomically: true, encoding: .utf8)
            if let snapshot {
                try redactedSnapshotJSON(snapshot, policy: policy)
                    .write(to: temporary.appendingPathComponent("snapshot.json"), atomically: true, encoding: .utf8)
            }
            let eventPayload = events.map { redacted(event: $0, policy: policy) }
            try json(["events": eventPayload]).write(to: temporary.appendingPathComponent("events.json"), atomically: true, encoding: .utf8)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: temporary, to: destination)
            return destination
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
    }

    public static func redactedSnapshotJSON(_ snapshot: Snapshot,
                                            policy: RedactionPolicy = RedactionPolicy()) -> String {
        let raw = json(redacted(Serialize.dict(snapshot), policy: policy))
        return policy.redactText(raw, snapshot: snapshot)
    }

    private static func json(_ value: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func redacted(_ value: Any, policy: RedactionPolicy) -> Any {
        if let dict = value as? [String: Any] {
            return dict.reduce(into: [String: Any]()) { result, pair in
                let key = pair.key.lowercased()
                if policy.redactSerials && key.contains("serial") { result[pair.key] = "[REDACTED]" }
                else if policy.redactHost && key == "host" { result[pair.key] = "[REDACTED]" }
                else if policy.redactLocationIDs && key.contains("location_id") { result[pair.key] = "[REDACTED]" }
                else if policy.redactPaths && (key.contains("path") || key.contains("mount")) { result[pair.key] = "[REDACTED]" }
                else { result[pair.key] = redacted(pair.value, policy: policy) }
            }
        }
        if let array = value as? [Any] { return array.map { redacted($0, policy: policy) } }
        return value
    }

    private static func redacted(event: UsbEvent, policy: RedactionPolicy) -> [String: Any] {
        var result: [String: Any] = ["kind": event.kind.rawValue, "at": ISO8601DateFormatter().string(from: event.seenAt)]
        if policy.redactEventIdentities { result["device"] = "[REDACTED]" }
        else { result["device"] = event.key }
        return result
    }
}
