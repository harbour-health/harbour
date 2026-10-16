// swift-tools-version: 5.10
import PackageDescription

#if os(Linux)
let cryptoTargets: [Target] = [.target(name: "CryptoKit", path: "Sources/LinuxCryptoKitBoundary")]
let cryptoDependencies: [Target.Dependency] = [.target(name: "CryptoKit")]
#else
let cryptoTargets: [Target] = []
let cryptoDependencies: [Target.Dependency] = []
#endif

let package = Package(
    name: "HarbourCancellationInvestigation",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../../HarbourCore")],
    targets: [
        .target(name: "llama", path: "Sources/llama", publicHeadersPath: "include"),
        .target(name: "HarbourRuntime", dependencies: ["llama"], path: "Sources/HarbourRuntime"),
        .target(name: "CancellationSubject", dependencies: [
            .product(name: "HarbourCore", package: "HarbourCore"), "HarbourRuntime"
        ] + cryptoDependencies, path: "Sources/CancellationSubject"),
        .testTarget(name: "CancellationInvestigationTests", dependencies: [
            "CancellationSubject", "HarbourRuntime", "llama",
            .product(name: "HarbourCore", package: "HarbourCore")
        ], path: "Tests", resources: [.copy("ChatView.reference.swift.txt")])
    ] + cryptoTargets
)
