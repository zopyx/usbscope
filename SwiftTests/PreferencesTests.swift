import Foundation
import XCTest
@testable import UsbScopeCore
@testable import UsbScopeUI

/// The persisted preferences: validation and the JSON codec are pure, so they
/// are verified without touching the real `UserDefaults`.
final class PreferencesTests: XCTestCase {
    func testDefaults() {
        let preferences = AppPreferences()
        XCTAssertEqual(preferences.defaultView, .ports)
        XCTAssertEqual(preferences.interval, 5)
        XCTAssertFalse(preferences.autoRefresh)
        XCTAssertTrue(preferences.notifications)
        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertEqual(preferences.language, .en)
        XCTAssertEqual(preferences.grouping, .none)
        XCTAssertTrue(preferences.hiddenColumns.isEmpty)
    }

    func testSanitizedReplacesUntrustedValues() {
        var preferences = AppPreferences()
        preferences.interval = 7.5                       // not an offered cadence
        preferences.grouping = .speed
        preferences.defaultView = .cables                // cables offer no grouping
        preferences.hiddenColumns = [
            "ports": ["Notes", "Nonsense"],
            "bogus": ["X"],
        ]
        let clean = preferences.sanitized()
        XCTAssertEqual(clean.interval, 5)
        XCTAssertEqual(clean.grouping, .none)
        XCTAssertEqual(clean.hiddenColumns, ["ports": ["Notes"]])
    }

    func testColumnVisibility() {
        var preferences = AppPreferences()
        preferences.hiddenColumns = ["devices": ["Serial"]]
        XCTAssertFalse(preferences.isColumnVisible(.devices, title: "Serial"))
        XCTAssertTrue(preferences.isColumnVisible(.devices, title: "Vendor"))
        XCTAssertTrue(preferences.isColumnVisible(.ports, title: "Serial"))
    }

    func testRoundTripThroughTheCodec() {
        var preferences = AppPreferences()
        preferences.defaultView = .devices
        preferences.interval = 10
        preferences.autoRefresh = true
        preferences.notifications = false
        preferences.appearance = .dark
        preferences.language = .de
        preferences.grouping = .deviceClass
        preferences.hiddenColumns = ["devices": ["Serial", "Tier"]]

        let restored = AppPreferences.decode(preferences.encoded())
        XCTAssertEqual(restored, preferences.sanitized())
    }

    func testDecodeFallsBackOnGarbage() {
        XCTAssertEqual(AppPreferences.decode(nil), AppPreferences())
        XCTAssertEqual(AppPreferences.decode(Data("not json".utf8)), AppPreferences())
    }

    func testStorePersistsThroughABackend() {
        let backend = MemoryPreferencesBackend()
        let store = PreferencesStore(backend: backend)

        XCTAssertEqual(store.load(), AppPreferences())
        var preferences = AppPreferences()
        preferences.language = .de
        preferences.grouping = .bus
        store.save(preferences)

        let reloaded = store.load()
        XCTAssertEqual(reloaded.language, .de)
        XCTAssertEqual(reloaded.grouping, .bus)
    }
}

/// The notification wording — the twin of `macapp/menubar.describe_changes`.
final class NotificationTextTests: XCTestCase {
    private func device(_ name: String, vendor: String?) -> UsbDevice {
        UsbDevice(name: name, vendor: vendor, vendorID: 1, productID: 2, locationID: 3)
    }

    func testDescribeSingleAddedDevice() {
        var changes = ChangeSet()
        changes.added = [device("YubiKey", vendor: "Yubico")]
        XCTAssertEqual(DeviceChangeText.describe(changes), "1 device connected: YubiKey (Yubico).")
    }

    func testDescribeRemovedAndPluralisation() {
        var changes = ChangeSet()
        changes.removed = [device("Keyboard", vendor: "Acme"), device("Mouse", vendor: nil)]
        XCTAssertEqual(
            DeviceChangeText.describe(changes),
            "2 devices disconnected: Keyboard (Acme) and Mouse."
        )
    }

    func testDescribeEmptyChangeSet() {
        XCTAssertEqual(DeviceChangeText.describe(ChangeSet()), "No device changes.")
    }

    func testLabelFallsBackToUnknownDevice() {
        XCTAssertEqual(DeviceChangeText.label(UsbDevice(name: "")), "Unknown device")
    }
}
