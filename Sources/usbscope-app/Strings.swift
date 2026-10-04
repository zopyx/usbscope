import Foundation
import UsbScopeCore
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
    case viewWarnings
    case filterPresets
    case presetAll
    case presetHID
    case presetStorage
    case presetConnected
    case timelinePowerTitle
    case timelineEventsTitle
    case timelineNoPower
    case timelineNoEvents
    case timelineValues
    case securityFindingsTitle
    case securityStorageTitle
    case securityHeadline
    case securityHonestLimits
    case securityEmptyFindings
    case securityEmptyStorage
    case severityWarning
    case severityAttention
    case severityInfo
    case securitySeverity
    case severityDefault
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
    case showDetailsAction
    case copyRow
    case copyIdentifier
    case compare
    case firstRunAbout
    case firstRunLocal
    case firstRunLimits
    case firstRunPrivacy
    case firstRunNotifications
    case continueAction
    case diagnostics
    case copy
    case export
    case done
    case sourceHealth
    case unknown
    case monitoring
    case freshness
    case warnings
    case warningField
    case warningMessage
    case warningRemediation
    case copyTechnicalDetails
    case guidedTroubleshooting
    case refreshToEvaluate
    case historicalDeviceEvent
    case vendor
    case locationID
    case historicalIdentity
    case commandPalette
    case showDevice
    case openSourceRow
    case noDetails
    case chargingPowerChart
    case filterHelp
    case fullDeviceDetails
    case genericSummary
    case disabled
    case version
    case overview
    case connections
    case history
    case host
    case connectedPorts
    case deviceCount
    case warningCount
    case commandsMenu
    case tableMenu
    case saveBaseline
    case loadBaseline
    case renameBaseline
    case clearBaselineAction
    case openDiagnostics
    case exportDiagnostics
    case copyDiagnostics
    case refreshAction
    case baselineHelp
    case copyHelp
    case exportHelp
    case diagnosticsHelp
    case notificationDetail
    case currentStatus
    case staleStatus
    case loadingStatus
    case capturedAt
    case monitoringProfile
    case profileBalanced
    case profileLowPower
    case lowPowerNote
    case sourceTimings
    case scenario
    case evidence
    case noMeasuredValues
    case observationHint
    case notificationBundleNote
    case notificationCheckoutNote
    case renameBaselineTitle
    case renameAction
    case cancel
    case ejectVolume
    case volume
    case mountPoint
    case mountedVolumesWarning
    case exportRedactedDiagnostics
    case exportIdentifierWarning
    case exportRedactionNote
    case diagnosticsWritten
    case diagnosticsFailed
    case exportWritten
    case exportFailed
    case ejected
    case emptyPorts
    case emptyCables
    case emptyDevices
    case emptyThunderbolt
    case emptyPower
    case emptyTimeline
    case emptySecurity
    case emptyUsb4
    case emptyDiff
    case emptyWarnings

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
        case .warnings: .viewWarnings
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
        case .viewWarnings: "Warnings"
        case .filterPresets: "Quick filter"
        case .presetAll: "All"
        case .presetHID: "HID only"
        case .presetStorage: "Storage only"
        case .presetConnected: "Connected only"
        case .timelinePowerTitle: "Charging watts over time"
        case .timelineEventsTitle: "Hotplug events"
        case .timelineNoPower: "No measured power yet."
        case .timelineNoEvents: "No hotplug events recorded yet."
        case .timelineValues: "Measured values"
        case .securityFindingsTitle: "Findings"
        case .securityStorageTitle: "USB mass storage"
        case .securityHeadline: "Security observations — heuristic, not a verdict"
        case .securityHonestLimits: "The security view reports observations from macOS. It is not malware detection; missing data is not evidence of malicious behaviour."
        case .securityEmptyFindings: "Nothing stood out in what macOS reports."
        case .securityEmptyStorage: "No USB mass storage attached — a Mac without one is normal."
        case .severityWarning: "Warning"
        case .severityAttention: "Attention"
        case .severityInfo: "Info"
        case .securitySeverity: "Security observation severity"
        case .severityDefault: "Rule default"
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
        case .showDetailsAction: "Show Details"
        case .copyRow: "Copy Row"
        case .copyIdentifier: "Copy Identifier"
        case .compare: "Compare"
        case .firstRunAbout: "usbscope collects USB information locally from macOS system sources. It does not send telemetry."
        case .firstRunLocal: "Some fields depend on macOS, hardware, or sandbox permissions. Missing values are shown as unavailable, not guessed."
        case .firstRunLimits: "Exports can contain hardware identifiers such as serials, host names, and location IDs. Diagnostic bundles redact these by default."
        case .firstRunPrivacy: "Notifications are optional and can be changed in Preferences."
        case .firstRunNotifications: "Notifications"
        case .continueAction: "Continue"
        case .diagnostics: "Diagnostics"
        case .copy: "Copy"
        case .export: "Export…"
        case .done: "Done"
        case .sourceHealth: "Source health"
        case .unknown: "unknown"
        case .monitoring: "Monitoring"
        case .freshness: "Freshness"
        case .warnings: "Warnings"
        case .warningField: "Field"
        case .warningMessage: "Message"
        case .warningRemediation: "Remediation"
        case .copyTechnicalDetails: "Copy technical details"
        case .guidedTroubleshooting: "Guided troubleshooting"
        case .refreshToEvaluate: "Refresh to evaluate the current machine."
        case .historicalDeviceEvent: "Historical device event"
        case .vendor: "Vendor"
        case .locationID: "Location ID"
        case .historicalIdentity: "This is the last recorded identity for the event; the device is not present in the current snapshot."
        case .commandPalette: "Command Palette…"
        case .showDevice: "Show device"
        case .openSourceRow: "Open source row"
        case .noDetails: "No details for the selection."
        case .chargingPowerChart: "Charging power chart"
        case .filterHelp: "Filter every column (all terms must match)"
        case .fullDeviceDetails: "Full device details"
        case .genericSummary: "Generic summary"
        case .disabled: "Disabled"
        case .version: "Version"
        case .overview: "Overview"
        case .connections: "Connections"
        case .history: "History"
        case .host: "Host"
        case .connectedPorts: "connected / ports"
        case .deviceCount: "devices"
        case .warningCount: "warnings"
        case .commandsMenu: "Commands"
        case .tableMenu: "Table"
        case .saveBaseline: "Save baseline…"
        case .loadBaseline: "Load baseline…"
        case .renameBaseline: "Rename baseline…"
        case .clearBaselineAction: "Clear baseline"
        case .openDiagnostics: "Open diagnostics"
        case .exportDiagnostics: "Export diagnostics…"
        case .copyDiagnostics: "Copy diagnostics"
        case .refreshAction: "Refresh"
        case .baselineHelp: "Baseline"
        case .copyHelp: "Copy"
        case .exportHelp: "Export"
        case .diagnosticsHelp: "Diagnostics"
        case .notificationDetail: "Notification detail"
        case .currentStatus: "Current"
        case .staleStatus: "Stale"
        case .loadingStatus: "Loading"
        case .capturedAt: "Captured"
        case .monitoringProfile: "Monitoring profile"
        case .profileBalanced: "Balanced"
        case .profileLowPower: "Low power"
        case .lowPowerNote: "Low-power monitoring skips Thunderbolt and charging reads; the status remains visibly partial."
        case .sourceTimings: "Source timings"
        case .scenario: "Scenario"
        case .evidence: "Evidence"
        case .noMeasuredValues: "No measured values"
        case .observationHint: "Shows the port or device this observation describes"
        case .notificationBundleNote: "Banners are posted for connecting and disconnecting devices."
        case .notificationCheckoutNote: "Silent in a checkout run: macOS only delivers notifications from an app bundle."
        case .renameBaselineTitle: "Rename baseline"
        case .renameAction: "Rename"
        case .cancel: "Cancel"
        case .ejectVolume: "Eject %@?"
        case .volume: "Volume"
        case .mountPoint: "Mount point"
        case .mountedVolumesWarning: "Mounted volumes may be unmounted."
        case .exportRedactedDiagnostics: "Export redacted diagnostics"
        case .exportIdentifierWarning: "Export may contain hardware identifiers"
        case .exportRedactionNote: "The export is redacted by default where possible. Review the destination before sharing it."
        case .diagnosticsWritten: "Diagnostics written"
        case .diagnosticsFailed: "Diagnostics failed"
        case .exportWritten: "Export written"
        case .exportFailed: "Export failed"
        case .ejected: "ejected"
        case .emptyPorts: "No ports reported by the port controller."
        case .emptyCables: "No cable or port-controller data."
        case .emptyDevices: "No USB device attached — connect one, then refresh."
        case .emptyThunderbolt: "No Thunderbolt/USB4 receptacle reported."
        case .emptyPower: "No battery or charger reported — a desktop Mac normally has neither."
        case .emptyTimeline: "No power history yet — the graph fills in as the app reads the machine."
        case .emptySecurity: "No security observations are available yet."
        case .emptyUsb4: "No Thunderbolt/USB4 router reported."
        case .emptyDiff: "No baseline loaded — use Compare with… to choose a snapshot JSON."
        case .emptyWarnings: "No source warnings were reported for the current snapshot."
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
        case .viewWarnings: "Warnungen"
        case .filterPresets: "Schnellfilter"
        case .presetAll: "Alle"
        case .presetHID: "Nur HID"
        case .presetStorage: "Nur Speicher"
        case .presetConnected: "Nur verbunden"
        case .timelinePowerTitle: "Ladeleistung über die Zeit"
        case .timelineEventsTitle: "Hotplug-Ereignisse"
        case .timelineNoPower: "Noch keine gemessene Leistung."
        case .timelineNoEvents: "Noch keine Hotplug-Ereignisse erfasst."
        case .timelineValues: "Messwerte"
        case .securityFindingsTitle: "Befunde"
        case .securityStorageTitle: "USB-Massenspeicher"
        case .securityHeadline: "Sicherheitsbeobachtungen — heuristisch, kein Urteil"
        case .securityHonestLimits: "Die Sicherheitsansicht zeigt Beobachtungen aus macOS. Sie ist keine Schadsoftware-Erkennung; fehlende Daten sind kein Hinweis auf bösartiges Verhalten."
        case .securityEmptyFindings: "In den von macOS gemeldeten Daten ist nichts Auffälliges enthalten."
        case .securityEmptyStorage: "Kein USB-Massenspeicher angeschlossen — auf einem Mac ohne solchen Speicher ist das normal."
        case .severityWarning: "Warnung"
        case .severityAttention: "Achtung"
        case .severityInfo: "Info"
        case .securitySeverity: "Schweregrad der Sicherheitsbeobachtung"
        case .severityDefault: "Regelstandard"
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
        case .showDetailsAction: "Details anzeigen"
        case .copyRow: "Zeile kopieren"
        case .copyIdentifier: "Kennung kopieren"
        case .compare: "Vergleichen"
        case .firstRunAbout: "usbscope erfasst USB-Informationen lokal aus macOS-Systemquellen. Es werden keine Telemetriedaten gesendet."
        case .firstRunLocal: "Einige Felder hängen von macOS, der Hardware oder Sandbox-Berechtigungen ab. Fehlende Werte werden als nicht verfügbar angezeigt, nicht erraten."
        case .firstRunLimits: "Exporte können Hardware-Kennungen wie Seriennummern, Rechnernamen und Location IDs enthalten. Diagnosepakete schwärzen diese standardmäßig."
        case .firstRunPrivacy: "Mitteilungen sind optional und können in den Einstellungen geändert werden."
        case .firstRunNotifications: "Mitteilungen"
        case .continueAction: "Weiter"
        case .diagnostics: "Diagnose"
        case .copy: "Kopieren"
        case .export: "Exportieren…"
        case .done: "Fertig"
        case .sourceHealth: "Quellstatus"
        case .unknown: "unbekannt"
        case .monitoring: "Überwachung"
        case .freshness: "Aktualität"
        case .warnings: "Warnungen"
        case .warningField: "Feld"
        case .warningMessage: "Meldung"
        case .warningRemediation: "Abhilfe"
        case .copyTechnicalDetails: "Technische Details kopieren"
        case .guidedTroubleshooting: "Geführte Fehlersuche"
        case .refreshToEvaluate: "Aktualisieren, um diesen Mac auszuwerten."
        case .historicalDeviceEvent: "Historisches Geräteereignis"
        case .vendor: "Hersteller"
        case .locationID: "Location ID"
        case .historicalIdentity: "Dies ist die zuletzt erfasste Identität des Ereignisses; das Gerät ist in der aktuellen Momentaufnahme nicht vorhanden."
        case .commandPalette: "Befehlspalette…"
        case .showDevice: "Gerät anzeigen"
        case .openSourceRow: "Quellzeile öffnen"
        case .noDetails: "Keine Details für die Auswahl."
        case .chargingPowerChart: "Ladeleistungsdiagramm"
        case .filterHelp: "Alle Spalten filtern (alle Begriffe müssen passen)"
        case .fullDeviceDetails: "Vollständige Gerätedetails"
        case .genericSummary: "Allgemeine Zusammenfassung"
        case .disabled: "Deaktiviert"
        case .version: "Version"
        case .overview: "Übersicht"
        case .connections: "Verbindungen"
        case .history: "Verlauf"
        case .host: "Rechner"
        case .connectedPorts: "verbunden / Anschlüsse"
        case .deviceCount: "Geräte"
        case .warningCount: "Warnungen"
        case .commandsMenu: "Befehle"
        case .tableMenu: "Tabelle"
        case .saveBaseline: "Vergleichsbasis speichern…"
        case .loadBaseline: "Vergleichsbasis laden…"
        case .renameBaseline: "Vergleichsbasis umbenennen…"
        case .clearBaselineAction: "Vergleichsbasis löschen"
        case .openDiagnostics: "Diagnose öffnen"
        case .exportDiagnostics: "Diagnose exportieren…"
        case .copyDiagnostics: "Diagnose kopieren"
        case .refreshAction: "Aktualisieren"
        case .baselineHelp: "Vergleichsbasis"
        case .copyHelp: "Kopieren"
        case .exportHelp: "Exportieren"
        case .diagnosticsHelp: "Diagnose"
        case .notificationDetail: "Mitteilungsdetails"
        case .currentStatus: "Aktuell"
        case .staleStatus: "Veraltet"
        case .loadingStatus: "Wird geladen"
        case .capturedAt: "Erfasst"
        case .monitoringProfile: "Überwachungsprofil"
        case .profileBalanced: "Ausgewogen"
        case .profileLowPower: "Energiesparmodus"
        case .lowPowerNote: "Die energiesparende Überwachung überspringt Thunderbolt- und Ladevorgänge; der Status bleibt sichtbar unvollständig."
        case .sourceTimings: "Quelllaufzeiten"
        case .scenario: "Szenario"
        case .evidence: "Beleg"
        case .noMeasuredValues: "Keine Messwerte"
        case .observationHint: "Zeigt den Anschluss oder das Gerät, auf das sich diese Beobachtung bezieht"
        case .notificationBundleNote: "Mitteilungen werden beim Verbinden und Trennen von Geräten angezeigt."
        case .notificationCheckoutNote: "Im Checkout-Lauf stumm: macOS zeigt Mitteilungen nur aus einem App-Bundle."
        case .renameBaselineTitle: "Vergleichsbasis umbenennen"
        case .renameAction: "Umbenennen"
        case .cancel: "Abbrechen"
        case .ejectVolume: "%@ auswerfen?"
        case .volume: "Volume"
        case .mountPoint: "Einhängepunkt"
        case .mountedVolumesWarning: "Eingehängte Volumes können ausgeworfen werden."
        case .exportRedactedDiagnostics: "Geschwärzte Diagnose exportieren"
        case .exportIdentifierWarning: "Export kann Hardware-Kennungen enthalten"
        case .exportRedactionNote: "Der Export wird nach Möglichkeit standardmäßig geschwärzt. Prüfen Sie das Ziel vor dem Teilen."
        case .diagnosticsWritten: "Diagnose geschrieben"
        case .diagnosticsFailed: "Diagnose fehlgeschlagen"
        case .exportWritten: "Export geschrieben"
        case .exportFailed: "Export fehlgeschlagen"
        case .ejected: "ausgeworfen"
        case .emptyPorts: "Der Port-Controller meldet keine Anschlüsse."
        case .emptyCables: "Keine Kabel- oder Port-Controller-Daten."
        case .emptyDevices: "Kein USB-Gerät angeschlossen — Gerät verbinden und aktualisieren."
        case .emptyThunderbolt: "Keine Thunderbolt-/USB4-Buchse gemeldet."
        case .emptyPower: "Keine Batterie oder kein Ladegerät gemeldet — ein Desktop-Mac hat normalerweise keines von beiden."
        case .emptyTimeline: "Noch keine Energiehistorie — das Diagramm füllt sich während der Messungen."
        case .emptySecurity: "Noch keine Sicherheitsbeobachtungen verfügbar."
        case .emptyUsb4: "Kein Thunderbolt-/USB4-Router gemeldet."
        case .emptyDiff: "Keine Vergleichsbasis geladen — mit „Vergleichen mit…“ eine Snapshot-JSON auswählen."
        case .emptyWarnings: "Für die aktuelle Momentaufnahme wurden keine Quellenwarnungen gemeldet."
        }
    }
}

/// Terse localisation helper: `L(.refreshNow, state.language)`.
func L(_ key: StringKey, _ language: AppLanguage) -> String {
    Strings.text(key, language)
}

extension Strings {
    static func emptyMessage(for view: AppView, _ language: AppLanguage) -> String {
        let key: StringKey
        switch view {
        case .ports: key = .emptyPorts
        case .cables: key = .emptyCables
        case .devices: key = .emptyDevices
        case .thunderbolt: key = .emptyThunderbolt
        case .power: key = .emptyPower
        case .timeline: key = .emptyTimeline
        case .security: key = .emptySecurity
        case .usb4: key = .emptyUsb4
        case .diff: key = .emptyDiff
        case .warnings: key = .emptyWarnings
        }
        return L(key, language)
    }

    static func securitySeverity(_ severity: FindingSeverity, _ language: AppLanguage) -> String {
        switch severity {
        case .warning: L(.severityWarning, language)
        case .attention: L(.severityAttention, language)
        case .info: L(.severityInfo, language)
        }
    }

    static func securitySeverity(_ rawValue: String, _ language: AppLanguage) -> String {
        securitySeverity(FindingSeverity(rawValue: rawValue) ?? .info, language)
    }

    static func securityRuleLabel(_ rule: String, _ language: AppLanguage) -> String {
        guard language == .de else {
            switch rule {
            case "mass-storage": return "Mass storage"
            case "hid-without-serial": return "HID without serial"
            case "hid-and-storage-on-device": return "HID and storage on device"
            case "composite-per-interface": return "Composite per interface"
            case "composite-iad": return "Composite IAD"
            case "restricted-by-macos": return "Restricted by macOS"
            case "restricted-transport": return "Restricted transport"
            case "no-usb-data": return "No USB data transport"
            case "hid-and-storage-on-port": return "HID and storage on port"
            default: return rule
            }
        }
        switch rule {
        case "mass-storage": return "Massenspeicher"
        case "hid-without-serial": return "HID ohne Seriennummer"
        case "hid-and-storage-on-device": return "HID und Speicher am Gerät"
        case "composite-per-interface": return "Composite pro Interface"
        case "composite-iad": return "Composite-IAD"
        case "restricted-by-macos": return "Von macOS eingeschränkt"
        case "restricted-transport": return "Eingeschränkter Transport"
        case "no-usb-data": return "Kein USB-Datentransport"
        case "hid-and-storage-on-port": return "HID und Speicher am Anschluss"
        default: return rule
        }
    }

    /// Localized table headers. The identifiers passed by the views are stable
    /// persistence keys; only the visible header is translated here.
    static func columnLabel(_ identifier: String, _ language: AppLanguage) -> String {
        guard language == .de else {
            return identifier
        }
        switch identifier {
        case "Port": return "Anschluss"
        case "Type": return "Typ"
        case "State": return "Status"
        case "Mode": return "Modus"
        case "Transports": return "Transporte"
        case "Cable": return "Kabel"
        case "Notes": return "Notizen"
        case "CC authentication": return "CC-Authentifizierung"
        case "Hash (CC / USB)": return "Hash (CC / USB)"
        case "PD spec": return "PD-Spezifikation"
        case "Power in": return "Eingangsleistung"
        case "Contract": return "Vertrag"
        case "Liquid": return "Flüssigkeit"
        case "Controller fw": return "Controller-Firmware"
        case "Device": return "Gerät"
        case "Vendor": return "Hersteller"
        case "VID:PID": return "VID:PID"
        case "Class": return "Klasse"
        case "Tier": return "Ebene"
        case "Transport": return "Transport"
        case "Serial": return "Seriennummer"
        case "Restricted": return "Eingeschränkt"
        case "Bus": return "Bus"
        case "Receptacle": return "Buchse"
        case "Link": return "Verbindung"
        case "Host / vendor": return "Host / Hersteller"
        case "Metric": return "Messgröße"
        case "Value": return "Wert"
        default: return identifier
        }
    }

    static func hostLabel(_ host: String, _ language: AppLanguage) -> String {
        "\(L(.host, language)): \(host)"
    }

    static func connectedPortsLabel(connected: Int, total: Int, _ language: AppLanguage) -> String {
        language == .de ? "\(connected) verbunden / \(total) Anschlüsse" : "\(connected) connected / \(total) ports"
    }

    static func deviceCountLabel(_ count: Int, _ language: AppLanguage) -> String {
        language == .de ? "\(count) Geräte" : "\(count) devices"
    }

    static func warningCountLabel(_ count: Int, _ language: AppLanguage) -> String {
        language == .de ? "\(count) Warnungen" : "\(count) warnings"
    }

    static func freshnessLabel(_ freshness: String, duration: String, _ language: AppLanguage) -> String {
        language == .de ? "Aktualität: \(freshness) · Lesedauer: \(duration)" : "Freshness: \(freshness) · read duration: \(duration)"
    }

    static func evidenceLabel(_ evidence: String, _ language: AppLanguage) -> String {
        language == .de ? "Beleg: \(evidence)" : "Evidence: \(evidence)"
    }

    static func eventLabel(kind: String, time: String, _ language: AppLanguage) -> String {
        language == .de ? "\(kind) um \(time)" : "\(kind) at \(time)"
    }

    static func sourceHealthLabel(source: String, status: String, _ language: AppLanguage) -> String {
        "\(source): \(status)"
    }

    static func monitoringLabel(_ status: String, _ language: AppLanguage) -> String {
        "\(L(.monitoring, language)): \(status)"
    }

    static func warningFieldLabel(field: String, message: String, _ language: AppLanguage) -> String {
        "\(field): \(message)"
    }

    static func vendorLabel(_ value: String, _ language: AppLanguage) -> String {
        "\(L(.vendor, language)): \(value)"
    }

    static func locationLabel(_ value: String, _ language: AppLanguage) -> String {
        "\(L(.locationID, language)): \(value)"
    }

    static func seconds(_ value: Int, _ language: AppLanguage) -> String {
        language == .de ? "\(value) s" : "\(value) s"
    }

    static func versionLabel(_ value: String, _ language: AppLanguage) -> String {
        "\(L(.version, language)) \(value)"
    }

    static func warningLabel(source: String, severity: String, _ language: AppLanguage) -> String {
        "\(source) · \(warningSeverityLabel(severity, language))"
    }

    static func warningSeverityLabel(_ severity: String, _ language: AppLanguage) -> String {
        guard language == .de else {
            switch severity.lowercased() {
            case "failed": return "failed"
            case "partial": return "partial"
            default: return severity
            }
        }
        switch severity.lowercased() {
        case "failed": return "fehlgeschlagen"
        case "partial": return "unvollständig"
        default: return severity
        }
    }

    static func findingAccessibilityLabel(severity: String, rule: String, subject: String,
                                          detail: String, _ language: AppLanguage) -> String {
        "\(severity), \(rule), \(subject). \(detail)"
    }

    static func licenseLabel(_ license: String, copyright: String, _ language: AppLanguage) -> String {
        "\(license) · \(copyright)"
    }

    static func freshnessStatus(_ freshness: DataFreshness, _ language: AppLanguage) -> String {
        switch freshness {
        case .current: L(.currentStatus, language)
        case .stale: L(.staleStatus, language)
        case .loading: L(.loadingStatus, language)
        case .unavailable: L(.unknown, language)
        }
    }

    static func capturedLabel(_ date: Date, _ language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return "\(L(.capturedAt, language)): \(formatter.string(from: date))"
    }

    static func ejectTitle(_ identifier: String, _ language: AppLanguage) -> String {
        String(format: L(.ejectVolume, language), identifier)
    }

    static func ejectDetails(name: String, mount: String, _ language: AppLanguage) -> String {
        "\(L(.volume, language)): \(name)\n\(L(.mountPoint, language)): \(mount)\n\(L(.mountedVolumesWarning, language))"
    }

    static func scenarioLabel(_ scenario: DiagnosticScenario, _ language: AppLanguage) -> String {
        if language == .en {
            switch scenario {
            case .slowConnection: return "Slow connection"
            case .chargeOnlyConnection: return "Charge-only connection"
            case .deviceMissing: return "Device missing"
            case .restrictedDevice: return "Restricted device"
            }
        }
        switch scenario {
        case .slowConnection: return "Langsame Verbindung"
        case .chargeOnlyConnection: return "Nur-Laden-Verbindung"
        case .deviceMissing: return "Gerät fehlt"
        case .restrictedDevice: return "Eingeschränktes Gerät"
        }
    }

    static func detailExplanation(for label: String, _ language: AppLanguage) -> String? {
        switch label {
        case "USB link", "Mode (bit/s)", "Speed":
            return language == .de
                ? "Von macOS für diesen Lesevorgang gemeldeter Linkzustand; dies ist nicht die maximale Fähigkeit des Anschlusses oder Kabels."
                : "Negotiated link state reported by macOS for this read; it is not the maximum capability the port or cable advertises."
        case "Cable", "e-marker":
            return language == .de
                ? "Die Kabelfähigkeit stammt vom Anschlusscontroller und, falls vorhanden, aus den elektronisch markierten Kabeldaten. Sie beweist nicht die aktuelle Datenrate."
                : "Cable capability comes from the port controller and, when present, its electronically marked cable data. It does not prove the current data rate."
        case "Power contract", "PD menu":
            return language == .de
                ? "Der Vertrag ist das ausgewählte USB-Power-Delivery-Ergebnis. Das PD-Menü listet beworbene Optionen, nicht den ausgehandelten Wert."
                : "The contract is the selected USB Power Delivery result. The PD menu lists advertised options; it is not the negotiated value."
        case "Transports", "Transport":
            return language == .de
                ? "Dies sind die von macOS für den Anschluss gemeldeten Transportfunktionen. Aktiv bedeutet für die aktuelle Verbindung ausgewählt."
                : "These are the transport functions macOS reports for the port. Active means selected for the current connection."
        case "Restricted by macOS", "Authorization":
            return language == .de
                ? "Dies ist eine Beobachtung des macOS-Transport- oder Autorisierungsstatus, kein Malware- oder Sicherheitsurteil."
                : "This is an observation from macOS transport or authorization state, not a malware or security verdict."
        case "Liquid detected", "Liquid state":
            return language == .de
                ? "Der Flüssigkeitsstatus ist ein vom Controller gemeldetes Sicherheitssignal. Ein nicht verfügbarer Wert bedeutet, dass macOS das Feld nicht bereitgestellt hat."
                : "Liquid status is a controller-reported safety signal. An unavailable value means macOS did not expose the field."
        default: return nil
        }
    }
}
