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
        .library(
            name: "PhoenixDynamic",
            type: .dynamic,
            targets: ["Phoenix"]),
    ],
    dependencies: [
        .package(
            name: "DispatchTimer",
            url: "https://github.com/shareup/dispatch-timer.git",
            from: "1.3.0"),
        .package(
            name: "Synchronized",
            url: "https://github.com/shareup/synchronized.git",
            from: "2.3.0"),
        .package(
            name: "WebSocket",
            url: "https://github.com/shareup/websocket-apple.git",
            from: "2.4.0"),
    ],
    targets: [
        .target(
            name: "Phoenix",
            dependencies: [
                .product(name: "DispatchTimerDynamic", package: "DispatchTimer"),
                .product(name: "SynchronizedDynamic", package: "Synchronized"),
                "WebSocket",
            ]),
        .testTarget(
            name: "PhoenixTests",
            dependencies: ["Phoenix"],
            exclude: ["phoenix-js", "server"]),
    ]
)
