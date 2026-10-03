// swift-tools-version: 6.0
import PackageDescription

// The Swift rewrite of usbscope. The Python tool and its suite stay in place
// while the Swift port is verified against the very same fixtures
// (tests/fixtures) — the two implementations must produce identical JSON.
//
// Layout:
//   UsbScopeCore   the domain model, the OS adapters and the JSON serialiser
//   UsbScopeUI     the presentation layer (table rows, details, diffing) — no
//                  SwiftUI, so it is unit-testable without a window server
//   usbscope       the CLI twin
//   usbscope-app   the SwiftUI app (five views, mirroring the Python app)
let package = Package(
    name: "usbscope",
    platforms: [.macOS("14.4")],
    products: [
        .library(name: "UsbScopeCore", targets: ["UsbScopeCore"]),
        .library(name: "UsbScopeUI", targets: ["UsbScopeUI"]),
        .executable(name: "usbscope", targets: ["usbscope"]),
        .executable(name: "usbscope-app", targets: ["usbscope-app"]),
    ],
    targets: [
        .target(name: "UsbScopeCore", path: "Sources/UsbScopeCore"),
        .target(name: "UsbScopeUI", dependencies: ["UsbScopeCore"], path: "Sources/UsbScopeUI"),
        .executableTarget(name: "usbscope", dependencies: ["UsbScopeCore"], path: "Sources/usbscope"),
        .executableTarget(
            name: "usbscope-app",
            dependencies: ["UsbScopeCore", "UsbScopeUI"],
            path: "Sources/usbscope-app"
        ),
        .testTarget(
            name: "UsbScopeCoreTests",
            dependencies: ["UsbScopeCore", "UsbScopeUI"],
            path: "SwiftTests",
            // The golden JSON is read from disk by absolute path, not bundled.
            exclude: ["Golden"]
        ),
    ]
)
