// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OwghatCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "OwghatCore",
            targets: ["OwghatCore"]
        )
    ],
    targets: [
        .target(
            name: "OwghatCore",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "OwghatCoreTests",
            dependencies: ["OwghatCore"]
        )
    ]
)
