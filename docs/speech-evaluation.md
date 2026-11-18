# Human speech evaluation

This study measures recognition from human audio. The existing medication-name text checks remain separate historical evidence. The initial medication plan is `docs/evaluation/speech-medications-v1.json`; its current status is **awaiting human recordings**, with no acoustic result or accuracy claim.

## Frozen plan and collection

The medication plan contains 24 scripts: six medication names in English and Canadian French, each isolated and in a short sentence. Record every script with at least two consenting speakers, once in quiet and once with ordinary background noise (at least 96 recordings). Use pseudonymous speaker IDs. Retain a consistent microphone position and note the noise source and recording setup. Accent descriptions are optional and self-described.

Read each script faithfully. A reviewer must listen and confirm the actual utterance matches its reference; recapture deviations rather than using an expected transcript that was never spoken. Use nonempty PCM WAV files. Keep audio and consent details outside Git, for example under ignored `build/speech-medications-v1/`. A rights reference may identify a private consent record or a dataset licence; it does not prove consent or speaker authenticity automatically.

Freeze the plan before recognition. Changing any script, target, variant, or planned coverage changes its SHA-256 and requires new bound manifests/results. Do not add accepted spellings after observing outputs.

Validate the plan:

```sh
python3 scripts/speech_evaluation.py \
  --plan docs/evaluation/speech-medications-v1.json --validate-plan
```

## Recording manifest

Write `recordings.json` next to the audio files. Compute SHA-256 on the exact plan bytes and each WAV. This deliberately incomplete example shows one row; it is not evaluation evidence:

```json
{
  "schema_version": 1,
  "suite_id": "harbour-medication-asr-v1",
  "plan_sha256": "SHA256_OF_PLAN",
  "recordings": [{
    "id": "speaker01-med01-en-isolated-quiet",
    "case_id": "med-01-en-isolated",
    "speaker_id": "speaker01",
    "condition": "quiet",
    "locale": "en-CA",
    "audio_path": "speaker01-med01-en-isolated-quiet.wav",
    "audio_sha256": "SHA256_OF_WAV",
    "reference": "acetaminophen",
    "reference_verified": true,
    "provenance": {
      "source_type": "human",
      "recorded_at": "2026-11-18T14:00:00-05:00",
      "device": "Actual recording device and microphone",
      "os": "Actual OS version",
      "rights": "Private consent record reference",
      "notes": "Microphone distance and noise setup"
    }
  }]
}
```

Paths are relative to the manifest directory and cannot escape it. The scorer checks the WAV and digest, derives duration/format, and binds the human-verified reference to the frozen script. It cannot verify collector attestations by listening.

## Recognition and output import

Run **the same WAV files** through each candidate recognizer, using each row's locale. Keep the original audio unchanged. For Harbour's on-device Apple recognizers, record the iPhone/iOS version, API/recognizer, asset availability and contextual hints. A different API, OS, hint list or model configuration is a separate system ID. Capture service failures and empty transcripts. Do not replace transcripts with medication matches, LLM corrections or fuzzy suggestions.

Export one JSON bundle per system. The importer is recognizer-independent: it scores captured raw outputs and does not call an inference service. Automated transcription adapters and actual device runs remain future collection work.

```json
{
  "schema_version": 1,
  "suite_id": "harbour-medication-asr-v1",
  "plan_sha256": "SHA256_OF_PLAN",
  "recordings_sha256": "SHA256_OF_RECORDINGS_JSON",
  "system": {
    "id": "apple-device-os-api-hints-v1",
    "recognizer": "Actual API or engine",
    "model": "Actual model or system-managed asset",
    "version": "Actual version or OS-bound asset description",
    "locales": ["en-CA", "fr-CA"],
    "device": "Actual inference device",
    "os": "Actual OS version",
    "settings": {"on_device": true, "contextual_hints": []}
  },
  "results": [{
    "recording_id": "speaker01-med01-en-isolated-quiet",
    "audio_sha256": "SHA256_OF_WAV",
    "locale": "en-CA",
    "status": "ok",
    "transcript": "Raw recognizer transcript",
    "latency_ms": 1200
  }]
}
```

For failure rows use `"status": "error"`, an `"error"` message and the same recording ID/hash/locale. The manifest, system configuration and complete result rows must be retained with the report. Never commit a real participant's identity or consent form.

## Scoring and completion

```sh
python3 scripts/speech_evaluation.py \
  --plan docs/evaluation/speech-medications-v1.json \
  --recordings build/speech-medications-v1/recordings.json \
  --results build/speech-medications-v1/apple.json \
  --results build/speech-medications-v1/other-system.json \
  --output build/speech-medications-v1/report.json
python3 -m unittest discover -s scripts -p 'test_speech_evaluation.py'
```

The policy is Unicode NFKC plus case folding, with punctuation, hyphens and apostrophes treated as token boundaries. Diacritics remain significant. Frozen target spans use zero-based token positions; `start` is inclusive and `end` exclusive. Canonical and explicitly accepted-variant name results are reported separately. Word error rate preserves substitution/deletion/insertion counts and the reference-word denominator. Name scoring uses the aligned target position; an unrelated mention elsewhere is insufficient. Raw transcripts and errors remain visible.

Reports retain grouping by case/name, locale, speaker, utterance type and noise condition. Missing or failed recognition rows contribute failures, not a smaller successful-only denominator. Empty successful transcripts count as deleted reference words. Compare systems only on the bound recordings; missing coverage keeps completion false. No corpus means no accuracy metrics. A complete coverage flag establishes execution coverage, not clinical reliability or acceptable accuracy.

Before #9 can close: collect and verify the full corpus, run at least two candidate configurations, publish the bound reports and representative errors, and document follow-up work. Record recognition errors separately from medication lookup and any later application correction. The status file must remain awaiting recordings until actual evidence exists.

