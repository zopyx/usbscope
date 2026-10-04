import Foundation

/// Small atomic file-write boundary shared by report and table exports.
///
/// The destination is replaced only after the complete temporary file is
/// written. A failed write removes its temporary sibling and leaves an
/// existing destination untouched.
public enum AtomicFile {
    @discardableResult
    public static func write(_ data: Data, to destination: URL) throws -> URL {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = parent.appendingPathComponent(
            ".(destination.lastPathComponent).tmp-(UUID().uuidString)"
        )
        do {
            try data.write(to: temporary, options: .atomic)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(
                    destination, withItemAt: temporary, backupItemName: nil,
                    options: .usingNewMetadataOnly
                )
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
            return destination
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    @discardableResult
    public static func write(_ text: String, to destination: URL,
                             encoding: String.Encoding = .utf8) throws -> URL {
        guard let data = text.data(using: encoding) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return try write(data, to: destination)
    }
}
