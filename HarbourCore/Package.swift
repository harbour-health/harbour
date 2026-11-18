// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HarbourCore",
    platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [
        .library(name: "HarbourCore", targets: ["HarbourCore"]),
        .executable(name: "medication-search-benchmark", targets: ["MedicationSearchBenchmark"])
    ],
    targets: [
        .target(name: "HarbourCore", resources: [.process("Resources")]),
        .executableTarget(name: "MedicationSearchBenchmark", dependencies: ["HarbourCore"]),
        .testTarget(name: "HarbourCoreTests", dependencies: ["HarbourCore"])
    ]
)
