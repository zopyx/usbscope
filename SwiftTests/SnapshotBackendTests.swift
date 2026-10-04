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

    /// A process independent ordering key for one value.
    private func key(_ object: Any) -> String {
        (try? canonical(object)) ?? String(describing: object)
    }

    /// The port records of a snapshot as canonical JSON.
    private func portJSON(_ snapshot: Snapshot) throws -> String {
        let dict = Serialize.dict(snapshot)
        return try canonical(XCTUnwrap(dict["ports"], "the snapshot has no ports key"))
    }

    /// The port records with the *set derived* arrays put in a defined order.
    ///
    /// `PowerSourceOptions` is an `OSSet` in the registry. `ioreg` writes it in
    /// whatever order the kernel holds it, the in-process reader sorts it; both are
    /// correct, because a set has no order. Comparing the two backends byte for byte
    /// would therefore assert something the registry never promised. Only that one
    /// path is normalised — ports, transports and devices keep their order, which *is*
    /// meaningful (and is pinned by the fixture golden).
    private func normalizedPortJSON(_ snapshot: Snapshot) throws -> String {
        let dict = Serialize.dict(snapshot)
        var ports = try XCTUnwrap(
            dict["ports"] as? [[String: Any]], "the snapshot has no ports array"
        )
        for index in ports.indices {
            guard var sources = ports[index]["power_sources"] as? [[String: Any]] else { continue }
            for source in sources.indices {
                guard let options = sources[source]["options"] as? [[String: Any]] else { continue }
                sources[source]["options"] = options.sorted { key($0) < key($1) }
            }
            ports[index]["power_sources"] = sources
        }
        return try canonical(ports)
    }

    /// A real snapshot through one backend. `ioreg` stays `nil`, so the backend
    /// — not an injected source — decides how the `IOPort` plane is read.
    private func liveSnapshot(_ backend: IORegSourceBackend) -> Snapshot {
        SnapshotBuilder.collect(ioregBackend: backend)
    }

    // MARK: - both backends agree

    /// The whole point of Plan B: the in-process read must be a drop-in for the
    /// subprocess, so both — and the default `.automatic`, which prefers it — must
    /// yield the same port records on the same machine. Set derived arrays are
    /// normalised; see `normalizedPortJSON`.
    func testInProcessAndSubprocessBackendsAgreeOnPorts() throws {
        let inProcess = liveSnapshot(.inProcess)
        guard !inProcess.ports.isEmpty else {
            throw XCTSkip("the registry is not readable in this environment; nothing to compare")
        }
        let subprocess = liveSnapshot(.subprocess)
        let automatic = liveSnapshot(.automatic)
        XCTAssertFalse(subprocess.ports.isEmpty, "the subprocess must find the same ports")

        let expected = try normalizedPortJSON(subprocess)
        XCTAssertEqual(
            try normalizedPortJSON(inProcess), expected, "in-process ports differ from the subprocess"
        )
        XCTAssertEqual(
            try normalizedPortJSON(automatic), expected, "the default backend is not the in-process read"
        )
    }

    /// The order the reader gives the set derived `PowerSourceOptions` must be a
    /// property of the *values*, not of the process' random hash seed — otherwise two
    /// reads of an unchanged machine differ and `baseline check` reports changes that
    /// never happened. This pins the canonical order.
    func testSetDerivedOptionsAreInCanonicalOrder() throws {
        let dict = Serialize.dict(liveSnapshot(.inProcess))
        let ports = try XCTUnwrap(dict["ports"] as? [[String: Any]])
        var checked = 0
        for port in ports {
            for source in port["power_sources"] as? [[String: Any]] ?? [] {
                guard let options = source["options"] as? [[String: Any]], options.count > 1 else {
                    continue
                }
                XCTAssertEqual(
                    options.map(key), options.map(key).sorted(),
                    "the option array is not in canonical order (process dependent sort?)"
                )
                checked += 1
            }
        }
        if checked == 0 {
            throw XCTSkip("no port with a multi-option power source on this machine")
        }
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
