// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Nexora",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Nexora", targets: ["ClashGlass"]),
        .executable(name: "NexoraTUNHelper", targets: ["NexoraTUNHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "5.1.3"),
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.3"
        )
    ],
    targets: [
        .target(name: "NexoraTUNSupport", dependencies: [.product(name: "Yams", package: "Yams")]),
        .executableTarget(name: "NexoraTUNHelper", dependencies: ["NexoraTUNSupport"]),
        .target(
            name: "ClashGlassCore",
            dependencies: ["NexoraTUNSupport"],
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
            dependencies: ["ClashGlassCore", "NexoraTUNSupport"],
            path: "Tests/ClashGlassTests"
        )
    ]
)
