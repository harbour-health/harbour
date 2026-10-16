# Building with xtool

Harbour has an additional SwiftPM/xtool build route for an arm64 iPhone app. The checked-in Xcode project remains the route for simulator tests and the existing TestFlight workflow. The root `Package.swift` exposes Harbour as a library product and reuses `HarbourCore` and `HarbourRuntime`; xtool links that product into an app. It does not import `Harbour.xcodeproj`. See xtool's [build command](https://github.com/xtool-org/xtool/blob/1.21.0/Sources/XToolSupport/DevCommand.swift) and [package planner](https://github.com/xtool-org/xtool/blob/1.21.0/Sources/PackLib/Planner.swift).

## Install the tools and SDK

Use xtool **1.21.0**, Python 3, and Swift **6.4** on Linux or Windows through WSL. On macOS, use the installed Xcode toolchain. Follow the upstream [Linux/Windows prerequisites](https://github.com/xtool-org/xtool/blob/1.21.0/Documentation/xtool.docc/Installation-Linux.md) and download the matching [xtool release](https://github.com/xtool-org/xtool/releases/tag/1.21.0).

For a Linux/WSL build, obtain Xcode 27 from [Apple Developer Downloads](https://developer.apple.com/download/all/?q=Xcode) and install its SDK directly:

```sh
xtool sdk install /path/to/Xcode_27.xip
xtool sdk status
```

The install command also accepts an extracted `Xcode.app` or a prepared `darwin.xtoolsdk` directory. SDK installation and a build without account signing do not require `xtool auth`; Apple's Xcode download requires Apple Account authentication and acceptance of Apple's licence. The supported setup uses a locally supplied Xcode archive/app or prepared Darwin SDK. The [SDK command implementation](https://github.com/xtool-org/xtool/blob/1.21.0/Sources/XToolSupport/SDKCommand.swift) describes these inputs. `xtool sdk status` must report `Darwin SDK is installed` before the wrapper attempts a Linux build.

## Prepare or build Harbour

Run from the repository root:

```sh
python3 scripts/xtool-build.py --prepare-only
python3 scripts/xtool-build.py --configuration release
```

On native Windows, use `python` in place of `python3` if needed; `--prepare-only` works there. Run the compilation step inside Linux/WSL or on macOS. Preparation downloads and verifies the pinned llama.cpp `b10549` release, extracts its iPhone arm64 slice, and generates `build/xtool/Info.plist`. To reuse an existing verified archive, pass `--runtime-archive /path/to/llama-b10549-xcframework.zip`.

The wrapper defaults to Release and invokes `xtool dev build` with an arm64 iOS target matching Harbour's deployment version. It builds without requesting account provisioning, device installation, or an upload. A completed build writes `xtool/Harbour.app`; the wrapper then checks its metadata, arm64 app/framework binaries, localizations, icons, and privacy manifests. Generated output is ignored by Git. Preparation alone does not establish that the app compiles or runs.

## Packaging and permissions

`xtool.yml` supplies the bundle ID, prepared plist, HealthKit entitlements, icon, and root resources using xtool's [version 1 schema](https://github.com/xtool-org/xtool/blob/1.21.0/Sources/PackLib/PackSchema.swift). The wrapper derives version `0.1`, build `1`, iOS 18 minimum, device families, orientations, and display name from the current Xcode settings. It retains all six permission descriptions and the English/Canadian French localization declarations from `Harbour/Info.plist`, and provides SwiftUI scene and launch metadata explicitly.

The English/French `.lproj` directories and app privacy manifest are copied to the app root because Harbour's localization helper uses `Bundle.main`. The icon comes from the existing PNG. The runtime helper creates the separate `HarbourRuntime/Vendor/llama-device.xcframework`, with a verified ownership manifest and the required runtime privacy declaration. The build wrapper selects this artifact with `HARBOUR_DEVICE_RUNTIME=1`; the regular Mac/simulator runtime remains the default for the Xcode workflow.

The Harbour SwiftPM target explicitly passes `-Xfrontend -enable-cross-import-overlays`. The SwiftBuild backend omitted this SDK toolset flag in the first native build, leaving the SwiftUI/PhotosUI overlay types `PhotosPicker` and `PhotosPickerItem` unresolved. This setting supplies the overlay support for the additional build route; the checked-in Xcode project is unchanged.

The binary target is named `llama` to match the actual framework: xtool's [packer](https://github.com/xtool-org/xtool/blob/1.21.0/Sources/PackLib/Packer.swift) discovers dynamic frameworks using the binary-target name and embeds them under `Frameworks`. The wrapper rejects a bundle missing `Frameworks/llama.framework/llama` or its privacy manifest.

## Validation and device use

The October 12, 2026 [validation report](results/xtool/validation.json) records successful preparation, manifest checks, and the Release arm64 iOS build:

- `--prepare-only` passed on Windows. The helper prepared the verified iPhone runtime and app plist, retaining bundle ID, version/build, iOS minimum, device families, both localizations, and all six permission descriptions. The full Xcode runtime was not modified.
- Root and runtime `swift package dump-package` checks passed in an isolated Swift 6.4 environment on the connected Linux host with `HARBOUR_DEVICE_RUNTIME=1`. They confirmed the Harbour library dependencies and the `llama` device binary target. These commands validate manifests, not UIKit/SwiftUI source types.
- The final native Release build passed with wrapper exit code 0 in 53.48 seconds, including 39.03 seconds reported by Swift build. `xtool/Harbour.app` passed validation for its arm64 executable and llama framework, metadata, both privacy manifests, and English/French main-bundle resources.

The [build log](results/xtool/native-build.log) retains four nonfatal concurrency warnings. Independent [binary and resource inspection](results/xtool/bundle-proof.json) confirms the app entry point, llama load path, framework search path, and HealthKit entitlement. Compilation used iPhoneOS 27.0; the linker records SDK 18.0 in the app's Mach-O metadata. The app still requires iOS 18. These are separate from device execution and distribution validation.

Local WSL could not start (`HCS_E_HYPERV_NOT_INSTALLED`), and the local Docker daemon was unavailable. Initially, verified xtool 1.21.0 on the connected Linux host reported `Not installed` for its Darwin SDK. The first direct arm64 build stopped before planning or compilation, and the wrapper exited with its missing-SDK diagnostic.

The user subsequently completed Apple Account authentication. Stable Xcode 27 downloaded from Apple and was transferred to the isolated Linux task cache; its observed size and SHA-256 matched across the transfer. The checksum is a local integrity fingerprint, not an Apple-published checksum. SDK extraction/installation completed successfully, supplying the iPhoneOS, iPhoneSimulator, and MacOSX 27.0 SDKs.

The first native build compiled HarbourCore and HarbourRuntime but failed on the app's unresolved PhotosUI overlay types. Adding the explicit cross-import overlay flag to the Harbour target resolved that failure, and the rerun compiled and packaged the complete app.

The build applied only a local ad-hoc entitlement signature. No Apple account provisioning or development/distribution signing, physical-device installation, or upload was performed. Native XCTest/XCUITest execution, on-device Metal inference, and actual iPhone memory/latency measurements remain unperformed. See [evaluation](evaluation.md) for the separate Windows model-inference results.

Installing on a physical device additionally requires developer signing/provisioning, a trusted device connection, and Developer Mode. Preserve `com.apple.developer.healthkit` and the usage descriptions when signing; Face ID uses the retained `NSFaceIDUsageDescription`. HealthKit capability availability is described by [Apple's membership table](https://developer.apple.com/help/account/reference/supported-capabilities-ios).

xtool's simulator install option is macOS-only, and this build route does not run Harbour's hosted XCTest/XCUITest suites. Its automatic signing path creates development-signed output. Use the existing [TestFlight workflow](testflight.md) for distribution and the Xcode scheme for native tests.
