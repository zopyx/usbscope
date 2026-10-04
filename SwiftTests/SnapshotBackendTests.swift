import Foundation
import XCTest
@testable import UsbScopeCore

/// The `IOPort` backend wiring (`docs/app-store.md`, Plan B): the in-process
/// IOKit reader is the default, `ioreg` is the fallback, and a caller may pin
/// either path. These tests read the *real* registry of the machine running the
/// suite, so the live comparisons skip (`XCTSkip`) instead of failing when the
/// registry cannot be read — a restricted CI runner is not a regression.
///
/// The progress hook is exercised against the fixture sources, so it needs no
/// registry access and always runs.
final class SnapshotBackendTests: XCTestCase {
    /// Canonical JSON text: sorted keys, no insignificant whitespace.
    private func canonical(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// The port records of a snapshot as canonical JSON.
    private func portJSON(_ snapshot: Snapshot) throws -> String {
        let dict = Serialize.dict(snapshot)
        return try canonical(XCTUnwrap(dict["ports"], "the snapshot has no ports key"))
    }

    /// A real snapshot through one backend. `ioreg` stays `nil`, so the backend
    /// — not an injected source — decides how the `IOPort` plane is read.
    private func liveSnapshot(_ backend: IORegSourceBackend) -> Snapshot {
        SnapshotBuilder.collect(ioregBackend: backend)
    }

    // MARK: - both backends agree

    /// The whole point of Plan B: the in-process read must be a drop-in for the
    /// subprocess, so both — and the default `.automatic`, which prefers it —
    /// must yield the same port records on the same machine at the same time.
    func testInProcessAndSubprocessBackendsAgreeOnPorts() throws {
        let inProcess = liveSnapshot(.inProcess)
        guard !inProcess.ports.isEmpty else {
            throw XCTSkip("the registry is not readable in this environment; nothing to compare")
        }
        let subprocess = liveSnapshot(.subprocess)
        let automatic = liveSnapshot(.automatic)
        XCTAssertFalse(subprocess.ports.isEmpty, "the subprocess must find the same ports")

        let expected = try portJSON(subprocess)
        XCTAssertEqual(try portJSON(inProcess), expected, "in-process ports differ from the subprocess")
        XCTAssertEqual(try portJSON(automatic), expected, "the default backend is not the in-process read")
    }

    // MARK: - timing (reported, never asserted)

    /// A timing comparison printed to the test log. Deliberately **not** an
    /// assertion: wall-clock time on a busy, warm-cache machine is noisy, and a
    /// flaky threshold would be worse than no claim. It measures the full
    /// `collect`, so the delta is the `ioreg` subprocess the default removes.
    func testBackendTimingComparisonIsReported() throws {
        let iterations = 3
        func measure(_ backend: IORegSourceBackend) -> Double {
            let start = Date()
            for _ in 0..<iterations { _ = liveSnapshot(backend) }
            return Date().timeIntervalSince(start) / Double(iterations)
        }
        // Warm the page cache so the first run does not pay for it twice.
        let probe = liveSnapshot(.inProcess)
        guard !probe.ports.isEmpty else {
            throw XCTSkip("the registry is not readable in this environment; timing would be empty")
        }
        let inProcess = measure(.inProcess)
        let subprocess = measure(.subprocess)
        print(
            "[timing] SnapshotBuilder.collect, \(iterations) iterations each: "
                + "in-process \(String(format: "%.3f", inProcess)) s, "
                + "subprocess \(String(format: "%.3f", subprocess)) s, "
                + "delta \(String(format: "%+.3f", inProcess - subprocess)) s"
        )

        // And the port reader alone, where the subprocess actually lives — the
        // full `collect` is dominated by `system_profiler`, which both backends
        // still spawn, so this is the sharper number.
        func measurePorts(_ backend: IORegSourceBackend) -> Double {
            let start = Date()
            for _ in 0..<iterations { _ = SnapshotBuilder.readPorts(backend: backend, explicit: nil) }
            return Date().timeIntervalSince(start) / Double(iterations)
        }
        let portsInProcess = measurePorts(.inProcess)
        let portsSubprocess = measurePorts(.subprocess)
        print(
            "[timing] IOPort read alone, \(iterations) iterations each: "
                + "in-process \(String(format: "%.4f", portsInProcess)) s, "
                + "subprocess \(String(format: "%.4f", portsSubprocess)) s, "
                + "delta \(String(format: "%+.4f", portsInProcess - portsSubprocess)) s"
        )
    }

    // MARK: - progress hook

    /// `progress` fires exactly once per stage, in `SnapshotStage` order, with a
    /// 1-based index and the total. Built from the fixtures, so it is
    /// deterministic and needs no registry access.
    func testProgressFiresOncePerStageInOrder() {
        var seen: [(SnapshotStage, Int, Int)] = []
        _ = SnapshotBuilder.collect(
            profiler: Fixtures.profiler,
            ioreg: Fixtures.ioreg,
            charging: Fixtures.charging,
            usbregistry: Fixtures.usbregistry,
            fabric: Fixtures.tbFabric,
            clock: { Date(timeIntervalSince1970: 1_790_000_000) },
            osVersion: Fixtures.osVersion,
            host: Fixtures.host,
            progress: { stage, index, total in seen.append((stage, index, total)) }
        )

        XCTAssertEqual(seen.map(\.0), SnapshotStage.allCases, "the stages did not fire once each, in order")
        XCTAssertEqual(seen.map(\.1), Array(1...SnapshotStage.allCases.count), "the indices are not 1…n")
        XCTAssertTrue(seen.allSatisfy { $0.2 == SnapshotStage.allCases.count }, "the total is not the stage count")
        XCTAssertEqual(SnapshotStage.allCases.count, 6)
    }

    /// The default is `nil`: omitting `progress` must still build a snapshot.
    func testProgressIsOptional() {
        let snapshot = SnapshotBuilder.collect(
            profiler: Fixtures.profiler,
            ioreg: Fixtures.ioreg,
            charging: Fixtures.charging,
            usbregistry: Fixtures.usbregistry,
            fabric: Fixtures.tbFabric,
            clock: { Date(timeIntervalSince1970: 1_790_000_000) },
            osVersion: Fixtures.osVersion,
            host: Fixtures.host
        )
        XCTAssertFalse(snapshot.ports.isEmpty)
    }

    /// An explicitly injected source wins over the backend — this is what keeps
    /// the golden fixture path (`Fixtures.ioreg`) byte-identical.
    func testExplicitSourceOverridesTheBackend() throws {
        for backend in [IORegSourceBackend.automatic, .subprocess, .inProcess] {
            let snapshot = SnapshotBuilder.collect(
                profiler: Fixtures.profiler,
                ioreg: Fixtures.ioreg,
                ioregBackend: backend,
                charging: Fixtures.charging,
                usbregistry: Fixtures.usbregistry,
                fabric: Fixtures.tbFabric,
                clock: { Date(timeIntervalSince1970: 1_790_000_000) },
                osVersion: Fixtures.osVersion,
                host: Fixtures.host
            )
            XCTAssertEqual(
                try portJSON(snapshot),
                try portJSON(Fixtures.snapshot()),
                "the injected fixture source was not used for backend \(backend)"
            )
        }
    }
}
