// swift-tools-version: 5.10
import PackageDescription

// Device-only preparation works without Xcode; keep the full Mac/simulator runtime separate.
let runtimePath = Context.environment["HARBOUR_DEVICE_RUNTIME"] == "1"
    ? "Vendor/llama-device.xcframework" : "Vendor/llama.xcframework"

let package = Package(
    name: "HarbourRuntime", platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [.library(name: "HarbourRuntime", targets: ["HarbourRuntime"]), .executable(name: "model-probe", targets: ["ModelProbe"])],
    dependencies: [.package(path: "../HarbourCore")],
    targets: [
        .binaryTarget(name: "llama", path: runtimePath),
        .target(name: "HarbourRuntime", dependencies: ["llama"]),
        .executableTarget(name: "ModelProbe", dependencies: ["HarbourRuntime", "HarbourCore"]),
        .testTarget(name: "HarbourRuntimeTests", dependencies: ["HarbourRuntime", "HarbourCore"])
    ]
)
