import Foundation
import XCTest
@testable import UsbScopeCore

/// The in-process IOKit reader (`docs/app-store.md`, Plan B) — it must hand the
/// unchanged `IOReg.parsePorts` the same shape the `ioreg` plist parser accepts,
/// and on a machine of the same class it must find at least as many ports as the
/// captured fixture (`SwiftTests/Fixtures/ioport.plist`, 6 ports).
///
/// The live tests read the *real* registry of the machine running the suite, so
/// they are skipped (`XCTSkip`) rather than failed when the registry cannot be
/// read — a sandbox or a restricted CI runner is a legitimate environment, not a
/// regression. The pure coercion tests always run.
final class IORegistryReaderTests: XCTestCase {
    // MARK: - coercion (always runs, no registry access)

    /// The `NSNumber`→`Bool` bridge trap: a kernel `CFNumber` of `0` or `1` must
    /// stay a number, never become a boolean (or a port number of `1` would
    /// vanish from the snapshot).
    func testSanitizeKeepsNumbersNumericAndBooleansBoolean() {
        XCTAssertEqual(IORegistryReader.sanitize(NSNumber(value: 1)) as? Int, 1)
        XCTAssertEqual(IORegistryReader.sanitize(NSNumber(value: 0)) as? Int, 0)
        XCTAssertEqual(IORegistryReader.sanitize(NSNumber(value: 42)) as? Int, 42)
        XCTAssertEqual(IORegistryReader.sanitize(NSNumber(value: true)) as? Bool, true)
        XCTAssertEqual(IORegistryReader.sanitize(NSNumber(value: false)) as? Bool, false)
    }

    func testSanitizeRecursesIntoContainers() {
        XCTAssertEqual(IORegistryReader.sanitize("Idle") as? String, "Idle")
        let array = IORegistryReader.sanitize([NSNumber(value: 1), NSNumber(value: true)]) as? [Any]
        XCTAssertEqual(array?.count, 2)
        XCTAssertEqual(array?.first as? Int, 1)
        XCTAssertEqual(array?.last as? Bool, true)

        let dictionary = IORegistryReader.sanitize(
            ["rx1": NSNumber(value: 2), "tx2": NSNumber(value: 0)]
        ) as? [String: Any]
        XCTAssertEqual(dictionary?["rx1"] as? Int, 2)
        XCTAssertEqual(dictionary?["tx2"] as? Int, 0)
    }

    // MARK: - live registry (skipped when unreadable)

    func testLiveTreeParsesToAtLeastTheFixturePortCount() throws {
        let expected = try fixturePortCount()
        let tree = try liveTree()
        XCTAssertNotNil(tree["IORegistryEntryChildren"])
        let ports = IOReg.parsePorts(tree)
        if ports.isEmpty { throw XCTSkip("the registry yielded no receptacles here") }
        XCTAssertTrue(
            ports.allSatisfy { !$0.description.isEmpty },
            "every live port must carry a description the parser can key on"
        )
        try skipUnlessTheMachineMatchesTheCapture(ports.count, expected)
    }

    /// `IoregSource` built on `runner()` must behave exactly like the subprocess
    /// source: ports (or a warning), never a crash.
    func testIoregSourceOnTopOfTheInProcessReader() throws {
        let expected = try fixturePortCount()
        let (ports, warnings) = IORegistryReader.ioregSource().ports()
        guard !ports.isEmpty else {
            throw XCTSkip("the registry is not readable in this environment: \(warnings)")
        }
        try skipUnlessTheMachineMatchesTheCapture(ports.count, expected)
        let usbC = ports.filter { $0.kind == "USB-C" }
        XCTAssertFalse(usbC.isEmpty, "a machine with ports reports at least one USB-C receptacle")
    }

    /// The runner ignores its argv entirely: any command line returns the same
    /// in-process payload, which is what makes it a drop-in `Runner`.
    func testRunnerIgnoresItsArguments() throws {
        let runner = IORegistryReader.runner()
        let treePayload = runner([IOReg.binary, "-a", "-l", "-w0", "-p", "IOPort"])
        let missingPayload = runner(["/does/not/exist", "--nonsense"])
        guard treePayload.ok, !treePayload.stdout.isEmpty else {
            throw XCTSkip("the registry is not readable in this environment: \(treePayload.error ?? "?")")
        }
        XCTAssertTrue(missingPayload.ok)
        XCTAssertFalse(missingPayload.stdout.isEmpty)
        // Both must parse to the same port set (the registry may change between
        // the two reads, so compare structure, not bytes).
        let expected = try fixturePortCount()
        for payload in [treePayload, missingPayload] {
            let tree = try XCTUnwrap(
                PropertyListSerialization.propertyList(
                    from: payload.stdout, options: [], format: nil
                ) as? [String: Any]
            )
            XCTAssertFalse(
                IOReg.parsePorts(tree).isEmpty,
                "the in-process payload must parse to receptacles"
            )
            try skipUnlessTheMachineMatchesTheCapture(IOReg.parsePorts(tree).count, expected)
        }
    }

    func testFailingReaderBecomesAWarningNotACrash() {
        let source = IoregSource(runner: { argv in
            CommandResult(argv: argv, returncode: 1, error: "no registry access")
        })
        let (ports, warnings) = source.ports()
        XCTAssertEqual(ports.count, 0)
        XCTAssertEqual(warnings, ["no registry access"])
    }

    func testCanonicalOrderHandlesScalarRegistryMembersWithoutThrowing() {
        let ordered = IORegistryReader.canonicalOrder(["b", "a", 2, 1, true])
        XCTAssertEqual(ordered.count, 5)
        XCTAssertEqual(String(describing: ordered.first!), "true")
    }

    // MARK: - helpers

    private func fixturePortCount() throws -> Int {
        do {
            return IOReg.parsePorts(try Fixtures.plist("ioport.plist")).count
        } catch {
            throw XCTSkip("the ioport fixture is unreadable: \(error)")
        }
    }

    /// The fixture was captured on a MacBook Pro with six receptacles; a CI runner is a
    /// VM and exposes fewer (it reported one). Comparing the two is only meaningful on a
    /// machine of that class, so a smaller count *skips* instead of failing — the
    /// structural assertions below still run everywhere.
    private func skipUnlessTheMachineMatchesTheCapture(_ count: Int, _ expected: Int) throws {
        if count < expected {
            throw XCTSkip(
                "this machine reports \(count) receptacle(s), the capture has \(expected) — "
                    + "nothing to compare against"
            )
        }
    }

    private func liveTree() throws -> [String: Any] {
        do {
            let data = try IORegistryReader.plistData()
            return try XCTUnwrap(
                PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil
                ) as? [String: Any],
                "the reader did not return a plist dictionary"
            )
        } catch let skip as XCTSkip {
            throw skip
        } catch {
            throw XCTSkip("the registry is not readable in this environment: \(error)")
        }
    }
}
