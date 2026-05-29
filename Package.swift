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
    ],
    targets: [
        .target(
            name: "MCGACore",
            dependencies: ["Yams"]
        ),
        .executableTarget(
            name: "MCGA",
            dependencies: ["MCGACore"]
        ),
        .executableTarget(
            name: "MCGASmokeTests",
            dependencies: ["MCGACore"]
        ),
    ]
)
