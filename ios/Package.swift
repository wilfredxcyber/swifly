// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Swifly",
    platforms: [
        .iOS(.v16)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.62.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0")
    ],
    targets: [
        .target(
            name: "Swifly",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services")
            ]
        )
    ]
)
