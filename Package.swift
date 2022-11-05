// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "Phoenix",
    platforms: [
        .macOS(.v11), .iOS(.v14), .tvOS(.v14), .watchOS(.v7),
    ],
    products: [
        .library(
            name: "Phoenix",
            targets: ["Phoenix"]
        ),
        .library(name: "Phoenix2", targets: ["Phoenix2"]),
    ],
    dependencies: [
        .package(
            name: "AsyncExtensions",
            url: "https://github.com/shareup/async-extensions.git",
            from: "1.3.1"
        ),
        .package(
            name: "DispatchTimer",
            url: "https://github.com/shareup/dispatch-timer.git",
            from: "2.0.1"
        ),
//        .package(
//            url: "https://github.com/apple/swift-async-algorithms",
//            from: "0.0.1"
//        ),
        .package(
            url: "https://github.com/apple/swift-collections.git",
            from: "1.0.2"
        ),
        .package(
            name: "Synchronized",
            url: "https://github.com/shareup/synchronized.git",
            from: "3.1.0"
        ),
        .package(
            name: "WebSocket",
            path: "../websocket-apple"
        ),
//        .package(
//            name: "WebSocket",
//            url: "https://github.com/shareup/websocket-apple.git",
//            from: "3.0.0"
//        ),
    ],
    targets: [
        .target(
            name: "Phoenix",
            dependencies: ["DispatchTimer", "Synchronized", "WebSocket"]
        ),
        .target(
            name: "Phoenix2",
            dependencies: [
                "DispatchTimer",
                .product(name: "Collections", package: "swift-collections"),
                "Synchronized",
                "WebSocket",
            ]
        ),
        .testTarget(
            name: "PhoenixTests",
            dependencies: ["Phoenix"],
            exclude: ["phoenix-js", "server"]
        ),
        .testTarget(
            name: "Phoenix2Tests",
            dependencies: [
                .product(name: "AsyncTestExtensions", package: "AsyncExtensions"),
                "Phoenix2",
            ],
            exclude: ["server"]
        ),
    ]
)
