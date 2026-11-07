// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Alloy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Alloy", targets: ["AlloyApp"]),
        .executable(name: "alloyctl", targets: ["AlloyCLI"]),
        .library(name: "AlloyCore", targets: ["AlloyCore"]),
    ],
    targets: [
        .target(name: "AlloyCore"),
        .executableTarget(name: "AlloyApp", dependencies: ["AlloyCore"]),
        .executableTarget(name: "AlloyCLI", dependencies: ["AlloyCore"]),
        .testTarget(name: "AlloyCoreTests", dependencies: ["AlloyCore"]),
    ],
    swiftLanguageModes: [.v5]
)
