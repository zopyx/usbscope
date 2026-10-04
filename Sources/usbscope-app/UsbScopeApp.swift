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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
        }
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
        }
        CommandMenu(L(.viewMenu, state.language)) {
            ForEach(Array(AppView.allCases.enumerated()), id: \.element) { index, view in
                Button(L(.of(view), state.language)) { state.view = view }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        CommandMenu("Table") {
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
            Button(L(.exportJSON, state.language)) { state.export(format: "json") }
                .keyboardShortcut("s", modifiers: .command)
            Button(L(.exportCSV, state.language)) { state.export(format: "csv") }
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // `--version` prints the bundle's version and exits before any window is
        // created; it is what `scripts/build_swift_app.py` uses to prove the
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
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
        for view in AppView.allCases {
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
        VStack(spacing: 0) {
            Group {
                switch state.view {
                case .ports: PortsView()
                case .cables: CablesView()
                case .devices: DevicesView()
                case .thunderbolt: ThunderboltView()
                case .power: PowerView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text(state.summaryLine).font(.callout)
                HStack(spacing: 6) {
                    if state.isLoading { ProgressView().controlSize(.small) }
                    Text(state.statusLine)
                        .font(.caption)
                        .foregroundStyle(state.errorMessage == nil ? Color.secondary : Color.orange)
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

    private var colorScheme: ColorScheme? {
        switch state.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker(L(.viewMenu, lang), selection: $state.view) {
                ForEach(AppView.allCases) { view in
                    Label(L(.of(view), lang), systemImage: view.systemImage).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .help(L(.viewMenu, lang) + " (⌘1–⌘5)")
        }
        ToolbarItem {
            TextField(L(.filter, lang), text: $state.search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
                .help("Filter every column (all terms must match)")
        }
        ToolbarItem {
            Button {
                state.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(state.isLoading)
            .help(L(.refreshNow, lang) + " (⌘R)")
        }
        ToolbarItem {
            Toggle(
                isOn: Binding(get: { state.autoRefresh }, set: { state.setAutoRefresh($0) })
            ) {
                Image(systemName: "timer")
            }
            .help(L(.toggleAutoRefresh, lang))
        }
        ToolbarItem {
            Menu {
                ForEach(PREFERENCE_INTERVALS, id: \.self) { value in
                    Button("\(Int(value)) s") { state.setInterval(value) }
                }
            } label: {
                Text("\(Int(state.interval))s")
            }
            .help(L(.intervalHelp, lang))
        }
        if !GroupField.fields(for: state.view).isEmpty {
            ToolbarItem {
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
        ToolbarItem {
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
        ToolbarItem {
            Menu {
                Button(L(.copySelected, lang)) { state.copyTable(selected: true) }
                Button(L(.copyWholeTable, lang)) { state.copyTable(selected: false) }
                Button(L(.copyJSON, lang)) { state.copyJSON() }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy")
        }
        ToolbarItem {
            Menu {
                Button(L(.exportJSON, lang)) { state.export(format: "json") }
                Button(L(.exportCSV, lang)) { state.export(format: "csv") }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export")
        }
        ToolbarItem {
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
