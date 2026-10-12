// swift-tools-version: 5.10
import PackageDescription

// xtool links this library product into an iOS app. Xcode keeps using its checked-in project.
let package = Package(
    name: "Harbour",
    defaultLocalization: "en",
    platforms: [.iOS("18.0")],
    products: [.library(name: "Harbour", targets: ["Harbour"])],
    dependencies: [.package(path: "HarbourCore"), .package(path: "HarbourRuntime")],
    targets: [
        .target(
            name: "Harbour",
            dependencies: [
                .product(name: "HarbourCore", package: "HarbourCore"),
                .product(name: "HarbourRuntime", package: "HarbourRuntime")
            ],
            path: "Harbour",
            // xtool.yml copies these resources to Bundle.main, preserving the existing lookup code.
            exclude: ["Assets.xcassets", "en.lproj", "fr-CA.lproj", "Info.plist", "Harbour.entitlements", "PrivacyInfo.xcprivacy"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        )
    ]
)
