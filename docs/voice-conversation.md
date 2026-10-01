# Voice conversation

## What it is

Turn-based voice conversation in the existing chat. Finished speech becomes a normal user message; the normal agent/tool response is read aloud, then the next listening turn begins.

## How it works

Chat's microphone menu offers Voice conversation and editable Dictate message. Conversation shows Listening/Finishing/Thinking/Speaking/Paused and an End voice action. Recognition partials update the draft. After 1.8 seconds without a changed, nonempty transcript, conversation ends audio input; duplicate callbacks do not extend that timer. This is a transcript debounce, so delayed recognition can affect when a turn ends. The Finish speaking button explicitly ends input. Dictation uses that explicit control and leaves an editable draft.

After input ends, the recognizer can finalize its text, with a two-second finalization timeout using the most recent partial. An error while still listening stops without sending a message. An error after Finish speaking or the debounce leaves the finalization timeout in place. Empty finalized conversation turns show an error and send no message. A final result is handled once even if the same recognition callback also contains an error.

`VoiceTurn` admits one message per turn and invalidates late callbacks after cancellation, replacement, or finalization, including empty finalization. `VoiceService` owns microphone taps, recognition requests, audio sessions, and speech synthesis. Speech output turns the microphone off; the next turn starts from the matching synthesizer completion callback. Cancelled or replaced playback cannot start another listening turn. Tool review screens pause automatic listening. Resume voice starts the next turn after review. Switching tabs, app backgrounding, model/topic sheets, app locking, and visit recording release the microphone and speech output. End voice leaves the ordinary text conversation in place.

Audio interruptions, a disconnected audio device, and media-service resets stop the current turn without sending its unfinished transcript or automatically reopening the microphone. Media-service resets recreate the audio engine and speech synthesizer. The service also stops on backgrounding and checks app activity before starting audio. Errors are visible in chat; starting voice again clears the previous error. Audio-session deactivation is limited to sessions owned by this service.

Spoken responses include structured medicine, reading, interaction, reminder, and history contents rather than only the result heading. The speaker button and conversation playback share `ChatMessage.spokenText`.

Read-aloud and conversation share `SpeechPreferences`. Automatic ranks the device's available voices by Premium, Enhanced, then Standard quality, preferring the app's Canadian dialect at equal quality. Higher-quality voices in another dialect of the same language can therefore replace a compact Canadian voice. Novelty and Personal Voice options are excluded. No matching language produces an explicit error rather than switching languages. An explicit voice choice overrides ranking while available; removal temporarily falls back to Automatic while retaining that preference.

Settings → Voice lists available voices with dialect and quality, a speaking-speed slider, and a localized preview. Voice selections are separate for English and French. The preview uses its own `VoiceService`, requests no microphone access, and stops on navigation, inactive scenes, voice/rate changes, and visit recording. Returning from system Settings or an available-voices notification refreshes the list. Downloads are managed by iOS; Harbour provides the system Settings path and does not promise that a particular Premium/Enhanced voice is offered for every language/device.

All voice messages use the same emergency checks, tool catalog, validation, persistence, confirmation screens, and local title generation as typed messages. Dictation remains a draft until the user taps Send. Voice cannot bypass medicine, reminder, dose, or question confirmation.

## How to change it

Modify `VoiceService` in `DeviceServices.swift` for platform audio behavior and `VoiceTurn.swift` for turn identity/deduplication. `ChatView` owns the voice-mode state and continues calling its ordinary `send()` function. Keep `.endAudio()` separate from cancellation: immediately cancelling a recognition request loses its final result. Guard callbacks by turn/utterance identity so cancelled audio cannot start another microphone session. Before launching an asynchronous voice start, check the current mode, scene, recorder, and review-screen state inside the task as well as when presenting the control.

`VoiceTurnTests` covers transcript revisions, duplicate callbacks, empty recognition corrections, cancellation, old-turn callbacks during a new turn, and repeated completion. Run `cd HarbourCore && swift test --filter VoiceTurnTests`. These tests exercise turn ownership rather than Apple recognition or microphone timing.

Change `SpeechVoiceSelection.swift` in HarbourCore for quality/dialect ranking and `SpeechPreferences.swift` for the AVFoundation adapter and persistence. Modify `VoiceSettingsView.swift` for selection and preview. `SpeechVoiceSelectionTests` verifies quality before dialect, Canadian ties, unavailable selections, language isolation, and invalid speed preferences. Physical-device checks must compare the preview and chat playback and confirm a downloaded voice becomes available; synthetic candidates cannot establish audible naturalness.

## Configuration

Requires Speech and microphone permission, an available `en-CA` or `fr-CA` recognizer supporting on-device recognition, and `requiresOnDeviceRecognition = true`. There is no server transcription fallback. Speech permission denial stops before requesting microphone permission. Speech playback uses the spoken-audio audio session; recognition uses the record/measurement session. `speech.voice.en-CA` and `speech.voice.fr-CA` in UserDefaults store Apple voice identifiers; an empty identifier means Automatic. `speech.speed` defaults to 1.0 and is bounded to 0.8–1.3 times `AVSpeechUtteranceDefaultSpeechRate`. Invalid/nonfinite stored values use the default. The debounce and finalization timeout are constants in `VoiceService`.

iOS may need recognition language assets installed before offline recognition is available. Higher-quality synthesis voices also require a system download. On iOS 26 and later, use Settings → Accessibility → Read & Speak → Voices; on iOS 18, use Spoken Content → Voices. Choose the app's language and an Enhanced or Premium option if offered. There are no speech provider credentials or server speech calls. The user must choose voice conversation explicitly.

## Dependencies

Apple Speech, AVFoundation, UIKit app lifecycle notifications, SwiftUI, local model runtime, existing chat tools and native review editors. Apple's [on-device recognition requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition) and [audio interruption guidance](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions) describe the underlying platform mechanisms.

Apple documents [voice quality](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality), [system voice downloads](https://support.apple.com/en-ie/111798), and [Read & Speak settings](https://support.apple.com/guide/iphone/hear-whats-on-the-screen-or-typed-iph96b214f0/ios). The API reports available voices; quality metadata and core ranking checks cannot guarantee how natural a specific device's voice sounds.

Simulator lifecycle/OCR tests are evidence for those mechanisms, not evidence of real microphone transcription accuracy. Physical-device testing remains necessary for first-use permissions, offline language assets, pauses, accents, background noise, disconnected headphones, incoming calls, and accessibility. Verify that speech output is not captured in the following listening turn; no echo-suppression claim follows from the core tests or simulator playback alone.
