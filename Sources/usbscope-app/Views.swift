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
    }
}

/// Centered empty state for a view without rows.
struct EmptyState: View {
    let message: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray").font(.largeTitle).foregroundStyle(.tertiary)
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
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
            let rows = state.filtered(portRows(snapshot, changes: state.changes))
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
                TableColumn("Port", value: \.nameSort) { CellText(text: $0.name, highlight: $0.highlight) }
                    .width(min: 90, ideal: 110)
            }
            if state.isColumnVisible(.ports, "Type") {
                TableColumn("Type", value: \.kindSort) { CellText(text: $0.kind) }
                    .width(min: 70, ideal: 90)
            }
            if state.isColumnVisible(.ports, "State") {
                TableColumn("State", value: \.stateSort) { CellText(text: $0.state) }
                    .width(min: 90, ideal: 110)
            }
            if state.isColumnVisible(.ports, "Mode") {
                TableColumn("Mode", value: \.modeSort) { CellText(text: $0.mode) }
                    .width(min: 160, ideal: 210)
            }
            if state.isColumnVisible(.ports, "Transports") {
                TableColumn("Transports", value: \.transportsSort) { CellText(text: $0.transports) }
                    .width(min: 120, ideal: 240)
            }
            if state.isColumnVisible(.ports, "Cable") {
                TableColumn("Cable", value: \.cableSort) { CellText(text: $0.cable) }
                    .width(min: 70, ideal: 90)
            }
            if state.isColumnVisible(.ports, "Notes") {
                TableColumn("Notes", value: \.notesSort) { CellText(text: $0.notes) }
                    .width(min: 160, ideal: 320)
            }
        }
        .overlay { if rows.isEmpty { EmptyState(message: emptyMessage(for: .ports)) } }
    }

    private func grouped(_ rows: [PortRow]) -> some View {
        let sections = groups(for: rows, by: state.groupField)
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
        .overlay { if rows.isEmpty { EmptyState(message: emptyMessage(for: .ports)) } }
    }
}

struct CablesView: View {
    @EnvironmentObject private var state: AppState
    @State private var sortOrder = [KeyPathComparator(\CableRow.portSort)]

    var body: some View {
        if let snapshot = state.snapshot {
            let rows = state.filtered(cableRows(snapshot, changes: state.changes))
            Table(rows, selection: $state.selection, sortOrder: $sortOrder) {
                if state.isColumnVisible(.cables, "Port") {
                    TableColumn("Port", value: \.portSort) { CellText(text: $0.port, highlight: $0.highlight) }
                        .width(min: 90, ideal: 110)
                }
                if state.isColumnVisible(.cables, "Cable") {
                    TableColumn("Cable", value: \.cableSort) { CellText(text: $0.cable) }
                        .width(min: 70, ideal: 100)
                }
                if state.isColumnVisible(.cables, "CC authentication") {
                    TableColumn("CC authentication", value: \.authenticationSort) { CellText(text: $0.authentication) }
                        .width(min: 110, ideal: 150)
                }
                if state.isColumnVisible(.cables, "Hash (CC / USB)") {
                    TableColumn("Hash (CC / USB)", value: \.hashSort) { CellText(text: $0.hash) }
                        .width(min: 110, ideal: 150)
                }
                if state.isColumnVisible(.cables, "PD spec") {
                    TableColumn("PD spec", value: \.specSort) { CellText(text: $0.spec) }
                        .width(min: 60, ideal: 70)
                }
                if state.isColumnVisible(.cables, "Power in") {
                    TableColumn("Power in", value: \.powerSort) { CellText(text: $0.powerIn) }
                        .width(min: 100, ideal: 200)
                }
                if state.isColumnVisible(.cables, "Contract") {
                    TableColumn("Contract", value: \.contractSort) { CellText(text: $0.contract) }
                        .width(min: 100, ideal: 160)
                }
                if state.isColumnVisible(.cables, "Liquid") {
                    TableColumn("Liquid", value: \.liquidSort) { CellText(text: $0.liquid) }
                        .width(min: 60, ideal: 80)
                }
                if state.isColumnVisible(.cables, "Controller fw") {
                    TableColumn("Controller fw", value: \.firmwareSort) { CellText(text: $0.firmware) }
                        .width(min: 90, ideal: 120)
                }
            }
            .overlay { if rows.isEmpty { EmptyState(message: emptyMessage(for: .cables)) } }
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
            let rows = state.filtered(deviceRows(snapshot, changes: state.changes))
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
                TableColumn("Device", value: \.nameSort) { CellText(text: $0.name, highlight: $0.highlight) }
                    .width(min: 140, ideal: 260)
            }
            if state.isColumnVisible(.devices, "Vendor") {
                TableColumn("Vendor", value: \.vendorSort) { CellText(text: $0.vendor) }
                    .width(min: 90, ideal: 130)
            }
            if state.isColumnVisible(.devices, "VID:PID") {
                TableColumn("VID:PID", value: \.idSort) { CellText(text: $0.idString) }
                    .width(min: 90, ideal: 110)
            }
            if state.isColumnVisible(.devices, "Mode") {
                TableColumn("Mode", value: \.modeSort) { CellText(text: $0.mode) }
                    .width(min: 150, ideal: 200)
            }
            if state.isColumnVisible(.devices, "Class") {
                TableColumn("Class", value: \.classSort) { CellText(text: $0.deviceClass) }
                    .width(min: 110, ideal: 150)
            }
            if state.isColumnVisible(.devices, "Tier") {
                TableColumn("Tier", value: \.tierSort) { CellText(text: $0.tier) }
                    .width(min: 40, ideal: 50)
            }
            if state.isColumnVisible(.devices, "Port") {
                TableColumn("Port", value: \.portSort) { CellText(text: $0.port) }
                    .width(min: 80, ideal: 100)
            }
            if state.isColumnVisible(.devices, "Transport") {
                TableColumn("Transport", value: \.transportSort) { CellText(text: $0.transport) }
                    .width(min: 80, ideal: 100)
            }
            if state.isColumnVisible(.devices, "Serial") {
                TableColumn("Serial", value: \.serialSort) { CellText(text: $0.serial) }
                    .width(min: 90, ideal: 140)
            }
            if state.isColumnVisible(.devices, "Restricted") {
                TableColumn("Restricted", value: \.restrictedSort) { CellText(text: $0.restricted) }
                    .width(min: 70, ideal: 90)
            }
        }
        .overlay { if rows.isEmpty { EmptyState(message: emptyMessage(for: .devices)) } }
    }

    private func grouped(_ rows: [DeviceRow]) -> some View {
        let sections = groups(for: rows, by: state.groupField)
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
        .overlay { if rows.isEmpty { EmptyState(message: emptyMessage(for: .devices)) } }
    }
}

struct ThunderboltView: View {
    @EnvironmentObject private var state: AppState
    @State private var sortOrder = [KeyPathComparator(\ThunderboltRow.busSort)]

    var body: some View {
        if let snapshot = state.snapshot {
            let rows = state.filtered(thunderboltRows(snapshot))
            Table(rows, selection: $state.selection, sortOrder: $sortOrder) {
                if state.isColumnVisible(.thunderbolt, "Bus") {
                    TableColumn("Bus", value: \.busSort) { CellText(text: $0.bus) }
                        .width(min: 140, ideal: 200)
                }
                if state.isColumnVisible(.thunderbolt, "Receptacle") {
                    TableColumn("Receptacle", value: \.receptacleSort) { CellText(text: $0.receptacle) }
                        .width(min: 70, ideal: 100)
                }
                if state.isColumnVisible(.thunderbolt, "State") {
                    TableColumn("State", value: \.stateSort) { CellText(text: $0.state) }
                        .width(min: 90, ideal: 110)
                }
                if state.isColumnVisible(.thunderbolt, "Link") {
                    TableColumn("Link", value: \.linkSort) { CellText(text: $0.link) }
                        .width(min: 90, ideal: 140)
                }
                if state.isColumnVisible(.thunderbolt, "Host / vendor") {
                    TableColumn("Host / vendor", value: \.hostSort) { CellText(text: $0.host) }
                        .width(min: 120, ideal: 200)
                }
            }
            .overlay { if rows.isEmpty { EmptyState(message: emptyMessage(for: .thunderbolt)) } }
        } else {
            LoadingView()
        }
    }
}

struct PowerView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let snapshot = state.snapshot {
            let rows = state.filtered(powerRows(snapshot))
            // The power view has no natural order to sort by.
            Table(rows, selection: $state.selection) {
                if state.isColumnVisible(.power, "Metric") {
                    TableColumn("Metric") { CellText(text: $0.metric) }
                        .width(min: 140, ideal: 220)
                }
                if state.isColumnVisible(.power, "Value") {
                    TableColumn("Value") { CellText(text: $0.value) }
                        .width(min: 200, ideal: 340)
                }
            }
            .overlay { if rows.isEmpty { EmptyState(message: emptyMessage(for: .power)) } }
        } else {
            LoadingView()
        }
    }
}

// MARK: - Detail sheet

struct DetailSheet: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L(.showDetails, state.language)).font(.headline)
                Spacer()
                Button("Done") { state.detailRowKey = nil }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            ScrollView {
                let pairs = state.detailPairs
                if pairs.isEmpty {
                    Text("No details for the selection.").foregroundStyle(.secondary).padding()
                } else {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                        ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                            GridRow {
                                Text(pair.0).foregroundStyle(.secondary).gridColumnAlignment(.leading)
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
