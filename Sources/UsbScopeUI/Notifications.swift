import Foundation
import UsbScopeCore

/// Notification text — the Swift twin of `usbscope.macapp.menubar.describe_changes`.
///
/// Kept free of `UserNotifications` so the wording is unit-testable without a
/// window server or a bundle; the app target only posts what these functions
/// return.
public enum DeviceChangeText {
    /// Name plus vendor of one device.
    public static func label(_ device: UsbDevice) -> String {
        let vendor = device.vendor?.trimmingCharacters(in: .whitespaces)
        let name = device.name.trimmingCharacters(in: .whitespaces)
        let text = name.isEmpty ? "Unknown device" : name
        if let vendor, !vendor.isEmpty { return "\(text) (\(vendor))" }
        return text
    }

    private static func describeGroup(_ devices: [UsbDevice], verb: String) -> String {
        let labels = devices.map(label)
        let noun = labels.count == 1 ? "device" : "devices"
        let listed: String
        switch labels.count {
        case 1: listed = labels[0]
        case 2: listed = "\(labels[0]) and \(labels[1])"
        default: listed = labels.dropLast().joined(separator: ", ") + " and \(labels.last!)"
        }
        return "\(labels.count) \(noun) \(verb): \(listed)."
    }

    /// Notification body for a change set, with correct pluralisation.
    public static func describe(_ changes: ChangeSet) -> String {
        var sentences: [String] = []
        if !changes.added.isEmpty { sentences.append(describeGroup(changes.added, verb: "connected")) }
        if !changes.removed.isEmpty { sentences.append(describeGroup(changes.removed, verb: "disconnected")) }
        return sentences.isEmpty ? "No device changes." : sentences.joined(separator: " ")
    }

    /// Localized notification body for the app target. The original overload
    /// remains the stable English CLI-compatible formatter.
    public static func describe(_ changes: ChangeSet, language: AppLanguage) -> String {
        guard language == .de else { return describe(changes) }
        var sentences: [String] = []
        if !changes.added.isEmpty { sentences.append(describeGroup(changes.added, added: true)) }
        if !changes.removed.isEmpty { sentences.append(describeGroup(changes.removed, added: false)) }
        return sentences.isEmpty ? "Keine Geräteänderungen." : sentences.joined(separator: " ")
    }

    private static func describeGroup(_ devices: [UsbDevice], added: Bool) -> String {
        let labels = devices.map { device in
            let vendor = device.vendor?.trimmingCharacters(in: .whitespaces)
            let name = device.name.trimmingCharacters(in: .whitespaces)
            let text = name.isEmpty ? "Unbekanntes Gerät" : name
            return vendor.map { "\(text) (\($0))" } ?? text
        }
        let listed: String
        switch labels.count {
        case 1: listed = labels[0]
        case 2: listed = "\(labels[0]) und \(labels[1])"
        default: listed = labels.dropLast().joined(separator: ", ") + " und \(labels.last!)"
        }
        let noun = labels.count == 1 ? "Gerät" : "Geräte"
        let verb = added ? "verbunden" : "getrennt"
        return "\(labels.count) \(noun) \(verb): \(listed)."
    }
}
