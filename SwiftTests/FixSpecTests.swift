import XCTest
@testable import UsbScopeCore
@testable import UsbScopeUI

final class FixSpecTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() { lock.lock(); value += 1; lock.unlock() }
        func incrementAndRead() -> Int { lock.lock(); value += 1; let result = value; lock.unlock(); return result }
        func decrement() { lock.lock(); value -= 1; lock.unlock() }
        func updateMaximum(_ candidate: Int) {
            lock.lock(); if candidate > value { value = candidate }; lock.unlock()
        }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    private struct RecordingExecutor: CommandExecutor {
        let result: CommandResult

        func run(_ argv: [String]) -> CommandResult {
            CommandResult(argv: argv, returncode: result.returncode, stdout: result.stdout,
                          error: result.error, stderr: result.stderr,
                          timedOut: result.timedOut, truncated: result.truncated)
        }

        func run(_ argv: [String], limits: Shell.Limits,
                 cancellation: (@Sendable () -> Bool)?) -> CommandResult {
            run(argv)
        }
    }

    func testShellTimeoutAndStderrAreBounded() {
        let result = Shell.run(["/bin/sh", "-c", "printf 'diagnostic' >&2; sleep 1"],
                               limits: .init(timeout: 0.05, maximumStdoutBytes: 32, maximumStderrBytes: 4))
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThanOrEqual(result.stderr.count, 4)
    }

    func testShellDrainsLargeStderrWithoutExceedingTheBound() {
        let result = Shell.run(["/bin/sh", "-c", "head -c 200000 /dev/zero >&2"],
                               limits: .init(timeout: 2, maximumStdoutBytes: 8, maximumStderrBytes: 128))
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.stderr.count, 128)
        XCTAssertTrue(result.truncated)
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

    func testCommandExecutionServiceUsesTheInjectableExecutor() async {
        let service = CommandExecutionService(executor: RecordingExecutor(
            result: CommandResult(argv: [], returncode: 0, stdout: Data("ok".utf8))))
        let result = await service.run(["fixture-command", "--safe"])
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.argv, ["fixture-command", "--safe"])
        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "ok")
    }

    func testSchemaMigrationRejectsFutureDocuments() {
        XCTAssertThrowsError(try SnapshotLoading.migrate(["schema_version": 99])) { error in
            XCTAssertEqual(error as? SnapshotLoadingError, .unsupportedSchema(99, current: Serialize.schemaVersion))
        }
    }

    func testCapabilityAndNegotiatedModesRemainSeparate() {
        var port = UsbPort(description: "USB-C@1", kind: "USB-C")
        port.connected = true
        port.transports = [
            Transport(kind: "USB2", active: true, speedMbps: 480),
            Transport(kind: "USB3", active: false, speedMbps: 5_000),
        ]
        XCTAssertEqual(port.negotiatedMode, .highSpeed)
        XCTAssertEqual(port.advertisedModes, [.highSpeed, .superSpeed])
        XCTAssertEqual(port.maximumObservedRate, 5_000)
        let encoded = Serialize.json(Snapshot(host: "host", osVersion: "1", seenAt: Date(), ports: [port]))
        XCTAssertTrue(encoded.contains("advertised_modes"))
        XCTAssertTrue(encoded.contains("negotiated_mode"))
        XCTAssertTrue(encoded.contains("maximum_observed_rate_mbps"))
    }

    func testDiagnosticRedactionRemovesIdentifiers() {
        let snapshot = Fixtures.snapshot()
        let text = DiagnosticBundle.redactedSnapshotJSON(snapshot)
        XCTAssertFalse(text.contains(snapshot.host))
        XCTAssertFalse(text.contains("17825792"))
    }

    func testAtomicFileReplacesOnlyAfterTheNewContentIsReady() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("usbscope-atomic-\(UUID().uuidString)", isDirectory: true)
        let destination = directory.appendingPathComponent("export.txt")
        defer { try? FileManager.default.removeItem(at: directory) }

        try AtomicFile.write("old", to: destination)
        try AtomicFile.write("new", to: destination)

        XCTAssertEqual(try String(contentsOf: destination), "new")
        let temporaryFiles = try FileManager.default.contentsOfDirectory(at: directory,
                                                                           includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".tmp-") }
        XCTAssertTrue(temporaryFiles.isEmpty)
    }

    func testLocalQAMetricsAreInMemoryAndDiagnosticReady() throws {
        var metrics = LocalQAMetrics(launchedAt: Date(timeIntervalSince1970: 1))
        metrics.record(snapshot: Fixtures.snapshot(), sourceStatuses: [
            "ports": .healthy,
            "storage": .failed,
        ])
        XCTAssertEqual(metrics.collectionAttempts, 1)
        XCTAssertEqual(metrics.sourceReads, 2)
        XCTAssertEqual(metrics.failedSourceReads, 1)
        XCTAssertEqual(metrics.failedSourceRate, 0.5)
        XCTAssertNotNil(metrics.timeToFirstSnapshot)
        XCTAssertNotNil(metrics.timeToIdentifyDevice)
        XCTAssertEqual(metrics.dictionary()["collection_attempts"] as? Int, 1)

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("usbscope-metrics-(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        try DiagnosticBundle.write(to: destination, snapshot: nil, warnings: [], metrics: metrics)
        let metadata = try String(contentsOf: destination.appendingPathComponent("metadata.json"))
        XCTAssertTrue(metadata.contains("collection_attempts"))
        XCTAssertTrue(metadata.contains("failed_source_rate"))
    }

    func testTroubleshootingReturnsEvidence() {
        let result = Troubleshooting.evaluate(.chargeOnlyConnection, snapshot: Fixtures.snapshot())
        XCTAssertFalse(result.recommendations.isEmpty)
        XCTAssertFalse(result.recommendations[0].evidence.isEmpty)
    }

    func testSecuritySeverityOverridesChangePresentationOnly() throws {
        let snapshot = Fixtures.snapshot()
        let baseline = Security.analyse(snapshot)
        let finding = try XCTUnwrap(baseline.findings.first)
        let policy = SecuritySeverityPolicy(overrides: [finding.rule: .info])
        let adjusted = Security.analyse(snapshot, policy: policy)
        let adjustedFinding = try XCTUnwrap(adjusted.findings.first { $0.rule == finding.rule })
        XCTAssertEqual(adjustedFinding.severity, .info)
        XCTAssertEqual(adjustedFinding.evidence, finding.evidence)
        XCTAssertEqual(adjustedFinding.detail, finding.detail)
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

    func testMergedWeakIdentityIsReportedAsAmbiguous() {
        let records = [UsbDevice(name: "Hub"), UsbDevice(name: "Hub")]
        let warnings = SnapshotBuilder.identityWarnings(records, source: "merged")
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("ambiguous weak identity"))
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

    func testSnapshotCoordinatorSerializesARefreshBurst() async {
        let calls = Counter()
        let active = Counter()
        let peak = Counter()
        let collector: SnapshotCoordinator.Collector = { _ in
            calls.increment()
            let current = active.incrementAndRead()
            peak.updateMaximum(current)
            try? await Task.sleep(for: .milliseconds(35))
            active.decrement()
            return Fixtures.snapshot()
        }
        let coordinator = SnapshotCoordinator(collect: collector)
        async let first = coordinator.request(.timer)
        try? await Task.sleep(for: .milliseconds(3))
        let rest = await withTaskGroup(of: SnapshotCoordinator.Result?.self,
                                       returning: [SnapshotCoordinator.Result?].self) { group in
            for reason in [SnapshotCoordinator.Reason.hotplug, .manual, .timer, .manual, .hotplug] {
                group.addTask { await coordinator.request(reason) }
            }
            var values: [SnapshotCoordinator.Result?] = []
            for await value in group { values.append(value) }
            return values
        }
        _ = await first
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(peak.count, 1)
        XCTAssertEqual(rest.count, 5)
        XCTAssertTrue(rest.allSatisfy { $0 != nil })
        XCTAssertTrue(rest.contains { $0?.reason == .manual })
    }

    func testSnapshotCoordinatorStopIsIdempotentAndRejectsNewWork() async {
        let coordinator = SnapshotCoordinator()
        await coordinator.stop()
        await coordinator.stop()
        let result = await coordinator.request(.manual)
        XCTAssertNil(result)
    }

    func testSnapshotCoordinatorDropsAnInFlightResultAfterStop() async {
        let coordinator = SnapshotCoordinator(collect: { _ in
            try? await Task.sleep(for: .milliseconds(40))
            return Fixtures.snapshot()
        })
        async let result = coordinator.request(.manual)
        try? await Task.sleep(for: .milliseconds(5))
        await coordinator.stop()
        let resultValue = await result
        XCTAssertNil(resultValue)
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

    func testLowPowerProfileMakesReducedSourcesExplicit() {
        let snapshot = SnapshotBuilder.collect(
            profiler: Fixtures.profiler,
            ioreg: Fixtures.ioreg,
            charging: Fixtures.charging,
            usbregistry: Fixtures.usbregistry,
            interfaces: Fixtures.interfaces,
            fabric: Fixtures.tbFabric,
            osVersion: Fixtures.osVersion,
            host: Fixtures.host,
            profile: .lowPower
        )
        XCTAssertNil(snapshot.charging)
        XCTAssertTrue(snapshot.thunderbolt.isEmpty)
        XCTAssertTrue(snapshot.thunderboltFabric.routers.isEmpty)
        XCTAssertTrue(snapshot.warnings.contains { $0.contains("low-power profile") })
    }
}
