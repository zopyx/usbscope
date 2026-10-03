import AppKit
import SwiftUI
import UsbScopeCore
import UsbScopeUI

/// usbscope-app — the SwiftUI twin of the Python/AppKit app: the same five
/// views on top of `UsbScopeCore`, with a view switcher, live search, sortable
/// columns, a detail sheet and JSON/CSV export.

@main
struct UsbScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Now") { state.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(state.isLoading)
            }
            CommandMenu("View") {
                ForEach(Array(AppView.allCases.enumerated()), id: \.element) { index, view in
                    Button(view.title) { state.view = view }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            CommandMenu("Table") {
                Button("Copy Selected Rows") { state.copyTable(selected: true) }
                    .keyboardShortcut("c", modifiers: .command)
                Button("Copy Whole Table") { state.copyTable(selected: false) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Copy Snapshot as JSON") { state.copyJSON() }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Divider()
                Button("Show Details") {
                    if let key = state.selection.first { state.detailRowKey = key }
                }
                .keyboardShortcut("d", modifiers: .command)
                Divider()
                Button("Export JSON…") { state.export(format: "json") }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Export CSV…") { state.export(format: "csv") }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
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

struct ContentView: View {
    @EnvironmentObject private var state: AppState

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
        .sheet(isPresented: detailSheetPresented) {
            DetailSheet().environmentObject(state)
        }
        .onChange(of: state.view) { _, _ in state.selection.removeAll() }
        .onAppear {
            if state.isIdle { state.refresh() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $state.view) {
                ForEach(AppView.allCases) { view in
                    Label(view.title, systemImage: view.systemImage).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .help("Switch view (⌘1–⌘5)")
        }
        ToolbarItem {
            TextField("Filter", text: $state.search)
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
            .help("Refresh now (⌘R)")
        }
        ToolbarItem {
            Toggle(isOn: Binding(get: { state.autoRefresh }, set: { state.setAutoRefresh($0) })) {
                Image(systemName: "timer")
            }
            .help("Auto-refresh")
        }
        ToolbarItem {
            Menu {
                ForEach([2.0, 5.0, 10.0, 30.0], id: \.self) { value in
                    Button("\(Int(value)) s") { state.setInterval(value) }
                }
            } label: {
                Text("\(Int(state.interval))s")
            }
            .help("Auto-refresh interval")
        }
        ToolbarItem {
            Menu {
                Button("Selected Rows (TSV)") { state.copyTable(selected: true) }
                Button("Whole Table (TSV)") { state.copyTable(selected: false) }
                Button("Snapshot (JSON)") { state.copyJSON() }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy")
        }
        ToolbarItem {
            Menu {
                Button("Export JSON…") { state.export(format: "json") }
                Button("Export CSV…") { state.export(format: "csv") }
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
            .help("Details of the selection (⌘D)")
        }
    }

    private var detailSheetPresented: Binding<Bool> {
        Binding(
            get: { state.detailRowKey != nil },
            set: { if !$0 { state.detailRowKey = nil } }
        )
    }
}
