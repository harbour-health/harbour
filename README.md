# Harbour for iOS

Native SwiftUI companion with local-model chat, editable voice input, symptom records, medicine comparison, readings, appointment notes, read-only Apple Health import, and doctor visit recording with editable transcripts and reviewed medicine changes. The app has no web view, inference server, analytics, or account requirement.

## Screenshots

Native iPhone simulator captures with fictional test records. Select an image to view it at full resolution.

### Light

| Today | Chat | Records | Settings |
| :---: | :---: | :---: | :---: |
| [<img src="docs/screenshots/01-today.png" alt="Today dashboard in light mode" width="220">](docs/screenshots/01-today.png) | [<img src="docs/screenshots/11-chat-empty.png" alt="New chat in light mode" width="220">](docs/screenshots/11-chat-empty.png) | [<img src="docs/screenshots/64-records.png" alt="Records browser in light mode" width="220">](docs/screenshots/64-records.png) | [<img src="docs/screenshots/16-settings.png" alt="Settings in light mode" width="220">](docs/screenshots/16-settings.png) |

### Dark

| Today | Chat | Records | Settings |
| :---: | :---: | :---: | :---: |
| [<img src="docs/screenshots/31-today-dark.png" alt="Today dashboard in dark mode" width="220">](docs/screenshots/31-today-dark.png) | [<img src="docs/screenshots/32-chat-dark.png" alt="New chat in dark mode" width="220">](docs/screenshots/32-chat-dark.png) | [<img src="docs/screenshots/65-records-dark.png" alt="Records browser in dark mode" width="220">](docs/screenshots/65-records-dark.png) | [<img src="docs/screenshots/38-settings-dark.png" alt="Settings in dark mode" width="220">](docs/screenshots/38-settings-dark.png) |

### Doctor visits

| Visits | Recorder | Visit summary | Medicine review |
| :---: | :---: | :---: | :---: |
| [<img src="docs/screenshots/67-visits.png" alt="Doctor visit history" width="220">](docs/screenshots/67-visits.png) | [<img src="docs/screenshots/68-visit-recorder.png" alt="Doctor visit recorder with a large start button" width="220">](docs/screenshots/68-visit-recorder.png) | [<img src="docs/screenshots/70-visit-summary.png" alt="Locally extracted visit summary and follow-up" width="220">](docs/screenshots/70-visit-summary.png) | [<img src="docs/screenshots/71-visit-medicine-review.png" alt="Review medicine changes before saving" width="220">](docs/screenshots/71-visit-medicine-review.png) |

See [doctor visits](docs/doctor-visits.md) for recording, transcript recovery, and medicine review. Physical-device speech accuracy still needs testing.

See [all captures](docs/screenshots/) and [capture details](docs/screenshots.md) for entry sheets, chat results, model downloads, and app lock.

## Run

Requires a Mac, Xcode with an iOS SDK, and CMake for the simulator inference library. Minimum app target: iOS 18.0.

```sh
cd csi4900/ios
bash scripts/prepare-runtime.sh
open Harbour.xcodeproj
```

Select the shared `Harbour` scheme and an iPhone simulator, then Run. The prepared runtime is already present in this working copy. On a real phone, choose your signing team in **Signing & Capabilities**, enable HealthKit for the bundle ID, and Run. No signing credentials are stored here.

Qwen Small downloads when the first chat message is sent, or from **Settings → Models**. The download is about 491 MB; Balanced is about 1.12 GB. Progress and cancellation are available. Verified models work without a network connection. Voice requires an available on-device English recognizer; it never silently switches to server transcription.

## Screens

- **Today:** recent readings and entry points to symptoms, medicines, interactions, and appointment notes.
- **Chat:** freeform messages; optional topic hints; model and effort controls beside the microphone; validated tool calls and locally generated conversation titles.
- **Records:** a large category browser leading to dedicated symptom, medicine, and reading lists, with native entry sheets and swipe deletion.
- **Visits:** a large recorder with pause/resume, saved audio, editable transcripts, source-quoted notes and follow-up, and confirmed medicine changes.
- **Settings:** appearance, optional Face ID or app PIN lock, model downloads, Apple Health import, record import/export, reset, and evaluation.

The current medicine catalog maps 11 names to ingredients and checks four cited pairs. Other pairs are unassessed. Symptom guidance uses fixed Ontario wording and does not establish a diagnosis. This is the existing honours-project scope carried into native code.

## Verification

```sh
swift test --package-path HarbourCore
swift test --package-path HarbourRuntime
xcodebuild -project Harbour.xcodeproj -scheme Harbour \
  -destination 'platform=iOS Simulator,name=Harbour QA' test
```

`testLocalModelChat` downloads Qwen Small if missing; budget network access and roughly 500 MB of free space. Other UI tests exercise manual entry, persisted records, draft preservation, and model controls. See [evaluation](docs/evaluation.md) for the device/model matrix, results, and limits.

The Xcode project is checked in. If adding source files, regenerate with `python3 scripts/generate-project.py`; this resets generated project settings, so change the generator for persistent configuration changes.

## Documentation

See [docs/README.md](docs/README.md).

See the [native screenshot gallery](docs/screenshots/index.html) for the current interface and entry/confirmation sheets. Today uses a recorded-value summary and equally sized illustrated shortcuts; the floating dock has icon-only buttons with accessible names. Appearance can follow the phone or be set to Light or Dark. See [app lock](docs/app-lock.md) for authentication, PIN retry behaviour, and protection limits.
