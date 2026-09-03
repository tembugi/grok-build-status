// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GrokBuildStatus",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GrokBuildStatus", targets: ["GrokBuildStatus"]),
    ],
    targets: [
        .target(name: "GrokBuildStatusCore"),
        .executableTarget(
            name: "GrokBuildStatus",
            dependencies: ["GrokBuildStatusCore"]
        ),
        .testTarget(
            name: "GrokBuildStatusCoreTests",
            dependencies: ["GrokBuildStatusCore"]
        ),
    ]
)
