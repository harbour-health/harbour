# Health and voice

## What it is

Native adapters provide read-only HealthKit import and on-device English or Canadian French speech recognition. Both are optional; manual records and typed chat work independently.

## How it works

Apple Health import requests access to heart rate, body temperature, and the systolic/diastolic quantities used by blood-pressure correlations. It reads up to 100 recent samples per type over the previous 30 days and converts them to bpm, degrees Celsius, and mmHg. Stable HealthKit UUIDs prevent reimporting the same sample. The app never writes back to HealthKit or requests unrelated data.

Read authorization intentionally cannot prove that the user granted access. An empty query reports that no readings are available; it does not claim permission was granted or denied. Import runs when explicitly requested, rather than continuously in the background. [Apple’s authorization documentation](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data) explains this privacy boundary.

Voice input requests speech and microphone authorization only when the microphone is used. `SFSpeechRecognizer` must support on-device recognition; `requiresOnDeviceRecognition` is always true. Dictation updates an editable draft until the user taps Send. The explicitly selected [voice conversation](voice-conversation.md) mode submits a completed utterance through the ordinary chat message and tool flow, reads the response with `AVSpeechSynthesizer`, and listens again after matching playback completion. Mutations still use the same human confirmation screens as typed chat.

An unsupported recognizer or denied permission produces a visible error. Speech permission denial stops before requesting microphone permission. Chat audio remains in the recognition pipeline rather than being written into record storage. The separate [doctor visit recorder](doctor-visits.md) explicitly saves audio and handles longer sessions.

Speech follows the active app localization through `L10n.isFrench`: Canadian French requests `fr-CA`, and English requests `en-CA`. This applies to chat dictation, live visit transcription, and retranscription of saved visit audio. The iOS 26 transcription adapter asks Apple for a supported equivalent locale; older adapters require on-device support for the requested locale. No adapter falls back to server recognition. Missing recognition support leaves typed input or saved visit audio available. Read-aloud prefers an available Canadian voice, then another available voice in the same language; if none exists, it shows an error. Audio and transcript content retain their original language.

Service errors, progress messages, and private notification bodies use `L10n`. Medicine-label OCR prioritizes the app's language while retaining both English and Canadian French recognition. It returns the label text as recognized rather than translating a medicine name or instruction.

## How to change it

Edit `DeviceServices.swift`. For a new HealthKit metric, request only its required quantity types, convert units explicitly, add a `ReadingKind`, and test ingestion and duplicate handling. Check physical-device permission flows whenever changing capabilities or privacy strings. Do not treat successful authorization-request completion as proof of read access.

For additional speech locales, update `SpeechLanguage` in `DeviceServices.swift` and check on-device support before starting. Keep dictation transcripts editable. Stop recognition when leaving chat, sending, or starting read-aloud. Model chat does not require speech to be enabled. `VoiceTurnTests` covers single delivery and stale/empty turn rejection; physical microphone behavior needs device testing. `VisitTranscription.swift` and `VisitRecorder.swift` share the selected locale; preserve their local-only recognition flags and audio checkpoint behavior when modifying them. Keep resource keys in English and use format resources for changing counts and percentages.

Chat dictation and read-aloud controls are disabled while a visit recorder is active. `VoiceService.stop` deactivates the shared audio session only if it owns recording/read-aloud activity, so leaving idle Chat cannot cut off a visit recording.

Voice starts carry a generation ID. Stopping or leaving chat invalidates pending permission requests and queued recognition callbacks, so granting a delayed permission cannot start recording after navigation or update a later draft.

`VoiceService` also stops on app backgrounding, audio interruptions, audio-device disconnection, and media-service resets. Interrupted speech does not trigger the next listening turn. A media-service reset recreates platform audio objects. Restart is explicit after an audio failure, and an idle service does not deactivate another feature's audio session.

When an enabled app lock replaces the navigation tree, chat teardown stops voice and cancels its model task. Returning from the background requires unlocking before another microphone request. The app lock's privacy curtain also covers any open entry or permission-adjacent screen while backgrounded; physical-device speech and snapshot behaviour still need acceptance testing.

## Configuration

`Harbour.entitlements` enables HealthKit. `Info.plist` supplies microphone, speech, and health-read usage descriptions. A development team and a provisioned HealthKit capability are needed for signed device installs. Bundle localization selects English (`en-CA`) or French (`fr-CA`) speech; device language assets determine availability. Read horizon and limits are constants in `HealthService.query`.

## Dependencies

Simulator HealthKit checks also need Xcode's simulated entitlements. Use a normal Run/test build or `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`; an unsigned compilation with `CODE_SIGNING_ALLOWED=NO` is a compile check and cannot verify HealthKit authorization. Xcode embeds simulator entitlements in the executable, so inspecting only the code-signature entitlement dictionary is insufficient.

HealthKit, Speech, AVFoundation, and the core reading validator. Speech and real HealthKit data/permission behaviour still require physical-device verification; simulator and empty-store results are not evidence of real-world recognition quality.
