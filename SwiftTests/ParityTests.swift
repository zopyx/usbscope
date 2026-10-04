import Foundation
import XCTest
@testable import UsbScopeCore

/// The serialiser's output over the fixtures must stay byte-identical to the
/// recorded golden — the regression pin that keeps the JSON shape from drifting.
///
/// The golden was originally produced by the Python implementation
/// (`usbscope.serialize.snapshot_to_dict`) that this repository used to carry. The
/// Python side is gone, so the file can no longer be *derived* from a second
/// implementation; it is read-only history that is moved deliberately when the
/// serialiser changes:
///
///     USBSCORE_REFRESH_GOLDEN=1 swift test --filter testFixtureSnapshotMatchesTheGolden
///
/// (`make swift-golden`). The refresh is env-gated on purpose: a golden that
/// rewrites itself would pin nothing.
final class ParityTests: XCTestCase {
    /// Set `USBSCORE_REFRESH_GOLDEN=1` to record the produced payload as the new
    /// golden instead of comparing against it.
    private static let refreshGolden =
        ProcessInfo.processInfo.environment["USBSCORE_REFRESH_GOLDEN"] == "1"

    /// Canonical JSON text: sorted keys, no insignificant whitespace.
    private func canonical(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func goldenObject() throws -> [String: Any] {
        let data = try Data(contentsOf: Fixtures.golden)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "golden JSON is not an object"
        )
    }

    func testFixtureSnapshotMatchesTheGolden() throws {
        var expected = try goldenObject()
        expected.removeValue(forKey: "seen_at")
        let produced = Fixtures.payload()

        if Self.refreshGolden {
            // Pretty + sorted so a human diff of the golden is readable.
            var data = try JSONSerialization.data(
                withJSONObject: produced, options: [.prettyPrinted, .sortedKeys]
            )
            data.append(0x0A)
            try data.write(to: Fixtures.golden)
            print("golden refreshed: \(Fixtures.golden.path)")
            return
        }

        let mine = try canonical(produced)
        let theirs = try canonical(expected)
        guard mine != theirs else { return }

        // Report only the differing JSON leaves so the failure is readable.
        let diffs = Self.leafDifferences(theirs, mine)
        XCTFail(
            "the serialiser drifted from the golden in \(diffs.count) place(s):\n"
                + diffs.prefix(40).joined(separator: "\n")
        )
    }

    func testSummaryCounts() throws {
        let summary = try XCTUnwrap(Fixtures.payload()["summary"] as? [String: Any])
        XCTAssertEqual(summary["ports"] as? Int, 6)
        XCTAssertEqual(summary["connected_ports"] as? Int, 2)
        XCTAssertEqual(summary["devices"] as? Int, 1)
        XCTAssertEqual(summary["emarked_cables"] as? Int, 0)
    }

    func testSchemaVersionAndPinnedHeader() throws {
        XCTAssertEqual(Serialize.schemaVersion, 1)
        let payload = Fixtures.payload()
        XCTAssertEqual(payload["model"] as? String, "MacBook Pro")
        XCTAssertEqual(payload["os_version"] as? String, "27.0.1")
        XCTAssertEqual(payload["host"] as? String, Fixtures.host)
        XCTAssertEqual(payload["warnings"] as? [String], [])
    }

    /// `seen_at` is the one field carrying the clock, so it is asserted apart
    /// from the golden comparison.
    func testSeenAtUsesTheInjectedClock() {
        // 1_790_000_000 is 2026-09-22T… in local time; just check the shape.
        let text = Serialize.dict(Fixtures.snapshot())["seen_at"] as? String ?? ""
        XCTAssertTrue(
            text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil,
            "seen_at is not the expected naive timestamp: \(text)"
        )
    }

    // MARK: - JSON leaf diffing

    /// Flatten nested objects into `a.b.c` leaves and report mismatches.
    static func leafDifferences(_ lhs: Any, _ rhs: Any, path: String = "") -> [String] {
        var out: [String] = []
        collect(lhs, rhs, path, &out)
        return out
    }

    private static func collect(_ lhs: Any, _ rhs: Any, _ path: String, _ out: inout [String]) {
        switch (lhs, rhs) {
        case let (l as [String: Any], r as [String: Any]):
            for key in Set(l.keys).union(r.keys).sorted() {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                switch (l[key], r[key]) {
                case let (lv?, rv?): collect(lv, rv, childPath, &out)
                case (nil, nil): continue
                default: out.append("\(childPath): missing on one side")
                }
            }
        case let (l as [Any], r as [Any]):
            if l.count != r.count {
                out.append("\(path): array length \(l.count) != \(r.count)")
            }
            for index in 0..<min(l.count, r.count) {
                collect(l[index], r[index], "\(path)[\(index)]", &out)
            }
        default:
            if !valueEquals(lhs, rhs) { out.append("\(path): \(fmt(lhs)) != \(fmt(rhs))") }
        }
    }

    private static func valueEquals(_ lhs: Any, _ rhs: Any) -> Bool {
        if lhs is NSNull || rhs is NSNull { return lhs is NSNull && rhs is NSNull }
        if let l = lhs as? NSNumber, let r = rhs as? NSNumber {
            // 0/1 bridge to Bool in NSNumber; compare by CF type and value.
            let lBool = CFGetTypeID(l) == CFBooleanGetTypeID()
            let rBool = CFGetTypeID(r) == CFBooleanGetTypeID()
            return lBool == rBool && l == r
        }
        if let l = lhs as? String, let r = rhs as? String { return l == r }
        if let l = lhs as? NSObject, let r = rhs as? NSObject { return l.isEqual(r) }
        return false
    }

    private static func fmt(_ value: Any) -> String {
        if value is NSNull { return "null" }
        return String(describing: value)
    }
}
