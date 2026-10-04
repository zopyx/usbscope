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
    case exportReport
    case reportFormat
    case reportFormatMarkdown
    case reportFormatHTML
    case reportWritten
    case reportFailed
    case showDetails
    case toggleAutoRefresh
    case intervalHelp
    case viewPorts
    case viewCables
    case viewDevices
    case viewThunderbolt
    case viewPower
    case viewTimeline
    case viewSecurity
    case viewUsb4
    case viewDiff
    case filterPresets
    case presetAll
    case presetHID
    case presetStorage
    case presetConnected
    case timelinePowerTitle
    case timelineEventsTitle
    case timelineNoPower
    case timelineNoEvents
    case securityFindingsTitle
    case securityStorageTitle
    case usb4Title
    case eject
    case ejecting
    case ejectFailed
    case compareWith
    case clearBaseline
    case baselineNone
    case diffNoChanges
    case appeared
    case disappeared
    case changed
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
    case collecting
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
        case .timeline: .viewTimeline
        case .security: .viewSecurity
        case .usb4: .viewUsb4
        case .diff: .viewDiff
        }
    }

    /// The key for a `ReportFormat`.
    static func of(_ format: ReportFormat) -> StringKey {
        switch format {
        case .markdown: .reportFormatMarkdown
        case .html: .reportFormatHTML
        }
    }

    /// The key for a `FilterPreset`.
    static func of(_ preset: FilterPreset) -> StringKey {
        switch preset {
        case .all: .presetAll
        case .hid: .presetHID
        case .storage: .presetStorage
        case .connected: .presetConnected
        }
    }

    /// The key for a `DiffChangeKind`.
    static func of(_ kind: DiffChangeKind) -> StringKey {
        switch kind {
        case .appeared: .appeared
        case .disappeared: .disappeared
        case .changed: .changed
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
        case .exportReport: "Export report…"
        case .reportFormat: "Format"
        case .reportFormatMarkdown: "Markdown"
        case .reportFormatHTML: "HTML"
        case .reportWritten: "Report written"
        case .reportFailed: "Report could not be written"
        case .showDetails: "Show details"
        case .toggleAutoRefresh: "Auto-refresh"
        case .intervalHelp: "Auto-refresh interval"
        case .viewPorts: "Ports"
        case .viewCables: "Cables"
        case .viewDevices: "Devices"
        case .viewThunderbolt: "Thunderbolt"
        case .viewPower: "Power"
        case .viewTimeline: "Timeline"
        case .viewSecurity: "Security"
        case .viewUsb4: "USB4"
        case .viewDiff: "Diff"
        case .filterPresets: "Quick filter"
        case .presetAll: "All"
        case .presetHID: "HID only"
        case .presetStorage: "Storage only"
        case .presetConnected: "Connected only"
        case .timelinePowerTitle: "Charging watts over time"
        case .timelineEventsTitle: "Hotplug events"
        case .timelineNoPower: "No measured power yet."
        case .timelineNoEvents: "No hotplug events recorded yet."
        case .securityFindingsTitle: "Findings"
        case .securityStorageTitle: "USB mass storage"
        case .usb4Title: "USB4 / Thunderbolt fabric"
        case .eject: "Eject"
        case .ejecting: "Ejecting…"
        case .ejectFailed: "Eject failed"
        case .compareWith: "Compare with…"
        case .clearBaseline: "Clear comparison"
        case .baselineNone: "No baseline loaded"
        case .diffNoChanges: "No changes against the baseline"
        case .appeared: "appeared"
        case .disappeared: "disappeared"
        case .changed: "changed"
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
        case .collecting: "collecting"
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
        case .exportReport: "Bericht exportieren…"
        case .reportFormat: "Format"
        case .reportFormatMarkdown: "Markdown"
        case .reportFormatHTML: "HTML"
        case .reportWritten: "Bericht geschrieben"
        case .reportFailed: "Bericht konnte nicht geschrieben werden"
        case .showDetails: "Details anzeigen"
        case .toggleAutoRefresh: "Automatisch aktualisieren"
        case .intervalHelp: "Intervall der automatischen Aktualisierung"
        case .viewPorts: "Anschlüsse"
        case .viewCables: "Kabel"
        case .viewDevices: "Geräte"
        case .viewThunderbolt: "Thunderbolt"
        case .viewPower: "Energie"
        case .viewTimeline: "Zeitverlauf"
        case .viewSecurity: "Sicherheit"
        case .viewUsb4: "USB4"
        case .viewDiff: "Vergleich"
        case .filterPresets: "Schnellfilter"
        case .presetAll: "Alle"
        case .presetHID: "Nur HID"
        case .presetStorage: "Nur Speicher"
        case .presetConnected: "Nur verbunden"
        case .timelinePowerTitle: "Ladeleistung über die Zeit"
        case .timelineEventsTitle: "Hotplug-Ereignisse"
        case .timelineNoPower: "Noch keine gemessene Leistung."
        case .timelineNoEvents: "Noch keine Hotplug-Ereignisse erfasst."
        case .securityFindingsTitle: "Befunde"
        case .securityStorageTitle: "USB-Massenspeicher"
        case .usb4Title: "USB4-/Thunderbolt-Fabric"
        case .eject: "Auswerfen"
        case .ejecting: "Wird ausgeworfen…"
        case .ejectFailed: "Auswerfen fehlgeschlagen"
        case .compareWith: "Vergleichen mit…"
        case .clearBaseline: "Vergleich löschen"
        case .baselineNone: "Keine Vergleichsbasis geladen"
        case .diffNoChanges: "Keine Änderungen gegenüber der Vergleichsbasis"
        case .appeared: "hinzugekommen"
        case .disappeared: "verschwunden"
        case .changed: "geändert"
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
        case .collecting: "sammle"
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
