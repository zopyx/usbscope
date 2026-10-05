import Foundation
import XCTest
@testable import UsbScopeCore
@testable import UsbScopeUI

/// The About window's content (`AboutInfo`) — the view only draws it, so the
/// facts and the copyable diagnostics are asserted here.
final class AboutTests: XCTestCase {
    func testFactsDescribeTheCapturedMachine() {
        let facts = AboutInfo.facts(Fixtures.snapshot())
        let byLabel = Dictionary(facts.map { ($0.label, $0.value) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(byLabel["Machine"], "MacBook Pro · Apple M3 Pro")
        XCTAssertEqual(byLabel["macOS"], "27.0.1")
        XCTAssertEqual(byLabel["Ports"], "6 total, 2 connected")
        XCTAssertEqual(byLabel["Devices"], "1")
        XCTAssertEqual(byLabel["Cables"], "0 e-marked")
        XCTAssertEqual(byLabel["USB4 / Thunderbolt"], "3 receptacle(s)")
        XCTAssertEqual(byLabel["Snapshot schema"], "version \(Serialize.schemaVersion)")
    }

    func testFactsAreEmptyBeforeTheFirstRead() {
        XCTAssertTrue(AboutInfo.facts(nil).isEmpty)
    }

    func testDiagnosticsCarryTheVersionLicenceAndSchema() {
        let text = AboutInfo.diagnostics(version: "0.9.0", snapshot: Fixtures.snapshot())
        XCTAssertTrue(text.hasPrefix("usbscope 0.9.0"))
        XCTAssertTrue(text.contains("MIT licensed"))
        XCTAssertTrue(text.contains(AboutInfo.repositoryURL))
        XCTAssertTrue(text.contains("Snapshot schema: version 1"))
        XCTAssertTrue(text.contains("Host: mac"))
    }

    func testDiagnosticsWorkWithoutASnapshot() {
        let text = AboutInfo.diagnostics(version: "0.0.0-unbundled", snapshot: nil)
        XCTAssertTrue(text.contains("usbscope 0.0.0-unbundled"))
        XCTAssertFalse(text.contains("Host:"))
    }

    func testTheProductCopyIsPresent() {
        XCTAssertEqual(AboutInfo.name, "usbscope")
        XCTAssertFalse(AboutInfo.tagline.isEmpty)
        XCTAssertFalse(AboutInfo.dataNote.isEmpty)
        XCTAssertEqual(AboutInfo.license, "MIT licensed")
        XCTAssertTrue(AboutInfo.copyright.contains("ZOPYX"))
        XCTAssertEqual(AboutInfo.fallbackVersion, "0.9.0")
    }
}
