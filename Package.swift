// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DiscordAppBuilder",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DiscordAppBuilder", targets: ["DiscordAppBuilder"])
    ],
    targets: [
        .executableTarget(
            name: "DiscordAppBuilder",
            linkerSettings: [
                .linkedFramework("JavaScriptCore")
            ]
        ),
        .testTarget(
            name: "DiscordAppBuilderTests",
            dependencies: ["DiscordAppBuilder"]
        )
    ]
)
