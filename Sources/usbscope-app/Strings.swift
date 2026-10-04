import Foundation
import UsbScopeUI

/// A small typed strings table for the user-facing chrome.
///
/// Codes and comments stay English; only the values differ per language. The
/// table is deliberately explicit (no .strings files, no bundle lookup) so a
/// missing translation is a compile error and the tests can assert both sides.
enum StringKey: String, CaseIterable {
    case appName
    case openWindow
    case refreshNow
    case quit
    case viewMenu
    case notifications
    case groupBy
    case columns
    case showAllColumns
    case preferences
    case prefGeneral
    case prefDefaultView
    case prefInterval
    case prefAutoRefresh
    case prefNotifications
    case prefAppearance
    case prefLanguage
    case prefGrouping
    case filter
    case autoRefresh
    case copySelected
    case copyWholeTable
    case copyJSON
    case exportJSON
    case exportCSV
    case showDetails
    case toggleAutoRefresh
    case intervalHelp
    case viewPorts
    case viewCables
    case viewDevices
    case viewThunderbolt
    case viewPower
    case groupNone
    case groupBus
    case groupClass
    case groupSpeed
    case appearanceSystem
    case appearanceLight
    case appearanceDark
    case languageEnglish
    case languageGerman
    case loading
    case aboutMenuTitle
    case aboutDocs
    case aboutSource
    case aboutCopy
    case aboutCopied
    case aboutWaiting

    /// The key for an `AppView`.
    static func of(_ view: AppView) -> StringKey {
        switch view {
        case .ports: .viewPorts
        case .cables: .viewCables
        case .devices: .viewDevices
        case .thunderbolt: .viewThunderbolt
        case .power: .viewPower
        }
    }

    /// The key for a `GroupField`.
    static func of(_ field: GroupField) -> StringKey {
        switch field {
        case .none: .groupNone
        case .bus: .groupBus
        case .deviceClass: .groupClass
        case .speed: .groupSpeed
        }
    }

    /// The key for an `Appearance`.
    static func of(_ appearance: Appearance) -> StringKey {
        switch appearance {
        case .system: .appearanceSystem
        case .light: .appearanceLight
        case .dark: .appearanceDark
        }
    }
}

enum Strings {
    /// The text for `key` in `language`.
    static func text(_ key: StringKey, _ language: AppLanguage) -> String {
        switch language {
        case .en: english(key)
        case .de: german(key)
        }
    }

    private static func english(_ key: StringKey) -> String {
        switch key {
        case .appName: "usbscope"
        case .openWindow: "Open usbscope"
        case .refreshNow: "Refresh now"
        case .quit: "Quit usbscope"
        case .viewMenu: "View"
        case .notifications: "Notifications"
        case .groupBy: "Group by"
        case .columns: "Columns"
        case .showAllColumns: "Show all"
        case .preferences: "Preferences"
        case .prefGeneral: "General"
        case .prefDefaultView: "Default view"
        case .prefInterval: "Refresh interval"
        case .prefAutoRefresh: "Auto-refresh"
        case .prefNotifications: "Notifications on device changes"
        case .prefAppearance: "Appearance"
        case .prefLanguage: "Language"
        case .prefGrouping: "Default grouping"
        case .filter: "Filter"
        case .autoRefresh: "Auto-refresh"
        case .copySelected: "Selected rows (TSV)"
        case .copyWholeTable: "Whole table (TSV)"
        case .copyJSON: "Snapshot (JSON)"
        case .exportJSON: "Export JSON…"
        case .exportCSV: "Export CSV…"
        case .showDetails: "Show details"
        case .toggleAutoRefresh: "Auto-refresh"
        case .intervalHelp: "Auto-refresh interval"
        case .viewPorts: "Ports"
        case .viewCables: "Cables"
        case .viewDevices: "Devices"
        case .viewThunderbolt: "Thunderbolt"
        case .viewPower: "Power"
        case .groupNone: "None"
        case .groupBus: "Bus"
        case .groupClass: "Class"
        case .groupSpeed: "Speed"
        case .appearanceSystem: "System"
        case .appearanceLight: "Light"
        case .appearanceDark: "Dark"
        case .languageEnglish: "English"
        case .languageGerman: "German"
        case .loading: "reading the USB subsystem…"
        case .aboutMenuTitle: "About usbscope"
        case .aboutDocs: "Documentation"
        case .aboutSource: "Source code"
        case .aboutCopy: "Copy diagnostics"
        case .aboutCopied: "Copied"
        case .aboutWaiting: "Reading this Mac…"
        }
    }

    private static func german(_ key: StringKey) -> String {
        switch key {
        case .appName: "usbscope"
        case .openWindow: "usbscope öffnen"
        case .refreshNow: "Jetzt aktualisieren"
        case .quit: "usbscope beenden"
        case .viewMenu: "Ansicht"
        case .notifications: "Mitteilungen"
        case .groupBy: "Gruppieren nach"
        case .columns: "Spalten"
        case .showAllColumns: "Alle einblenden"
        case .preferences: "Einstellungen"
        case .prefGeneral: "Allgemein"
        case .prefDefaultView: "Standardansicht"
        case .prefInterval: "Aktualisierungsintervall"
        case .prefAutoRefresh: "Automatisch aktualisieren"
        case .prefNotifications: "Mitteilungen bei Geräteänderungen"
        case .prefAppearance: "Erscheinungsbild"
        case .prefLanguage: "Sprache"
        case .prefGrouping: "Standardgruppierung"
        case .filter: "Filter"
        case .autoRefresh: "Automatisch aktualisieren"
        case .copySelected: "Ausgewählte Zeilen (TSV)"
        case .copyWholeTable: "Ganze Tabelle (TSV)"
        case .copyJSON: "Momentaufnahme (JSON)"
        case .exportJSON: "JSON exportieren…"
        case .exportCSV: "CSV exportieren…"
        case .showDetails: "Details anzeigen"
        case .toggleAutoRefresh: "Automatisch aktualisieren"
        case .intervalHelp: "Intervall der automatischen Aktualisierung"
        case .viewPorts: "Anschlüsse"
        case .viewCables: "Kabel"
        case .viewDevices: "Geräte"
        case .viewThunderbolt: "Thunderbolt"
        case .viewPower: "Energie"
        case .groupNone: "Keine"
        case .groupBus: "Bus"
        case .groupClass: "Klasse"
        case .groupSpeed: "Geschwindigkeit"
        case .appearanceSystem: "System"
        case .appearanceLight: "Hell"
        case .appearanceDark: "Dunkel"
        case .languageEnglish: "Englisch"
        case .languageGerman: "Deutsch"
        case .loading: "USB-Subsystem wird gelesen…"
        case .aboutMenuTitle: "Über usbscope"
        case .aboutDocs: "Dokumentation"
        case .aboutSource: "Quellcode"
        case .aboutCopy: "Diagnose kopieren"
        case .aboutCopied: "Kopiert"
        case .aboutWaiting: "Dieser Mac wird gelesen…"
        }
    }
}

/// Terse localisation helper: `L(.refreshNow, state.language)`.
func L(_ key: StringKey, _ language: AppLanguage) -> String {
    Strings.text(key, language)
}
