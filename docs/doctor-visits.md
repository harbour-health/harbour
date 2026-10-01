# Doctor visits

## What it is

Visits is a native recorder and visit history with saved audio, an editable transcript, locally extracted notes/follow-up, and reviewable medicine changes. Recording is explicitly started by the user for their own visit; it does not have an all-participant permission gate.

## How it works

The icon-only floating dock opens Visits. The recorder has a large start/pause/resume control, timer, microphone-level waveform, and separate Finish action. Finishing opens the saved visit and automatically prepares a summary when a transcript exists. Typed notes can use the same summary/review flow without microphone or speech access. Visit details separate Summary and Transcript, support playback, renaming/editing, text sharing, and confirmed deletion.

`VisitRecorder` writes AAC audio through a locked `VisitAudioWriter` directly from the audio tap. The app stores a provisional visit before starting capture, checkpoints its transcript and duration every ten seconds, and closes the audio file on finishing. A provisional/interrupted flag lets a later launch identify an incomplete session. Pause excludes elapsed wall time from the displayed recording duration. An audio-session interruption pauses capture. Backgrounding finishes capture and marks it interrupted; this first implementation intentionally records while Harbour is in the foreground. No background audio capability is enabled.

On iOS 26+, `SpeechAnalyzer`/`SpeechTranscriber` handles long-form English speech with live partial text. Apple-managed speech assets may download on first use, with visible preparation progress. An audio converter supplies the analyzer's supported PCM format and a bounded 128-buffer queue; conversion/backlog failures explicitly report incomplete transcription while preserving the full audio. Transcription warnings are persisted with the visit and remain visible in its details until a successful saved-audio retry. The older `SFSpeechRecognizer` implementation rolls live requests every 45 seconds, requires on-device recognition, and preserves partial text. Speech permission/support failure falls back visibly to audio-only recording. The Transcript page can retry transcription from saved audio: iOS 26 uses file analysis; older iOS sequentially transcribes protected 44-second temporary chunks. No audio or transcript is uploaded to an inference/transcription service.

The local Qwen model receives transcript chunks of at most 1,800 characters and produces an extractive JSON summary. Every note, follow-up, and proposed medicine change must retain an exact source quote. Invalid/invented quotes or doses are rejected. Unknown medicine names remain notes; they cannot acquire model-invented ingredients. Obvious follow-up source sentences are retained even if the small model omits that JSON category; these remain verbatim quotes and never trigger a booking. Only catalog/saved medicines with explicit action wording become medicine proposals. Negated/question/speculative source sentences are rejected, including when the output quote omits the negation. These checks reduce specific errors; they do not establish clinical correctness or distinguish the clinician from the patient.

Medicine proposals are never automatically applied. The review page begins with no selected changes. Saving requires selecting changes and acknowledging that names/instructions were checked against a prescription or visit notes. The mutation revalidates the quote and ingredient mapping, rejects conflicting changes to one medicine, and requires the medicine list to match its extraction-time baseline. Applying changes and recording the visit's audit entries is one atomic archive write. Repeated application is blocked. Editing/retranscribing clears the old summary; it preserves already-applied audit entries and does not undo confirmed medicine changes. Follow-up quotes stay with the visit; they do not create calendar bookings or reminders.

`Archive.visits` is an optional field in the existing version-1 archive, so archives without visits still decode. Audio filenames are derived from the visit UUID and checked before constructing a URL. Both audio and JSON use complete file protection. Deleting a visit removes its audio after the archive mutation succeeds; deleting all records also removes the audio directory. Visit sharing exports a plain-text note/transcript when requested. The existing Records export remains a clinical-record export and excludes visit/audio history. iOS backups may include these protected files; there is no iCloud synchronization service.

## How to change it

- `HarbourCore/Visits.swift`: data structures, chunking, prompt, source validation, and the medicine mutation boundary.
- `Harbour/VisitRecorder.swift`: permissions, live speech sessions, PCM/AAC writer, pause/interruption lifecycle, and playback.
- `Harbour/VisitTranscription.swift`: saved-audio retry, model assets, and the legacy chunk recognizer's cancellation/timeout.
- `Harbour/VisitsView.swift`: recorder/history, summary, editable transcript, and confirmation UI.
- `Harbour/AppStore.swift`: protected visit persistence, baseline checks, audit writes, audio paths/deletion, and text sharing.
- `HarbourApp.swift`/`Dashboard.swift`: navigation, background finish, and the active recorder indicator. Chat dictation, read-aloud, and full reset are disabled while a recorder session is active. Idle chat/playback teardown releases the shared audio session only when it owns an active session.

Keep microphone tap work off the main actor and lock writer ownership. Invalidate delayed permission/model callbacks before accepting a new session. Never replace saved audio/transcripts on an empty/error result, silently substitute a server recognizer, or infer a dose. Add meaningful adversarial fixtures when expanding the extractor. New top-level Swift source files require regenerating the Xcode project.

## Configuration

The app still targets iOS 18. Live modern transcription is guarded by iOS 26 availability; English uses `en-CA` or Apple's compatible locale. Audio is AAC at 32 kbps with the microphone's sample rate/channel count, approximately 14 MB/hour before container overhead. The recording limit is 90 minutes; the checkpoint interval is ten seconds. Manual transcripts are limited to 200,000 characters. Summary output has a 650-token budget per chunk within the runtime's 2,048-token context. Selected model/download/effort settings remain managed by `ModelManager`; visit extraction needs its own larger output budget.

`Info.plist` explains microphone and speech use for both chat and visits. These permission requests happen on explicit use. Recording cancellation resolves the app's pending permission waiter and invalidates its session ID, so a later system reply cannot start a cancelled recording.

## Dependencies

SwiftUI, AVFoundation, Speech, Foundation, `HarbourCore`, and the existing local `HarbourRuntime` model. No new package, account, recording server, or paid service is required.

References: [Google Recorder's record/pause/transcript pattern](https://support.google.com/pixelphone/answer/16267367?hl=en), [Apple SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [Apple's speech sample](https://developer.apple.com/documentation/speech/bringing-advanced-speech-to-text-capabilities-to-your-app), [legacy recognizer session limit](https://developer.apple.com/documentation/speech/sfspeechrecognizer), and [on-device recognition requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition).

For the Ontario starting scope, the federal Criminal Code's [section 184(2)(a)](https://laws.justice.gc.ca/eng/acts/c-46/section-184.html) supplies the participant-consent exception and [section 183.1](https://www.laws-lois.justice.gc.ca/eng/acts/C-46/section-183.1.html) addresses consent by one of multiple participants. This is why Harbour does not require the doctor to grant permission in the app. This design is for a patient recording a conversation they participate in, rather than recording other people's visits.
