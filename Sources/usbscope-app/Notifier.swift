import Foundation
import UserNotifications
import UsbScopeCore
import UsbScopeUI

/// Whether this process may talk to `UNUserNotificationCenter`.
///
/// macOS **aborts** (a C-level abort no `catch` can see) when an unbundled
/// process asks the notification centre — as documented by the Python app in
/// `macapp/menubar.py`. The check therefore compares the bundle identifier
/// instead of testing for the framework: a checkout run (`swift run`) has no
/// bundle identifier and stays silent; only an `.app` bundle (or our own
/// identifier) is allowed through.
enum NotificationGuard {
    static let bundleIdentifier = "com.zopyx.usbscope"

    static var isBundledRun: Bool {
        if Bundle.main.bundleURL.pathExtension == "app" { return true }
        return Bundle.main.bundleIdentifier == bundleIdentifier
    }
}

/// Posts connect/disconnect notifications; a strict no-op outside a bundle.
@MainActor
final class DeviceNotifier {
    private let supported: Bool
    private var authorized = false
    private var identifier = 0

    init() {
        supported = NotificationGuard.isBundledRun
        guard supported else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.authorized = granted }
        }
    }

    /// Whether the notification path is usable in this session.
    var available: Bool { supported }

    /// One notification per appeared or disappeared device.
    func notify(_ changes: ChangeSet, enabled: Bool, detail: NotificationDetail = .full) {
        guard supported, enabled, detail != .disabled, authorized else { return }
        for device in changes.added {
            let body = detail == .full ? DeviceChangeText.describe(single(device, added: true)) : "A USB device connected."
            post(body, subtitle: "Device connected")
        }
        for device in changes.removed {
            let body = detail == .full ? DeviceChangeText.describe(single(device, added: false)) : "A USB device disconnected."
            post(body, subtitle: "Device disconnected")
        }
    }

    private func single(_ device: UsbDevice, added: Bool) -> ChangeSet {
        var changes = ChangeSet()
        if added { changes.added = [device] } else { changes.removed = [device] }
        return changes
    }

    private func post(_ body: String, subtitle: String) {
        identifier += 1
        let content = UNMutableNotificationContent()
        content.title = "usbscope"
        content.subtitle = subtitle
        content.body = body
        let request = UNNotificationRequest(
            identifier: "usbscope.change.\(identifier)", content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
