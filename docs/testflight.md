# TestFlight distribution

## What it is

`scripts/testflight.py` archives Harbour for physical iOS devices and exports or uploads it for internal TestFlight testing. Every export sets `testFlightInternalTestingOnly = true`; this workflow does not submit an App Store release or external beta review.

## How it works

The script refreshes the prepared runtime's privacy manifests, creates a signed Release archive with Xcode automatic provisioning, verifies the bundle identity and team, then writes `ExportOptions.plist` and invokes Xcode distribution. Export is the default; uploading requires `--upload`. Logs, archives, signing output, and IPAs belong in ignored `build/` output. Signing credentials stay in Xcode and the macOS keychain.

Create an iOS app record in App Store Connect for `com.matteopolak.harbour` before uploading. Choose English (Canada) as the primary language and a unique listing name. The approved listing name is **Harbour Health**; the installed display name remains Harbour. Apple may require the account holder to accept an updated developer agreement; the script cannot resolve that account requirement.

```sh
# Local distribution export; no upload.
python3 scripts/testflight.py --team-id YOURTEAMID --build-number 2 \
  --output build/testflight-2

# Upload the already reviewed archive, restricted to internal TestFlight.
python3 scripts/testflight.py --team-id YOURTEAMID --skip-archive \
  --output build/testflight-2 --upload
```

An upload command succeeding means Apple accepted the transfer. Check processing status in App Store Connect → TestFlight, and add the processed build to an internal testing group with the intended existing App Store Connect user. Upload alone does not establish installability. Do not select an external testing group or a public TestFlight link for this project.

## How to change it

Keep the internal-only flag in `scripts/testflight.py`. Use a fresh positive `--build-number` and output folder for each new upload; build numbers are not silently changed by Xcode. `--archive PATH --skip-archive` supports an archive prepared separately. Change persistent version/bundle settings in `scripts/generate-project.py`, then regenerate the project. The screenshot fixture is under `#if DEBUG` and excluded from Release archives.

## Configuration

- `--team-id`, or `HARBOUR_TEAM_ID`: the ten-character Apple developer team identifier.
- `--build-number`: overrides the checked-in build number for a new archive.
- `--output`: archive, DerivedData, export options, and log directory.
- `--skip-archive`: reuse the existing archive; cannot be combined with a new build number.
- `--upload`: upload rather than export locally.
- `Harbour/Info.plist`: display name, permission descriptions, and encryption declaration.
- [Distribution privacy](distribution-privacy.md): required-reason manifests included in the app/runtime.

## Dependencies

macOS, Python 3, Xcode with the iOS SDK, an active Apple Developer Program membership, Xcode account sign-in, signing access, and the prepared llama framework. An upload also requires network access and an App Store Connect app record. App Store screenshots are generated separately; see [App Store screenshots](app-store-screenshots.md).

Apple references: [upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds), [internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers), and [beta distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).

## Upload validation

Apple requires both HealthKit purpose-description keys for this entitlement/API configuration, including `NSHealthUpdateUsageDescription`. The English and Canadian French descriptions state that Harbour imports readings and does not write Apple Health records; the authorization request still asks for no write types. The first upload attempt identified the missing key, which was added before retrying.

The pinned upstream llama device framework has no matching dSYM in the prepared archive. Xcode reports a symbol-upload warning for that framework. This reduces native-runtime crash symbolication; the app's own dSYM is present. Do not claim complete runtime crash diagnostics or replace the binary without repeating runtime validation.

## Verified run — October 1, 2026

Harbour **0.1 (1)** was archived with Xcode 27.0, signed, and uploaded successfully to the **Harbour Health** app record (`6818333712`, bundle `com.matteopolak.harbour`). App Store Connect showed **Build 1 Internal** and **Ready to Test** after processing. No App Store release or external testing review was submitted.

The corrected Release package contains both privacy manifests and six permission descriptions in each bundled language, with no GGUF weights or Debug screenshot-fixture markers. The native runtime's missing dSYM warning remains as described above. The independent screenshot runs and permission coverage check are recorded in [App Store screenshots](app-store-screenshots.md).

The **Harbour testing** internal group contains this build and the account holder as its single tester; App Store Connect confirmed the tester status as **Invited**. Automatic distribution of future builds is disabled. Invitation codes/links and account email addresses are not stored in the repository.

## Chat and voice update

Version 0.1 build 2 was signed and uploaded on October 1, 2026, with internal-only distribution retained. It contains ordinary local-model replies and recent chat context, model-selected tools without keyword routing, and localized voice selection/preview/speed settings. Release archive and upload logs are under `/private/tmp/harbour-testflight-chat-voice/` in the producing workspace. Apple accepted and processed the upload; build 2 is now Testing in the existing Harbour testing internal group. Automatic distribution remains disabled. Its existing llama dSYM warning remains non-blocking. No public App Store submission or external beta review was made for this update.

## Spacing and loading update

Version 0.1 build 3 was signed and accepted by Apple on October 1, 2026 at 9:54 PM Toronto time. It contains equal reading-summary insets and shared 20-point loading marks for chat and visits. Release archive/upload logs are under `/private/tmp/harbour-testflight-spacing-build3/`. Internal-only distribution remains enabled; no public release or external review was submitted. Apple processed build 3, and App Store Connect confirmed it as Testing in the existing Harbour testing internal group. Automatic distribution remains disabled. The upstream llama symbol-upload warning remains unchanged.
