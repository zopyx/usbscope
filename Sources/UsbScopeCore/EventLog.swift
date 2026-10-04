import Foundation

/// Append-only JSONL log of attach/detach events.
///
/// The default location is
/// `~/Library/Application Support/usbscope/events.jsonl`; the directory is
/// created when the log is opened. Every line is one JSON object, the timestamp
/// is ISO-8601 (`2026-10-03T17:00:00Z`) and the device identity is the same
/// `deviceKey` the table rows and the differ use, so a log line can be matched
/// against a row.
///
/// The file is never rewritten and never truncated — the log only grows, and a
/// line that does not parse (a truncated write, a hand edit) is skipped by
/// `read()` instead of failing the whole history. Writes are serialised with a
/// lock, so the watcher can append from its own queue while the UI reads.
public final class EventLog: @unchecked Sendable {
    /// Sub-directory below the application support directory.
    public static let directoryName = "usbscope"
    /// File name of the log inside that directory.
    public static let fileName = "events.jsonl"

    /// `~/Library/Application Support/usbscope`.
    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// `~/Library/Application Support/usbscope/events.jsonl`.
    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        defaultDirectory(fileManager: fileManager).appendingPathComponent(fileName)
    }

    public let url: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private let maximumBytes: Int
    private let maximumAge: TimeInterval
    private let retainedRotations: Int

    /// Open (and create) the log; `url` defaults to `defaultURL()`.
    public init(url: URL? = nil, fileManager: FileManager = .default,
                maximumBytes: Int = 2 * 1024 * 1024,
                maximumAge: TimeInterval = 30 * 24 * 60 * 60,
                retainedRotations: Int = 3) throws {
        self.fileManager = fileManager
        self.url = url ?? Self.defaultURL(fileManager: fileManager)
        self.maximumBytes = max(1024, maximumBytes)
        self.maximumAge = max(0, maximumAge)
        self.retainedRotations = max(1, retainedRotations)
        try fileManager.createDirectory(
            at: self.url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
    }

    /// Append one event.
    public func append(_ event: UsbEvent) throws {
        try append([event])
    }

    /// Append several events as consecutive lines (one file open).
    public func append(_ events: [UsbEvent]) throws {
        guard !events.isEmpty else { return }
        var payload = Data()
        let encoder = Self.encoder()
        for event in events {
            payload.append(try encoder.encode(event))
            payload.append(0x0A)  // newline: one JSON object per line
        }
        lock.lock()
        defer { lock.unlock() }
        try rotateIfNeeded(incomingBytes: payload.count)
        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } else {
            try payload.write(to: url, options: .atomic)
        }
    }

    private func rotateIfNeeded(incomingBytes: Int) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let modified = attributes[.modificationDate] as? Date
        guard size + incomingBytes > maximumBytes ||
                (maximumAge > 0 && modified.map { Date().timeIntervalSince($0) > maximumAge } == true)
        else { return }
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        for index in stride(from: retainedRotations - 1, through: 1, by: -1) {
            let old = directory.appendingPathComponent("\(base).\(index).jsonl")
            let next = directory.appendingPathComponent("\(base).\(index + 1).jsonl")
            if fileManager.fileExists(atPath: old.path) {
                if index + 1 > retainedRotations { try? fileManager.removeItem(at: next) }
                else { try? fileManager.moveItem(at: old, to: next) }
            }
        }
        let first = directory.appendingPathComponent("\(base).1.jsonl")
        try? fileManager.removeItem(at: first)
        try fileManager.moveItem(at: url, to: first)
    }

    /// Read every parseable line, oldest first.
    ///
    /// A missing file is an empty log, not an error; a malformed line is skipped.
    public func read() throws -> [UsbEvent] {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let raw = try Data(contentsOf: url)
        let decoder = Self.decoder()
        var events: [UsbEvent] = []
        for line in raw.split(separator: 0x0A) where !line.isEmpty {
            if let event = try? decoder.decode(UsbEvent.self, from: Data(line)) {
                events.append(event)
            }
        }
        return events
    }

    /// Remove the log file (the directory stays). Mainly for tests and a reset.
    public func remove() throws {
        lock.lock()
        defer { lock.unlock() }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
