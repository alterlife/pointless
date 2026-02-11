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
            targets: ["Pointless"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Pointless",
            path: "Sources/Pointless"
        )
    ]
)
