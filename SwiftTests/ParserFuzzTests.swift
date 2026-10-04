import XCTest
@testable import UsbScopeCore

/// Small deterministic fuzz corpus for adapter boundaries. The inputs are
/// intentionally type-incorrect and oddly nested; parsers must degrade to
/// empty/unknown values rather than trap or recurse without a bound.
final class ParserFuzzTests: XCTestCase {
    func testMalformedTreesDoNotCrashAcrossAdapters() {
        var deep: [String: Any] = ["unexpected": NSNull()]
        for _ in 0..<200 {
            deep = ["IORegistryEntryChildren": [deep]]
        }

        let corpus: [[String: Any]] = [
            [:],
            ["IORegistryEntryChildren": [NSNull(), "not a node", 7, ["UsbLinkSpeed": "fast"]]],
            ["_items": [true, 3.14, ["USBDeviceKeyVendorID": ["nested"]]]],
            ["bDeviceClass": "eight", "Device Speed": ["unexpected": "shape"]],
            ["IOClass": 42, "PowerSourceOptions": [NSNull(), ["MaxPower": "unknown"]]],
            deep,
        ]

        for root in corpus {
            _ = IOReg.parsePorts(root)
            _ = USBRegistry.devices(in: root)
            _ = ThunderboltSwitch.parse(root)
            _ = ChargingParser.batteryNode(root)
            _ = USBInterfaceSource.parse([root])
            Profiler.iterate(root) { _ in }
        }
    }
}
