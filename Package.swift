// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacLaunchpad",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LaunchpadCore", targets: ["LaunchpadCore"])
    ],
    targets: [
        .target(name: "LaunchpadCore"),
        .testTarget(name: "LaunchpadCoreTests", dependencies: ["LaunchpadCore"])
    ]
)
