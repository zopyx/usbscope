import Foundation
import UniformTypeIdentifiers
import XCTest
import UsbScopeCore
@testable import UsbScopeUI

/// The pure parts of the app's "Export report…" action: the format description
/// (extension, content type, suggested name), the extension fix-up for a save
/// panel URL and — the point of the whole feature — that the app renders the
/// report through UsbScopeCore's generator and not a second copy of it.
final class ReportExportTests: XCTestCase {
    // MARK: - Format description

    func testFormatExtensions() {
        XCTAssertEqual(ReportFormat.markdown.fileExtension, "md")
        XCTAssertEqual(ReportFormat.html.fileExtension, "html")
    }

    func testFormatContentTypesMatchTheFormat() {
        // `UTType.markdown` is macOS 27+; the type is derived from the
        // extension here, which resolves to the same registered UTI.
        XCTAssertEqual(ReportFormat.html.contentType, .html)
        XCTAssertEqual(ReportFormat.markdown.contentType.identifier, "net.daringfireball.markdown")
        XCTAssertTrue(ReportFormat.markdown.contentType.conforms(to: .text))
    }

    func testSuggestedFilenamesCarryTheExtension() {
        XCTAssertEqual(ReportFormat.markdown.suggestedFilename, "usbscope-report.md")
        XCTAssertEqual(ReportFormat.html.suggestedFilename, "usbscope-report.html")
    }

    /// The popup lists `allCases` in order; pin it so the default (first) entry
    /// stays Markdown, the CLI's default format.
    func testCaseOrderPinsThePopupOrder() {
        XCTAssertEqual(ReportFormat.allCases, [.markdown, .html])
    }

    // MARK: - Save panel URL fix-up

    func testURLKeepsTheBaseAndForcesTheFormatExtension() {
        let html = ReportFormat.html.replacingExtension(
            of: URL(fileURLWithPath: "/tmp/usbscope-report.md")
        )
        XCTAssertEqual(html.lastPathComponent, "usbscope-report.html")
        XCTAssertEqual(html.deletingLastPathComponent().path, "/tmp")

        let markdown = ReportFormat.markdown.replacingExtension(
            of: URL(fileURLWithPath: "/tmp/report.html")
        )
        XCTAssertEqual(markdown.lastPathComponent, "report.md")
    }

    func testURLAWithoutExtensionGetsOne() {
        let url = ReportFormat.markdown.replacingExtension(
            of: URL(fileURLWithPath: "/tmp/Usb Scope")
        )
        XCTAssertEqual(url.lastPathComponent, "Usb Scope.md")
    }

    func testADottedDirectoryIsNotMistakenForAnExtension() {
        // `deletingPathExtension` only touches the last path component.
        let url = ReportFormat.html.replacingExtension(
            of: URL(fileURLWithPath: "/tmp/my.dossier/report")
        )
        XCTAssertEqual(url.path, "/tmp/my.dossier/report.html")
    }

    // MARK: - The generator is the CLI's

    func testDispatcherIsByteForByteTheReportGenerator() {
        let snapshot = Fixtures.snapshot()
        let storage = [
            StorageDevice(
                identifier: "disk3", name: "Stick", capacityBytes: 32_000_000_000,
                readOnly: false, mountPoint: "/Volumes/Stick"
            ),
        ]
        XCTAssertEqual(
            ReportExport.text(.markdown, snapshot: snapshot, storage: storage),
            Report.markdown(snapshot, storage: storage)
        )
        XCTAssertEqual(
            ReportExport.text(.html, snapshot: snapshot, storage: storage),
            Report.html(snapshot, storage: storage)
        )
    }

    func testStorageReachesBothFormats() {
        let storage = [StorageDevice(identifier: "disk7", name: "Backup")]
        let snapshot = Fixtures.snapshot()
        XCTAssertTrue(
            ReportExport.text(.markdown, snapshot: snapshot, storage: storage).contains("disk7")
        )
        XCTAssertTrue(
            ReportExport.text(.html, snapshot: snapshot, storage: storage).contains("disk7")
        )
    }
}
