# Voice lab

A local Mac audition tool for comparing neural speech independently of the iOS app. It runs Kokoro 82M and Supertonic 3 through ONNX Runtime, with editable text, voice selection, English/French, speed, and Supertonic denoising steps. It does not change the app's speech engine.

## How it works

`scripts/voice-lab.py` serves `scripts/voice-lab.html` on loopback only. A single worker serializes synthesis and keeps loaded models warm. Generated WAV files and voice presets live under the supplied temporary asset directory. The browser supports playback and previous takes; **Play on Mac** invokes `afplay` when browser audio is inconvenient. Initial model loading is included in the displayed generation time.

## Running

Install `kokoro-onnx`, `soundfile`, and the official Supertonic Python requirements into an isolated environment. Download `kokoro-v1.0.onnx` and `voices-v1.0.bin` from the [Kokoro ONNX model release](https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.1). The asset directory must also contain the official Supertonic checkout at `supertonic/`, its ONNX assets at `supertonic/assets/onnx/`, and Hugging Face model metadata at `supertonic-model-info.json` (including pinned revision and LFS digests). Missing Supertonic presets download from that pinned revision on demand.

```sh
/private/tmp/harbour-voice-audition/venv/bin/python scripts/voice-lab.py \
  --assets /private/tmp/harbour-voice-audition --port 8766
```

Open `http://127.0.0.1:8766/`. Stop the server with Ctrl-C. Delete the temporary asset directory after finishing auditions; no model files belong in Git. Do not expose this developer server to the network.

## Changing it

Edit `catalog()` for model voices/languages and `synthesize()` for backend-specific controls. Keep controls limited to parameters the actual engine implements. The Kokoro frontend here uses eSpeak; the eventual native iOS frontend must be assessed separately. WAV files survive a server restart, while the in-memory take list does not.

## Dependencies and licensing

- [Kokoro ONNX](https://github.com/thewh1teagle/kokoro-onnx): MIT runtime wrapper; Apache 2.0 model weights. Its phonemizer/eSpeak dependencies have separate licences.
- [Supertonic 3](https://huggingface.co/Supertone/supertonic-3/blob/main/LICENSE): OpenRAIL-M weights, including medical-advice/interpretation restrictions. Private use should not be assumed to waive those terms. Upstream was archived in September 2026. Resolve suitability before incorporating it into Harbour; neutral speech comparison is separate from a deployment decision.
- Python, NumPy, SoundFile, ONNX Runtime and macOS `afplay`.

The first Supertonic F1 sample used eight steps at speed 1.0. The listener liked the sound but reported an extra “two” before “Tuesday”; the input contained “Tuesday” once. This is a human-reported synthesis issue, not a measured speech benchmark. No voice training or model weight changes were made.

## Preferred voices

After listening to Kokoro, the user selected `af_heart` as the preferred female voice and `am_liam` as the preferred male voice. Use these for the next native speech-backend comparison. Other presets remain available in the lab. This records listening preference; the iOS app still uses its existing speech backend until a separately verified native Kokoro integration is completed.
