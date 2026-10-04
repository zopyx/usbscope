import AppKit
import SwiftUI
import UsbScopeCore
import UsbScopeUI

/// The About window: a glossy card with the app icon, the live facts of this
/// Mac and the licence, plus the diagnostics the copy button puts on the
/// clipboard. The content comes from `AboutInfo` (headless, unit-tested); this
/// file only draws it.
struct AboutView: View {
    @EnvironmentObject private var state: AppState

    @State private var copied = false

    private var lang: AppLanguage { state.language }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 18) {
                iconPlate
                title
                Text(AboutInfo.tagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.35)

                facts
                Text(AboutInfo.dataNote)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.tertiary)

                buttons
                Text(Strings.licenseLabel(AboutInfo.license, copyright: AboutInfo.copyright, lang))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Pieces

    /// Accent-tinted gradient with a soft sheen over the window material.
    private var backdrop: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            RadialGradient(
                colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.02)],
                center: .top,
                startRadius: 8,
                endRadius: 420
            )
            LinearGradient(
                colors: [.white.opacity(0.10), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }

    private var iconPlate: some View {
        Group {
            if let image = AboutIcon.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 116, height: 116)
            } else {
                Image(systemName: "cable.connector")
                    .font(.system(size: 62, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 116, height: 116)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }

    private var title: some View {
        VStack(spacing: 3) {
            Text(AboutInfo.name)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
            Text(Strings.versionLabel(AboutIcon.version, state.language))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var facts: some View {
        let items = AboutInfo.facts(state.snapshot)
        if items.isEmpty {
            Text(L(.aboutWaiting, lang))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 7) {
                ForEach(items, id: \.label) { fact in
                    GridRow {
                        Text(fact.label)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(fact.value)
                            .monospacedDigit()
                            .textSelection(.enabled)
                            .gridColumnAlignment(.leading)
                    }
                }
            }
            .font(.callout)
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Link(destination: URL(string: AboutInfo.documentationURL)!) {
                Label(L(.aboutDocs, lang), systemImage: "book")
            }
            Link(destination: URL(string: AboutInfo.repositoryURL)!) {
                Label(L(.aboutSource, lang), systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Button {
                copyDiagnostics()
            } label: {
                Label(copied ? L(.aboutCopied, lang) : L(.aboutCopy, lang),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .disabled(state.snapshot == nil)
        }
        .controlSize(.large)
        .buttonStyle(.bordered)
        .tint(.accentColor)
    }

    private func copyDiagnostics() {
        let text = AboutInfo.diagnostics(version: AboutIcon.version, snapshot: state.snapshot)
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

/// Shows the About window as its own centred panel.
///
/// A borderless-feeling AppKit window (transparent titlebar, movable by its
/// background, fixed content size) reads more like a real About box than a
/// `Window` scene, and it can be opened from the app menu without threading
/// `openWindow` through the command builder.
@MainActor
enum AboutPanel {
    private static var window: NSWindow?

    static func show(state: AppState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: AboutView().environmentObject(state))
        let panel = NSWindow(contentViewController: host)
        panel.title = "About usbscope"
        panel.styleMask = [.titled, .closable, .fullSizeContentView]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.setContentSize(host.view.fittingSize)
        panel.center()
        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Locates the app icon: the bundle's `.icns`, the repository copy when running
/// from a checkout, and finally whatever macOS shows for the process.
enum AboutIcon {
    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? AboutInfo.fallbackVersion
    }

    @MainActor
    static var image: NSImage? {
        if let bundled = Bundle.main.url(forResource: "usbscope", withExtension: "icns"),
           let image = NSImage(contentsOf: bundled) {
            return image
        }
        // `swift run` has no bundle resources: walk up from the executable to
        // find `assets/icon/usbscope.icns` in the checkout.
        var directory = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent("assets/icon/usbscope.icns")
            if let image = NSImage(contentsOf: candidate) { return image }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return NSApp.applicationIconImage
    }
}
