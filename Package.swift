// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TeleBase",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "TeleBase", targets: ["TeleBase"])
    ],
    dependencies: [],
    targets: [
        .target(name: "TeleBase"),
        .testTarget(name: "TeleBaseTests", dependencies: ["TeleBase"])
    ]
)
