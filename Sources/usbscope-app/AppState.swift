import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UsbScopeCore
import UsbScopeUI

private let appArchitectureName: String = {
    #if arch(arm64)
    "arm64"
    #else
    "x86_64"
    #endif
}()

/// The `UserDefaults` slice the preferences persist into.
///
/// The suite matches the Python app's domain (`com.zopyx.usbscope`) so a
/// checkout run and a bundled run write the same place; the key is distinct so
/// the two implementations never clobber each other's format.
final class UserDefaultsBackend: PreferencesBackend {
    static let suiteName = "com.zopyx.usbscope"

    private let defaults: UserDefaults

    /// A bundled app already owns the `com.zopyx.usbscope` domain, and macOS
    /// refuses to open a *suite* by the process's own bundle identifier
    /// ("Using your own bundle identifier as an NSUserDefaults suite name does
    /// not make sense and will not work") — so the bundle uses `standard` and
    /// only a checkout run (which has no such identifier) opens the suite.
    init(defaults: UserDefaults? = UserDefaultsBackend.resolve()) {
        self.defaults = defaults ?? .standard
    }

    private static func resolve() -> UserDefaults? {
        if Bundle.main.bundleIdentifier == suiteName { return .standard }
        return UserDefaults(suiteName: suiteName)
    }

    func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    func set(_ data: Data?, forKey key: String) { defaults.set(data, forKey: key) }
}

/// The source-level facts shown by the persistent status control.
struct SourceHealthRow: Identifiable {
    let source: String
    let status: SourceHealth
    let duration: TimeInterval?
    let warning: String?
    let lastSuccess: Date?

    var id: String { source }
}

/// Observable app state: the current snapshot, the selected view, the search
/// text, the auto-refresh cadence and the change set of the last refresh.
///
/// Collection runs off the main thread (it shells out to `system_profiler` and
/// `ioreg`); the state machine is idle → loading → loaded, with an error
/// message instead of a crash when a source fails. Every user choice that
/// survives a launch is persisted through `PreferencesStore`.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var changes: ChangeSet?
    @Published private(set) var reads = 0
    @Published private(set) var isLoading = false
    /// Which OS source the running `collect` is reading, or `nil` when idle.
    /// `SnapshotBuilder` reports one value per stage, so the status line can name
    /// the step instead of showing an opaque spinner for ~1.3 s.
    @Published private(set) var progress: SnapshotProgress?
    @Published private(set) var errorMessage: String?

    @Published var view: AppView = .ports {
        didSet {
            if view != oldValue {
                saveViewPreferences(for: oldValue, searchValue: search,
                                    filterValue: filterPreset, groupingValue: groupField,
                                    selectionValue: selection)
                loadViewPreferences(for: view)
                if !currentViewPreferences.preserveSelection { selection.removeAll() }
            }
            persist()
        }
    }
    @Published var search = "" { didSet { if !restoringViewPreferences { saveViewPreferences(for: view); persist() } } }
    @Published var interval: Double = 5 { didSet { persist() } }
    @Published private(set) var autoRefresh = false
    @Published var appearance: Appearance = .system { didSet { persist() } }
    @Published var language: AppLanguage = .en { didSet { persist() } }
    @Published private(set) var notificationsEnabled = true { didSet { persist() } }
    @Published private(set) var notificationDetail: NotificationDetail = .generic { didSet { persist() } }
    @Published var groupField: GroupField = .none { didSet { if !restoringViewPreferences { saveViewPreferences(for: view) }; persist() } }
    @Published private(set) var monitoringProfile: MonitoringProfile = .balanced { didSet { persist() } }
    @Published private(set) var securitySeverityPolicy = SecuritySeverityPolicy.standard { didSet { persist() } }
    @Published private(set) var hiddenColumns: [AppView: Set<String>] = [:] { didSet { persist() } }

    /// The quick filter on top of the search text (session only, not persisted).
    @Published var filterPreset: FilterPreset = .all { didSet { if !restoringViewPreferences { saveViewPreferences(for: view); persist() } } }

    @Published private(set) var viewPreferences: [AppView: ViewPreferences] = [:]
    private var restoringViewPreferences = false

    private var currentViewPreferences: ViewPreferences { viewPreferences[view] ?? ViewPreferences() }

    /// The USB mass-storage inventory of the last read (the Security tab).
    @Published private(set) var storage: [StorageDevice] = []
    @Published private(set) var storageErrors: [SourceError] = []

    /// The recorded hotplug events (newest first), for the Timeline tab.
    @Published private(set) var events: [UsbEvent] = []

    /// The snapshot the Diff tab compares against, and where it came from.
    @Published private(set) var baseline: Snapshot?
    @Published private(set) var baselineName: String?
    @Published private(set) var baselineError: String?

    /// The device being ejected right now, and the outcome of the last eject.
    @Published private(set) var ejecting: String?
    @Published private(set) var ejectMessage: String?

    /// How many hotplug events the Timeline keeps in memory.
    static let eventLimit = 500

    /// Selected rows of the current view (row ids).
    @Published var selection = Set<String>() {
        didSet { if !restoringViewPreferences { saveViewPreferences(for: view); persist() } }
    }

    /// The row whose detail sheet is open, if any.
    @Published var detailRowKey: String?
    @Published var historicalEvent: UsbEvent?

    /// The outcome line of the last report export (a written file or a failure),
    /// shown in the status footer; `nil` before the first export.
    @Published private(set) var reportMessage: String?
    @Published private(set) var reportFailed = false
    @Published private(set) var storageStatus: SourceHealth = .notApplicable
    @Published private(set) var storageWarnings: [String] = []
    @Published private(set) var readWarnings: [String] = []
    @Published private(set) var sourceHealth: [String: SourceHealth] = [:]
    @Published private(set) var sourceWarningsBySource: [String: [String]] = [:]
    @Published private(set) var sourceLastSuccessAt: [String: Date] = [:]
    @Published var showFirstRun = false
    @Published var showDiagnostics = false
    @Published var showCommandPalette = false
    @Published private(set) var lastSuccessfulSnapshot: Snapshot?
    @Published private(set) var lastAttemptAt: Date?
    @Published private(set) var lastFailureAt: Date?
    @Published private(set) var dataFreshness: DataFreshness = .unavailable
    @Published private(set) var lastReadDuration: TimeInterval?
    @Published private(set) var sourceTimings: [String: TimeInterval] = [:]

    /// The aggregate status belongs in the persistent header; individual
    /// source rows remain available through `sourceHealthRows`.
    var overallSourceHealth: SourceHealth {
        if dataFreshness == .stale, lastSuccessfulSnapshot != nil { return .stale }
        let statuses = Set(sourceHealth.values)
        if statuses.isEmpty { return .notApplicable }
        if statuses.contains(.failed) { return .failed }
        if statuses.contains(.partial) { return .partial }
        if statuses.contains(.unsupported) { return .unsupported }
        if statuses.allSatisfy({ $0 == .notApplicable }) { return .notApplicable }
        return .healthy
    }

    var sourceHealthRows: [SourceHealthRow] {
        let names = Set(sourceHealth.keys)
            .union(sourceTimings.keys)
            .union(sourceWarningsBySource.keys)
            .union(sourceLastSuccessAt.keys)
        return names.sorted().map { source in
            SourceHealthRow(source: source,
                            status: sourceHealth[source] ?? .notApplicable,
                            duration: sourceTimings[source],
                            warning: sourceWarningsBySource[source]?.joined(separator: " · "),
                            lastSuccess: sourceLastSuccessAt[source])
        }
    }
    /// Whether the main window is currently on screen. Menu-bar-only mode keeps
    /// event-driven monitoring alive but avoids the periodic and timeline work
    /// that is only useful while the dashboard is visible.
    @Published private(set) var mainWindowVisible = true

    private var previous: Snapshot?
    private var timer: Timer?
    private let store: PreferencesStore
    private let notifier: DeviceNotifier?

    /// Snapshots with their deltas and the power timeline they form.
    private let history = SnapshotHistory()

    /// Append-only hotplug log (`~/Library/Application Support/usbscope/events.jsonl`).
    /// A read-only home without application support is the only failure mode, so it
    /// stays optional instead of taking the app down.
    private let eventLog: EventLog? = try? EventLog()

    /// The IOKit hotplug watcher started on launch.
    private var watcher: UsbHotplugWatcher?
    private var refreshTask: Task<Void, Never>?
    private let coordinator = SnapshotCoordinator()
    private let collectionService = SnapshotCollectionService()
    private let commandService = CommandExecutionService()
    private var refreshGeneration: UInt64 = 0
    private var appliedAt: Date?
    private var qaMetrics = LocalQAMetrics()

    var isIdle: Bool { snapshot == nil && !isLoading }

    /// Whether the watcher got real IOKit notifications (vs. the polling fallback).
    var isHotplugEventDriven: Bool { watcher?.isEventDriven ?? false }
    var monitoringStatus: String { watcher?.status ?? "disabled" }

    /// The charging watts over time, as far as the app has seen them.
    var powerTimeline: [PowerPoint] { history.powerTimeline() }

    init(
        store: PreferencesStore = PreferencesStore(backend: UserDefaultsBackend()),
        notifier: DeviceNotifier? = DeviceNotifier(),
        monitoring: Bool = true
    ) {
        self.store = store
        self.notifier = notifier
        showFirstRun = !UserDefaults.standard.bool(forKey: "usbscope.firstRunExplained.v1")
        let preferences = store.load()
        view = preferences.defaultView
        interval = preferences.interval
        autoRefresh = preferences.autoRefresh
        appearance = preferences.appearance
        language = preferences.language
        notificationsEnabled = preferences.notifications
        notificationDetail = preferences.notificationDetail
        groupField = preferences.grouping
        monitoringProfile = preferences.monitoringProfile
        securitySeverityPolicy = SecuritySeverityPolicy(overrides: preferences.securitySeverityOverrides.compactMapValues(FindingSeverity.init(rawValue:)))
        hiddenColumns = preferences.hiddenColumns.reduce(into: [:]) { result, entry in
            if let view = AppView(rawValue: entry.key) { result[view] = Set(entry.value) }
        }
        viewPreferences = preferences.viewPreferences.reduce(into: [:]) { result, entry in
            if let view = AppView(rawValue: entry.key) { result[view] = entry.value }
        }
        loadViewPreferences(for: view)
        // Own the IOKit notifications for the lifetime of the app; the watcher
        // collects its own baseline off the main thread, so launch is not blocked.
        if monitoring { startMonitoring() }
        if preferences.autoRefresh { startTimer() }
        loadEventHistory()
    }

    /// Read the tail of the hotplug log into memory for the Timeline tab.
    ///
    /// The read is file IO, so it stays off the main actor. The hop back has to be a
    /// MainActor-inheriting `Task`, not `Task.detached` + `MainActor.run`: the latter
    /// makes `self` task-isolated, and capturing it in a main-actor closure is a
    /// data-race error on Swift 6.1.2.
    private func loadEventHistory() {
        guard let eventLog else { return }
        Task { @MainActor [weak self] in
            let loaded = await Task.detached(priority: .utility) { (try? eventLog.read()) ?? [] }.value
            self?.events = Array(loaded.suffix(Self.eventLimit).reversed())
        }
    }

    // MARK: - Hotplug monitoring

    /// Start the hotplug watcher. Safe to call more than once.
    func startMonitoring() {
        guard watcher == nil else { return }
        let profile = monitoringProfile == .lowPower ? SnapshotCollectionProfile.lowPower : .full
        let watcher = UsbHotplugWatcher(collect: {
            self.collectionService.collectSynchronously(profile: profile)
        })
        watcher.start { [weak self] update in
            Task { @MainActor in self?.handleHotplug(update) }
        }
        self.watcher = watcher
    }

    func stopMonitoring() {
        watcher?.stop()
        watcher = nil
    }

    /// Switch between dashboard and menu-bar-only resource policies.
    ///
    /// The watcher remains active in both modes so hotplug notifications and
    /// the compact status item stay current. The timer and power timeline are
    /// dashboard work, so they pause while the main window is closed.
    func setMainWindowVisible(_ visible: Bool) {
        guard mainWindowVisible != visible else { return }
        mainWindowVisible = visible
        timer?.invalidate()
        timer = nil
        guard visible else { return }
        if autoRefresh { startTimer() }
        if snapshot != nil, !isLoading { refresh() }
    }

    /// Idempotent lifecycle stop used by the app delegate and tests.
    func shutdown() {
        refreshGeneration &+= 1
        refreshTask?.cancel()
        Task { await coordinator.stop() }
        refreshTask = nil
        timer?.invalidate()
        timer = nil
        stopMonitoring()
        progress = nil
        isLoading = false
    }

    /// Record the hotplug events, then submit the snapshot to the same
    /// coordinator used by manual and timer refreshes. The watcher has already
    /// collected the candidate snapshot in order to diff the edge; routing its
    /// result through the coordinator is what prevents it from racing a read
    /// already in flight and mutating presentation state out of order.
    private func handleHotplug(_ update: UsbHotplugWatcher.Update) {
        if let eventLog, !update.events.isEmpty {
            let events = update.events
            // The log is I/O; keep it off the main thread.
            Task.detached(priority: .utility) { try? eventLog.append(events) }
            // Newest first, so the Timeline shows the latest edge on top.
            self.events = Array((Array(events.reversed()) + self.events).prefix(Self.eventLimit))
        }
        let candidate = update.snapshot
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await coordinator.request(.hotplug, collector: { _ in candidate })
            guard let result else { return }
            apply(result.snapshot, generation: nil)
        }
    }

    // MARK: - Preferences

    private func persist() {
        let preferences = AppPreferences(
            defaultView: view,
            interval: interval,
            autoRefresh: autoRefresh,
            notifications: notificationsEnabled,
            notificationDetail: notificationDetail,
            appearance: appearance,
            language: language,
            grouping: groupField,
            monitoringProfile: monitoringProfile,
            hiddenColumns: hiddenColumns.reduce(into: [:]) { result, entry in
                result[entry.key.rawValue] = Array(entry.value).sorted()
            },
            securitySeverityOverrides: securitySeverityPolicy.overrides.mapValues(\.rawValue),
            viewPreferences: viewPreferences.reduce(into: [:]) { result, entry in
                result[entry.key.rawValue] = entry.value
            }
        )
        store.save(preferences)
    }

    private func saveViewPreferences(
        for view: AppView,
        searchValue: String? = nil,
        filterValue: FilterPreset? = nil,
        groupingValue: GroupField? = nil,
        selectionValue: Set<String>? = nil
    ) {
        guard !restoringViewPreferences else { return }
        var value = viewPreferences[view] ?? ViewPreferences()
        value.search = searchValue ?? (view == self.view ? search : value.search)
        value.filterPreset = filterValue ?? (view == self.view ? filterPreset : value.filterPreset)
        value.grouping = groupingValue ?? (view == self.view ? groupField : value.grouping)
        if let selectionValue { value.selection = selectionValue.sorted() }
        else if view == self.view { value.selection = selection.sorted() }
        viewPreferences[view] = value
    }

    private func loadViewPreferences(for view: AppView) {
        let value = viewPreferences[view] ?? ViewPreferences()
        restoringViewPreferences = true
        search = value.search
        filterPreset = value.filterPreset
        groupField = GroupField.fields(for: view).contains(value.grouping) ? value.grouping : .none
        selection = value.preserveSelection ? Set(value.selection) : []
        restoringViewPreferences = false
    }

    func setNotifications(_ enabled: Bool) { notificationsEnabled = enabled }
    func setNotificationDetail(_ detail: NotificationDetail) { notificationDetail = detail }
    func setMonitoringProfile(_ profile: MonitoringProfile) {
        monitoringProfile = profile
        stopMonitoring()
        startMonitoring()
        if isLoading { return }
        refresh()
    }

    func securitySeverity(for rule: String) -> FindingSeverity? {
        securitySeverityPolicy.overrides[rule]
    }

    func setSecuritySeverity(_ severity: FindingSeverity?, for rule: String) {
        var overrides = securitySeverityPolicy.overrides
        if let severity { overrides[rule] = severity } else { overrides.removeValue(forKey: rule) }
        securitySeverityPolicy = SecuritySeverityPolicy(overrides: overrides)
    }

    func sortPreference(for view: AppView) -> (key: String?, ascending: Bool) {
        let value = viewPreferences[view] ?? ViewPreferences()
        return (value.sortKey, value.sortAscending)
    }

    func setSortPreference(for view: AppView, key: String?, ascending: Bool) {
        var value = viewPreferences[view] ?? ViewPreferences()
        value.sortKey = key
        value.sortAscending = ascending
        viewPreferences[view] = value
        persist()
    }

    func dismissFirstRun() {
        UserDefaults.standard.set(true, forKey: "usbscope.firstRunExplained.v1")
        showFirstRun = false
    }

    /// Whether a column of `view` is currently visible.
    func isColumnVisible(_ view: AppView, _ title: String) -> Bool {
        !(hiddenColumns[view]?.contains(title) ?? false)
    }

    func toggleColumn(_ view: AppView, _ title: String) {
        var hidden = hiddenColumns[view] ?? []
        if hidden.contains(title) { hidden.remove(title) } else { hidden.insert(title) }
        hiddenColumns[view] = hidden
    }

    func showAllColumns(_ view: AppView) { hiddenColumns[view] = [] }

    // MARK: - Refresh

    func refresh() {
        guard !isLoading else { return }
        lastAttemptAt = Date()
        dataFreshness = snapshot == nil ? .loading : .stale
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isLoading = true
        errorMessage = nil
        progress = nil
        let profile = monitoringProfile == .lowPower ? SnapshotCollectionProfile.lowPower : .full
        refreshTask = Task { [weak self] in
            guard let appState = self else { return }
            let collector: SnapshotCoordinator.Collector = { progress in
                await appState.collectionService.collect(profile: profile, progress: progress)
            }
            let result = await appState.coordinator.request(.manual, collector: collector, progress: { [weak appState] stage, index, total in
                let value = SnapshotProgress(stage: stage, index: index, total: total)
                Task { @MainActor [weak appState] in
                    guard let appState, appState.refreshGeneration == generation else { return }
                    appState.progress = value
                }
            })
            let inventory = await appState.collectionService.inventory()
            guard let result else { return }
            guard let self, self.refreshGeneration == generation, !Task.isCancelled else { return }
            self.storage = inventory.devices
            self.storageStatus = inventory.status
            self.storageWarnings = inventory.warnings
            self.storageErrors = inventory.errors
            self.lastReadDuration = result.duration
            self.sourceTimings = result.stageTimings
            if inventory.status == .failed { self.lastFailureAt = Date() }
            self.apply(result.snapshot, generation: generation)
            self.refreshTask = nil
        }
    }

    /// Collect one snapshot on the calling (main) thread and apply it.
    ///
    /// Only the offscreen `--snapshot` render uses this: it must have a snapshot
    /// before it draws, and it has no run loop to wait on a `Task` for.
    func loadSynchronously() {
        isLoading = true
        let inventory = collectionService.inventorySynchronously()
        storage = inventory.devices
        storageStatus = inventory.status
        storageWarnings = inventory.warnings
        storageErrors = inventory.errors
        let profile = monitoringProfile == .lowPower ? SnapshotCollectionProfile.lowPower : .full
        apply(collectionService.collectSynchronously(profile: profile), generation: nil)
    }

    /// Apply a decoded fixture for deterministic offscreen rendering. This is
    /// intentionally separate from live collection so screenshot checks never
    /// shell out to the host or persist fixture data as a user snapshot.
    func loadSnapshotForRendering(_ fresh: Snapshot) {
        isLoading = true
        storage = []
        storageStatus = .notApplicable
        storageWarnings = []
        storageErrors = []
        sourceTimings = [:]
        apply(fresh, generation: nil)
    }

    private func apply(_ fresh: Snapshot, generation: UInt64?) {
        if let generation, generation != refreshGeneration { return }
        if let appliedAt, fresh.seenAt < appliedAt { return }
        let sourceWarnings = fresh.warnings + storageWarnings
        let currentHealth = health(for: sourceWarnings)
        qaMetrics.record(snapshot: fresh, sourceStatuses: currentHealth)
        readWarnings = sourceWarnings
        updateSourceHealthMetadata(health: currentHealth, warnings: sourceWarnings, capturedAt: fresh.seenAt)
        let complete = sourceWarnings.isEmpty && storageStatus != .partial && storageStatus != .failed && storageStatus != .stale
        if !complete, lastSuccessfulSnapshot != nil {
            lastFailureAt = Date()
            dataFreshness = .stale
            sourceHealth = currentHealth
            errorMessage = sourceWarnings.joined(separator: " · ")
            isLoading = false
            progress = nil
            return
        }
        appliedAt = fresh.seenAt
        if complete {
            lastSuccessfulSnapshot = fresh
            dataFreshness = .current
        } else {
            // Keep the last warning-free read as the support baseline; the
            // displayed partial result is explicitly stale rather than being
            // presented as a complete current snapshot.
            dataFreshness = .stale
        }
        changes = diffSnapshots(previous: previous, current: fresh)
        previous = fresh
        snapshot = fresh
        if !complete { lastFailureAt = Date() }
        sourceHealth = currentHealth
        reads += 1
        isLoading = false
        progress = nil
        if mainWindowVisible {
            history.record(fresh)
        }
        if sourceWarnings.isEmpty {
            errorMessage = nil
        } else {
            errorMessage = sourceWarnings.joined(separator: " · ")
        }
        if notificationsEnabled, let changes, changes.deviceCount > 0 {
            notifier?.notify(changes, enabled: true, detail: notificationDetail, language: language)
        }
        reconcileSelection()
    }

    private func health(for warnings: [String]) -> [String: SourceHealth] {
        var health = Dictionary(uniqueKeysWithValues: SnapshotStage.allCases.map { ($0.rawValue, SourceHealth.healthy) })
        for warning in warnings {
            let source = warning.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "unknown"
            let failed = warning.localizedCaseInsensitiveContains("failed")
                || warning.localizedCaseInsensitiveContains("invalid")
                || warning.localizedCaseInsensitiveContains("timeout")
            health[source] = failed ? .failed : .partial
        }
        health["storage"] = storageStatus
        return health
    }

    private func updateSourceHealthMetadata(health: [String: SourceHealth], warnings: [String], capturedAt: Date) {
        var bySource: [String: [String]] = [:]
        for warning in warnings {
            let source = warning.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "unknown"
            bySource[source, default: []].append(warning)
        }
        sourceWarningsBySource = bySource
        sourceHealth = health
        for (source, status) in health where status == .healthy {
            sourceLastSuccessAt[source] = capturedAt
        }
    }

    private func reconcileSelection() {
        guard let snapshot else { selection.removeAll(); detailRowKey = nil; return }
        let ids = Set(Presentation.tableRows(for: view, snapshot: snapshot).map(\.id))
        selection.formIntersection(ids)
        if let detailRowKey, !ids.contains(detailRowKey) { self.detailRowKey = nil }
    }

    // MARK: - Auto refresh

    func setAutoRefresh(_ enabled: Bool) {
        autoRefresh = enabled
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(interval, 1), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func setInterval(_ value: Double) {
        interval = value
        if autoRefresh { setAutoRefresh(true) }  // restart with the new cadence
    }

    // MARK: - Current rows

    /// The rows of the current view, filtered by the quick preset and then by
    /// the search text (both filters must pass; the preset is applied first).
    func filtered<T: Searchable & PresetFilterable>(_ rows: [T]) -> [T] {
        let selected = rows.filter { filterPreset.matches($0) }
        let terms = search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return selected }
        return selected.filter { row in terms.allSatisfy { row.searchText.contains($0) } }
    }

    /// `collecting Charging · 5/6` while a read is in flight, `collecting …`
    /// before the first stage reports.
    var loadingLine: String {
        ProgressPresentation.text(progress, verb: L(.collecting, language))
    }

    var summaryLine: String {
        if let snapshot { return Presentation.summaryText(snapshot, language: language) }
        return isLoading ? loadingLine : L(.loading, language)
    }

    var statusLine: String {
        guard let snapshot else { return L(.loading, language) }
        return Presentation.statusText(
            snapshot, interval: autoRefresh ? interval : nil, reads: reads,
            changes: changes, filterQuery: search, language: language
        )
    }

    var title: String {
        snapshot.map(Presentation.headerText) ?? "usbscope"
    }

    /// The compact menu bar title: `connected/ports`, plus a warning symbol.
    var menuBarTitle: String {
        guard let snapshot else { return "usbscope" }
        let base = "\(snapshot.connectedPorts.count)/\(snapshot.ports.count)"
        return readWarnings.isEmpty ? base : "\(base) ⚠"
    }

    var menuBarTooltip: String {
        guard let snapshot else { return "usbscope — \(L(.loading, language))" }
        var parts = [
            Strings.connectedPortsLabel(connected: snapshot.connectedPorts.count,
                                        total: snapshot.ports.count, language),
            Strings.deviceCountLabel(snapshot.devices.count, language),
        ]
        if !readWarnings.isEmpty { parts.append(Strings.warningCountLabel(readWarnings.count, language)) }
        return parts.joined(separator: " · ")
    }

    /// Detail pairs for the row whose sheet is open.
    var detailPairs: [(String, String)] {
        guard let snapshot, let key = detailRowKey else { return [] }
        return Presentation.details(snapshot, view: view, rowKey: key, language: language)
    }

    // MARK: - Security, timeline, USB4 fabric & diff

    /// The security report of the current snapshot (the Security tab).
    var securityReport: SecurityReport? {
        snapshot.map { Security.analyse($0, policy: securitySeverityPolicy) }
    }

    /// Resolve a security observation to the current source row. If the
    /// object detached between analysis and activation, leave the user on the
    /// relevant view with a normal empty selection instead of guessing.
    func openFinding(_ finding: FindingRow) {
        guard let snapshot else { return }
        if let portName = finding.port,
           let port = snapshot.ports.first(where: { $0.name == portName }) {
            view = .ports
            selection = [portKey(port)]
            detailRowKey = portKey(port)
            return
        }
        if let device = snapshot.devices.first(where: {
            if let locationID = finding.locationID { return $0.locationID == locationID }
            return finding.device == $0.label || finding.subject == $0.label
        }) {
            view = .devices
            selection = [deviceKey(device)]
            detailRowKey = deviceKey(device)
        }
    }

    /// The storage inventory as rows, each with its eject state.
    var storageInventory: [StorageRow] { SecurityPresentation.storageRows(storage) }

    /// The USB4/Thunderbolt fabric of the current snapshot as tree rows.
    var fabricRows: [FabricRow] {
        FabricPresentation.rows(snapshot?.thunderboltFabric ?? ThunderboltFabric())
    }

    /// The power sparkline geometry of the recorded history.
    var timelineGeometry: TimelineGeometry { TimelineGeometry(powerTimeline) }

    /// The recorded hotplug events, newest first.
    var hotplugRows: [EventRow] { eventRows(events) }

    func openEvent(_ row: EventRow) {
        guard let snapshot else { return }
        if let device = snapshot.devices.first(where: {
            deviceKey($0) == row.key || (row.locationID != nil && $0.locationID == row.locationID)
        }) {
            view = .devices
            selection = [deviceKey(device)]
            detailRowKey = deviceKey(device)
        } else {
            historicalEvent = events.first(where: { $0.key == row.key && $0.locationID == row.locationID })
        }
    }

    /// The live machine against the loaded baseline (`nil` without one).
    var baselineDiff: ChangeSet? {
        guard let baseline, let snapshot else { return nil }
        return diffSnapshots(previous: baseline, current: snapshot)
    }

    /// Load a snapshot JSON as the comparison baseline.
    func loadBaseline(_ url: URL) {
        do {
            baseline = try SnapshotLoading.snapshot(from: url)
            baselineName = url.lastPathComponent
            baselineError = nil
        } catch {
            baseline = nil
            baselineName = nil
            baselineError = "\(error)"
        }
    }

    func clearBaseline() {
        baseline = nil
        baselineName = nil
        baselineError = nil
    }

    func saveBaseline() {
        guard let snapshot else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "usbscope-baseline.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Baseline.save(snapshot, to: url.path)
            baseline = snapshot; baselineName = url.lastPathComponent; baselineError = nil
        } catch { baselineError = error.localizedDescription }
    }

    func renameBaseline() {
        guard baseline != nil else { return }
        let alert = NSAlert()
        alert.messageText = L(.renameBaselineTitle, language)
        let field = NSTextField(string: baselineName ?? L(.baselineNone, language))
        field.frame.size = NSSize(width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L(.renameAction, language))
        alert.addButton(withTitle: L(.cancel, language))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        baselineName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ask for a snapshot JSON (a save panel) and load it as the baseline.
    func pickBaseline() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.message = L(.compareWith, language)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadBaseline(url)
    }

    /// Run `diskutil eject` for a storage device, then refresh the inventory.
    func confirmEject(_ row: StorageRow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Strings.ejectTitle(row.identifier, language)
        alert.informativeText = Strings.ejectDetails(name: row.name, mount: row.mount, language)
        alert.addButton(withTitle: L(.cancel, language))
        alert.addButton(withTitle: L(.eject, language))
        alert.buttons.first?.keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        eject(row)
    }

    func eject(_ row: StorageRow) {
        guard let argv = row.ejectCommand, ejecting == nil else { return }
        ejecting = row.id
        ejectMessage = nil
        let failed = L(.ejectFailed, language)
        let language = self.language
        let identifier = row.identifier
        // Same shape as `loadEventHistory`: the subprocess stays off the main actor,
        // the state change happens on it.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.commandService.run(argv)
            let message = result.ok
                ? "\(identifier) \(L(.ejected, language))"
                : "\(failed): \(identifier) (\(result.error ?? "exit \(result.returncode)"))"
            self.ejecting = nil
            self.ejectMessage = message
            self.refresh()
        }
    }

    // MARK: - Clipboard & export

    /// Row ids currently visible (filtered) in the current view.
    private var visibleRows: [(id: String, cells: [String])] {
        guard let snapshot else { return [] }
        return Presentation.tableRows(for: view, snapshot: snapshot)
    }

    private func tsv(_ rows: [(id: String, cells: [String])], header: Bool) -> String {
        var lines: [String] = []
        if header { lines.append(Presentation.headers(for: view).joined(separator: "\t")) }
        lines.append(contentsOf: rows.map { $0.cells.joined(separator: "\t") })
        return lines.joined(separator: "\n")
    }

    /// Copy the whole table (or only the selected rows) as TSV.
    func copyTable(selected: Bool) {
        guard let snapshot else { return }
        let rows = selected
            ? visibleRows.filter { selection.contains($0.id) }
            : visibleRows
        guard !rows.isEmpty else { return }
        writeClipboard(RedactionPolicy().redactText(tsv(rows, header: selected ? false : true),
                                                     snapshot: snapshot, storage: storage))
    }

    func copyRow(_ id: String) {
        guard let snapshot, let row = visibleRows.first(where: { $0.id == id }) else { return }
        writeClipboard(RedactionPolicy().redactText(row.cells.joined(separator: "\t"), snapshot: snapshot, storage: storage))
    }

    func copyIdentifier(_ id: String) {
        guard let snapshot else { return }
        writeClipboard(RedactionPolicy().redactText(id, snapshot: snapshot, storage: storage))
    }

    /// Copy the raw snapshot as JSON.
    func copyJSON() {
        guard let snapshot else { return }
        writeClipboard(DiagnosticBundle.redactedSnapshotJSON(snapshot, storage: storage))
    }

    func copyDiagnostics() {
        guard confirmExportDisclosure(format: "clipboard-diagnostics") else { return }
        let policy = RedactionPolicy()
        let safeWarnings = snapshot.map { current in
            readWarnings.map { warning in policy.redactText(warning, snapshot: current, storage: storage) }
        } ?? readWarnings
        let safeErrors = storageErrors.map { error in
            var value: [String: Any] = [
                "code": error.code.rawValue,
                "source": error.source,
                "operation": error.operation,
                "severity": error.severity,
                "user_message": error.userMessage,
                "technical_message": error.technicalMessage,
            ]
            if let action = error.recoveryAction { value["recovery_action"] = action }
            if let snapshot {
                value = value.mapValues { item in
                    guard let text = item as? String else { return item }
                    return policy.redactText(text, snapshot: snapshot, storage: storage)
                }
            }
            return value
        }
        var payload: [String: Any] = [
            "app": "usbscope", "version": AboutIcon.version,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": appArchitectureName,
            "schema_version": Serialize.schemaVersion,
            "freshness": dataFreshness.rawValue, "storage_status": storageStatus.rawValue,
            "storage_warnings": snapshot.map { current in
                storageWarnings.map { warning in policy.redactText(warning, snapshot: current, storage: storage) }
            } ?? storageWarnings,
            "warnings": safeWarnings,
            "storage_errors": safeErrors,
            "source_health": sourceHealth.mapValues(\.rawValue),
            "source_timings": sourceTimings,
            "monitoring": isHotplugEventDriven ? "IOKit event-driven" : "polling/disabled",
            "metrics": qaMetrics.dictionary(),
        ]
        if let lastAttemptAt { payload["last_attempt_at"] = ISO8601DateFormatter().string(from: lastAttemptAt) }
        if let lastFailureAt { payload["last_failure_at"] = ISO8601DateFormatter().string(from: lastFailureAt) }
        payload["recent_events"] = events.map { event in
            let safeName: String
            if let snapshot {
                safeName = policy.redactText(event.name, snapshot: snapshot, storage: storage)
            } else {
                safeName = policy.redactEventIdentities ? "[REDACTED]" : event.name
            }
            return ["kind": event.kind.rawValue, "name": safeName,
             "seen_at": ISO8601DateFormatter().string(from: event.seenAt)]
        }
        if let snapshot {
            payload["snapshot"] = (try? JSONSerialization.jsonObject(
                with: Data(DiagnosticBundle.redactedSnapshotJSON(snapshot, policy: policy, storage: storage).utf8)
            )) ?? [:]
        }
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        writeClipboard(String(decoding: data, as: UTF8.self))
    }

    func copyWarnings() {
        let policy = RedactionPolicy()
        let warnings = snapshot.map { current in
            readWarnings.map { policy.redactText($0, snapshot: current, storage: storage) }
        } ?? readWarnings
        guard !warnings.isEmpty else { return }
        writeClipboard(warnings.joined(separator: "\n"))
    }

    /// Copy one warning selected in the data-quality view with the same
    /// identifier redaction used by aggregate diagnostics.
    func copyWarning(_ warning: String) {
        let policy = RedactionPolicy()
        let text = snapshot.map { policy.redactText(warning, snapshot: $0, storage: storage) } ?? warning
        writeClipboard(text)
    }

    func exportDiagnostics() {
        guard confirmExportDisclosure(format: "diagnostics") else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "usbscope-diagnostics"
        panel.message = L(.exportRedactedDiagnostics, language)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DiagnosticBundle.write(to: url, snapshot: snapshot,
                                       warnings: readWarnings,
                                       timings: sourceTimings.merging(lastReadDuration.map { ["snapshot": $0] } ?? [:]) { current, _ in current },
                                       events: events, errors: storageErrors, metrics: qaMetrics,
                                       storage: storage)
            reportFailed = false
            reportMessage = "\(L(.diagnosticsWritten, language)): \(url.lastPathComponent)"
        } catch {
            reportFailed = true
            reportMessage = "\(L(.diagnosticsFailed, language)): \(error.localizedDescription)"
        }
    }

    private func writeClipboard(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    /// Write the current view to a file via a save panel (`csv` or `json`).
    func export(format: ExportFormat) {
        guard let snapshot else { return }
        guard confirmExportDisclosure(format: format.rawValue) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "usbscope-\(view.rawValue).\(format.rawValue)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let rawText = format == .csv
            ? Presentation.csv(for: view, snapshot: snapshot)
            : Serialize.json(snapshot)
        let text = RedactionPolicy().redactText(rawText, snapshot: snapshot, storage: storage)
        do {
            try AtomicFile.write(text, to: url)
            reportFailed = false
            reportMessage = "\(L(.exportWritten, language)): \(url.lastPathComponent)"
        } catch {
            reportFailed = true
            reportMessage = "\(L(.exportFailed, language)): \(error.localizedDescription)"
        }
    }

    /// Ask for a destination (a save panel with a Markdown/HTML popup), render
    /// the report through UsbScopeCore's generator — the very bytes
    /// `usbscope report` writes — and save it.
    ///
    /// A write failure lands in the status footer instead of vanishing into
    /// `try?`, so a read-only volume or a full disk is visible rather than a
    /// save panel that silently did nothing.
    func exportReport() {
        guard let snapshot else { return }
        let language = self.language

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for format in ReportFormat.allCases {
            popup.addItem(withTitle: L(.of(format), language))
        }
        popup.selectItem(at: 0)
        let label = NSTextField(labelWithString: L(.reportFormat, language))
        let accessory = NSStackView(views: [label, popup])
        accessory.orientation = .horizontal
        accessory.spacing = 8
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        accessory.frame = NSRect(x: 0, y: 0, width: 360, height: 34)

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.message = L(.exportReport, language)
        panel.allowedContentTypes = ReportFormat.allCases.map(\.contentType)
        panel.nameFieldStringValue = ReportFormat.markdown.suggestedFilename
        panel.accessoryView = accessory
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let index = min(max(popup.indexOfSelectedItem, 0), ReportFormat.allCases.count - 1)
        let format = ReportFormat.allCases[index]
        guard confirmExportDisclosure(format: format.rawValue) else { return }
        // `storage` is filled by the collection service in `refresh()` —
        // the same call the CLI's `report` makes, so both list the same mass
        // storage as the snapshot they belong to.
        let text = ReportExport.text(format, snapshot: snapshot, storage: storage,
                                     redactionPolicy: RedactionPolicy(),
                                     language: language == .de ? .german : .english)
        let destination = format.replacingExtension(of: url)
        do {
            try AtomicFile.write(text, to: destination)
            reportFailed = false
            reportMessage = "\(L(.reportWritten, language)): \(destination.lastPathComponent)"
        } catch {
            reportFailed = true
            reportMessage = "\(L(.reportFailed, language)): \(error.localizedDescription)"
        }
    }

    private func confirmExportDisclosure(format: String) -> Bool {
        let key = "usbscope.exportDisclosure.v1.\(format)"
        if UserDefaults.standard.bool(forKey: key) { return true }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L(.exportIdentifierWarning, language)
        alert.informativeText = L(.exportRedactionNote, language)
        alert.addButton(withTitle: L(.continueAction, language))
        alert.addButton(withTitle: L(.cancel, language))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        UserDefaults.standard.set(true, forKey: key)
        return true
    }
}
