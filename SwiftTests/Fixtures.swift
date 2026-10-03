import Foundation
import XCTest
import UsbScopeCore

/// Access to the fixtures the Python suite also uses (`tests/fixtures`) plus the
/// golden JSON the Python implementation produced from them.
///
/// The paths are derived from this file's location, so the suite works from a
/// checkout wherever it lives. The fixtures are *not* bundled as a resource:
/// the Swift and the Python suite must read the exact same bytes.
enum Fixtures {
    private static let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    static let repoRoot = testDirectory.deletingLastPathComponent()

    static let directory = repoRoot.appendingPathComponent("tests/fixtures")

    /// `snapshot.json` — `usbscope.serialize.snapshot_to_dict` over the fixtures.
    static let golden = testDirectory.appendingPathComponent("Golden/snapshot.json")

    /// The identity the fixtures were captured with; the Python suite pins the
    /// same two values in `tests/conftest.py`.
    static let host = "mac"
    static let osVersion = "27.0.1"

    /// The raw bytes of a fixture file.
    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    /// A command runner that serves fixture files keyed by the data type.
    static func runner(_ files: [String: String]) -> Runner {
        { argv in
            for (key, file) in files where argv.contains(key) {
                guard let payload = try? Data(contentsOf: directory.appendingPathComponent(file)) else {
                    return CommandResult(argv: argv, returncode: 1, error: "unreadable fixture \(file)")
                }
                return CommandResult(argv: argv, returncode: 0, stdout: payload)
            }
            return CommandResult(argv: argv, returncode: 1, error: "no fixture for \(argv.joined(separator: " "))")
        }
    }

    static var profiler: SystemProfiler {
        SystemProfiler(runner: runner([
            "SPUSBHostDataType": "usbhost.json",
            "SPUSBDataType": "usb_legacy_empty.json",
            "SPThunderboltDataType": "thunderbolt.json",
            "SPHardwareDataType": "hardware.json",
        ]))
    }

    static var ioreg: IoregSource {
        IoregSource(runner: runner(["IOPort": "ioport.plist"]))
    }

    static var charging: ChargingSource {
        ChargingSource(runner: runner([
            "SPPowerDataType": "power.json",
            "AppleSmartBattery": "battery.plist",
        ]))
    }

    static var usbregistry: USBRegistrySource {
        USBRegistrySource(runner: runner(["IOUSB": "usbplane.plist"]))
    }

    /// A parsed plist fixture (for the parsers that take a tree directly).
    static func plist(_ name: String) throws -> [String: Any] {
        let raw = try data(name)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: raw, options: [], format: nil)
                as? [String: Any],
            "fixture \(name) is not a plist dictionary"
        )
    }

    /// A full snapshot built from the captured payloads, with a pinned clock.
    static func snapshot() -> Snapshot {
        SnapshotBuilder.collect(
            profiler: profiler,
            ioreg: ioreg,
            charging: charging,
            usbregistry: usbregistry,
            clock: { Date(timeIntervalSince1970: 1_790_000_000) },
            osVersion: osVersion,
            host: host
        )
    }

    /// The snapshot as the JSON-compatible dictionary, minus `seen_at` (which
    /// carries the injected clock and is compared separately).
    static func payload() -> [String: Any] {
        var dict = Serialize.dict(snapshot())
        dict.removeValue(forKey: "seen_at")
        return dict
    }
}
