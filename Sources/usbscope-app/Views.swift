import SwiftUI
import UsbScopeCore
import UsbScopeUI

// MARK: - Cell rendering

/// The colour a semantic style maps to.
func styleColor(_ style: CellStyle) -> Color {
    switch style {
    case .default, .bold: .primary
    case .dim: .secondary
    case .green: .green
    case .yellow: .orange
    case .red: .red
    case .cyan: .teal
    case .magenta: .purple
    }
}

/// The colour a change highlight maps to.
func highlightColor(_ highlight: Highlight) -> Color {
    switch highlight {
    case .added: .green
    case .removed: .red
    case .changed: .orange
    }
}

/// One table cell: the styled text, optionally overridden by a row highlight.
struct CellText: View {
    let text: StyledText
    var highlight: Highlight?

    var body: some View {
        Text(text.text)
            .foregroundStyle(highlight.map(highlightColor) ?? styleColor(text.style))
            .fontWeight(text.style == .bold || highlight != nil ? .semibold : .regular)
            .lineLimit(1)
            .help(text.text)
            .accessibilityLabel(text.text)
    }
}

private extension View {
    func usbRowMenu(language: AppLanguage, show: @escaping () -> Void, copy: @escaping () -> Void,
                    identifier: @escaping () -> Void, compare: @escaping () -> Void) -> some View {
        contextMenu {
            Button(L(.showDetailsAction, language), action: show)
            Button(L(.copyRow, language), action: copy)
            Button(L(.copyIdentifier, language), action: identifier)
            Button(L(.compare, language), action: compare)
        }
    }
}

/// Centered empty state for a view without rows.
struct EmptyState: View {
    @EnvironmentObject private var state: AppState
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray").font(.largeTitle).foregroundStyle(.tertiary)
            Text(message).foregroundStyle(.secondary)
            Label(Strings.sourceHealthLabel(source: L(.sourceHealth, state.language),
                                            status: Strings.sourceStatus(state.overallSourceHealth, state.language),
                                            state.language),
                  systemImage: "waveform.path.ecg")
                .font(.caption)
                .foregroundStyle(state.overallSourceHealth == .healthy ? Color.secondary : Color.orange)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FirstRunSheet: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L(.aboutMenuTitle, state.language), systemImage: "info.circle")
                .font(.title2.bold())
            Text(L(.firstRunAbout, state.language))
            Text(L(.firstRunLocal, state.language))
            Text(L(.firstRunLimits, state.language))
            Text(L(.firstRunPrivacy, state.language))
            HStack {
                Spacer()
                Button(L(.continueAction, state.language)) { state.dismissFirstRun() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .accessibilityElement(children: .contain)
    }
}

/// Compact, persistent source status control for the main dashboard header.
struct SourceHealthControl: View {
    @EnvironmentObject private var state: AppState
    @State private var showingDetails = false

    private var status: SourceHealth { state.overallSourceHealth }

    private var statusColor: Color {
        switch status {
        case .healthy: .green
        case .partial, .stale: .orange
        case .failed: .red
        case .unsupported, .notApplicable: .secondary
        }
    }

    private var statusIcon: String {
        switch status {
        case .healthy: "checkmark.circle"
        case .partial: "exclamationmark.circle"
        case .failed: "xmark.circle"
        case .stale: "clock.badge.exclamationmark"
        case .unsupported: "questionmark.circle"
        case .notApplicable: "minus.circle"
        }
    }

    var body: some View {
        Button {
            showingDetails.toggle()
        } label: {
            Label(Strings.sourceStatus(status, state.language), systemImage: statusIcon)
                .foregroundStyle(statusColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(L(.sourceHealth, state.language)): \(Strings.sourceStatus(status, state.language))")
        .help(L(.sourceHealth, state.language))
        .popover(isPresented: $showingDetails) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L(.sourceHealth, state.language), systemImage: statusIcon)
                        .font(.headline)
                        .foregroundStyle(statusColor)
                    Spacer()
                    Text(Strings.sourceStatus(status, state.language))
                        .foregroundStyle(statusColor)
                }
                Divider()
                if state.sourceHealthRows.isEmpty {
                    Text(L(.refreshToEvaluate, state.language))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.sourceHealthRows) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(row.source).font(.body.monospaced())
                                Spacer()
                                Text(Strings.sourceStatus(row.status, state.language))
                                    .foregroundStyle(row.status == .healthy ? Color.secondary : Color.orange)
                            }
                            HStack(spacing: 12) {
                                if let duration = row.duration {
                                    Label(String(format: "%.3fs", duration), systemImage: "stopwatch")
                                }
                                if let lastSuccess = row.lastSuccess {
                                    Label(lastSuccess.formatted(date: .abbreviated, time: .shortened),
                                          systemImage: "checkmark.circle")
                                } else {
                                    Label(L(.sourceNoSuccessfulRead, state.language), systemImage: "minus.circle")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if let warning = row.warning {
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .lineLimit(3)
                            } else {
                                Text(L(.sourceWarning, state.language) + ": —")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(sourceRowAccessibilityLabel(row))
                    }
                }
            }
            .padding(16)
            .frame(width: 430)
        }
    }

    private func sourceRowAccessibilityLabel(_ row: SourceHealthRow) -> String {
        let duration = row.duration.map { String(format: "%.3fs", $0) } ?? "—"
        let lastSuccess = row.lastSuccess?.formatted(date: .abbreviated, time: .shortened)
            ?? L(.sourceNoSuccessfulRead, state.language)
        let warning = row.warning ?? "—"
        return "\(row.source), \(Strings.sourceStatus(row.status, state.language)), \(L(.sourceDuration, state.language)): \(duration), \(L(.sourceWarning, state.language)): \(warning), \(L(.sourceLastSuccess, state.language)): \(lastSuccess)"
    }
}

struct DiagnosticsSheet: View {
    @EnvironmentObject private var state: AppState
    @State private var scenario: DiagnosticScenario = .slowConnection

    private var evaluation: DiagnosticEvaluation? {
        guard let snapshot = state.snapshot else { return nil }
        return Troubleshooting.evaluate(scenario, snapshot: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L(.diagnostics, state.language), systemImage: "cross.case").font(.title2.bold())
                Spacer()
                Button(L(.copy, state.language)) { state.copyDiagnostics() }
                Button(L(.export, state.language)) { state.exportDiagnostics() }
                Button(L(.done, state.language)) { state.showDiagnostics = false }.keyboardShortcut(.cancelAction)
            }
            Divider()
            HStack {
                Text(L(.sourceHealth, state.language)).font(.headline)
                Spacer()
                Text(state.storageStatus.rawValue)
                    .foregroundStyle(state.storageStatus == .healthy ? Color.secondary : Color.orange)
            }
            ForEach(state.sourceHealth.keys.sorted(), id: \.self) { source in
                HStack(spacing: 8) {
                    Image(systemName: state.sourceHealth[source] == .healthy ? "checkmark.circle" : "exclamationmark.circle")
                    Text(source).font(.caption.monospaced())
                    Spacer()
                    Text(Strings.sourceStatus(state.sourceHealth[source] ?? .notApplicable, state.language))
                        .font(.caption)
                        .foregroundStyle(state.sourceHealth[source] == .healthy ? Color.secondary : Color.orange)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Strings.sourceHealthLabel(source: source,
                                                              status: Strings.sourceStatus(state.sourceHealth[source] ?? .notApplicable, state.language),
                                                              state.language))
            }
            Text(Strings.monitoringLabel(state.monitoringStatus, state.language))
                .font(.caption).foregroundStyle(.secondary)
            Text(Strings.freshnessLabel(state.dataFreshness.rawValue,
                                        duration: state.lastReadDuration.map { String(format: "%.2fs", $0) } ?? "—",
                                        state.language))
                .font(.caption).foregroundStyle(.secondary)
            if !state.sourceTimings.isEmpty {
                DisclosureGroup(L(.sourceTimings, state.language)) {
                    ForEach(state.sourceTimings.keys.sorted(), id: \.self) { source in
                        HStack {
                            Text(source).font(.caption.monospaced())
                            Spacer()
                            Text(String(format: "%.3fs", state.sourceTimings[source] ?? 0))
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
            }
            let warningRows = WarningPresentation.rows(state.readWarnings, language: state.language)
            if !warningRows.isEmpty {
                HStack {
                    Text(L(.warnings, state.language)).font(.headline)
                    Spacer()
                    Button(L(.copyTechnicalDetails, state.language)) { state.copyWarnings() }
                }
                ForEach(warningRows) { warning in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(Strings.warningLabel(source: warning.source, severity: warning.severity, state.language), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(Strings.warningFieldLabel(field: warning.field, message: warning.message, state.language))
                        Text(warning.remediation).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Text(L(.guidedTroubleshooting, state.language)).font(.headline)
            Picker(L(.scenario, state.language), selection: $scenario) {
                ForEach(DiagnosticScenario.allCases, id: \.self) { item in
                    Text(Strings.scenarioLabel(item, state.language)).tag(item)
                }
            }
            if let evaluation {
                Text(Strings.diagnosticSummary(evaluation.scenario, outcome: evaluation.outcome,
                                               state.language))
                ForEach(evaluation.recommendations, id: \.title) { recommendation in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Strings.diagnosticRecommendationTitle(evaluation.scenario,
                                                                    state.language))
                            .fontWeight(.semibold)
                        Text(Strings.diagnosticRecommendationAction(evaluation.scenario,
                                                                    state.language))
                        Text(Strings.evidenceLabel(recommendation.evidence.joined(separator: " · "), state.language))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(L(.refreshToEvaluate, state.language)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Warnings / data quality

struct WarningsView: View {
    @EnvironmentObject private var state: AppState

    private var rows: [WarningRow] {
        WarningPresentation.rows(state.readWarnings, language: state.language)
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                EmptyState(message: Strings.emptyMessage(for: .warnings, state.language),
                           actionTitle: L(.refreshAction, state.language)) { state.refresh() }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label(L(.warnings, state.language), systemImage: AppView.warnings.systemImage)
                            .font(.title3.bold())
                        Spacer()
                        Button(L(.copyTechnicalDetails, state.language)) { state.copyWarnings() }
                            .keyboardShortcut("c", modifiers: [.command, .shift])
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    Table(rows) {
                        TableColumn(L(.sourceHealth, state.language)) { row in
                            Text(row.source).font(.caption.monospaced())
                        }
                        TableColumn(L(.severityWarning, state.language)) { row in
                            Label(Strings.warningSeverityLabel(row.severity, state.language), systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        TableColumn(L(.capturedAt, state.language)) { _ in
                            Text(state.snapshot.map { Strings.capturedLabel($0.seenAt, state.language) }
                                 ?? Strings.freshnessStatus(.unavailable, state.language))
                                .font(.caption)
                        }
                        TableColumn(L(.warningField, state.language)) { row in Text(row.field).font(.caption.monospaced()) }
                        TableColumn(L(.warningMessage, state.language)) { row in Text(row.message).lineLimit(2) }
                        TableColumn(L(.warningRemediation, state.language)) { row in Text(row.remediation).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    .contextMenu(forSelectionType: WarningRow.ID.self) { ids in
                        if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                            Button(L(.copyTechnicalDetails, state.language)) { state.copyWarning(row.technical) }
                        }
                    }
                    .accessibilityLabel(L(.warnings, state.language))
                }
            }
        }
        .padding(.top, 2)
    }
}

struct HistoricalEventSheet: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L(.historicalDeviceEvent, state.language), systemImage: "clock.arrow.circlepath")
                .font(.title2.bold())
            if let event = state.historicalEvent {
                Text(event.name).font(.headline)
                Text(Strings.eventLabel(kind: event.kind.rawValue.capitalized,
                                        time: TimelineFormat.clock.string(from: event.seenAt), state.language))
                if let vendor = event.vendor { Text(Strings.vendorLabel(vendor, state.language)) }
                if let locationID = event.locationID { Text(Strings.locationLabel(String(locationID), state.language)) }
                Text(L(.historicalIdentity, state.language))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack { Spacer(); Button(L(.done, state.language)) { state.historicalEvent = nil }.keyboardShortcut(.cancelAction) }
        }
        .padding(24)
        .frame(width: 420, height: 240)
    }
}

struct CommandPalette: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""

    private struct Command: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let enabled: Bool
        let action: () -> Void

        init(id: String, title: String, symbol: String, enabled: Bool = true, action: @escaping () -> Void) {
            self.id = id
            self.title = title
            self.symbol = symbol
            self.enabled = enabled
            self.action = action
        }
    }

    private var commands: [Command] {
        [
            Command(id: "overview", title: L(.overview, state.language), symbol: "gauge") { state.view = .ports; state.showCommandPalette = false },
            Command(id: "ports", title: L(.of(.ports), state.language), symbol: "cable.connector") { state.view = .ports; state.showCommandPalette = false },
            Command(id: "cables", title: L(.of(.cables), state.language), symbol: "link") { state.view = .cables; state.showCommandPalette = false },
            Command(id: "devices", title: L(.of(.devices), state.language), symbol: "externaldrive.connected.to.line.below") { state.view = .devices; state.showCommandPalette = false },
            Command(id: "thunderbolt", title: L(.of(.thunderbolt), state.language), symbol: "bolt.horizontal") { state.view = .thunderbolt; state.showCommandPalette = false },
            Command(id: "power", title: L(.of(.power), state.language), symbol: "bolt.fill") { state.view = .power; state.showCommandPalette = false },
            Command(id: "security", title: L(.of(.security), state.language), symbol: "lock.shield") { state.view = .security; state.showCommandPalette = false },
            Command(id: "timeline", title: L(.of(.timeline), state.language), symbol: "chart.xyaxis.line") { state.view = .timeline; state.showCommandPalette = false },
            Command(id: "usb4", title: L(.of(.usb4), state.language), symbol: "point.3.connected.trianglepath.dotted") { state.view = .usb4; state.showCommandPalette = false },
            Command(id: "diff", title: L(.of(.diff), state.language), symbol: "arrow.left.arrow.right") { state.view = .diff; state.showCommandPalette = false },
            Command(id: "warnings", title: L(.of(.warnings), state.language), symbol: AppView.warnings.systemImage) { state.view = .warnings; state.showCommandPalette = false },
            Command(id: "refresh", title: L(.refreshNow, state.language), symbol: "arrow.clockwise") { state.showCommandPalette = false; state.refresh() },
            Command(id: "diagnostics", title: L(.diagnostics, state.language), symbol: "cross.case") { state.showCommandPalette = false; state.showDiagnostics = true },
            Command(id: "copy-diagnostics", title: L(.aboutCopy, state.language), symbol: "doc.on.doc") { state.showCommandPalette = false; state.copyDiagnostics() },
            Command(id: "export-diagnostics", title: L(.export, state.language), symbol: "square.and.arrow.up") { state.showCommandPalette = false; state.exportDiagnostics() },
            Command(id: "export-report", title: L(.exportReport, state.language), symbol: "doc.richtext",
                    enabled: state.snapshot != nil) { state.showCommandPalette = false; state.exportReport() },
            Command(id: "copy-table", title: L(.copyWholeTable, state.language), symbol: "tablecells",
                    enabled: state.snapshot != nil) { state.showCommandPalette = false; state.copyTable(selected: false) },
            Command(id: "copy-selected", title: L(.copySelected, state.language), symbol: "checkmark.rectangle.stack",
                    enabled: !state.selection.isEmpty) { state.showCommandPalette = false; state.copyTable(selected: true) },
            Command(id: "show-details", title: L(.showDetails, state.language), symbol: "info.circle",
                    enabled: !state.selection.isEmpty) {
                state.showCommandPalette = false
                state.detailRowKey = state.selection.first
            },
            Command(id: "export-json", title: L(.exportJSON, state.language), symbol: "curlybraces",
                    enabled: state.snapshot != nil) { state.showCommandPalette = false; state.export(format: .json) },
            Command(id: "export-csv", title: L(.exportCSV, state.language), symbol: "tablecells",
                    enabled: state.snapshot != nil) { state.showCommandPalette = false; state.export(format: .csv) },
            Command(id: "save-baseline", title: L(.saveBaseline, state.language), symbol: "externaldrive.badge.timemachine",
                    enabled: state.snapshot != nil) { state.showCommandPalette = false; state.saveBaseline() },
            Command(id: "load-baseline", title: L(.loadBaseline, state.language), symbol: "folder") { state.showCommandPalette = false; state.pickBaseline() },
            Command(id: "clear-baseline", title: L(.clearBaselineAction, state.language), symbol: "trash",
                    enabled: state.baseline != nil) { state.showCommandPalette = false; state.clearBaseline() },
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L(.commandPalette, state.language), text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { filtered.first?.action() }
                Button(L(.done, state.language)) { state.showCommandPalette = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            List(filtered) { command in
                Button { command.action() } label: {
                    Label(command.title, systemImage: command.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(!command.enabled)
                .buttonStyle(.plain)
                .padding(.vertical, 5)
            }
        }
        .frame(width: 460, height: 420)
    }

    private var filtered: [Command] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return commands }
        return commands.filter { $0.title.lowercased().contains(needle) }
    }
}

/// Shown while the first read of a session is running (the idle→loading step
/// of the three-state UI).
struct LoadingView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(L(.loading, state.language)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A section header for the grouped list rendering: the bucket title and count.
struct GroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text(verbatim: String(count)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - The five views

struct PortsView: View {
    @EnvironmentObject private var state: AppState
    @State private var sortOrder = [KeyPathComparator(\PortRow.nameSort)]

    var body: some View {
        if let snapshot = state.snapshot {
            let rows = state.filtered(portRows(snapshot, changes: state.changes, language: state.language))
            if state.groupField == .none {
                table(rows)
            } else {
                grouped(rows)
            }
        } else {
            LoadingView()
        }
    }

    @ViewBuilder
    private func table(_ rows: [PortRow]) -> some View {
        Table(rows, selection: $state.selection, sortOrder: $sortOrder) {
            if state.isColumnVisible(.ports, "Port") {
                TableColumn(Strings.columnLabel("Port", state.language), value: \.nameSort) { row in
                    CellText(text: row.name, highlight: row.highlight)
                        .usbRowMenu(language: state.language, show: { state.detailRowKey = row.id }, copy: { state.copyRow(row.id) },
                                    identifier: { state.copyIdentifier(row.id) }, compare: { state.view = .diff })
                }
                    .width(min: 90, ideal: 110)
            }
            if state.isColumnVisible(.ports, "Type") {
                TableColumn(Strings.columnLabel("Type", state.language), value: \.kindSort) { CellText(text: $0.kind) }
                    .width(min: 70, ideal: 90)
            }
            if state.isColumnVisible(.ports, "State") {
                TableColumn(Strings.columnLabel("State", state.language), value: \.stateSort) { CellText(text: $0.state) }
                    .width(min: 90, ideal: 110)
            }
            if state.isColumnVisible(.ports, "Mode") {
                TableColumn(Strings.columnLabel("Mode", state.language), value: \.modeSort) { CellText(text: $0.mode) }
                    .width(min: 160, ideal: 210)
            }
            if state.isColumnVisible(.ports, "Transports") {
                TableColumn(Strings.columnLabel("Transports", state.language), value: \.transportsSort) { CellText(text: $0.transports) }
                    .width(min: 120, ideal: 240)
            }
            if state.isColumnVisible(.ports, "Cable") {
                TableColumn(Strings.columnLabel("Cable", state.language), value: \.cableSort) { CellText(text: $0.cable) }
                    .width(min: 70, ideal: 90)
            }
            if state.isColumnVisible(.ports, "Notes") {
                TableColumn(Strings.columnLabel("Notes", state.language), value: \.notesSort) { CellText(text: $0.notes) }
                    .width(min: 160, ideal: 320)
            }
        }
        .overlay {
            if rows.isEmpty {
                EmptyState(message: Strings.emptyMessage(for: .ports, state.language),
                           actionTitle: L(.refreshNow, state.language), action: state.refresh)
            }
        }
        .onAppear { sortOrder = TableSortPersistence.ports(state.sortPreference(for: .ports)) }
        .onChange(of: sortOrder) { _, newValue in
            if let first = newValue.first {
                state.setSortPreference(for: .ports, key: TableSortPersistence.portKey(first),
                                        ascending: first.order == .forward)
            }
        }
    }

    private func grouped(_ rows: [PortRow]) -> some View {
        let sections = groups(for: rows, by: state.groupField, language: state.language)
        return List(selection: $state.selection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        HStack(spacing: 12) {
                            CellText(text: row.name, highlight: row.highlight)
                                .frame(width: 110, alignment: .leading)
                            CellText(text: row.state).frame(width: 100, alignment: .leading)
                            CellText(text: row.mode).frame(width: 190, alignment: .leading)
                            CellText(text: row.notes)
                            Spacer(minLength: 0)
                        }
                        .tag(row.id)
                    }
                } header: {
                    GroupHeader(title: section.title, count: section.rows.count)
                }
            }
        }
        .overlay {
            if rows.isEmpty {
                EmptyState(message: Strings.emptyMessage(for: .ports, state.language),
                           actionTitle: L(.refreshNow, state.language), action: state.refresh)
            }
        }
    }
}

struct CablesView: View {
    @EnvironmentObject private var state: AppState
    @State private var sortOrder = [KeyPathComparator(\CableRow.portSort)]

    var body: some View {
        if let snapshot = state.snapshot {
            let rows = state.filtered(cableRows(snapshot, changes: state.changes, language: state.language))
            Table(rows, selection: $state.selection, sortOrder: $sortOrder) {
                if state.isColumnVisible(.cables, "Port") {
                    TableColumn(Strings.columnLabel("Port", state.language), value: \.portSort) { row in
                        CellText(text: row.port, highlight: row.highlight)
                            .usbRowMenu(language: state.language, show: { state.detailRowKey = row.id }, copy: { state.copyRow(row.id) },
                                        identifier: { state.copyIdentifier(row.id) }, compare: { state.view = .diff })
                    }
                        .width(min: 90, ideal: 110)
                }
                if state.isColumnVisible(.cables, "Cable") {
                    TableColumn(Strings.columnLabel("Cable", state.language), value: \.cableSort) { CellText(text: $0.cable) }
                        .width(min: 70, ideal: 100)
                }
                if state.isColumnVisible(.cables, "CC authentication") {
                    TableColumn(Strings.columnLabel("CC authentication", state.language), value: \.authenticationSort) { CellText(text: $0.authentication) }
                        .width(min: 110, ideal: 150)
                }
                if state.isColumnVisible(.cables, "Hash (CC / USB)") {
                    TableColumn(Strings.columnLabel("Hash (CC / USB)", state.language), value: \.hashSort) { CellText(text: $0.hash) }
                        .width(min: 110, ideal: 150)
                }
                if state.isColumnVisible(.cables, "PD spec") {
                    TableColumn(Strings.columnLabel("PD spec", state.language), value: \.specSort) { CellText(text: $0.spec) }
                        .width(min: 60, ideal: 70)
                }
                if state.isColumnVisible(.cables, "Power in") {
                    TableColumn(Strings.columnLabel("Power in", state.language), value: \.powerSort) { CellText(text: $0.powerIn) }
                        .width(min: 100, ideal: 200)
                }
                if state.isColumnVisible(.cables, "Contract") {
                    TableColumn(Strings.columnLabel("Contract", state.language), value: \.contractSort) { CellText(text: $0.contract) }
                        .width(min: 100, ideal: 160)
                }
                if state.isColumnVisible(.cables, "Liquid") {
                    TableColumn(Strings.columnLabel("Liquid", state.language), value: \.liquidSort) { CellText(text: $0.liquid) }
                        .width(min: 60, ideal: 80)
                }
                if state.isColumnVisible(.cables, "Controller fw") {
                    TableColumn(Strings.columnLabel("Controller fw", state.language), value: \.firmwareSort) { CellText(text: $0.firmware) }
                        .width(min: 90, ideal: 120)
                }
            }
            .overlay {
                if rows.isEmpty {
                    EmptyState(message: Strings.emptyMessage(for: .cables, state.language),
                               actionTitle: L(.refreshNow, state.language), action: state.refresh)
                }
            }
            .onAppear { sortOrder = TableSortPersistence.cables(state.sortPreference(for: .cables)) }
            .onChange(of: sortOrder) { _, newValue in
                if let first = newValue.first {
                    state.setSortPreference(for: .cables, key: TableSortPersistence.cableKey(first),
                                            ascending: first.order == .forward)
                }
            }
        } else {
            LoadingView()
        }
    }
}

struct DevicesView: View {
    @EnvironmentObject private var state: AppState
    @State private var sortOrder = [KeyPathComparator(\DeviceRow.nameSort)]

    var body: some View {
        if let snapshot = state.snapshot {
            let rows = state.filtered(deviceRows(snapshot, changes: state.changes, language: state.language))
            if state.groupField == .none {
                table(rows)
            } else {
                grouped(rows)
            }
        } else {
            LoadingView()
        }
    }

    @ViewBuilder
    private func table(_ rows: [DeviceRow]) -> some View {
        Table(rows, selection: $state.selection, sortOrder: $sortOrder) {
            if state.isColumnVisible(.devices, "Device") {
                TableColumn(Strings.columnLabel("Device", state.language), value: \.nameSort) { row in
                    CellText(text: row.name, highlight: row.highlight)
                    .usbRowMenu(language: state.language, show: { state.detailRowKey = row.id }, copy: { state.copyRow(row.id) },
                                    identifier: { state.copyIdentifier(row.id) }, compare: { state.view = .diff })
                }
                    .width(min: 140, ideal: 260)
            }
            if state.isColumnVisible(.devices, "Vendor") {
                TableColumn(Strings.columnLabel("Vendor", state.language), value: \.vendorSort) { CellText(text: $0.vendor) }
                    .width(min: 90, ideal: 130)
            }
            if state.isColumnVisible(.devices, "VID:PID") {
                TableColumn(Strings.columnLabel("VID:PID", state.language), value: \.idSort) { CellText(text: $0.idString) }
                    .width(min: 90, ideal: 110)
            }
            if state.isColumnVisible(.devices, "Mode") {
                TableColumn(Strings.columnLabel("Mode", state.language), value: \.modeSort) { CellText(text: $0.mode) }
                    .width(min: 150, ideal: 200)
            }
            if state.isColumnVisible(.devices, "Class") {
                TableColumn(Strings.columnLabel("Class", state.language), value: \.classSort) { CellText(text: $0.deviceClass) }
                    .width(min: 110, ideal: 150)
            }
            if state.isColumnVisible(.devices, "Tier") {
                TableColumn(Strings.columnLabel("Tier", state.language), value: \.tierSort) { CellText(text: $0.tier) }
                    .width(min: 40, ideal: 50)
            }
            if state.isColumnVisible(.devices, "Port") {
                TableColumn(Strings.columnLabel("Port", state.language), value: \.portSort) { CellText(text: $0.port) }
                    .width(min: 80, ideal: 100)
            }
            if state.isColumnVisible(.devices, "Transport") {
                TableColumn(Strings.columnLabel("Transport", state.language), value: \.transportSort) { CellText(text: $0.transport) }
                    .width(min: 80, ideal: 100)
            }
            if state.isColumnVisible(.devices, "Serial") {
                TableColumn(Strings.columnLabel("Serial", state.language), value: \.serialSort) { CellText(text: $0.serial) }
                    .width(min: 90, ideal: 140)
            }
            if state.isColumnVisible(.devices, "Restricted") {
                TableColumn(Strings.columnLabel("Restricted", state.language), value: \.restrictedSort) { CellText(text: $0.restricted) }
                    .width(min: 70, ideal: 90)
            }
        }
        .overlay {
            if rows.isEmpty {
                EmptyState(message: Strings.emptyMessage(for: .devices, state.language),
                           actionTitle: L(.refreshNow, state.language), action: state.refresh)
            }
        }
        .onAppear { sortOrder = TableSortPersistence.devices(state.sortPreference(for: .devices)) }
        .onChange(of: sortOrder) { _, newValue in
            if let first = newValue.first {
                state.setSortPreference(for: .devices, key: TableSortPersistence.deviceKey(first),
                                        ascending: first.order == .forward)
            }
        }
    }

    private func grouped(_ rows: [DeviceRow]) -> some View {
        let sections = groups(for: rows, by: state.groupField, language: state.language)
        return List(selection: $state.selection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        HStack(spacing: 12) {
                            CellText(text: row.name, highlight: row.highlight)
                                .frame(width: 220, alignment: .leading)
                            CellText(text: row.vendor).frame(width: 130, alignment: .leading)
                            CellText(text: row.idString).frame(width: 110, alignment: .leading)
                            CellText(text: row.mode).frame(width: 190, alignment: .leading)
                            CellText(text: row.deviceClass)
                            Spacer(minLength: 0)
                        }
                        .tag(row.id)
                    }
                } header: {
                    GroupHeader(title: section.title, count: section.rows.count)
                }
            }
        }
        .overlay {
            if rows.isEmpty {
                EmptyState(message: Strings.emptyMessage(for: .devices, state.language),
                           actionTitle: L(.refreshNow, state.language), action: state.refresh)
            }
        }
    }
}

struct ThunderboltView: View {
    @EnvironmentObject private var state: AppState
    @State private var sortOrder = [KeyPathComparator(\ThunderboltRow.busSort)]

    var body: some View {
        if let snapshot = state.snapshot {
            let rows = state.filtered(thunderboltRows(snapshot, language: state.language))
            Table(rows, selection: $state.selection, sortOrder: $sortOrder) {
                if state.isColumnVisible(.thunderbolt, "Bus") {
                    TableColumn(Strings.columnLabel("Bus", state.language), value: \.busSort) { row in
                        CellText(text: row.bus)
                        .usbRowMenu(language: state.language, show: { state.detailRowKey = row.id }, copy: { state.copyRow(row.id) },
                                        identifier: { state.copyIdentifier(row.id) }, compare: { state.view = .diff })
                    }
                        .width(min: 140, ideal: 200)
                }
                if state.isColumnVisible(.thunderbolt, "Receptacle") {
                    TableColumn(Strings.columnLabel("Receptacle", state.language), value: \.receptacleSort) { CellText(text: $0.receptacle) }
                        .width(min: 70, ideal: 100)
                }
                if state.isColumnVisible(.thunderbolt, "State") {
                    TableColumn(Strings.columnLabel("State", state.language), value: \.stateSort) { CellText(text: $0.state) }
                        .width(min: 90, ideal: 110)
                }
                if state.isColumnVisible(.thunderbolt, "Link") {
                    TableColumn(Strings.columnLabel("Link", state.language), value: \.linkSort) { CellText(text: $0.link) }
                        .width(min: 90, ideal: 140)
                }
                if state.isColumnVisible(.thunderbolt, "Host / vendor") {
                    TableColumn(Strings.columnLabel("Host / vendor", state.language), value: \.hostSort) { CellText(text: $0.host) }
                        .width(min: 120, ideal: 200)
                }
            }
            .overlay {
                if rows.isEmpty {
                    EmptyState(message: Strings.emptyMessage(for: .thunderbolt, state.language),
                               actionTitle: L(.refreshNow, state.language), action: state.refresh)
                }
            }
            .onAppear { sortOrder = TableSortPersistence.thunderbolt(state.sortPreference(for: .thunderbolt)) }
            .onChange(of: sortOrder) { _, newValue in
                if let first = newValue.first {
                    state.setSortPreference(for: .thunderbolt, key: TableSortPersistence.thunderboltKey(first),
                                            ascending: first.order == .forward)
                }
            }
        } else {
            LoadingView()
        }
    }
}

struct PowerView: View {
    @EnvironmentObject private var state: AppState
    @State private var sortOrder = [KeyPathComparator(\PowerRow.metricSort)]

    var body: some View {
        if let snapshot = state.snapshot {
            let rows = state.filtered(powerRows(snapshot, language: state.language))
            Table(rows, selection: $state.selection, sortOrder: $sortOrder) {
                if state.isColumnVisible(.power, "Metric") {
                    TableColumn(Strings.columnLabel("Metric", state.language)) { CellText(text: $0.metric) }
                        .width(min: 140, ideal: 220)
                }
                if state.isColumnVisible(.power, "Value") {
                    TableColumn(Strings.columnLabel("Value", state.language)) { CellText(text: $0.value) }
                        .width(min: 200, ideal: 340)
                }
            }
            .overlay {
                if rows.isEmpty {
                    EmptyState(message: Strings.emptyMessage(for: .power, state.language),
                               actionTitle: L(.refreshNow, state.language), action: state.refresh)
                }
            }
            .onAppear { sortOrder = TableSortPersistence.power(state.sortPreference(for: .power)) }
            .onChange(of: sortOrder) { _, newValue in
                if let first = newValue.first {
                    state.setSortPreference(for: .power, key: TableSortPersistence.powerKey(first),
                                            ascending: first.order == .forward)
                }
            }
        } else {
            LoadingView()
        }
    }
}

// MARK: - Timeline

/// The Timeline tab: the charging watts over time (`AppState.powerTimeline`)
/// as a sparkline drawn with `Canvas`, and the hotplug events of the
/// `EventLog`, newest first. No third-party chart library.
struct TimelineView: View {
    @EnvironmentObject private var state: AppState

    private var lang: AppLanguage { state.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            powerSection
            Divider()
            eventsSection
        }
    }

    private var powerSection: some View {
        let geometry = state.timelineGeometry
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L(.timelinePowerTitle, lang)).font(.headline)
                Spacer()
                if let range = geometry.rangeText {
                    Text(range).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if geometry.isEmpty {
                Text(L(.timelineNoPower, lang))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                Canvas { context, size in
                    drawSparkline(geometry, context: &context, size: size)
                }
                .frame(height: 150)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                .accessibilityLabel(L(.chargingPowerChart, lang))
                .accessibilityValue(geometry.rangeText ?? L(.noMeasuredValues, lang))
                if let times = geometry.timeRangeText() {
                    Text(times).font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup(L(.timelineValues, lang)) {
                    ForEach(Array(state.powerTimeline.enumerated()), id: \.offset) { _, point in
                        let time = TimelineFormat.clock.string(from: point.at)
                        let measured = point.watts.map { String(format: "%.2f W", $0) } ?? "—"
                        HStack {
                            Text(time).monospacedDigit()
                            Spacer()
                            Text(measured).monospacedDigit()
                            if let stateOfCharge = point.stateOfCharge {
                                Text(verbatim: "\(stateOfCharge)%").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(time), \(measured)")
                    }
                }
                .font(.caption)
            }
        }
        .padding(12)
    }

    /// The sparkline: a line through the measured points plus a dot each.
    private func drawSparkline(_ geometry: TimelineGeometry, context: inout GraphicsContext, size: CGSize) {
        let inset: CGFloat = 12
        let plot = CGRect(
            x: inset, y: inset,
            width: max(size.width - 2 * inset, 1), height: max(size.height - 2 * inset, 1)
        )
        func position(_ point: (x: Double, y: Double)) -> CGPoint {
            CGPoint(x: plot.minX + CGFloat(point.x) * plot.width, y: plot.maxY - CGFloat(point.y) * plot.height)
        }
        var line = Path()
        for (index, point) in geometry.unitPoints.enumerated() {
            let spot = position(point)
            if index == 0 { line.move(to: spot) } else { line.addLine(to: spot) }
        }
        context.stroke(line, with: .color(.accentColor), lineWidth: 2)
        for point in geometry.unitPoints {
            let spot = position(point)
            context.fill(
                Path(ellipseIn: CGRect(x: spot.x - 2.5, y: spot.y - 2.5, width: 5, height: 5)),
                with: .color(.accentColor)
            )
        }
    }

    private var eventsSection: some View {
        let rows = state.hotplugRows
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L(.timelineEventsTitle, lang)).font(.headline)
                Spacer()
                Text(verbatim: String(rows.count)).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
            if rows.isEmpty {
                Text(L(.timelineNoEvents, lang)).foregroundStyle(.secondary).padding(12)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(rows) { row in
                            Button {
                                state.openEvent(row)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(row.time).monospacedDigit().foregroundStyle(.secondary)
                                        .frame(width: 70, alignment: .leading)
                                    Text(row.kind)
                                        .foregroundStyle(row.isAttach ? Color.green : Color.red)
                                        .frame(width: 72, alignment: .leading)
                                    Text(row.name).fontWeight(.semibold)
                                    Text(row.detail).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityHint(L(.showDevice, lang))
                            .contextMenu {
                                Button(L(.showDevice, lang)) { state.openEvent(row) }
                                Button(L(.copyIdentifier, lang)) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(row.key, forType: .string)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Security

/// The Security tab: `Security.analyse` on the current snapshot (severity badge,
/// rule, subject, why) plus the USB storage inventory with its Eject buttons and
/// the CLI's honest "what this is NOT" note.
struct SecurityView: View {
    @EnvironmentObject private var state: AppState

    private var lang: AppLanguage { state.language }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                countsBlock
                findingsBlock
                storageBlock
                Text(L(.securityHonestLimits, lang)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var countsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let report = state.securityReport {
                ForEach(SecurityPresentation.counts(report), id: \.label) { item in
                    HStack {
                        Text(Strings.securitySeverity(item.label.lowercased(), lang))
                            .foregroundStyle(styleColor(item.style)).fontWeight(.semibold)
                        Spacer()
                        Text(verbatim: String(item.count)).monospacedDigit()
                    }
                    .frame(maxWidth: 320)
                    .accessibilityElement(children: .combine)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            Text(L(.securityHeadline, lang)).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var findingsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(.securityFindingsTitle, lang)).font(.headline)
            if let report = state.securityReport, !report.isEmpty {
                ForEach(SecurityPresentation.findingRows(report)) { row in
                    findingView(row)
                }
            } else {
                Text(L(.securityEmptyFindings, lang)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var storageBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(.securityStorageTitle, lang)).font(.headline)
            let storageReadFailed = state.storageStatus == .failed
                || state.storageStatus == .partial
                || state.storageStatus == .stale
            if storageReadFailed {
                let status = state.storageStatus
                Label(status == .failed ? L(.storageUnavailable, lang) : L(.storagePartial, lang),
                      systemImage: status == .failed ? "xmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(status == .failed ? Color.red : Color.orange)
                    .accessibilityValue(Strings.sourceStatus(status, lang))
                ForEach(state.readWarnings.filter { $0.hasPrefix("storage:") }, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            if state.storageInventory.isEmpty {
                if !storageReadFailed {
                    Text(L(.securityEmptyStorage, lang)).foregroundStyle(.secondary)
                } else {
                    Button(L(.refreshNow, lang)) { state.refresh() }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                ForEach(state.storageInventory) { row in storageView(row) }
            }
            if let message = state.ejectMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func findingView(_ row: FindingRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(Strings.securitySeverity(row.severity, lang))
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(styleColor(row.severityStyle).opacity(0.18), in: Capsule())
                    .foregroundStyle(styleColor(row.severityStyle))
                Text(row.rule).font(.system(.body, design: .monospaced))
                Spacer()
                Text(row.subject).foregroundStyle(.secondary)
            }
            Text(row.detail).font(.callout)
            if row.port != nil || row.device != nil || row.locationID != nil {
                Button(L(.openSourceRow, lang)) { state.openFinding(row) }
                    .buttonStyle(.link)
                    .accessibilityHint(L(.observationHint, lang))
            }
            if !row.evidence.isEmpty {
                DisclosureGroup(L(.evidence, state.language)) {
                    ForEach(row.evidence.keys.sorted(), id: \.self) { key in
                        HStack(alignment: .top, spacing: 6) {
                            Text(key).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(row.evidence[key] ?? "")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Strings.findingAccessibilityLabel(severity: row.severity, rule: row.rule,
                                                              subject: row.subject, detail: row.detail, lang))
        .contextMenu {
            Button(L(.openSourceRow, lang)) { state.openFinding(row) }
            Button(L(.copyTechnicalDetails, lang)) {
                state.copyIdentifier(row.device ?? row.port ?? row.subject)
            }
            Button(L(.compare, lang)) { state.view = .diff }
        }
    }

    private func storageView(_ row: StorageRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(row.identifier) · \(row.name)").fontWeight(.semibold)
                Text(verbatim: "\(row.capacity) · \(row.mode) · \(row.mount)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if state.ejecting == row.id {
                ProgressView().controlSize(.small)
            }
            Button(L(.eject, lang)) { state.confirmEject(row) }
                .disabled(!row.ejectEnabled || state.ejecting != nil)
                .help(row.ejectReason ?? L(.eject, lang))
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(L(.copyIdentifier, lang)) { state.copyIdentifier(row.identifier) }
            Button(L(.eject, lang)) { state.confirmEject(row) }
                .disabled(!row.ejectEnabled || state.ejecting != nil)
        }
    }
}

// MARK: - USB4 / Thunderbolt fabric

/// The USB4 tab: the routers → ports → tunnels tree of `ioreg -c
/// IOThunderboltSwitch`, with the raw link speed/width values and the note that
/// they are raw enumerations.
struct Usb4View: View {
    @EnvironmentObject private var state: AppState

    private var lang: AppLanguage { state.language }

    private var fabric: ThunderboltFabric { state.snapshot?.thunderboltFabric ?? ThunderboltFabric() }

    var body: some View {
        let rows = state.fabricRows
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L(.usb4Title, lang)).font(.headline)
                Spacer()
                Text(FabricPresentation.summary(fabric)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
            if rows.isEmpty {
                EmptyState(message: Strings.emptyMessage(for: .usb4, lang),
                           actionTitle: L(.refreshNow, lang), action: state.refresh)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(rows) { row in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: symbol(for: row.kind))
                                    .frame(width: 18)
                                    .foregroundStyle(color(for: row.kind))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).fontWeight(row.kind == .router ? .semibold : .regular)
                                    if !row.detail.isEmpty {
                                        Text(row.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let raw = row.rawLink {
                                        Text(raw).font(.system(.caption, design: .monospaced)).foregroundStyle(.teal)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.leading, CGFloat(row.depth) * 18)
                            .padding(.vertical, 1)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(
                                [row.title, row.detail, row.rawLink].compactMap { $0 }.filter { !$0.isEmpty }
                                    .joined(separator: ", ")
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(FabricPresentation.rawLinkNote)
                    .font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
    }

    private func symbol(for kind: FabricRowKind) -> String {
        switch kind {
        case .router: "cpu"
        case .port: "cable.connector"
        case .tunnel: "arrow.turn.down.right"
        }
    }

    private func color(for kind: FabricRowKind) -> Color {
        switch kind {
        case .router: .purple
        case .port: .teal
        case .tunnel: .green
        }
    }
}

// MARK: - Diff / baseline

/// The Diff tab: pick a snapshot JSON (e.g. one written by `usbscope baseline
/// save`), then show what appeared, disappeared and changed against the live
/// machine via `diffSnapshots`.
struct DiffView: View {
    @EnvironmentObject private var state: AppState

    private var lang: AppLanguage { state.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(L(.compareWith, lang)) { state.pickBaseline() }
                Button(L(.exportJSON, lang)) { state.export(format: .json) }
                Button(L(.clearBaseline, lang)) { state.clearBaseline() }
                    .disabled(state.baseline == nil)
                Spacer()
                if let name = state.baselineName {
                    Label(name, systemImage: "doc").foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(12)
            Divider()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = state.baselineError {
            Text(error).foregroundStyle(.orange).padding(12)
            Spacer(minLength: 0)
        } else if let changes = state.baselineDiff {
            let rows = DiffPresentation.rows(changes)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 18) {
                    ForEach(DiffPresentation.counts(changes), id: \.kind) { item in
                        HStack(spacing: 5) {
                            Circle().fill(highlightColor(highlightFor(item.kind))).frame(width: 8, height: 8)
                            Text(verbatim: "\(item.count) \(L(.of(item.kind), lang))").monospacedDigit()
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                Divider()
                if rows.isEmpty {
                    Text(L(.diffNoChanges, lang))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(rows) { row in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(L(.of(row.kind), lang))
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundStyle(highlightColor(highlightFor(row.kind)))
                                        .frame(width: 92, alignment: .leading)
                                    Text(row.item).fontWeight(.semibold)
                                    Text(row.detail).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right").font(.largeTitle).foregroundStyle(.tertiary)
                Text(L(.baselineNone, lang)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func highlightFor(_ kind: DiffChangeKind) -> Highlight {
        switch kind {
        case .appeared: .added
        case .disappeared: .removed
        case .changed: .changed
        }
    }
}

// MARK: - Detail sheet

struct DetailSheet: View {
    @EnvironmentObject private var state: AppState

    private func explanation(for label: String) -> String? {
        Strings.detailExplanation(for: label, state.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L(.showDetails, state.language)).font(.headline)
                Spacer()
                Button(L(.done, state.language)) { state.detailRowKey = nil }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            ScrollView {
                let pairs = state.detailPairs
                if pairs.isEmpty {
                    Text(L(.noDetails, state.language)).foregroundStyle(.secondary).padding()
                } else {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                        ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                            GridRow {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(pair.0).foregroundStyle(.secondary)
                                    if let help = explanation(for: pair.0) {
                                        Text(help).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .gridColumnAlignment(.leading)
                                Text(pair.1).textSelection(.enabled)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }
}
