// swift-tools-version: 6.0
import PackageDescription

// usbscope — Swift only. The tool, its test suite and its packaging are all in
// this package; the fixtures under SwiftTests/Fixtures and the golden under
// SwiftTests/Golden pin the JSON shape.
//
// Layout:
//   UsbScopeCore   the domain model, the OS adapters and the JSON serialiser
//   UsbScopeUI     the presentation layer (table rows, details, diffing) — no
//                  SwiftUI, so it is unit-testable without a window server
//   usbscope       the CLI
//   usbscope-app   the SwiftUI app (ten views, including data-quality warnings)
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
        .executableTarget(
            name: "usbscope",
            // UsbScopeUI is plain Swift (no SwiftUI): the CLI reuses its wording for
            // the security, USB4 fabric, diff and preset rows, so a front end cannot
            // drift from the other.
            dependencies: ["UsbScopeCore", "UsbScopeUI"],
            path: "Sources/usbscope"
        ),
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
            exclude: ["Golden", "Fixtures"]
        ),
    ]
)
