// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MockHandTracking",
    platforms: [.visionOS(.v1)],
    products: [
        .library(name: "MockHandTracking", targets: ["MockHandTracking"])
    ],
    targets: [
        .target(
            name: "MockHandTracking",
            path: "Sources/MockHandTracking"
        )
    ]
)
