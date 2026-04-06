// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Phoenix",
    platforms: [
        .macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9),
    ],
    products: [
        .library(name: "Phoenix", targets: ["Phoenix"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/shareup/async-extensions.git",
            from: "4.3.0"
        ),
        .package(
            url: "https://github.com/shareup/dispatch-timer.git",
            from: "3.0.1"
        ),
        .package(
            url: "https://github.com/shareup/json-apple.git",
            from: "1.4.1"
        ),
        .package(
            url: "https://github.com/apple/swift-collections.git",
            from: "1.1.2"
        ),
        .package(
            url: "https://github.com/shareup/synchronized.git",
            from: "4.0.1"
        ),
        .package(
            url: "https://github.com/shareup/websocket-apple.git",
            from: "4.1.0"
        ),
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
