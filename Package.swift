// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MacLaunchpad",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LaunchpadCore", targets: ["LaunchpadCore"])
    ],
    targets: [
        .target(name: "LaunchpadCore"),
        .testTarget(
            name: "LaunchpadCoreTests",
            dependencies: ["LaunchpadCore"],
            swiftSettings: [
                .unsafeFlags([
                    "-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing",
                ])
            ]
        )
    ]
)
