// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DicyaninMockHandTracking",
    platforms: [.visionOS(.v1), .macOS(.v13), .iOS("18.0")],
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
        .library(name: "DicyaninHandRecording", targets: ["DicyaninHandRecording"]),
        // Reusable volumetric loading view with a 3D extruded text logo, shown
        // while heavy modes (e.g. the advanced game mode) load. visionOS only.
        .library(name: "DicyaninLoadingView", targets: ["DicyaninLoadingView"]),
        // Shared pinch-grab fruit simulation: the visionOS immersive scene and
        // the macOS webcam runner overlay both drive this model with the same
        // head-relative hand stream, so the fruit behaves identically in each.
        .library(name: "DicyaninFruitScene", targets: ["DicyaninFruitScene"])
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
        .target(
            name: "DicyaninLoadingView",
            path: "Sources/DicyaninLoadingView"
        ),
        .target(
            name: "DicyaninFruitScene",
            path: "Sources/DicyaninFruitScene"
        ),
        .testTarget(
            name: "DicyaninFruitSceneTests",
            dependencies: ["DicyaninFruitScene"],
            path: "Tests/DicyaninFruitSceneTests"
        ),
        .testTarget(
            name: "DicyaninHandRecordingTests",
            dependencies: ["DicyaninHandRecording", "DicyaninMockHandTracking", "DicyaninHandTrackingTransport"],
            path: "Tests/DicyaninHandRecordingTests"
        ),
        .testTarget(
            name: "DicyaninHandTrackingTransportTests",
            dependencies: ["DicyaninHandTrackingTransport"],
            path: "Tests/DicyaninHandTrackingTransportTests"
        ),
        .testTarget(
            name: "DicyaninMockHandTrackingTests",
            dependencies: ["DicyaninMockHandTracking", "DicyaninHandTrackingTransport"],
            path: "Tests/DicyaninMockHandTrackingTests"
        )
    ]
)
