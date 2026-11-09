// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HarbourSpeech", platforms: [.iOS("18.0"), .macOS(.v14)],
    products: [.library(name: "HarbourSpeech", targets: ["HarbourSpeech"])],
    dependencies: [],
    targets: [
        .binaryTarget(name: "OrtStatic", path: "Vendor/OrtStatic.xcframework"),
        .target(
            name: "OnnxRuntimeBindings",
            dependencies: ["OrtStatic"],
            path: "Vendor/OnnxRuntimeBindings",
            exclude: [
                "ReadMe.md",
                "format_objc.sh",
                "test",
                "docs",
                "ort_checkpoint.mm",
                "ort_checkpoint_internal.h",
                "ort_training_session_internal.h",
                "ort_training_session.mm",
                "include/ort_checkpoint.h",
                "include/ort_training_session.h",
                "include/onnxruntime_training.h"
            ],
            cxxSettings: [.define("SPM_BUILD")],
            linkerSettings: [.linkedFramework("CoreML"), .linkedFramework("Accelerate"), .linkedLibrary("c++")]
        ),
        .binaryTarget(name: "EspeakNG", path: "Vendor/EspeakNG.xcframework"),
        .target(name: "CPhonemizer", dependencies: ["EspeakNG"], publicHeadersPath: "include"),
        .target(
            name: "HarbourSpeech",
            dependencies: ["CPhonemizer", "OnnxRuntimeBindings"],
            resources: [.copy("Resources/espeak-ng-data"), .copy("Resources/Notices"), .process("Resources/vocab.json")]
        ),
        .testTarget(name: "HarbourSpeechTests", dependencies: ["HarbourSpeech"])
    ],
    cxxLanguageStandard: .cxx17
)
