// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MCGA",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "MCGA", targets: ["MCGA"]),
        .executable(name: "MCGASmokeTests", targets: ["MCGASmokeTests"]),
        .library(name: "MCGACore", targets: ["MCGACore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.3"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(
            name: "MCGACore",
            dependencies: ["Yams"]
        ),
        .executableTarget(
            name: "MCGA",
            dependencies: [
                "MCGACore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            // The app bundle embeds Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"])]
        ),
        .executableTarget(
            name: "MCGASmokeTests",
            dependencies: ["MCGACore"]
        ),
    ]
)
