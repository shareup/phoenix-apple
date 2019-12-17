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
    dependencies: [
        .package(url: "https://github.com/shareup/synchronized.git", .upToNextMajor(from: "1.2.0")),
        .package(url: "https://github.com/shareup/forever.git", .upToNextMajor(from: "0.0.0")),
        .package(url: "https://github.com/shareup/simple-publisher.git", .upToNextMajor(from: "1.2.0")),
        .package(url: "https://github.com/shareup/atomic.git", .upToNextMajor(from: "1.0.0")),
    ],
    targets: [
        .target(
            name: "Phoenix",
            dependencies: ["Atomic", "SimplePublisher", "Synchronized", "Forever"]),
        .testTarget(
            name: "PhoenixTests",
            dependencies: ["Phoenix"]),
    ]
)
