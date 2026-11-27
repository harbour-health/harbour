# Medication-name text checks — November 9, 2026

These are actual local model generations on Mac Metal with the current app routing prompt and source validator. Empty saved records; greedy sampling; grammar-constrained tool JSON. Raw generations, timings and validation errors are retained in the adjacent JSON files.

| Check | Alex · 0.5B | Sam · 1.5B |
| --- | ---: | ---: |
| Difficult-name add requests · correct route and exact identity | 12/12 | 12/12 |
| Negated add · correct reply route | 0/2 | 0/2 |
| Negated add · source validator blocked write | 2/2 | 2/2 |
| Misspelled medicine · unresolved, no automatic substitution | 1/1 | 1/1 |
| Personal name only · reply, no medicine write | 1/1 | 1/1 |
| Complete expected outcome, including correct route | **14/16** | **14/16** |

Alex chose `add_medication` for both negations; Sam chose `remove_medication`. Both were rejected as `forbidden` by the existing source validator. These are routing failures, not successful model understanding. The phonetic case selected add but was rejected as `missingMedicine`, as expected: similar names are offered for human review only.

The paired-name subset uses the identical English/French requests with Amira Hassan, Jean-François Nguyen, Gurpreet Singh and Aïcha Diallo (all fictional). It passed 8/8 on both models. A separate Wei Chen introduction did not create a medication. This small sample checks regressions; it does not establish demographic or accent fairness.

Difficult medicines include hydrochlorothiazide, rosuvastatine, levothyroxine, empagliflozine, rivaroxaban and pantoprazole. Exact identities come from the bundled source vocabulary, not names invented by the model. Current core tests also check source counts, canonical French aliases, bounded mentions, priority/budget of speech context and the no-fuzzy-mutation boundary.

## Reproduce and change

Build `swift build --package-path HarbourRuntime -c release --product model-probe`, then:

```sh
HarbourRuntime/.build/release/model-probe /path/to/model.gguf \
  --medication-name-suite \
  --dataset docs/evaluation/medication-name-cases.json \
  --output /tmp/medication-names.json
```

Use the pinned app GGUF weights. On this Mac, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for build commands. Fixture expectations are written before running and are not fed to the model. Extend the dataset rather than changing scores after inspecting failures.

## Limits and dependencies

No audio, acoustic speech-to-text accuracy, accents, generated reply quality, dose extraction, appointment/visit summarization or 7B model is evaluated here. These results do not supersede the broader summary/chat evaluations. Speech hints are wired to both recognition paths, but their acoustic benefit remains unmeasured. Requires HarbourCore, HarbourRuntime/llama.cpp, local model files and Mac Metal; no hosted inference or newly downloaded weights were used.
