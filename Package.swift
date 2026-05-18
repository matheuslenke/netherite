// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Netherite",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Netherite", targets: ["Netherite"])
    ],
    targets: [
        .executableTarget(
            name: "Netherite",
            path: "Sources/Netherite",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "NetheriteTests",
            dependencies: ["Netherite"],
            path: "Tests/NetheriteTests"
        )
    ]
)
