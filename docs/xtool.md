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

The binary target is named `llama` to match the actual framework: xtool's [packer](https://github.com/xtool-org/xtool/blob/1.21.0/Sources/PackLib/Packer.swift) discovers dynamic frameworks using the binary-target name and embeds them under `Frameworks`. The wrapper rejects a bundle missing `Frameworks/llama.framework/llama` or its privacy manifest.

## Validation and device use

The October 12, 2026 [validation report](results/xtool/validation.json) records the completed preparation and manifest checks:

- `--prepare-only` passed on Windows. The helper prepared the verified iPhone runtime and app plist, retaining bundle ID, version/build, iOS minimum, device families, both localizations, and all six permission descriptions. The full Xcode runtime was not modified.
- Root and runtime `swift package dump-package` checks passed in an isolated Swift 6.4 environment on the connected Linux host with `HARBOUR_DEVICE_RUNTIME=1`. They confirmed the Harbour library dependencies and the `llama` device binary target. These commands validate manifests, not UIKit/SwiftUI source types.

Local WSL could not start (`HCS_E_HYPERV_NOT_INSTALLED`), and the local Docker daemon was unavailable. On the connected Linux host, verified xtool 1.21.0 reported `Not installed` for its Darwin SDK. The direct arm64 build stopped before planning or compilation, and the wrapper exited with its missing-SDK diagnostic. The attempted Apple Xcode download opened Apple Account sign-in; no authenticated Xcode 27 archive or prepared Darwin SDK was available. Native compilation remains blocked until that SDK input is supplied. No app bundle was produced, so the final bundle checks did not run. See [evaluation](evaluation.md) for the separate Windows model-inference results.

Installing on a physical device additionally requires developer signing/provisioning, a trusted device connection, and Developer Mode. Preserve `com.apple.developer.healthkit` and the usage descriptions when signing; Face ID uses the retained `NSFaceIDUsageDescription`. HealthKit capability availability is described by [Apple's membership table](https://developer.apple.com/help/account/reference/supported-capabilities-ios).

xtool's simulator install option is macOS-only, and this build route does not run Harbour's hosted XCTest/XCUITest suites. Its automatic signing path creates development-signed output. Use the existing [TestFlight workflow](testflight.md) for distribution and the Xcode scheme for native tests.
