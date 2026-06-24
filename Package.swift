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
        .library(name: "DicyaninHandGlove", targets: ["DicyaninHandGlove"]),
        // v4.0: record live/mock glove hand-tracking sessions, persist them,
        // and replay the captured glove animation. Cross-platform (visionOS +
        // macOS), built on the mock controller and the shared transport packet.
        .library(name: "DicyaninHandRecording", targets: ["DicyaninHandRecording"])
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
            path: "Sources/DicyaninHandGlove",
            resources: [
                .process("Resources/LeftGlove.usdz"),
                .process("Resources/RightGlove.usdz")
            ]
        ),
        .target(
            name: "DicyaninHandRecording",
            dependencies: ["DicyaninMockHandTracking", "DicyaninHandTrackingTransport"],
            path: "Sources/DicyaninHandRecording"
        ),
        .testTarget(
            name: "DicyaninHandRecordingTests",
            dependencies: ["DicyaninHandRecording", "DicyaninMockHandTracking", "DicyaninHandTrackingTransport"],
            path: "Tests/DicyaninHandRecordingTests"
        )
    ]
)
