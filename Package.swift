// swift-tools-version:5.9
import PackageDescription

// CaptureCore holds everything that can be tested without macOS network
// extension APIs: the app list ("intercept spec"), the CONNECT request to Hotline,
// the helper's arguments and the address check.
// The app and the extension (see project.yml) are thin layers on top.
let package = Package(
    name: "HotlineCapture",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CaptureCore", targets: ["CaptureCore"]),
    ],
    targets: [
        .target(name: "CaptureCore"),
        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"]),
    ]
)
