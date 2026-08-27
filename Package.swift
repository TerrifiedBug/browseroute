// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
]

let package = Package(
    name: "Browseroute",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Browseroute", targets: ["Browseroute"]),
        .library(name: "BrowserouteCore", targets: ["BrowserouteCore"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "BrowserouteCore",
            swiftSettings: swiftSettings,
        ),
        .executableTarget(
            name: "Browseroute",
            dependencies: [
                "BrowserouteCore",
            ],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "BrowserouteCoreTests",
            dependencies: ["BrowserouteCore"],
            swiftSettings: swiftSettings,
        ),
    ],
)
