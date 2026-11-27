# Voice conversation

## What it is

Full-screen voice conversation backed by the existing chat. Finished speech becomes a normal user message; the normal agent/tool response is read aloud, then the next listening turn begins.

## How it works

Chat's microphone menu offers Voice conversation and editable Dictate message. Conversation opens a dedicated full-screen surface with an animated blue shape and Connecting/Listening/Finishing/Thinking/Speaking/Paused states. The regular chat, toolbar and floating dock are hidden; completed turns continue using the same message store. End voice restores the text conversation and any typed draft that existed before voice mode. Leaving voice mode stops audio without cancelling an already-submitted model reply. Recognition partials update the draft. After 1.8 seconds without a changed, nonempty transcript, conversation ends audio input; duplicate callbacks do not extend that timer. This is a transcript debounce, so delayed recognition can affect when a turn ends. The full-screen microphone control pauses input without sending an unfinished partial, resumes listening, or interrupts playback to start a new turn. Dictation retains its separate Finish dictation control and leaves an editable draft.

After input ends, the recognizer can finalize its text, with a two-second finalization timeout using the most recent partial. An error while still listening stops without sending a message. An error after Finish speaking or the debounce leaves the finalization timeout in place. Empty finalized conversation turns show an error and send no message. A final result is handled once even if the same recognition callback also contains an error.

`VoiceTurn` admits one message per turn and invalidates late callbacks after cancellation, replacement, or finalization, including empty finalization. `VoiceService` owns microphone taps, recognition requests, audio sessions, and speech synthesis. Speech output turns the microphone off; the next turn starts from the matching synthesizer completion callback. Cancelled or replaced playback cannot start another listening turn. Tool review screens pause automatic listening. Resume voice starts the next turn after review. Switching tabs, app backgrounding, model/topic sheets, app locking, and visit recording release the microphone and speech output. End voice leaves the ordinary text conversation in place.

Audio interruptions, a disconnected audio device, and media-service resets stop the current turn without sending its unfinished transcript or automatically reopening the microphone. Media-service resets recreate the audio engine and player. The service also stops on backgrounding and checks app activity before starting audio. Errors are visible in chat; starting voice again clears the previous error. Audio-session deactivation is limited to sessions owned by this service.

Spoken responses include structured medicine, reading, interaction, reminder, and history contents rather than only the result heading. The speaker button and conversation playback share `ChatMessage.spokenText`.

Read-aloud and conversation share the local Kokoro engine. Settings → Voice offers Female (`af_heart`, default), Male (`am_liam`), speaking speed, and preview. The first playback downloads hash-verified model assets with progress and cancellation. No spoken health text is sent to a service. See [neural speech](neural-speech.md) for inference, build dependencies and limitations.

All voice messages use the same emergency checks, tool catalog, validation, persistence, confirmation screens, and local title generation as typed messages. Dictation remains a draft until the user taps Send. Voice cannot bypass medicine, reminder, dose, or question confirmation.

## How to change it

`RootView` owns the voice-presentation binding passed to `ChatView`. This hides the dock directly across navigation hosting boundaries. The voice surface replaces the chat layout inside a stable root ZStack rather than presenting another navigation stack or full-screen cover, so presenting it does not call chat's disappear/cancellation handler and root-owned tool review drawers can still appear. Native medicine/reminder confirmations remain required. Errors pause voice and appear on the voice surface; they do not automatically eject the user into chat.

`VoiceConversationView.swift` owns the responsive layout and Canvas/TimelineView shape. Listening and speaking deformation uses RMS levels from microphone and playback-mixer taps, with attack/release smoothing in a separate observable `VoiceVisualization`. Audio buffers stay on the tap callback thread; only a scalar level crosses to the main actor. Generation IDs reject late updates after stop. Output taps are removed when playback stops. The frame timeline runs at up to 30 Hz for gentle idle/waiting motion, pauses for muted state, and becomes static under Reduce Motion. Audio samples and partial transcripts are not displayed in the full-screen view. Chat controls are removed from the visual and accessibility hierarchies while voice mode is open; message persistence remains owned by the same AppStore.

Modify `VoiceService` in `DeviceServices.swift` for platform audio behavior and `VoiceTurn.swift` for turn identity/deduplication. `ChatView` owns the voice-mode state and continues calling its ordinary `send()` function. Keep `.endAudio()` separate from cancellation: immediately cancelling a recognition request loses its final result. Guard callbacks by turn/utterance identity so cancelled audio cannot start another microphone session. Before launching an asynchronous voice start, check the current mode, scene, recorder, and review-screen state inside the task as well as when presenting the control.

`VoiceTurnTests` covers transcript revisions, duplicate callbacks, empty recognition corrections, cancellation, old-turn callbacks during a new turn, and repeated completion. Run `cd HarbourCore && swift test --filter VoiceTurnTests`. These tests exercise turn ownership rather than Apple recognition or microphone timing.

Change `SpeechPreferences.swift` for the two-voice preference and speed persistence, `VoiceSettingsView.swift` for controls, and `HarbourSpeech` for phonemization/inference. The former Apple-voice ranking helper is retained only as legacy test coverage; it is not the app's speech engine.

## Configuration

Recognition requires Speech and microphone permission and an available `en-CA` or `fr-CA` recognizer supporting on-device recognition. `requiresOnDeviceRecognition` is true; there is no server fallback. Playback requires the separately downloaded Kokoro assets, not Speech/microphone permission. `speech.kokoroVoice` defaults to `af_heart`; invalid values restore that default. `speech.speed` defaults to 1.0, bounded to 0.8–1.3. The transcript debounce and finalization timeout live in `VoiceService`.

## Dependencies

Apple Speech, AVFoundation, UIKit app lifecycle notifications, SwiftUI, local model runtime, existing chat tools and native review editors. Apple's [on-device recognition requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition) and [audio interruption guidance](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions) describe the underlying platform mechanisms.

Simulator lifecycle/OCR tests are evidence for those mechanisms, not evidence of real microphone transcription accuracy. Physical-device testing remains necessary for first-use permissions, offline language assets, pauses, accents, background noise, disconnected headphones, incoming calls, and accessibility. Verify that speech output is not captured in the following listening turn; no echo-suppression claim follows from the core tests or simulator playback alone.

## Full-screen verification

`VoiceConversationUITests` checks that voice mode hides chat/navigation, retains the conversation after exit, and renders in French, dark appearance and landscape. `--voice-conversation-fixture --voice-ui-state listening|speaking|thinking|paused` are Debug-only presentation fixtures; they do not open the microphone or establish recognition accuracy. Their generated-looking chat entries are explicitly fictional test data and are excluded from Release code.

`VoicePlaybackTests` uses cached Kokoro assets to verify real playback-mixer level updates and rejection of stale updates after stopping. It prints a skip reason if the assets are missing and never downloads them for the test. This is a simulator playback check, not physical-phone microphone, recognition or echo-cancellation acceptance.

The full-screen layout reduces the illustration at accessibility text sizes and permits scrolling if the content exceeds the viewport. The largest-text UI check confirms the End control remains reachable. English/French source localization checks passed; all three voice UI checks, actual cached-Kokoro playback metering, and the native-model-manager inhaler-summary regression passed locally before build 6.

A user reported only generic meeting notes from a recorded version of the inhaler example while confirming its transcription was accurate. The native-model-manager test retained the complete instructions locally with the cached Balanced model, including persistence. This does not reproduce or fix the phone-specific report. No transcription fault, model-output cause or clinical-quality improvement is claimed without that device's result. The earlier text benchmark was not an audio-to-summary acceptance test.
