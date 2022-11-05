// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Phoenix",
    platforms: [
        .macOS(.v11), .iOS(.v14), .tvOS(.v14), .watchOS(.v7),
    ],
    products: [
        .library(
            name: "Phoenix",
            targets: ["Phoenix"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/shareup/dispatch-timer.git",
            from: "3.0.0"),
        .package(
            url: "https://github.com/shareup/synchronized.git",
            from: "4.0.0"),
        .package(
            url: "https://github.com/shareup/websocket-apple.git",
            from: "2.5.2"),
    ],
    targets: [
        .target(
            name: "Phoenix",
            dependencies: [
                .product(name: "DispatchTimer", package: "dispatch-timer"),
                .product(name: "Synchronized", package: "synchronized"),
                .product(name: "WebSocket", package: "websocket-apple"),
            ]),
        .testTarget(
            name: "PhoenixTests",
            dependencies: ["Phoenix"],
            exclude: ["phoenix-js", "server"]),
    ]
)
