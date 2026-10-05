import XCTest
@testable import UsbScopeCore

/// Deterministic scale guards for the large-data acceptance criteria. These are
/// deliberately modest enough for hosted CI, while catching accidental
/// quadratic work in report generation and unbounded history growth.
final class PerformanceTests: XCTestCase {
    func testLargeReportFixtureStaysWithinBudget() {
        let base = Fixtures.snapshot()
        let devices = (0..<500).map { index in
            UsbDevice(name: "Fixture Device (index)", vendor: "Fixture Vendor",
                      vendorID: 0x1200 + index % 16, productID: index,
                      locationID: 0x01000000 + index, speedMbps: 480,
                      source: "system_profiler")
        }
        var snapshot = base
        snapshot.buses = [Bus(name: "Large fixture bus", devices: devices)]

        let clock = ContinuousClock()
        let start = clock.now
        let markdown = Report.markdown(snapshot)
        let elapsed = start.duration(to: clock.now)

        XCTAssertGreaterThan(markdown.count, 10_000)
        XCTAssertLessThan(elapsed, .seconds(5), "large report generation exceeded the CI budget")
    }

    func testLargeHistoryRemainsBounded() {
        let history = SnapshotHistory(capacity: 500)
        let snapshot = Fixtures.snapshot()
        for index in 0..<1_000 {
            var sample = snapshot
            sample.seenAt = Date(timeIntervalSince1970: TimeInterval(index))
            history.record(sample)
        }
        XCTAssertEqual(history.count, 500)
        XCTAssertEqual(history.entries.first?.at, Date(timeIntervalSince1970: 500))
    }
}
