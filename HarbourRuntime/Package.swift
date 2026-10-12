// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HarbourRuntime", platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [.library(name: "HarbourRuntime", targets: ["HarbourRuntime"]), .executable(name: "model-probe", targets: ["ModelProbe"])],
    dependencies: [.package(path: "../HarbourCore")],
    targets: [
        .binaryTarget(name: "LlamaBinary", path: "Vendor/llama.xcframework"),
        .target(name: "HarbourRuntime", dependencies: ["LlamaBinary"]),
        .executableTarget(name: "ModelProbe", dependencies: ["HarbourRuntime", "HarbourCore"]),
        .testTarget(name: "HarbourRuntimeTests", dependencies: ["HarbourRuntime", "HarbourCore"])
    ]
)
