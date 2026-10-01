# Voice conversation

## What it is

Turn-based voice conversation in the existing chat. Finished speech becomes a normal user message; the normal agent/tool response is read aloud, then the next listening turn begins.

## How it works

Chat's microphone menu offers Voice conversation and editable Dictate message. Conversation shows Listening/Finishing/Thinking/Speaking/Paused and an End voice action. Recognition partials update the draft. After 1.8 seconds without a changed, nonempty transcript, conversation ends audio input; duplicate callbacks do not extend that timer. This is a transcript debounce, so delayed recognition can affect when a turn ends. The Finish speaking button explicitly ends input. Dictation uses that explicit control and leaves an editable draft.

After input ends, the recognizer can finalize its text, with a two-second finalization timeout using the most recent partial. An error while still listening stops without sending a message. An error after Finish speaking or the debounce leaves the finalization timeout in place. Empty finalized conversation turns show an error and send no message. A final result is handled once even if the same recognition callback also contains an error.

`VoiceTurn` admits one message per turn and invalidates late callbacks after cancellation, replacement, or finalization, including empty finalization. `VoiceService` owns microphone taps, recognition requests, audio sessions, and speech synthesis. Speech output turns the microphone off; the next turn starts from the matching synthesizer completion callback. Cancelled or replaced playback cannot start another listening turn. Tool review screens pause automatic listening. Resume voice starts the next turn after review. Switching tabs, app backgrounding, model/topic sheets, app locking, and visit recording release the microphone and speech output. End voice leaves the ordinary text conversation in place.

Audio interruptions, a disconnected audio device, and media-service resets stop the current turn without sending its unfinished transcript or automatically reopening the microphone. Media-service resets recreate the audio engine and speech synthesizer. The service also stops on backgrounding and checks app activity before starting audio. Errors are visible in chat; starting voice again clears the previous error. Audio-session deactivation is limited to sessions owned by this service.

Spoken responses include structured medicine, reading, interaction, reminder, and history contents rather than only the result heading. The speaker button and conversation playback share `ChatMessage.spokenText`.

All voice messages use the same emergency checks, tool catalog, validation, persistence, confirmation screens, and local title generation as typed messages. Dictation remains a draft until the user taps Send. Voice cannot bypass medicine, reminder, dose, or question confirmation.

## How to change it

Modify `VoiceService` in `DeviceServices.swift` for platform audio behavior and `VoiceTurn.swift` for turn identity/deduplication. `ChatView` owns the voice-mode state and continues calling its ordinary `send()` function. Keep `.endAudio()` separate from cancellation: immediately cancelling a recognition request loses its final result. Guard callbacks by turn/utterance identity so cancelled audio cannot start another microphone session. Before launching an asynchronous voice start, check the current mode, scene, recorder, and review-screen state inside the task as well as when presenting the control.

`VoiceTurnTests` covers transcript revisions, duplicate callbacks, empty recognition corrections, cancellation, old-turn callbacks during a new turn, and repeated completion. Run `cd HarbourCore && swift test --filter VoiceTurnTests`. These tests exercise turn ownership rather than Apple recognition or microphone timing.

## Configuration

Requires Speech and microphone permission, an available English Canada recognizer supporting on-device recognition, and `requiresOnDeviceRecognition = true`. There is no server transcription fallback. Speech permission denial stops before requesting microphone permission. Speech playback uses `en-CA`, rate 0.45, and the spoken-audio audio session; recognition uses the record/measurement session. The debounce and finalization timeout are currently constants in `VoiceService`. iOS may need its language assets installed before offline recognition is available. The user must choose the voice mode explicitly.

## Dependencies

Apple Speech, AVFoundation, UIKit app lifecycle notifications, SwiftUI, local model runtime, existing chat tools and native review editors. Apple's [on-device recognition requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition) and [audio interruption guidance](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions) describe the underlying platform mechanisms.

Simulator lifecycle/OCR tests are evidence for those mechanisms, not evidence of real microphone transcription accuracy. Physical-device testing remains necessary for first-use permissions, offline language assets, pauses, accents, background noise, disconnected headphones, incoming calls, and accessibility. Verify that speech output is not captured in the following listening turn; no echo-suppression claim follows from the core tests or simulator playback alone.
