# Personal-name speech study

Execution is **awaiting human recordings**. This plan supports #10 and reuses the [human speech protocol](speech-evaluation.md) and scorer introduced for #9. Its text fixtures and unit tests are preparation; they are not acoustic results.

## Scope and frozen cases

`docs/evaluation/speech-personal-names-v1.json` has 24 cases: six fictional names, each isolated and within a short English or Canadian French utterance. The naming-tradition groups are Arabic, Spanish, Punjabi and Chinese. Examples include Amira Hassan, Omar Al-Khatib, María José García López and José Luis Rodríguez. Groups label the planned names, not speakers' ethnicity or the accuracy of an entire language.

The scripts cover a hyphenated family name, compound given names, multiple surnames and diacritics. The intended spelling is the canonical target. Predeclared Spanish accent-free spellings are accepted variants; strict scores retain the diacritics, and variant-accepted scores are separate. Do not add a variant because a recognizer emitted it.

The utterance locale is always `en-CA` or `fr-CA`. No Arabic- or Spanish-language speech support is claimed. A future full-language study needs a separately frozen plan, recognizer support checks and its own results.

## Collection and pronunciation

Use the same recording manifest and result-bundle contracts as the medication study, with this plan's suite ID and digest. For every case in each quiet/background-noise condition, collect at least two distinct speakers and two self-described accent descriptions (at least 96 recordings overall). If a speaker prefers not to describe their accent, retain their recording outside the completed study rather than inferring one. No ethnicity field is needed.

Ask speakers to read the fictional scripts faithfully in a pronunciation they can produce confidently. Record pronunciation/transliteration notes in `provenance.notes`, and have a reviewer listen to confirm the reference and intended name before recognition. Obtain help from someone familiar with a name's pronunciation when needed; spelling alone cannot establish acoustic ground truth. Preserve the actual pronunciation rather than synthesizing or correcting audio.

A recording's provenance includes:

```json
{
  "source_type": "human",
  "recorded_at": "2026-11-18T14:00:00-05:00",
  "device": "Actual microphone/device",
  "os": "Actual OS",
  "rights": "Private consent/licence reference",
  "accent": "Speaker's self-description",
  "notes": "Pronunciation and recording setup, confirmed before recognition"
}
```

Run identical audio through each candidate configuration. Retain the recognizer/model/version, locale, device/OS, hints and original transcript for each. The plan's name groups must all be represented, and missing accent/speaker/condition coverage prevents completion.

## Commands and interpretation

```sh
python3 scripts/speech_evaluation.py --plan docs/evaluation/speech-personal-names-v1.json --validate-plan
python3 scripts/speech_evaluation.py \
  --plan docs/evaluation/speech-personal-names-v1.json \
  --recordings build/speech-personal-names-v1/recordings.json \
  --results build/speech-personal-names-v1/system-a.json \
  --results build/speech-personal-names-v1/system-b.json \
  --output build/speech-personal-names-v1/report.json
```

Reports show strict/accepted target scores and word errors by naming group, accent, speaker, case, locale, utterance type and noise. Retain raw substitutions/omissions, errors and missing rows. Acoustic results must remain separate from LLM routing and medication matching. Compare variants and failures as well as aggregate scores; a small purposive set does not establish demographic fairness.

Before #10 can close, collect and verify the corpus, run the same files across at least two configurations, publish bound reports and representative failures by group, and record follow-up work. The existing typed-name report remains historical evidence with its original limits.
