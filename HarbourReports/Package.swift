// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HarbourReports", platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [.library(name: "HarbourReports", targets: ["HarbourReports"])],
    targets: [
        .binaryTarget(name: "TypstBridge", path: "Vendor/HarbourTypst.xcframework"),
        .target(name: "HarbourReports", dependencies: ["TypstBridge"], resources: [.process("Resources")])
    ]
)
