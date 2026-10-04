import Foundation
import XCTest
import UsbScopeCore

/// Access to the captured fixtures (`SwiftTests/Fixtures`) plus the frozen
/// golden JSON under `SwiftTests/Golden`.
///
/// The paths are derived from this file's location, so the suite works from a
/// checkout wherever it lives. The fixtures are *not* bundled as a resource:
/// they are read from disk by absolute path, so what the tests read is exactly
/// what a human can open.
enum Fixtures {
    private static let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    static let repoRoot = testDirectory.deletingLastPathComponent()

    static let directory = testDirectory.appendingPathComponent("Fixtures")

    /// `Golden/snapshot.json` — the frozen reference of the serialised snapshot
    /// over the fixtures. It was produced by the Python implementation that this
    /// repository used to carry; the generator is gone, so the file is read-only
    /// history that pins the JSON shape.
    static let golden = testDirectory.appendingPathComponent("Golden/snapshot.json")

    /// The identity the fixtures were captured with; the golden was written with
    /// the same two values, so a mismatch means the fixture identity drifted.
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

    /// The USB4/Thunderbolt fabric issues one command; served from the switch capture.
    static var tbFabric: ThunderboltFabricSource {
        ThunderboltFabricSource(runner: runner(["IOThunderboltSwitch": "tb_switch.plist"]))
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

    /// A parsed plist fixture of any shape (the Thunderbolt switch capture is an array).
    static func plistValue(_ name: String) throws -> Any {
        let raw = try data(name)
        return try PropertyListSerialization.propertyList(from: raw, options: [], format: nil)
    }

    /// A full snapshot built from the captured payloads, with a pinned clock.
    static func snapshot() -> Snapshot {
        SnapshotBuilder.collect(
            profiler: profiler,
            ioreg: ioreg,
            charging: charging,
            usbregistry: usbregistry,
            fabric: tbFabric,
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
