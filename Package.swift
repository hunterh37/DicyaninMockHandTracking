// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DicyaninMockHandTracking",
    platforms: [.visionOS(.v1)],
    products: [
        .library(name: "DicyaninMockHandTracking", targets: ["DicyaninMockHandTracking"])
    ],
    targets: [
        .target(
            name: "DicyaninMockHandTracking",
            path: "Sources/DicyaninMockHandTracking"
        )
    ]
)
