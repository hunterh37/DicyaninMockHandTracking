// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DicyaninMockHandTracking",
    platforms: [.visionOS(.v1), .macOS(.v13)],
    products: [
        .library(name: "DicyaninMockHandTracking", targets: ["DicyaninMockHandTracking"]),
        // Shared, cross-platform transport used by the macOS webcam runner and
        // the live visionOS app to exchange hand poses over the network.
        .library(name: "DicyaninHandTrackingTransport", targets: ["DicyaninHandTrackingTransport"]),
        // Glove hands built on Apple's "Tracking and visualizing hand movement"
        // sample: a rigged glove that maps every hand-skeleton joint, with a
        // simulator bridge to the mock controller. visionOS only.
        .library(name: "DicyaninHandGlove", targets: ["DicyaninHandGlove"])
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
        ),
        .target(
            name: "DicyaninHandGlove",
            dependencies: ["DicyaninMockHandTracking"],
            path: "Sources/DicyaninHandGlove"
        )
    ]
)
