# Health and voice

## What it is

Native adapters provide read-only HealthKit import and on-device English speech recognition. Both are optional; manual records and typed chat work independently.

## How it works

Apple Health import requests access to heart rate, body temperature, and the systolic/diastolic quantities used by blood-pressure correlations. It reads up to 100 recent samples per type over the previous 30 days and converts them to bpm, degrees Celsius, and mmHg. Stable HealthKit UUIDs prevent reimporting the same sample. The app never writes back to HealthKit or requests unrelated data.

Read authorization intentionally cannot prove that the user granted access. An empty query reports that no readings are available; it does not claim permission was granted or denied. Import runs when explicitly requested, rather than continuously in the background. [Apple’s authorization documentation](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data) explains this privacy boundary.

Voice input requests microphone and speech authorization only when the microphone is used. `SFSpeechRecognizer` must support on-device recognition; `requiresOnDeviceRecognition` is always true. Transcription updates the draft and is never submitted automatically. An unsupported recognizer or denied permission produces a visible error. Chat dictation audio remains in the recognition pipeline rather than being written into record storage. The separate [doctor visit recorder](doctor-visits.md) explicitly saves audio and handles longer sessions. Read-aloud uses AVSpeechSynthesizer.

## How to change it

Edit `DeviceServices.swift`. For a new HealthKit metric, request only its required quantity types, convert units explicitly, add a `ReadingKind`, and test ingestion and duplicate handling. Check physical-device permission flows whenever changing capabilities or privacy strings. Do not treat successful authorization-request completion as proof of read access.

For additional speech locales, check on-device support before starting. Keep transcripts editable. Stop recognition when leaving chat, sending, or starting read-aloud. Model chat does not require speech to be enabled.

Chat dictation and read-aloud controls are disabled while a visit recorder is active. `VoiceService.stop` deactivates the shared audio session only if it owns recording/read-aloud activity, so leaving idle Chat cannot cut off a visit recording.

Voice starts carry a generation ID. Stopping or leaving chat invalidates pending permission requests and queued recognition callbacks, so granting a delayed permission cannot start recording after navigation or update a later draft.

When an enabled app lock replaces the navigation tree, chat teardown stops voice and cancels its model task. Returning from the background requires unlocking before another microphone request. The app lock's privacy curtain also covers any open entry or permission-adjacent screen while backgrounded; physical-device speech and snapshot behaviour still need acceptance testing.

## Configuration

`Harbour.entitlements` enables HealthKit. `Info.plist` supplies microphone, speech, and health-read usage descriptions. A development team and a provisioned HealthKit capability are needed for signed device installs. English locale is `en-CA`; device language assets determine availability. Read horizon and limits are constants in `HealthService.query`.

## Dependencies

Simulator HealthKit checks also need Xcode's simulated entitlements. Use a normal Run/test build or `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`; an unsigned compilation with `CODE_SIGNING_ALLOWED=NO` is a compile check and cannot verify HealthKit authorization. Xcode embeds simulator entitlements in the executable, so inspecting only the code-signature entitlement dictionary is insufficient.

HealthKit, Speech, AVFoundation, and the core reading validator. Speech and real HealthKit data/permission behaviour still require physical-device verification; simulator and empty-store results are not evidence of real-world recognition quality.
