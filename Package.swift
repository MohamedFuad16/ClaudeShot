// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ClaudeShot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClaudeShot", targets: ["ClaudeShot"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeShot",
            path: "Sources/ClaudeShot"
        )
    ]
)
