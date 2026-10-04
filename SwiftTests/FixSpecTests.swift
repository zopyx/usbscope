import XCTest
@testable import UsbScopeCore
@testable import UsbScopeUI

final class FixSpecTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    func testShellTimeoutAndStderrAreBounded() {
        let result = Shell.run(["/bin/sh", "-c", "printf 'diagnostic' >&2; sleep 1"],
                               limits: .init(timeout: 0.05, maximumStdoutBytes: 32, maximumStderrBytes: 4))
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThanOrEqual(result.stderr.count, 4)
    }

    func testCommandFailuresMapToStableStructuredErrors() {
        let result = CommandResult(argv: ["diskutil", "list"], returncode: 1,
                                   error: "permission denied")
        let failure = result.sourceError(source: "diskutil", operation: "list")
        XCTAssertEqual(failure?.code, .commandFailed)
        XCTAssertEqual(failure?.source, "diskutil")
        XCTAssertEqual(failure?.operation, "list")
        XCTAssertEqual(failure?.technicalMessage, "permission denied")
    }

    func testCommandExecutorUsesBoundedShellPolicy() {
        let executor = ShellCommandExecutor(limits: .init(timeout: 0.05,
                                                           maximumStdoutBytes: 8,
                                                           maximumStderrBytes: 8))
        let result = executor.run(["/bin/sh", "-c", "printf 123456789; sleep 1"])
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThanOrEqual(result.stdout.count, 8)
    }

    func testSchemaMigrationRejectsFutureDocuments() {
        XCTAssertThrowsError(try SnapshotLoading.migrate(["schema_version": 99])) { error in
            XCTAssertEqual(error as? SnapshotLoadingError, .unsupportedSchema(99, current: Serialize.schemaVersion))
        }
    }

    func testDiagnosticRedactionRemovesIdentifiers() {
        let snapshot = Fixtures.snapshot()
        let text = DiagnosticBundle.redactedSnapshotJSON(snapshot)
        XCTAssertFalse(text.contains(snapshot.host))
        XCTAssertFalse(text.contains("17825792"))
    }

    func testTroubleshootingReturnsEvidence() {
        let result = Troubleshooting.evaluate(.chargeOnlyConnection, snapshot: Fixtures.snapshot())
        XCTAssertFalse(result.recommendations.isEmpty)
        XCTAssertFalse(result.recommendations[0].evidence.isEmpty)
    }

    func testWarningsCarrySourceSeverityAndRecovery() {
        let rows = WarningPresentation.rows([
            "diskutil: diskutil list failed: unavailable",
            "ioreg: missing optional field"
        ])
        XCTAssertEqual(rows.map(\.source), ["diskutil", "ioreg"])
        XCTAssertEqual(rows.first?.severity, "failed")
        XCTAssertFalse(rows.last?.remediation.isEmpty ?? true)
    }

    func testSourcePrecedenceReportsOnlyMaterialDisagreements() {
        let first = UsbDevice(name: "A", serial: "one", speedMbps: 480, source: "ioPort")
        let same = UsbDevice(name: "A", serial: "one", speedMbps: 480, source: "ioreg")
        let different = UsbDevice(name: "A", serial: "two", speedMbps: 5000, source: "ioreg")
        XCTAssertTrue(SourcePrecedence.conflicts(first, same).isEmpty)
        XCTAssertEqual(SourcePrecedence.conflicts(first, different), ["serial", "speed_mbps"])
    }

    func testDeviceIdentityExplainsStrengthWithoutChangingLegacyEventKeys() {
        let located = UsbDevice(name: "A", locationID: 7)
        let serial = UsbDevice(name: "A", serial: "S")
        let weak = UsbDevice(name: "A")
        XCTAssertEqual(deviceIdentity(located).strength, .locationID)
        XCTAssertEqual(deviceIdentity(serial).strength, .serial)
        XCTAssertTrue(deviceIdentity(weak).isWeak)
        XCTAssertEqual(deviceKey(serial), "device:serial:S")
    }

    func testDiagnosticBundleRedactsWarningsAtomically() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("usbscope-diagnostic-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        let snapshot = Fixtures.snapshot()
        try DiagnosticBundle.write(to: destination, snapshot: snapshot,
                                   warnings: ["ioreg: locationID 17825792 failed"],
                                   errors: [SourceError(code: .commandTimedOut, source: "ioreg",
                                                        operation: "read", userMessage: "Timed out",
                                                        technicalMessage: "deadline")])
        let metadata = try String(contentsOf: destination.appendingPathComponent("metadata.json"))
        let snapshotJSON = try String(contentsOf: destination.appendingPathComponent("snapshot.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("events.json").path))
        XCTAssertFalse(metadata.contains("17825792"))
        XCTAssertFalse(snapshotJSON.contains("17825792"))
        XCTAssertTrue(metadata.contains("provenance"))
        XCTAssertTrue(metadata.contains("commandTimedOut"))

        try DiagnosticBundle.write(to: destination, snapshot: snapshot,
                                   warnings: ["replacement succeeded"])
        let replacement = try String(contentsOf: destination.appendingPathComponent("metadata.json"))
        XCTAssertTrue(replacement.contains("replacement succeeded"))
    }

    func testSnapshotCoordinatorCoalescesAndKeepsStrongestReason() async {
        let calls = Counter()
        let collector: SnapshotCoordinator.Collector = { progress in
            calls.increment()
            progress(.ports, 1, 1)
            try? await Task.sleep(for: .milliseconds(40))
            return Fixtures.snapshot()
        }
        let coordinator = SnapshotCoordinator(collect: collector)
        async let first = coordinator.request(.timer)
        try? await Task.sleep(for: .milliseconds(5))
        async let second = coordinator.request(.manual)
        let results = await (first, second)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(results.0?.reason, .manual)
        XCTAssertEqual(results.1?.reason, .manual)
        let keys = results.0.map { Set($0.stageTimings.keys) } ?? []
        XCTAssertEqual(keys, ["ports"])
    }

    func testSnapshotCoordinatorStopIsIdempotentAndRejectsNewWork() async {
        let coordinator = SnapshotCoordinator()
        await coordinator.stop()
        await coordinator.stop()
        let result = await coordinator.request(.manual)
        XCTAssertNil(result)
    }

    func testStableMetadataCacheExpiresAndInvalidates() {
        let cache = StableMetadataCache(lifetime: 10)
        let captured = Date(timeIntervalSince1970: 100)
        cache.insert(.init(model: "Mac", chip: "Apple", capturedAt: captured), for: "host|os")
        XCTAssertEqual(cache.value(for: "host|os", at: captured.addingTimeInterval(9))?.model, "Mac")
        XCTAssertNil(cache.value(for: "host|os", at: captured.addingTimeInterval(11)))

        cache.insert(.init(model: "Mac", chip: "Apple", capturedAt: captured), for: "host|os")
        cache.invalidate()
        XCTAssertNil(cache.value(for: "host|os", at: captured))
    }

    func testDeviceProvenanceIdentifiesNormalizedSources() {
        var device = UsbDevice(name: "Hub", source: "ioreg", deviceClass: 9)
        device.interfaces = [DeviceInterface(number: 0)]
        XCTAssertEqual(device.fieldProvenance["identity"], FactSource.ioUSB)
        XCTAssertEqual(device.fieldProvenance["descriptors"], FactSource.ioUSB)
        XCTAssertEqual(device.fieldProvenance["interfaces"], FactSource.interfaceRegistry)
    }
}
