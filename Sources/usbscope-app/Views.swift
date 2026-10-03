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

/// Shown while the first read of a session is running.
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("reading the USB subsystem…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - The five views

struct PortsView: View {
    @EnvironmentObject private var state: AppState
    @State private var sortOrder = [KeyPathComparator(\PortRow.nameSort)]

    var body: some View {
        if let snapshot = state.snapshot {
            let rows = state.filtered(portRows(snapshot, changes: state.changes))
            Table(rows, selection: $state.selection, sortOrder: $sortOrder) {
                TableColumn("Port", value: \.nameSort) { CellText(text: $0.name, highlight: $0.highlight) }
                    .width(min: 90, ideal: 110)
                TableColumn("Type", value: \.kindSort) { CellText(text: $0.kind) }
                    .width(min: 70, ideal: 90)
                TableColumn("State", value: \.stateSort) { CellText(text: $0.state) }
                    .width(min: 90, ideal: 110)
                TableColumn("Mode", value: \.modeSort) { CellText(text: $0.mode) }
                    .width(min: 160, ideal: 210)
                TableColumn("Transports", value: \.transportsSort) { CellText(text: $0.transports) }
                    .width(min: 120, ideal: 240)
                TableColumn("Cable", value: \.cableSort) { CellText(text: $0.cable) }
                    .width(min: 70, ideal: 90)
                TableColumn("Notes", value: \.notesSort) { CellText(text: $0.notes) }
                    .width(min: 160, ideal: 320)
            }
            .overlay { if rows.isEmpty { EmptyState(message: emptyMessage(for: .ports)) } }
        } else {
            LoadingView()
        }
    }
}

struct CablesView: View {
    @EnvironmentObject private var state: AppState
    @State private var sortOrder = [KeyPathComparator(\CableRow.portSort)]

    var body: some View {
        if let snapshot = state.snapshot {
            let rows = state.filtered(cableRows(snapshot, changes: state.changes))
            Table(rows, selection: $state.selection, sortOrder: $sortOrder) {
                TableColumn("Port", value: \.portSort) { CellText(text: $0.port, highlight: $0.highlight) }
                    .width(min: 90, ideal: 110)
                TableColumn("Cable", value: \.cableSort) { CellText(text: $0.cable) }
                    .width(min: 70, ideal: 100)
                TableColumn("CC authentication", value: \.authenticationSort) { CellText(text: $0.authentication) }
                    .width(min: 110, ideal: 150)
                TableColumn("Hash (CC / USB)", value: \.hashSort) { CellText(text: $0.hash) }
                    .width(min: 110, ideal: 150)
                TableColumn("PD spec", value: \.specSort) { CellText(text: $0.spec) }
                    .width(min: 60, ideal: 70)
                TableColumn("Power in", value: \.powerSort) { CellText(text: $0.powerIn) }
                    .width(min: 100, ideal: 200)
                TableColumn("Contract", value: \.contractSort) { CellText(text: $0.contract) }
                    .width(min: 100, ideal: 160)
                TableColumn("Liquid", value: \.liquidSort) { CellText(text: $0.liquid) }
                    .width(min: 60, ideal: 80)
                TableColumn("Controller fw", value: \.firmwareSort) { CellText(text: $0.firmware) }
                    .width(min: 90, ideal: 120)
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
            Table(rows, selection: $state.selection, sortOrder: $sortOrder) {
                TableColumn("Device", value: \.nameSort) { CellText(text: $0.name, highlight: $0.highlight) }
                    .width(min: 140, ideal: 260)
                TableColumn("Vendor", value: \.vendorSort) { CellText(text: $0.vendor) }
                    .width(min: 90, ideal: 130)
                TableColumn("VID:PID", value: \.idSort) { CellText(text: $0.idString) }
                    .width(min: 90, ideal: 110)
                TableColumn("Mode", value: \.modeSort) { CellText(text: $0.mode) }
                    .width(min: 150, ideal: 200)
                TableColumn("Class", value: \.classSort) { CellText(text: $0.deviceClass) }
                    .width(min: 110, ideal: 150)
                TableColumn("Tier", value: \.tierSort) { CellText(text: $0.tier) }
                    .width(min: 40, ideal: 50)
                TableColumn("Port", value: \.portSort) { CellText(text: $0.port) }
                    .width(min: 80, ideal: 100)
                TableColumn("Transport", value: \.transportSort) { CellText(text: $0.transport) }
                    .width(min: 80, ideal: 100)
                TableColumn("Serial", value: \.serialSort) { CellText(text: $0.serial) }
                    .width(min: 90, ideal: 140)
                TableColumn("Restricted", value: \.restrictedSort) { CellText(text: $0.restricted) }
                    .width(min: 70, ideal: 90)
            }
            .overlay { if rows.isEmpty { EmptyState(message: emptyMessage(for: .devices)) } }
        } else {
            LoadingView()
        }
    }
}

struct ThunderboltView: View {
    @EnvironmentObject private var state: AppState
    @State private var sortOrder = [KeyPathComparator(\ThunderboltRow.busSort)]

    var body: some View {
        if let snapshot = state.snapshot {
            let rows = state.filtered(thunderboltRows(snapshot))
            Table(rows, selection: $state.selection, sortOrder: $sortOrder) {
                TableColumn("Bus", value: \.busSort) { CellText(text: $0.bus) }
                    .width(min: 140, ideal: 200)
                TableColumn("Receptacle", value: \.receptacleSort) { CellText(text: $0.receptacle) }
                    .width(min: 70, ideal: 100)
                TableColumn("State", value: \.stateSort) { CellText(text: $0.state) }
                    .width(min: 90, ideal: 110)
                TableColumn("Link", value: \.linkSort) { CellText(text: $0.link) }
                    .width(min: 90, ideal: 140)
                TableColumn("Host / vendor", value: \.hostSort) { CellText(text: $0.host) }
                    .width(min: 120, ideal: 200)
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
                TableColumn("Metric") { CellText(text: $0.metric) }
                    .width(min: 140, ideal: 220)
                TableColumn("Value") { CellText(text: $0.value) }
                    .width(min: 200, ideal: 340)
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
                Text("Details").font(.headline)
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
