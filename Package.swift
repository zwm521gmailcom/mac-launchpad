// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacLaunchpad",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LaunchpadCore", targets: ["LaunchpadCore"]),
        .executable(name: "MacLaunchpad", targets: ["LaunchpadApp"])
    ],
    targets: [
        .target(name: "LaunchpadCore"),
        .executableTarget(name: "LaunchpadApp", dependencies: ["LaunchpadCore"]),
        .testTarget(name: "LaunchpadCoreTests", dependencies: ["LaunchpadCore"])
    ]
)
