// swift-tools-version: 5.10
import PackageDescription

let package = Package(name: "HarbourCore", platforms: [.iOS("18.0"), .macOS(.v13)], products: [.library(name: "HarbourCore", targets: ["HarbourCore"])], targets: [.target(name: "HarbourCore"), .testTarget(name: "HarbourCoreTests", dependencies: ["HarbourCore"])])
