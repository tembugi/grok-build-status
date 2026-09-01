// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GrokStatus",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GrokStatus", targets: ["GrokStatus"]),
    ],
    targets: [
        .target(name: "GrokStatusCore"),
        .executableTarget(
            name: "GrokStatus",
            dependencies: ["GrokStatusCore"]
        ),
        .testTarget(
            name: "GrokStatusCoreTests",
            dependencies: ["GrokStatusCore"]
        ),
    ]
)
