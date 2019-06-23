// swift-tools-version:5.1
import PackageDescription
let package = Package(
    name: "Phoenix",
    platforms: [
        .macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v5),
    ],
    products: [
        .library(
            name: "Phoenix",
            targets: ["Phoenix"]),
    ],
    dependencies: [ ],
    targets: [
        .target(
            name: "Phoenix",
            dependencies: []),
        .testTarget(
            name: "PhoenixTests",
            dependencies: ["Phoenix"]),
    ]
)
