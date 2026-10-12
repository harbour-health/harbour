// swift-tools-version: 5.10
import PackageDescription

// Device-only preparation works without Xcode; keep the full Mac/simulator runtime separate.
let runtimePath = Context.environment["HARBOUR_DEVICE_RUNTIME"] == "1"
    ? "Vendor/llama-device.xcframework" : "Vendor/llama.xcframework"

#if os(Linux)
// Manifests run on the host, including Linux hosts cross-compiling the Apple app.
let llamaTarget: Target = Context.environment["HARBOUR_LINUX_RUNTIME"] == "1"
    ? .systemLibrary(name: "llama", path: "Sources/LlamaLinux", pkgConfig: "llama")
    : .binaryTarget(name: "llama", path: runtimePath)
#else
let llamaTarget: Target = .binaryTarget(name: "llama", path: runtimePath)
#endif

let package = Package(
    name: "HarbourRuntime", platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [.library(name: "HarbourRuntime", targets: ["HarbourRuntime"]), .executable(name: "model-probe", targets: ["ModelProbe"]), .executable(name: "model-eval", targets: ["ModelEval"])],
    dependencies: [.package(path: "../HarbourCore")],
    targets: [
        llamaTarget,
        .target(name: "HarbourRuntime", dependencies: ["llama"]),
        .executableTarget(name: "ModelProbe", dependencies: ["HarbourRuntime", "HarbourCore"]),
        .executableTarget(name: "ModelEval", dependencies: ["HarbourRuntime", "HarbourCore", "llama"]),
        .testTarget(name: "HarbourRuntimeTests", dependencies: ["HarbourRuntime", "HarbourCore"])
    ]
)
