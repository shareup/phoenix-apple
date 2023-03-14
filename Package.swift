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
            targets: ["Phoenix"]
        ),
        .library(name: "Phoenix2", targets: ["Phoenix2"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/shareup/async-extensions.git",
            from: "2.3.1"
        ),
        .package(
            url: "https://github.com/shareup/dispatch-timer.git",
            from: "3.0.0"
        ),
//        .package(
//            url: "https://github.com/apple/swift-async-algorithms",
//            from: "0.0.1"
//        ),
        .package(
            url: "https://github.com/shareup/json-apple.git",
            from: "1.1.0"
        ),
        .package(
            url: "https://github.com/apple/swift-collections.git",
            from: "1.0.3"
        ),
        .package(
            url: "https://github.com/shareup/synchronized.git",
            from: "4.0.0"
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
            dependencies: [
                .product(name: "DispatchTimer", package: "dispatch-timer"),
                .product(name: "Synchronized", package: "synchronized"),
                "WebSocket",
            ]
        ),
        .target(
            name: "Phoenix2",
            dependencies: [
                .product(name: "DispatchTimer", package: "dispatch-timer"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "JSON", package: "json-apple"),
                .product(name: "Synchronized", package: "synchronized"),
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
                .product(name: "AsyncExtensions", package: "async-extensions"),
                .product(name: "AsyncTestExtensions", package: "async-extensions"),
                "Phoenix2",
            ]
        ),
    ]
)
