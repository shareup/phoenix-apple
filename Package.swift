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
//        .package(url: "https://github.com/shareup/forever.git", .upToNextMajor(from: "0.0.0")),
        .package(path: "/Users/myobie/src/github.com/shareup/forever")
    ],
    targets: [
        .target(
            name: "Phoenix",
            dependencies: ["Synchronized", "Forever"]),
        .testTarget(
            name: "PhoenixTests",
            dependencies: ["Phoenix"]),
    ]
)
