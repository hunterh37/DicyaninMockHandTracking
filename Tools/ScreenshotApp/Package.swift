// swift-tools-version: 5.9
import PackageDescription

// macOS screenshot generator for README assets.
// Renders the package's SwiftUI control views to PNG via ImageRenderer.
// The library sources are copied into Sources/ScreenshotApp/Lib by generate.sh
// (single source of truth lives in ../../Sources/DicyaninMockHandTracking).
let package = Package(
    name: "ScreenshotApp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ScreenshotApp",
            path: "Sources/ScreenshotApp"
        )
    ]
)
