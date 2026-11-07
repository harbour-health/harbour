# Neural speech

## What it is

On-device Kokoro speech for chat replies, read-aloud and previews. The only selectable styles are `af_heart` (Female, default) and `am_liam` (Male), matching the local audition.

## How it works

`KokoroAssets` downloads the 325.5 MB ONNX model and two 522 KB style tensors on first use. Fixed byte counts and SHA-256 checks gate installation; partial downloads are removed and installed assets are excluded from backups. Progress and cancellation appear in voice settings and voice chat. Only static assets are downloaded; speech text remains local.

`HarbourSpeech` serializes eSpeak NG phonemization and ONNX CPU inference in one actor. eSpeak supplies pronunciation, not the audible voice. English/French IPA tokens feed Kokoro with the chosen style and bounded speed. Text is split at natural boundaries into short chunks, rendered at 24 kHz, and queued through `AVAudioPlayerNode`. The app limits queued buffers and invalidates callbacks on Stop, navigation, interruption or backgrounding. A synchronous inference chunk may finish after cancellation; its audio is discarded. There is no Apple synthesis fallback.

## How to change it

Change asset revisions/checksums in `KokoroAssets.swift`, inference/token mapping in `KokoroSpeech.swift`, and audio-session ownership in `VoiceService`. Keep asset, model and tokenizer versions coordinated. New styles need explicit approval and audition; do not silently expand the two-voice list. English style presets can pronounce French but a native French speaker should assess accent and intelligibility. Simulator playback does not establish physical-device speed, battery impact or conversational echo behavior.

Build dependencies before generating the Xcode project:

```sh
brew install cmake ninja
python3 scripts/prepare-speech.py
python3 scripts/prepare-onnx.py
python3 scripts/generate-project.py
swift test --package-path HarbourSpeech
```

The ONNX script packages Microsoft's verified static archives with its original Objective-C bindings. Namespaced C headers avoid collisions with the static Typst library. eSpeak uses a genuine dynamic framework; do not embed a static framework wrapper as an executable framework. The scripts pin source commits, retain modifications in readable build code and support iPhone, arm64 simulator and Mac tests.

## Configuration

`speech.kokoroVoice`: `af_heart` or `am_liam`; unknown/missing values restore Female. `speech.speed`: 0.8–1.3, default 1.0. ONNX uses two CPU threads. Optional real-synthesis package tests use `HARBOUR_KOKORO_MODEL` and `HARBOUR_KOKORO_VOICES`; ordinary package tests need no voice-model download. Model assets live under Application Support/Voices/Kokoro. Generated SDKs, build outputs and phonemizer data are ignored by Git.

## Dependencies and notices

Kokoro-82M is Apache-2.0; ONNX Runtime 1.24.2 is MIT. eSpeak NG 1.52.0 is GPL-3.0-or-later, with additional bundled-data notices. The resource bundle includes eSpeak's license texts and ONNX's MIT notice. Source and complete build modifications are pinned in `prepare-speech.py` (upstream commit `4870adfa25b1a32b4361592f1be8a40337c58d6c`). Preserve applicable notices and source obligations when distributing builds; the phonemizer is not an MIT dependency. AVFoundation supplies playback and Apple Speech supplies separate on-device recognition.

## Distribution metadata

`prepare-speech.py` writes `MinimumOSVersion = 18.0` into both iOS eSpeak framework slices, matching their compiler targets. The macOS slice uses `LSMinimumSystemVersion = 14.0`. Apple rejects uploads when an embedded iOS dynamic framework omits its minimum OS, even if local archive/export succeeded. `testflight.py` checks every embedded dynamic framework's minimum-OS metadata before export/upload. Existing prepared artifacts need their matching plist metadata refreshed or must be rebuilt after changing this packaging code; do not change the compiled minimum version by editing metadata alone.

The current eSpeak and upstream llama artifacts do not include matching dSYMs, so Xcode can report non-blocking symbol-upload warnings. App-owned dSYMs are present; complete native speech/runtime crash symbolication is not claimed.
