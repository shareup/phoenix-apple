// swift-tools-version:5.3
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
        .package(
            name: "DispatchTimer",
            url: "https://github.com/shareup/dispatch-timer.git",
            from: "2.0.0"),
        .package(
            name: "Synchronized",
            url: "https://github.com/shareup/synchronized.git",
            from: "3.0.0"),
        .package(
            name: "WebSocket",
            url: "https://github.com/shareup/websocket-apple.git",
            from: "2.5.0"),
    ],
    targets: [
        .target(
            name: "Phoenix",
            dependencies: ["DispatchTimer", "Synchronized", "WebSocket"]),
        .testTarget(
            name: "PhoenixTests",
            dependencies: ["Phoenix"],
            exclude: ["phoenix-js", "server"]),
    ]
)
