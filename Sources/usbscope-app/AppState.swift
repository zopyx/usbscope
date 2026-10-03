import AppKit
import Foundation
import SwiftUI
import UsbScopeCore
import UsbScopeUI

/// Observable app state: the current snapshot, the selected view, the search
/// text, the auto-refresh cadence and the change set of the last refresh.
///
/// Collection runs off the main thread (it shells out to `system_profiler` and
/// `ioreg`); the state machine is idle → loading → loaded, with an error
/// message instead of a crash when a source fails.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var changes: ChangeSet?
    @Published private(set) var reads = 0
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    @Published var view: AppView = .ports
    @Published var search = ""
    @Published var interval: Double = 5
    @Published private(set) var autoRefresh = false

    /// Selected rows of the current view (row ids).
    @Published var selection = Set<String>()

    /// The row whose detail sheet is open, if any.
    @Published var detailRowKey: String?

    private var previous: Snapshot?
    private var timer: Timer?

    /// Snapshots with their deltas and the power timeline they form.
    private let history = SnapshotHistory()

    /// Append-only hotplug log (`~/Library/Application Support/usbscope/events.jsonl`).
    /// A read-only home without application support is the only failure mode, so it
    /// stays optional instead of taking the app down.
    private let eventLog: EventLog? = try? EventLog()

    /// The IOKit hotplug watcher started on launch.
    private var watcher: UsbHotplugWatcher?

    var isIdle: Bool { snapshot == nil && !isLoading }

    /// Whether the watcher got real IOKit notifications (vs. the polling fallback).
    var isHotplugEventDriven: Bool { watcher?.isEventDriven ?? false }

    /// The charging watts over time, as far as the app has seen them.
    var powerTimeline: [PowerPoint] { history.powerTimeline() }

    init() {
        // Own the IOKit notifications for the lifetime of the app; the watcher
        // collects its own baseline off the main thread, so launch is not blocked.
        startMonitoring()
    }

    // MARK: - Hotplug monitoring

    /// Start the hotplug watcher. Safe to call more than once.
    func startMonitoring() {
        guard watcher == nil else { return }
        let watcher = UsbHotplugWatcher()
        watcher.start { [weak self] update in
            Task { @MainActor in self?.handleHotplug(update) }
        }
        self.watcher = watcher
    }

    func stopMonitoring() {
        watcher?.stop()
        watcher = nil
    }

    /// Record the hotplug events and show the fresh snapshot immediately.
    private func handleHotplug(_ update: UsbHotplugWatcher.Update) {
        if let eventLog, !update.events.isEmpty {
            let events = update.events
            // The log is I/O; keep it off the main thread.
            Task.detached(priority: .utility) { try? eventLog.append(events) }
        }
        apply(update.snapshot)
    }


    // MARK: - Refresh

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            let fresh = await Task.detached(priority: .userInitiated) {
                SnapshotBuilder.collect()
            }.value
            apply(fresh)
        }
    }

    private func apply(_ fresh: Snapshot) {
        changes = diffSnapshots(previous: previous, current: fresh)
        previous = fresh
        snapshot = fresh
        reads += 1
        isLoading = false
        history.record(fresh)
        if fresh.warnings.isEmpty {
            errorMessage = nil
        } else {
            errorMessage = fresh.warnings.joined(separator: " · ")
        }
    }

    // MARK: - Auto refresh

    func setAutoRefresh(_ enabled: Bool) {
        autoRefresh = enabled
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: max(interval, 1), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func setInterval(_ value: Double) {
        interval = value
        if autoRefresh { setAutoRefresh(true) }  // restart with the new cadence
    }

    // MARK: - Current rows

    /// The rows of the current view, filtered by the search text.
    func filtered<T: Searchable>(_ rows: [T]) -> [T] {
        let terms = search.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return rows }
        return rows.filter { row in terms.allSatisfy { row.searchText.contains($0) } }
    }

    var summaryLine: String {
        snapshot.map(Presentation.summaryText) ?? "reading…"
    }

    var statusLine: String {
        guard let snapshot else { return "reading the USB subsystem…" }
        return Presentation.statusText(
            snapshot, interval: autoRefresh ? interval : nil, reads: reads,
            changes: changes, filterQuery: search
        )
    }

    var title: String {
        snapshot.map(Presentation.headerText) ?? "usbscope"
    }

    /// Detail pairs for the row whose sheet is open.
    var detailPairs: [(String, String)] {
        guard let snapshot, let key = detailRowKey else { return [] }
        return Presentation.details(snapshot, view: view, rowKey: key)
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
        guard snapshot != nil else { return }
        let rows = selected
            ? visibleRows.filter { selection.contains($0.id) }
            : visibleRows
        guard !rows.isEmpty else { return }
        writeClipboard(tsv(rows, header: selected ? false : true))
    }

    /// Copy the raw snapshot as JSON.
    func copyJSON() {
        guard let snapshot else { return }
        writeClipboard(Serialize.json(snapshot))
    }

    private func writeClipboard(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    /// Write the current view to a file via a save panel (`csv` or `json`).
    func export(format: String) {
        guard let snapshot else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "usbscope-\(view.rawValue).\(format)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = format == "csv"
            ? Presentation.csv(for: view, snapshot: snapshot)
            : Serialize.json(snapshot)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
