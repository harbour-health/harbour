# Distribution privacy manifests

## What it is

The distribution bundles include Apple's required-reason API declarations. These describe app preferences and the native model runtime's access to its local model-file metadata.

## How it works

`Harbour/PrivacyInfo.xcprivacy` is copied into the app by the generated resource phase. It declares app-scoped UserDefaults (`CA92.1`), used by model/effort preferences and SwiftUI appearance storage.

`scripts/runtime-privacy.py` writes a separate manifest into every prepared llama framework slice. It declares file metadata inside the app container (`C617.1`), matching the native runtime's filesystem checks on downloaded model files. This is a repository-added declaration based on the pinned runtime source; it is not an upstream vendor attestation. The existing runtime's `clock_gettime` timing calls are not in Apple's listed system-boot-time API category, so no unsupported reason is added for them.

Both manifests declare no tracking or developer-collected data. Records, audio, and inference remain on device. User-initiated exports and model-download requests still exist; these manifests do not replace App Store privacy answers, permission descriptions, or a privacy policy.

## How to change it

Audit new dependencies and calls against [Apple's required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api). Add only reasons that match actual use. If replacing llama, inspect that version's source and binary imports before retaining its declaration. Change the runtime stamp script rather than editing ignored Vendor files by hand.

Run `bash scripts/prepare-runtime.sh` before distribution. When the runtime is already present, this refreshes the manifests without downloading or rebuilding it. Xcode signs the embedded framework during the app build. Never modify the finished signed archive to insert a manifest; rebuild instead.

## Configuration

The app declaration lives in `Harbour/PrivacyInfo.xcprivacy`; the generator registers it as a resource. `HARBOUR_RUNTIME_VENDOR` controls the framework destination used by `prepare-runtime.sh`. Runtime manifests are created by `scripts/runtime-privacy.py` in each framework bundle's resource location.

## Dependencies

Python 3 `plistlib`, the prepared pinned llama framework, the generated Xcode resource phase, and Xcode distribution signing. Apple defines the [approved reason codes](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons).
