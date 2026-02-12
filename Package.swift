// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pointless",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Pointless",
            targets: ["PointlessApp"]
        ),
        .library(
            name: "PointlessCore",
            targets: ["PointlessCore"]
        )
    ],
    targets: [
        .target(
            name: "PointlessCore",
            path: "Sources/Pointless"
        ),
        .executableTarget(
            name: "PointlessApp",
            dependencies: ["PointlessCore"],
            path: "Sources/PointlessApp"
        ),
        .testTarget(
            name: "PointlessTests",
            dependencies: ["PointlessCore"],
            path: "Tests/PointlessTests"
        )
    ]
)
