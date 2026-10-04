import CryptoKit
import Foundation
import XCTest

@testable import UsbScopeCore

/// `usbscope report` — the Markdown and HTML renderer.
///
/// The two hashes pin the *exact* bytes of both formats over the fixture snapshot.
/// They are re-pinned deliberately when the content changes; the last change was the
/// interface descriptors feeding the security rules (the composite note now names the
/// interfaces, and a HID interface without a serial is flagged).
final class ReportTests: XCTestCase {
    private let markdownSHA256 = "451ebf65fae191e581f392ce3342587a2e84ca2e9f3fc001c2d38ace37af9d7e"
    private let htmlSHA256 = "9601c7cc3ca7d466ca5860ee8a349e2e2c51aee5d9d01d251511425bf014d74d"

    private func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - markdown

    func testMarkdownHasEverySection() {
        let text = Report.markdown(Fixtures.snapshot(), storage: [])
        XCTAssertTrue(text.hasPrefix("# usbscope report\n"))
        XCTAssertTrue(text.contains("- Machine: MacBook Pro · Apple M3 Pro · macOS 27.0.1"))
        XCTAssertTrue(text.contains("- Host: mac"))
        XCTAssertTrue(text.contains("- Ports: 6 total · 2 connected · 0 e-marked cable(s)"))
        XCTAssertTrue(text.contains("- Devices: 1"))
        XCTAssertTrue(text.contains("## Ports"))
        XCTAssertTrue(text.contains("| Port | Type | State | Mode | Cable | Devices |"))
        XCTAssertTrue(text.contains("| USB-C@3 | USB-C | connected | USB 1.1 Full-Speed · 12 Mbit/s |"))
        XCTAssertTrue(text.contains("## Devices"))
        XCTAssertTrue(text.contains("| Yubico YubiKey OTP+FIDO+CCID | 0x1050:0x0407 | per-interface | 1 |"))
        XCTAssertTrue(text.contains("## Cables"))
        XCTAssertTrue(text.contains("## Power"))
        XCTAssertTrue(text.contains("## Security findings"))
        XCTAssertTrue(text.contains("composite-per-interface"))
        XCTAssertTrue(text.contains("## USB mass storage"))
        XCTAssertTrue(text.contains("## Warnings"))
    }

    func testMarkdownEscapesPipesInCells() {
        var value = UsbPort(description: "Port-USB-C@1", kind: "USB-C")
        value.devices = [UsbDevice(name: "weird|name", vendorID: 1, productID: 2, locationID: 1)]
        let snapshot = Snapshot(
            host: "mac", osVersion: "27.0.1", seenAt: Date(timeIntervalSince1970: 0), ports: [value]
        )
        XCTAssertTrue(Report.markdown(snapshot, storage: []).contains("weird\\|name"))
    }

    func testMarkdownEmptyMachineIsHonest() {
        let empty = Snapshot(
            host: "mac", osVersion: "27.0.1", seenAt: Date(timeIntervalSince1970: 0), model: "Mac mini"
        )
        let text = Report.markdown(empty, storage: [])
        XCTAssertTrue(text.contains("_no receptacles reported_"))
        XCTAssertTrue(text.contains("_no USB devices attached_"))
        XCTAssertTrue(text.contains("_none_"))
    }

    // MARK: - html

    func testHTMLIsSelfContained() {
        let text = Report.html(Fixtures.snapshot(), storage: [])
        XCTAssertTrue(text.hasPrefix("<!doctype html>"))
        XCTAssertTrue(text.contains("<title>usbscope report</title>"))
        XCTAssertTrue(text.contains("<style>"))
        XCTAssertTrue(text.hasSuffix("</html>\n"))
        XCTAssertFalse(text.contains("http://"))
        XCTAssertFalse(text.contains("https://"))
        XCTAssertFalse(text.contains("<link"))
        XCTAssertFalse(text.contains("<script"))
        XCTAssertTrue(text.contains("USB 1.1 Full-Speed"))
        XCTAssertTrue(text.contains("composite-per-interface"))
    }

    func testHTMLEscapesMarkup() {
        let empty = Snapshot(
            host: "a<b>&'\"", osVersion: "27.0.1", seenAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(Report.html(empty, storage: []).contains("a&lt;b&gt;&amp;&#x27;&quot;"))
    }

    // MARK: - cross-language parity

    func testFixtureMarkdownHashIsPinned() {
        XCTAssertEqual(sha256(Report.markdown(Fixtures.snapshot(), storage: [])), markdownSHA256)
    }

    func testFixtureHTMLHashIsPinned() {
        XCTAssertEqual(sha256(Report.html(Fixtures.snapshot(), storage: [])), htmlSHA256)
    }
}
