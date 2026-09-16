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
        .executableTarget(
            name: "Boardly",
            resources: [
                // AppIcon.iconset 供 make-app.sh 打包 .app 时使用（iconutil 编译为 icns）。
                .copy("Resources")
            ]
        ),
        .testTarget(name: "BoardlyTests", dependencies: ["Boardly"])
    ]
)
