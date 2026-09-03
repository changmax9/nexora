// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Nexora",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Nexora", targets: ["ClashGlass"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.3"
        )
    ],
    targets: [
        .target(
            name: "ClashGlassCore",
            path: "Sources/ClashGlassCore"
        ),
        .executableTarget(
            name: "ClashGlass",
            dependencies: [
                "ClashGlassCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/ClashGlass"
        ),
        .testTarget(
            name: "ClashGlassTests",
            dependencies: ["ClashGlassCore"],
            path: "Tests/ClashGlassTests"
        )
    ]
)
