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
                if let times = geometry.timeRangeText() {
                    Text(times).font(.caption).foregroundStyle(.secondary)
                }
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
                Text("\(rows.count)").monospacedDigit().foregroundStyle(.secondary)
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
                Text(SecurityPresentation.honestLimits).font(.caption).foregroundStyle(.secondary)
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
                        Text(item.label).foregroundStyle(styleColor(item.style)).fontWeight(.semibold)
                        Spacer()
                        Text("\(item.count)").monospacedDigit()
                    }
                    .frame(maxWidth: 320)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            Text(SecurityPresentation.headline).font(.caption).foregroundStyle(.secondary)
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
                Text(SecurityPresentation.emptyReportText).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var storageBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(.securityStorageTitle, lang)).font(.headline)
            if state.storageInventory.isEmpty {
                Text(SecurityPresentation.emptyStorageText).foregroundStyle(.secondary)
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
                Text(row.severity)
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(styleColor(row.severityStyle).opacity(0.18), in: Capsule())
                    .foregroundStyle(styleColor(row.severityStyle))
                Text(row.rule).font(.system(.body, design: .monospaced))
                Spacer()
                Text(row.subject).foregroundStyle(.secondary)
            }
            Text(row.detail).font(.callout)
        }
        .padding(.vertical, 2)
    }

    private func storageView(_ row: StorageRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(row.identifier) · \(row.name)").fontWeight(.semibold)
                Text("\(row.capacity) · \(row.mode) · \(row.mount)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if state.ejecting == row.id {
                ProgressView().controlSize(.small)
            }
            Button(L(.eject, lang)) { state.eject(row) }
                .disabled(!row.ejectEnabled || state.ejecting != nil)
                .help(row.ejectReason ?? L(.eject, lang))
        }
        .padding(.vertical, 2)
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
                EmptyState(message: emptyMessage(for: .usb4))
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
                Button(L(.exportJSON, lang)) { state.export(format: "json") }
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
                            Text("\(item.count) \(L(.of(item.kind), lang))").monospacedDigit()
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
