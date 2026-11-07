# Testing

## What it is

Layered checks for deterministic health-record rules, local inference contracts, neural speech and native iPhone flows. Text-model accuracy results are reported separately from app correctness tests.

## How it works

Core and runtime tests run without downloading an LLM. Speech tests check the two supported preferences, chunking and pronunciation; the real waveform test explicitly skips unless local model/style paths are supplied. Hosted tests exercise persistence, permissions, exports, PDF rendering and playback. UI tests inspect actual navigation, confirmation screens and presentation lifetimes. Simulator-only limitations are explicit skips, never successful device checks.

```sh
swift test --package-path HarbourCore
swift test --package-path HarbourRuntime
swift test --package-path HarbourSpeech

HARBOUR_KOKORO_MODEL=/path/kokoro-v1.0.onnx \
HARBOUR_KOKORO_VOICES=/path/to/styles \
swift test --package-path HarbourSpeech
```

Native checks use the shared Harbour scheme, a selected simulator UDID, one worker and ad-hoc signing. Signing matters for Keychain-backed lock state; an unsigned build can compile while failing at launch. Use an isolated test simulator rather than the user's active preview. Run UI automation serially to avoid competing simulator/test-manager sessions.

```sh
xcodebuild test -project Harbour.xcodeproj -scheme Harbour \
  -destination 'platform=iOS Simulator,id=SIMULATOR-UDID' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

Use [App Store screenshots](app-store-screenshots.md) for ten validated images per language. Those are authored fixtures, not evidence of inference accuracy. [Text evaluation](text-model-evaluation.md) freezes model, source, prompt and dataset hashes and retains raw generations; [results](evaluation/results.md) distinguish scoring stages and rejected experiments.

## How to change it

Put record-rule tests in HarbourCore, runtime parser/sampler tests in HarbourRuntime, and audio frontend tests in HarbourSpeech. Use hosted tests for services and UI tests for actual presentation/gesture regressions. Add new Swift files through `scripts/generate-project.py`. Assertions should verify user-visible outcomes and mutation boundaries; do not replace failed flows with canned responses or silently skip them. Capture settled layouts after animations and inspect the images.

## Configuration

The speech environment variables above enable neural synthesis only. Native completion tests require Kokoro assets installed in the test app. `--app-store-screenshots` is a DEBUG-only, separate fictional store; `--ui-test-unlocked` bypasses lock presentation for ordinary UI fixtures. Do not use those flags as production behavior. CI's optional model-accuracy workflow is skipped on ordinary pushes; a skipped job is not an accuracy pass.

## Dependencies

Xcode and an installed iOS simulator runtime, prepared llama/Typst/speech libraries, Swift and Python. Speech preparation needs CMake/Ninja and report preparation needs Rust. Physical-device checks remain necessary for microphone accuracy, locked-device encryption, interruptions, thermal/memory behaviour and sustained real-time voice performance.
