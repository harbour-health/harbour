# App Store screenshots

## What it is

`scripts/app-store-screenshots.sh` produces ten native portrait iPhone screenshots in light mode, separately from the existing README and QA gallery. Saved health inputs are fictional; visit notes are manually seeded and chat is empty. This workflow does not run model inference or establish model correctness.

## How it works

Run from the iOS repository:

```sh
scripts/app-store-screenshots.sh
scripts/app-store-screenshots.sh --locale fr-CA
```

The script checks the installed iOS 26.5 runtime, iPhone 17 Pro Max device type, prepared runtime framework, and Python/Pillow, and refreshes the prepared framework’s privacy manifests before creating a disposable simulator. It sets light appearance and a 9:41 status bar, runs the dedicated Debug UI test with one build job and no parallel simulators, exports XCTest attachments, and removes only the simulator it created on exit. No runtime or model weights are downloaded. Keep normal simulator ad hoc signing enabled: disabling signing prevents the Keychain-backed app lock from initializing on a fresh simulator.

The `--app-store-screenshots` launch argument enables a Debug-only fixture in `AppStore`, stores it in its own `AppStoreScreenshots` subfolder, resets it on each launch, and selects Light appearance. The fixture contains two medicines, three readings, one symptom, one manual visit note, and one appointment question. No personal data or previous simulator state is copied. Release builds exclude this fixture and its launch-argument handling.

The captures are Today, Records, Medicines, Readings, Symptoms, Visits, saved visit transcript, Appointment preparation, Timeline, and empty Chat. UI assertions check navigation, expected content, and absence of keyboard/alerts before capture. XCTest failures stop the shell pipeline. The exporter also requires exactly one passed test, exactly ten uniquely named captures, and native 1320 × 2868 dimensions. PNGs are converted to RGB without resampling to remove alpha.

The default output is a new `build/app-store-screenshots/<locale>/<UTC timestamp>/` directory. Its ten numbered PNGs are the upload candidates. `manifest.json` records device/test/attachment timestamps, Xcode version, fixture provenance, dimensions, and SHA-256 hashes. `contact-sheet.jpg` is a review aid; `run/` retains the result bundle, build log, and simulator UUID. Existing output directories are rejected. A failed run retains available diagnostics and cannot produce a complete manifest.

Review every PNG at full resolution before uploading, especially text clipping and system overlays. Capture generation does not upload images or publish the app. The dashboard date heading reflects the capture day; the seeded record dates are fixed at October 1, 2026, so repeat runs reproduce the content and navigation rather than byte-identical images across OS revisions or days.

### Verified capture run: October 1, 2026

Both dedicated UI tests passed on Xcode 27.0 (27A266a), iPhone 17 Pro Max, iOS 26.5 (23F77). Each set contains ten RGB PNGs at native 1320 × 2868. Every original PNG and both contact sheets were visually inspected. These are local ignored outputs, available on the producing workstation:

| Locale | Result | Output directory from the iOS repository |
| --- | --- | --- |
| English (`en-CA`) | 1 test passed, 10 captures | `build/app-store-screenshots/en-CA/20261001-review-3/` |
| Canadian French (`fr-CA`) | 1 test passed, 10 captures | `build/app-store-screenshots/fr-CA/20261001-review/` |

Each directory contains `manifest.json`, `contact-sheet.jpg`, and `run/screenshots.xcresult`. The exporter was also checked against the earlier failed unsigned simulator test: it rejected that result and created no published output. Normal simulator signing resolved the Keychain initialization failure.

`HarbourTests/HarbourLocalizationTests/testPackagedPermissionDescriptionsCoverAllNativeAccess` also passed (1/1) on a separate disposable simulator using the cached build. Its result bundle is `build/app-store-screenshots/permission-check.xcresult`; it checks the packaged native permission purpose strings and does not exercise permission grants.

The captured health records and manual visit text are the seeded fictional fixture. Chat has no messages; no inference, visit summarization, OCR, recording, permission grants, or model downloads occurred in these capture runs. Some native scroll content extends behind the floating navigation or below the drawer edge, as it does during normal app navigation; the exported PNGs retain the full device screen.

## How to change it

Edit `prepareAppStoreScreenshots()` in `Harbour/AppStore.swift` to change fictional inputs, with English and Canadian French versions for free text. Keep all fixture code inside `#if DEBUG`. Edit `HarbourAppStoreScreenshotTests` in `HarbourUITests/HarbourUITests.swift` for navigation and attachment names; keep the exporter's ordered `names` list synchronized. Do not add inferred summaries or synthetic model replies that could be mistaken for inference evidence.

Edit `scripts/export-app-store-screenshots.py` for validation, provenance, or the contact sheet. It deliberately does not use the broader QA gallery exporter and does not update README gallery markers. Changing the simulator device requires updating the dimension check after checking Apple's current accepted screenshot sizes.

## Configuration

`--locale en-CA` is the default; `--locale fr-CA` selects the bundled Canadian French UI and French fixture inputs. `--output DIRECTORY` chooses a new, nonexistent destination. `PYTHON` selects a Python executable with Pillow installed. `HARBOUR_SCREENSHOT_DERIVED_DATA` optionally overrides the shared build cache at `build/app-store-screenshots/DerivedData`; use different cache paths for concurrent runs. Reusing this cache avoids recompiling unchanged native code for a second locale. The script uses the currently selected Xcode (`DEVELOPER_DIR`/`xcode-select`), Debug configuration, iOS 26.5, and iPhone 17 Pro Max. Output under `build/` is already ignored by Git.

## Dependencies

macOS, installed Xcode command-line tools, the already installed iOS 26.5 simulator runtime, Python 3 with Pillow, and `HarbourRuntime/Vendor/llama.xcframework` are required. Prepare the native runtime using [Local models](local-models.md) before running this script. The workflow uses `xcodebuild`, `simctl`, `xcresulttool`, the native app, and its XCTest UI target; it needs no account, signing identity, Apple Health grant, notification permission, network download, or model cache.
