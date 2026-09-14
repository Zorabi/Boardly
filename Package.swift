// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Boardly",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Boardly", targets: ["Boardly"])
    ],
    targets: [
        .executableTarget(name: "Boardly"),
        .testTarget(name: "BoardlyTests", dependencies: ["Boardly"])
    ]
)
