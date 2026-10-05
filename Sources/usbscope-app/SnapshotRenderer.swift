import AppKit
import Foundation
import SwiftUI
import UsbScopeCore
import UsbScopeUI

/// The offscreen render behind `usbscope-app --snapshot <path.png> [--view ports]`.
///
/// The Python app has exactly this mode; it is what proves the window renders
/// without a human at the screen. Here the content is built as an
/// `NSHostingView` inside an *ordered-out* window — never shown — laid out and
/// cached into a bitmap, so no screen, no screen-recording permission and no
/// window server focus are involved. The process then exits with the PNG on disk.
///
/// `--view` accepts any `AppView` raw value (`ports`, `cables`, `devices`,
/// `thunderbolt`, `power`, `timeline`, `security`, `usb4`, `diff`, `warnings`).
enum SnapshotRenderer {
    /// Parse `--snapshot` / `--view` / `--baseline` / `--fixture` /
    /// `--accessibility-size` from the command line; `nil`
    /// when no screenshot was asked for.
    ///
    /// `--view` without `--snapshot` is ignored (the app just opens that view);
    /// `--baseline` loads a snapshot JSON into the Diff tab before the render.
    static func requested() -> (path: String, view: AppView, baseline: String?, fixture: String?, accessibilitySize: Bool)? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else {
            return nil
        }
        let path = arguments[index + 1]
        var view = AppView.ports
        if let viewIndex = arguments.firstIndex(of: "--view"), viewIndex + 1 < arguments.count,
           let parsed = AppView(rawValue: arguments[viewIndex + 1]) {
            view = parsed
        }
        var baseline: String?
        if let baselineIndex = arguments.firstIndex(of: "--baseline"), baselineIndex + 1 < arguments.count {
            baseline = arguments[baselineIndex + 1]
        }
        var fixture: String?
        if let fixtureIndex = arguments.firstIndex(of: "--fixture"), fixtureIndex + 1 < arguments.count {
            fixture = arguments[fixtureIndex + 1]
        }
        return (path, view, baseline, fixture, arguments.contains("--accessibility-size"))
    }

    /// Build the window offscreen, write the PNG and exit.
    @MainActor
    static func run(path: String, view: AppView, baseline: String? = nil, fixture: String? = nil,
                    accessibilitySize: Bool = false) -> Never {
        let state = AppState(
            store: PreferencesStore(backend: MemoryPreferencesBackend()),
            notifier: nil,
            monitoring: false
        )
        state.view = view
        if let fixture {
            do {
                let snapshot = try SnapshotLoading.snapshot(from: URL(fileURLWithPath: fixture))
                state.loadSnapshotForRendering(snapshot)
            } catch {
                FileHandle.standardError.write(Data("usbscope-app: could not load fixture \(fixture): \(error)\n".utf8))
                exit(1)
            }
        } else {
            state.loadSynchronously()
        }
        if let baseline {
            state.loadBaseline(URL(fileURLWithPath: baseline))
            FileHandle.standardError.write(
                Data("baseline \(baseline) → \(state.baseline == nil ? "NOT loaded" : "loaded")\n".utf8)
            )
        }

        guard let image = image(state: state, accessibilitySize: accessibilitySize) else {
            FileHandle.standardError.write(Data("usbscope-app: could not render the window\n".utf8))
            exit(1)
        }
        guard let data = pngData(image) else {
            FileHandle.standardError.write(Data("usbscope-app: could not encode the PNG\n".utf8))
            exit(1)
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(
                Data("usbscope-app: cannot write \(path): \(error)\n".utf8)
            )
            exit(1)
        }
        FileHandle.standardError.write(
            Data("rendered \(view.rawValue) → \(path) (\(data.count) bytes)\n".utf8)
        )
        exit(0)
    }

    /// The window size a render uses; wide enough for the busiest table.
    private static let size = NSSize(width: 1280, height: 760)

    /// Lay the content out offscreen and cache it into an `NSImage`.
    @MainActor
    static func image(state: AppState, accessibilitySize: Bool = false) -> NSImage? {
        // The hosting view has no opaque background of its own, so an offscreen
        // cache would render its default (black) text on a transparent bitmap.
        // Paint the window background first, in the current appearance, so the
        // capture looks like the window does on screen.
        let root = ZStack {
            Color(nsColor: .windowBackgroundColor)
            ContentView().environmentObject(state)
        }
        let hostedRoot: AnyView = accessibilitySize
            ? AnyView(root.dynamicTypeSize(.accessibility3))
            : AnyView(root)
        let hosting = NSHostingView(rootView: hostedRoot)
        hosting.frame = NSRect(origin: .zero, size: size)

        // An ordered-out window is enough for AppKit to give the hosting view a
        // backing store; ordering it in would need a visible screen.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        window.setFrame(NSRect(origin: .zero, size: size), display: false)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        // SwiftUI builds the AppKit table during a layout pass; pump the run loop
        // briefly so the rows exist before the cache, without ever showing it.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return nil
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
