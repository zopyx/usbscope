import AppKit
import SwiftUI
import UsbScopeCore
import UsbScopeUI

/// usbscope-app — the SwiftUI twin of the Python/AppKit app: the same five
/// views on top of `UsbScopeCore`, with a view switcher, live search, sortable
/// columns, a detail sheet, JSON/CSV export, a menu bar extra, a `⌘,`
/// preferences window, DE/EN localisation and per-view column layouts.

@main
struct UsbScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(state)
                .onAppear { delegate.state = state }
        }
        .defaultSize(width: 1180, height: 720)
        .defaultPosition(.center)
        .windowResizability(.automatic)
        .commands { commands }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(state)
        } label: {
            Text(state.menuBarTitle).monospacedDigit().help(state.menuBarTooltip)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView()
                .environmentObject(state)
        }
    }

    @CommandsBuilder
    private var commands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L(.aboutMenuTitle, state.language)) { AboutPanel.show(state: state) }
        }
        CommandGroup(after: .newItem) {
            Button(L(.refreshNow, state.language)) { state.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(state.isLoading)
            Divider()
            Button(L(.exportReport, state.language)) { state.exportReport() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(state.snapshot == nil)
        }
        CommandMenu(L(.viewMenu, state.language)) {
            ForEach(AppView.allCases) { view in
                Button(L(.of(view), state.language)) { state.view = view }
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(view.shortcutNumber)")), modifiers: .command
                    )
            }
        }
        CommandMenu(L(.commandsMenu, state.language)) {
            Button(L(.commandPalette, state.language)) { state.showCommandPalette = true }
                .keyboardShortcut("k", modifiers: [.command])
            Button(L(.refreshAction, state.language)) { state.refresh() }.keyboardShortcut("r", modifiers: .command)
            Button(L(.exportDiagnostics, state.language)) { state.exportDiagnostics() }
            Button(L(.copyDiagnostics, state.language)) { state.copyDiagnostics() }
            Button(L(.openDiagnostics, state.language)) { state.showDiagnostics = true }
            Button(L(.saveBaseline, state.language)) { state.saveBaseline() }.disabled(state.snapshot == nil)
            Button(L(.loadBaseline, state.language)) { state.pickBaseline() }
            Button(L(.clearBaselineAction, state.language)) { state.clearBaseline() }.disabled(state.baseline == nil)
            Divider()
            ForEach(AppView.allCases) { item in
                Button(L(.of(item), state.language)) { state.view = item }
            }
        }
        CommandMenu(L(.tableMenu, state.language)) {
            Button(L(.copySelected, state.language)) { state.copyTable(selected: true) }
                .keyboardShortcut("c", modifiers: .command)
            Button(L(.copyWholeTable, state.language)) { state.copyTable(selected: false) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button(L(.copyJSON, state.language)) { state.copyJSON() }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            Divider()
            Button(L(.showDetails, state.language)) {
                if let key = state.selection.first { state.detailRowKey = key }
            }
            .keyboardShortcut("d", modifiers: .command)
            Divider()
            Button(L(.exportJSON, state.language)) { state.export(format: .json) }
                .keyboardShortcut("s", modifiers: .command)
            Button(L(.exportCSV, state.language)) { state.export(format: .csv) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}

/// A plain executable is not automatically a regular app; force the activation
/// policy so the window gets focus and a Dock entry when run via `swift run`.
///
/// `usbscope-app --print-rows` collects one snapshot, prints the row count of
/// every view and exits — the headless self test of the app's data path (the
/// Python app has `--snapshot` for the same reason).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("usbscope.main-window")

    weak var state: AppState?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // `--version` prints the bundle's version and exits before any window is
        // created; it is what `scripts/build-swift-app.sh` uses to prove the
        // assembled bundle actually runs.
        if CommandLine.arguments.contains("--version") {
            let version = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
            print("usbscope-app \(version ?? "0.0.0-unbundled")")
            exit(0)
        }
        if CommandLine.arguments.contains("--print-rows") {
            SelfTest.runAndExit()
        }
        // `--snapshot out.png [--view security]` renders the window offscreen and
        // exits — the same mode the Python app has (and the build script uses).
        if let request = SnapshotRenderer.requested() {
            MainActor.assumeIsolated {
                SnapshotRenderer.run(path: request.path, view: request.view, baseline: request.baseline)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installWindowObservers()
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
            window.identifier = Self.mainWindowIdentifier
            window.setFrameAutosaveName("usbscope-main-window")
            window.minSize = NSSize(width: 900, height: 460)
        }
    }

    private func installWindowObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(mainWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(mainWindowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
    }

    @objc private func mainWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == Self.mainWindowIdentifier else { return }
        state?.setMainWindowVisible(false)
    }

    @objc private func mainWindowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == Self.mainWindowIdentifier else { return }
        state?.setMainWindowVisible(true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        state?.shutdown()
        return .terminateNow
    }

    /// A menu bar extra keeps working after the window closes, so the app stays
    /// alive; "Quit usbscope" in the status menu terminates it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

enum SelfTest {
    /// Build the presentation of every view from a live snapshot and print it.
    static func runAndExit() -> Never {
        let snapshot = SnapshotBuilder.collect()
        print(Presentation.headerText(snapshot))
        print(Presentation.summaryText(snapshot))
        for view in AppView.tableViews {
            let rows = Presentation.tableRows(for: view, snapshot: snapshot)
            print("  \(view.rawValue): \(rows.count) row(s), \(Presentation.headers(for: view).count) columns")
        }
        if !snapshot.warnings.isEmpty {
            print("warnings: \(snapshot.warnings.joined(separator: " · "))")
        }
        exit(0)
    }
}

// MARK: - Menu bar extra

/// The status item menu: view switching, refresh, notifications and quit.
struct MenuBarContent: View {
    @EnvironmentObject private var state: AppState

    private var lang: AppLanguage { state.language }

    var body: some View {
        Button(L(.openWindow, lang)) { showWindow() }
        Divider()
        Picker(L(.viewMenu, lang), selection: $state.view) {
            ForEach(AppView.allCases) { view in
                Text(L(.of(view), lang)).tag(view)
            }
        }
        .pickerStyle(.inline)
        Divider()
        Button(L(.refreshNow, lang)) { state.refresh() }
            .keyboardShortcut("r")
            .disabled(state.isLoading)
        Toggle(
            L(.notifications, lang),
            isOn: Binding(get: { state.notificationsEnabled }, set: { state.setNotifications($0) })
        )
        Divider()
        Button(L(.quit, lang)) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Bring the main window forward (or re-focus it if it is already open).
    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Main window

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    private var lang: AppLanguage { state.language }

    var body: some View {
        NavigationSplitView {
            List(selection: $state.view) {
                Section(L(.overview, lang)) {
                    Label(L(.overview, lang), systemImage: "gauge.with.dots.needle.33percent")
                        .tag(AppView.ports)
                }
                Section(L(.connections, lang)) {
                    ForEach([AppView.cables, .devices, .thunderbolt, .usb4]) { item in
                        Label(L(.of(item), lang), systemImage: item.systemImage).tag(item)
                    }
                }
                Section(L(.of(.power), lang)) {
                    Label(L(.of(.power), lang), systemImage: AppView.power.systemImage).tag(AppView.power)
                }
                Section(L(.of(.security), lang)) {
                    Label(L(.of(.security), lang), systemImage: AppView.security.systemImage).tag(AppView.security)
                }
                Section(L(.history, lang)) {
                    ForEach([AppView.timeline, .diff]) { item in
                        Label(L(.of(item), lang), systemImage: item.systemImage).tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 360)
            .navigationTitle(L(.appName, lang))
        } detail: {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(Strings.hostLabel(state.snapshot?.host ?? "—", lang), systemImage: "desktopcomputer")
                Label(Strings.connectedPortsLabel(connected: state.snapshot?.connectedPorts.count ?? 0,
                                                  total: state.snapshot?.ports.count ?? 0, lang), systemImage: "cable.connector")
                Label(Strings.deviceCountLabel(state.snapshot?.devices.count ?? 0, lang), systemImage: "externaldrive")
                let warningCount = state.readWarnings.count
                if warningCount > 0 {
                    Label(Strings.warningCountLabel(warningCount, lang), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(Strings.freshnessStatus(state.dataFreshness, lang))
                    .font(.caption).foregroundStyle(state.dataFreshness == .current ? Color.secondary : Color.orange)
                if let captured = state.snapshot?.seenAt {
                    Text(Strings.capturedLabel(captured, lang))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let duration = state.lastReadDuration {
                    Text(String(format: "%.2fs", duration)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .help(state.dataFreshness == .stale ? (state.errorMessage ?? Strings.freshnessStatus(.stale, lang)) :
                  Strings.capturedLabel(state.snapshot?.seenAt ?? Date(), lang))
            Group {
                switch state.view {
                case .ports: PortsView()
                case .cables: CablesView()
                case .devices: DevicesView()
                case .thunderbolt: ThunderboltView()
                case .power: PowerView()
                case .timeline: TimelineView()
                case .security: SecurityView()
                case .usb4: Usb4View()
                case .diff: DiffView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text(state.summaryLine).font(.callout)
                HStack(spacing: 6) {
                    if state.isLoading {
                        // Determinate once the first stage reports, so the bar
                        // advances through ports → buses → … → registry instead of
                        // spinning without saying what is being read.
                        if let fraction = state.progress?.fraction {
                            ProgressView(value: fraction)
                                .progressViewStyle(.linear)
                                .frame(width: 90)
                                .controlSize(.small)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    Text(state.isLoading ? state.loadingLine : state.statusLine)
                        .font(.caption)
                        .foregroundStyle(state.errorMessage == nil ? Color.secondary : Color.orange)
                    if let message = state.reportMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(state.reportFailed ? Color.orange : Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
        .navigationTitle(state.title)
        .toolbar { toolbar }
        .frame(minWidth: 900, minHeight: 460)
        .preferredColorScheme(colorScheme)
        .sheet(isPresented: detailSheetPresented) {
            DetailSheet().environmentObject(state)
        }
        .sheet(isPresented: $state.showFirstRun) {
            FirstRunSheet().environmentObject(state)
        }
        .sheet(isPresented: $state.showDiagnostics) {
            DiagnosticsSheet().environmentObject(state)
        }
        .sheet(isPresented: $state.showCommandPalette) {
            CommandPalette().environmentObject(state)
        }
        .sheet(isPresented: Binding(
            get: { state.historicalEvent != nil },
            set: { if !$0 { state.historicalEvent = nil } }
        )) {
            HistoricalEventSheet().environmentObject(state)
        }
        .onAppear {
            if state.isIdle { state.refresh() }
            // `--show-about` opens the panel straight away: a checkout run cannot
            // be clicked from a script, so this is how the About window is
            // smoke-tested (the same idea as `--print-rows`).
            if CommandLine.arguments.contains("--show-about") {
                AboutPanel.show(state: state)
                // stderr, so the smoke test sees it without waiting for a flush
                FileHandle.standardError.write(
                    Data("about panel opened — \(AboutInfo.name) \(AboutIcon.version)\n".utf8)
                )
            }
        }
        }
    }

    private var colorScheme: ColorScheme? {
        switch state.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(id: "view-selector", placement: .principal) {
            // A row of buttons, not `Picker(.segmented)`: a segmented picker is a single
            // AppKit control, so one `.help` covers every segment and hovering an icon
            // reported the generic "View" instead of its own name. Each button carries
            // its own tooltip — `Ports (⌘1)`, `Diff (⌘9)`.
            HStack(spacing: 2) {
                ForEach(AppView.allCases) { view in
                    let selected = state.view == view
                    Button {
                        state.view = view
                    } label: {
                        Image(systemName: view.systemImage)
                            .frame(minWidth: 22, minHeight: 18)
                    }
                    .buttonStyle(.borderless)
                    .background(
                        selected ? Color.accentColor.opacity(0.22) : Color.clear,
                        in: .rect(cornerRadius: 5)
                    )
                    .foregroundStyle(selected ? Color.accentColor : Color.primary)
                    .help(view.helpText(L(.of(view), lang)))
                    .accessibilityLabel(L(.of(view), lang))
                }
            }
        }
        // Search, quick filter, baseline and the refresh controls share one group:
        // `ToolbarContentBuilder` accepts at most ten top-level items.
        ToolbarItemGroup {
            TextField(L(.filter, lang), text: $state.search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
                .help(L(.filterHelp, lang))
            Menu {
                Picker(L(.filterPresets, lang), selection: $state.filterPreset) {
                    ForEach(FilterPreset.allCases) { preset in
                        Text(L(.of(preset), lang)).tag(preset)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: state.filterPreset == .all
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill")
            }
            .help(L(.filterPresets, lang))
            Button { state.pickBaseline() } label: {
                Image(systemName: "square.on.square.dashed")
            }
            .help(L(.compareWith, lang))
            Menu {
                Button(L(.saveBaseline, lang)) { state.saveBaseline() }.disabled(state.snapshot == nil)
                Button(L(.loadBaseline, lang)) { state.pickBaseline() }
                Button(L(.renameBaseline, lang)) { state.renameBaseline() }.disabled(state.baseline == nil)
                Button(L(.clearBaselineAction, lang)) { state.clearBaseline() }.disabled(state.baseline == nil)
            } label: { Image(systemName: "externaldrive.badge.timemachine") }
                .help(L(.baselineHelp, lang))
            Button {
                state.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(state.isLoading)
            .help(L(.refreshNow, lang) + " (⌘R)")
            Toggle(
                isOn: Binding(get: { state.autoRefresh }, set: { state.setAutoRefresh($0) })
            ) {
                Image(systemName: "timer")
            }
            .help(L(.toggleAutoRefresh, lang))
            Menu {
                ForEach(PREFERENCE_INTERVALS, id: \.self) { value in
                    Button(Strings.seconds(Int(value), state.language)) { state.setInterval(value) }
                }
            } label: {
                Text(verbatim: Strings.seconds(Int(state.interval), state.language))
            }
            .help(L(.intervalHelp, lang))
        }
        if !GroupField.fields(for: state.view).isEmpty {
            ToolbarItem(id: "grouping", placement: .automatic) {
                Menu {
                    Picker(L(.groupBy, lang), selection: $state.groupField) {
                        ForEach(GroupField.fields(for: state.view)) { field in
                            Text(L(.of(field), lang)).tag(field)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "rectangle.3.group")
                }
                .help(L(.groupBy, lang))
            }
        }
        if AppView.tableViews.contains(state.view) {
            ToolbarItem(id: "columns", placement: .automatic) {
                Menu {
                    ForEach(Presentation.headers(for: state.view), id: \.self) { header in
                        Toggle(
                            header,
                            isOn: Binding(
                                get: { state.isColumnVisible(state.view, header) },
                                set: { _ in state.toggleColumn(state.view, header) }
                            )
                        )
                    }
                    Divider()
                    Button(L(.showAllColumns, lang)) { state.showAllColumns(state.view) }
                } label: {
                    Image(systemName: "tablecells")
                }
                .help(L(.columns, lang))
            }
        }
        ToolbarItemGroup {
            Menu {
                Button(L(.copySelected, lang)) { state.copyTable(selected: true) }
                Button(L(.copyWholeTable, lang)) { state.copyTable(selected: false) }
                Button(L(.copyJSON, lang)) { state.copyJSON() }
                Button(L(.copyDiagnostics, lang)) { state.copyDiagnostics() }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help(L(.copyHelp, lang))
            Menu {
                Button(L(.exportJSON, lang)) { state.export(format: .json) }
                Button(L(.exportCSV, lang)) { state.export(format: .csv) }
                Divider()
                Button(L(.exportReport, lang)) { state.exportReport() }
                    .disabled(state.snapshot == nil)
                Button(L(.exportDiagnostics, lang)) { state.exportDiagnostics() }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help(L(.exportHelp, lang))
            Button { state.showDiagnostics = true } label: {
                Image(systemName: "cross.case")
            }
            .help(L(.diagnosticsHelp, lang))
            Button {
                if let key = state.selection.first { state.detailRowKey = key }
            } label: {
                Image(systemName: "info.circle")
            }
            .disabled(state.selection.isEmpty)
            .help(L(.showDetails, lang) + " (⌘D)")
        }
    }

    private var detailSheetPresented: Binding<Bool> {
        Binding(
            get: { state.detailRowKey != nil },
            set: { if !$0 { state.detailRowKey = nil } }
        )
    }
}
