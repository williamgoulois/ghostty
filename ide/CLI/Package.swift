// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ghosttyide-cli",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ide", targets: ["GhosttyIDECLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "GhosttyIDECLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources"
        ),
    ]
)
