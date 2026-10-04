import Foundation
import UsbScopeCore

/// Everything the app remembers between launches.
///
/// The value type, its validation and the JSON codec live here (no AppKit) so
/// they are unit-testable; the app target only wraps a `UserDefaults` suite in
/// a `PreferencesBackend`. Everything read from disk is treated as untrusted
/// and passed through `sanitized()`.

/// The window appearance the user picked.
public enum Appearance: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// English label; the app localises it.
    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// The UI language. Codes and comments stay English; the labels are localised
/// by the app's typed strings table.
public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case en
    case de

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .en: "English"
        case .de: "Deutsch"
        }
    }
}

public enum NotificationDetail: String, CaseIterable, Identifiable, Codable, Sendable {
    case full, generic, disabled
    public var id: String { rawValue }
}

/// The refresh cadences the app offers.
public let PREFERENCE_INTERVALS: [Double] = [1, 2, 5, 10, 30]

public struct AppPreferences: Codable, Equatable, Sendable {
    public var defaultView: AppView = .ports
    public var interval: Double = 5
    public var autoRefresh: Bool = false
    public var notifications: Bool = true
    public var notificationDetail: NotificationDetail = .generic
    public var appearance: Appearance = .system
    public var language: AppLanguage = .en
    public var grouping: GroupField = .none
    /// Hidden column titles per view raw value.
    public var hiddenColumns: [String: [String]] = [:]

    public init() {}

    public init(
        defaultView: AppView = .ports,
        interval: Double = 5,
        autoRefresh: Bool = false,
        notifications: Bool = true,
        notificationDetail: NotificationDetail = .generic,
        appearance: Appearance = .system,
        language: AppLanguage = .en,
        grouping: GroupField = .none,
        hiddenColumns: [String: [String]] = [:]
    ) {
        self.defaultView = defaultView
        self.interval = interval
        self.autoRefresh = autoRefresh
        self.notifications = notifications
        self.notificationDetail = notificationDetail
        self.appearance = appearance
        self.language = language
        self.grouping = grouping
        self.hiddenColumns = hiddenColumns
    }

    /// A copy with every invalid value replaced by a default.
    public func sanitized() -> AppPreferences {
        var copy = AppPreferences()
        copy.defaultView = defaultView
        copy.interval = PREFERENCE_INTERVALS.contains(interval) ? interval : 5
        copy.autoRefresh = autoRefresh
        copy.notifications = notifications
        copy.notificationDetail = NotificationDetail(rawValue: notificationDetail.rawValue) ?? .generic
        copy.appearance = Appearance(rawValue: appearance.rawValue) ?? .system
        copy.language = AppLanguage(rawValue: language.rawValue) ?? .en
        copy.grouping = GroupField.fields(for: defaultView).contains(grouping) ? grouping : .none
        copy.hiddenColumns = hiddenColumns.reduce(into: [:]) { result, entry in
            guard let view = AppView(rawValue: entry.key) else { return }
            let headers = Set(Presentation.headers(for: view))
            let hidden = entry.value.filter { headers.contains($0) }
            if !hidden.isEmpty { result[view.rawValue] = hidden }
        }
        return copy
    }

    /// Whether a column is visible in a view (unknown titles default to visible).
    public func isColumnVisible(_ view: AppView, title: String) -> Bool {
        !(hiddenColumns[view.rawValue]?.contains(title) ?? false)
    }

    /// Decode stored data; anything unusable falls back to the defaults.
    public static func decode(_ data: Data?) -> AppPreferences {
        guard let data, let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) else {
            return AppPreferences()
        }
        return decoded.sanitized()
    }

    public func encoded() -> Data {
        (try? JSONEncoder().encode(sanitized())) ?? Data()
    }
}

/// The slice of storage the preferences need; `UserDefaults` conforms in the
/// app target, a dictionary-backed store backs the tests.
public protocol PreferencesBackend: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

/// Loads and saves `AppPreferences` through a backend.
public final class PreferencesStore {
    public static let defaultKey = "usbscope.swiftPreferences"

    private let backend: PreferencesBackend
    private let key: String

    public init(backend: PreferencesBackend, key: String = PreferencesStore.defaultKey) {
        self.backend = backend
        self.key = key
    }

    public func load() -> AppPreferences {
        AppPreferences.decode(backend.data(forKey: key))
    }

    public func save(_ preferences: AppPreferences) {
        backend.set(preferences.encoded(), forKey: key)
    }
}

/// In-memory backend, used by the tests (and a fallback when no defaults exist).
public final class MemoryPreferencesBackend: PreferencesBackend {
    private var storage: [String: Data] = [:]

    public init() {}

    public func data(forKey key: String) -> Data? { storage[key] }
    public func set(_ data: Data?, forKey key: String) {
        if let data { storage[key] = data } else { storage[key] = nil }
    }
}
