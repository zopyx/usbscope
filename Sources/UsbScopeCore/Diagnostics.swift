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

/// Non-invasive, local-only QA measurements. These values are kept in memory
/// and are written only when a user explicitly exports or copies diagnostics;
/// they are never transmitted or persisted as telemetry.
public struct LocalQAMetrics: Codable, Sendable, Equatable {
    public let launchedAt: Date
    public private(set) var collectionAttempts: Int
    public private(set) var sourceReads: Int
    public private(set) var failedSourceReads: Int
    public private(set) var firstSnapshotAt: Date?
    public private(set) var firstDeviceAt: Date?

    public init(launchedAt: Date = Date()) {
        self.launchedAt = launchedAt
        collectionAttempts = 0
        sourceReads = 0
        failedSourceReads = 0
        firstSnapshotAt = nil
        firstDeviceAt = nil
    }

    public var timeToFirstSnapshot: TimeInterval? {
        firstSnapshotAt.map { max(0, $0.timeIntervalSince(launchedAt)) }
    }

    public var timeToIdentifyDevice: TimeInterval? {
        firstDeviceAt.map { max(0, $0.timeIntervalSince(launchedAt)) }
    }

    public var failedSourceRate: Double? {
        guard sourceReads > 0 else { return nil }
        return Double(failedSourceReads) / Double(sourceReads)
    }

    /// Record one applied collection and the health reported by each source.
    public mutating func record(snapshot: Snapshot, sourceStatuses: [String: SourceHealth]) {
        collectionAttempts += 1
        sourceReads += sourceStatuses.values.filter { $0 != .notApplicable }.count
        failedSourceReads += sourceStatuses.values.filter {
            switch $0 {
            case .failed, .stale, .unsupported: true
            case .healthy, .partial, .notApplicable: false
            }
        }.count
        if firstSnapshotAt == nil { firstSnapshotAt = snapshot.seenAt }
        if firstDeviceAt == nil, !snapshot.devices.isEmpty { firstDeviceAt = snapshot.seenAt }
    }

    /// Stable, redaction-free scalar fields for the local diagnostics document.
    public func dictionary() -> [String: Any] {
        [
            "launched_at": ISO8601DateFormatter().string(from: launchedAt),
            "collection_attempts": collectionAttempts,
            "source_reads": sourceReads,
            "failed_source_reads": failedSourceReads,
            "time_to_first_snapshot_seconds": timeToFirstSnapshot ?? NSNull(),
            "time_to_identify_device_seconds": timeToIdentifyDevice ?? NSNull(),
            "failed_source_rate": failedSourceRate ?? NSNull(),
        ]
    }
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
                             metrics: LocalQAMetrics? = nil,
                             policy: RedactionPolicy = RedactionPolicy(),
                             storage: [StorageDevice] = []) throws -> URL {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(".diagnostics-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        do {
            let safeWarnings = snapshot.map { current in
                warnings.map { policy.redactText($0, snapshot: current) }
            } ?? warnings
            let provenance: [[String: Any]] = snapshot?.devices.enumerated().map { index, device in
                [
                    "device_index": index,
                    "fields": device.fieldProvenance.mapValues(\.rawValue),
                ]
            } ?? []
            let errorPayload: [[String: Any]] = errors.map { error in
                func safe(_ text: String) -> String {
                    snapshot.map { policy.redactText(text, snapshot: $0, storage: storage) } ?? text
                }
                var value: [String: Any] = [
                    "code": error.code.rawValue,
                    "source": safe(error.source),
                    "operation": safe(error.operation),
                    "severity": safe(error.severity),
                    "user_message": safe(error.userMessage),
                    "technical_message": safe(error.technicalMessage),
                ]
                if let recoveryAction = error.recoveryAction {
                    value["recovery_action"] = safe(recoveryAction)
                }
                return value
            }
            let payload: [String: Any] = [
                "format_version": formatVersion,
                "generated_at": ISO8601DateFormatter().string(from: Date()),
                "app": "usbscope",
                "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
                "architecture": architecture,
                "warnings": safeWarnings,
                "errors": errorPayload,
                "timings": timings,
                "redaction": [
                    "serials": policy.redactSerials, "host": policy.redactHost,
                    "location_ids": policy.redactLocationIDs, "paths": policy.redactPaths,
                    "event_identities": policy.redactEventIdentities,
                ],
                "provenance": provenance,
            ]
            var completePayload = payload
            if let metrics { completePayload["metrics"] = metrics.dictionary() }
            try json(completePayload).write(to: temporary.appendingPathComponent("metadata.json"), atomically: true, encoding: .utf8)
            if let snapshot {
                try redactedSnapshotJSON(snapshot, policy: policy, storage: storage)
                    .write(to: temporary.appendingPathComponent("snapshot.json"), atomically: true, encoding: .utf8)
            }
            let eventPayload = events.map { redacted(event: $0, policy: policy) }
            try json(["events": eventPayload]).write(to: temporary.appendingPathComponent("events.json"), atomically: true, encoding: .utf8)
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: temporary,
                                         backupItemName: nil, options: .usingNewMetadataOnly)
            } else {
                try fm.moveItem(at: temporary, to: destination)
            }
            return destination
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
    }

    public static func redactedSnapshotJSON(_ snapshot: Snapshot,
                                            policy: RedactionPolicy = RedactionPolicy(),
                                            storage: [StorageDevice] = []) -> String {
        let raw = json(redacted(Serialize.dict(snapshot), policy: policy))
        return policy.redactText(raw, snapshot: snapshot, storage: storage)
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
