// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DicyaninMockHandTracking",
    platforms: [.visionOS(.v1), .macOS(.v13)],
    products: [
        .library(name: "DicyaninMockHandTracking", targets: ["DicyaninMockHandTracking"]),
        // Shared, cross-platform transport used by the macOS webcam runner and
        // the live visionOS app to exchange hand poses over the network.
        .library(name: "DicyaninHandTrackingTransport", targets: ["DicyaninHandTrackingTransport"])
    ],
    targets: [
        .target(
            name: "DicyaninHandTrackingTransport",
            path: "Sources/DicyaninHandTrackingTransport"
        ),
        .target(
            name: "DicyaninMockHandTracking",
            dependencies: ["DicyaninHandTrackingTransport"],
            path: "Sources/DicyaninMockHandTracking"
        )
    ]
)
