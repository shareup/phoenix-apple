// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "Phoenix",
    platforms: [
        .macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v8),
    ],
    products: [
        .library(name: "Phoenix", targets: ["Phoenix"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/shareup/async-extensions.git",
            from: "4.0.0"
        ),
        .package(
            url: "https://github.com/shareup/dispatch-timer.git",
            from: "3.0.0"
        ),
        .package(
            url: "https://github.com/shareup/json-apple.git",
            from: "1.2.0"
        ),
        .package(
            url: "https://github.com/apple/swift-collections.git",
            from: "1.0.3"
        ),
        .package(
            url: "https://github.com/shareup/synchronized.git",
            from: "4.0.0"
        ),
        .package(path: "../websocket-apple"),
//        .package(
//            url: "https://github.com/shareup/websocket-apple.git",
//            from: "3.0.0"
//        ),
    ],
    targets: [
        .target(
            name: "Phoenix",
            dependencies: [
                .product(name: "AsyncExtensions", package: "async-extensions"),
                .product(name: "DispatchTimer", package: "dispatch-timer"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "JSON", package: "json-apple"),
                .product(name: "Synchronized", package: "synchronized"),
                .product(name: "WebSocket", package: "websocket-apple"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-enable-actor-data-race-checks",
                ]),
            ]
        ),
        .testTarget(
            name: "PhoenixTests",
            dependencies: [
                .product(name: "AsyncExtensions", package: "async-extensions"),
                .product(name: "AsyncTestExtensions", package: "async-extensions"),
                "Phoenix",
            ]
        ),
    ]
)
