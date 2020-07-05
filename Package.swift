// swift-tools-version:5.2
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
        .package(name: "Synchronized", url: "git@github.com:shareup/synchronized.git", from: "2.0.0"),
        .package(name: "WebSocket", url: "git@github.com:shareup/websocket-apple.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "Phoenix",
            dependencies: ["Synchronized", "WebSocket"]),
        .testTarget(
            name: "PhoenixTests",
            dependencies: ["Phoenix"]),
    ]
)
