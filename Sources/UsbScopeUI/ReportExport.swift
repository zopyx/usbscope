import Foundation
import UniformTypeIdentifiers
import UsbScopeCore

/// The two human-readable report formats the app can export — the same two the
/// CLI's `usbscope report --format md|html` writes.
///
/// The pure parts of the export live here (the extension, the content type and
/// the suggested file name), so the Swift suite can pin them without a window
/// server; the app only wires them into an `NSSavePanel`.
public enum ReportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case html

    public var id: String { rawValue }

    /// The file extension of a saved report (`md` / `html`).
    public var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .html: "html"
        }
    }

    /// The content type for a save panel, so macOS filters and completes the
    /// name the way the chosen format expects. Derived from the extension
    /// (`UTType.markdown` itself is newer than the app's floor).
    public var contentType: UTType {
        UTType(filenameExtension: fileExtension) ?? .plainText
    }

    /// The suggested file name (no directory) for a save panel.
    public var suggestedFilename: String { "usbscope-report.\(fileExtension)" }

    /// `url` with its extension forced to this format's, so a saved file always
    /// carries the extension its content actually matches. A name without an
    /// extension is kept and given one.
    public func replacingExtension(of url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension(fileExtension)
    }
}

/// The bridge from a `ReportFormat` to UsbScopeCore's report generator.
///
/// The app must not grow a second report renderer: both branches call the very
/// same `Report.markdown` / `Report.html` the CLI's `usbscope report` uses, so
/// the two front ends cannot drift apart.
public enum ReportExport {
    /// Render the report in `format`, byte for byte the document the CLI writes.
    public static func text(
        _ format: ReportFormat, snapshot: Snapshot, storage: [StorageDevice],
        redactionPolicy: RedactionPolicy? = nil
    ) -> String {
        switch format {
        case .markdown:
            if let redactionPolicy { return Report.markdown(snapshot, storage: storage, redactionPolicy: redactionPolicy) }
            return Report.markdown(snapshot, storage: storage)
        case .html:
            if let redactionPolicy { return Report.html(snapshot, storage: storage, redactionPolicy: redactionPolicy) }
            return Report.html(snapshot, storage: storage)
        }
    }
}
