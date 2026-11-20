# Medication search verification

This protocol covers [#14](https://github.com/harbour-health/harbour/issues/14). The app searches the bundled official English/French vocabulary plus its curated familiar products. Source date, scope, counts and hashes remain in the [vocabulary manifest](../medication-vocabulary-manifest.json).

## Behavior and verification matrix

| Area | Expected result | Evidence |
| --- | --- | --- |
| Normal ranking | Exact name, exact ingredient, name prefix, ingredient prefix, name substring, then ingredient substring; ties are stable. All normal matches precede approximate suggestions. | Core medication-search tests. |
| Minor typos | Phonetic folding plus optimal string alignment handles adjacent transpositions, deletion, insertion, substitution and spacing variants for generic and curated familiar brand names. Leading-letter errors have a one-edit budget; newly supported four-letter phonetic queries require at most one normalized spelling edit. Existing longer-query phonetic matches remain supported. | Published query tables in the Core tests, including `netformin`, `emtformin`, `aleev`, `alvee` and the retained `adveel` match. |
| Ambiguity | Preserve distinct candidates; a suggestion never enables exact resolution or a validated write. | Custom-entry alias-conflict and confirmation tests. |
| English/French | Case/diacritic folding and official aliases behave consistently. | Core fixtures and bilingual native UI checks. |
| No matches | Clear no-match text appears when both normal and similar-name lists are empty; manual unconfirmed entry remains possible. | Native no-match/stale-result tests. |
| Confirmation | Selecting a similar name resets product confirmation and leaves Save disabled until checked. | Native candidate-selection test and existing confirmation tests. |
| Responsiveness | Measure normal, approximate and combined UI search against the full vocabulary in release mode. | Benchmark JSON/log for the tested CI commit. |

Actual Core, focused native and benchmark outcomes are recorded below for the tested source commit. Passing focused checks do not imply the entire CI workflow passed.

The current leading-letter/short-name revision adds four newly supported typo cases, a regression for existing phonetic matching, and ambiguity/two-edit rejection checks. These changes preserve exact resolution and the editor's selection/confirmation flow. Its fresh release measurements appear in the version 2 section below; the earlier native checks and version 1 reports remain historical evidence. Local Python reproduction checked the intended candidates against the bundled data, unrelated inputs, short-name ambiguity, and bounded edit-distance equivalence; it does not replace Swift execution.

## Reproduce

```sh
swift test --package-path HarbourCore
python3 scripts/audit-localization.py
mkdir -p build
swift run --package-path HarbourCore --configuration release medication-search-benchmark \
  --output build/medication-search.json --iterations 50
```

The native `MedicationSearchUITests` suite is selected by CI. It uses the common editor and fictional queries, without model inference, microphone capture or speech downloads. New UI files are registered by `scripts/generate-project.py`.

## Performance protocol

The version 2 benchmark first initializes the actual bundled vocabulary and records the entry count/publication date. It then measures sixteen fixed query categories with fifty samples each for normal search, suggestions, and the UI's normal-then-fallback path. The matrix includes exact generic/brand names, broad/ambiguous prefixes, French accents/aliases, generic/brand typos, leading-letter errors, short-brand transpositions and unrelated input. This produces 48 query/operation rows; the historical version 1 reports below contain twelve queries and 36 rows.

Each operation is warmed once. The report retains raw milliseconds, median, p95, maximum and a result-count checksum. First initialization is measured separately; it is not an uncached-disk claim. JSON includes compiled debug/release configuration, source commit when run in CI, OS and processor count. The CLI refuses to overwrite an existing result file.

CI publishes `harbour-medication-search` and prints the JSON in its job log, so results remain inspectable if artifact downloads are unavailable. Inspect the **release** report for the exact tested commit before treating responsiveness as verified. A narrow shared-runner latency threshold would be flaky; the observed values and outliers must be reviewed instead.

Mac/simulator results measure the full dataset and actual matching code; they do not establish physical-iPhone frame time or battery use. If the measured path stalls interactive typing, fix or move the work before closing the issue. No iPhone timing or acoustic-accuracy result is invented here.

## Evidence review

### Actual verification

The final expanded-typo [focused run 44679170836](https://github.com/harbour-health/harbour/actions/runs/44679170836), source `9258a93`, completed successfully: all 160 Core tests (including all seven medication-search methods) and both bilingual native UI methods passed. No-match/stale-result/manual-entry checks took 148.222 seconds; transposition-selection/product-confirmation checks took 76.501 seconds. Each method completed English and Canadian French on an iPhone 17 Pro ARM64 simulator running iOS 26.4.1, with Xcode 26.6 (17F113). The [raw excerpt](medication-search/verification-9258a93-focused.txt) and [evidence manifest](medication-search/evidence.json) preserve the exact source and results. The AAC probe also passed; model-accuracy checks were skipped. This is a passing focused workflow, not a claim that the separate full smoke run has finished.

The initial expanded-typo [run 44677252620](https://github.com/harbour-health/harbour/actions/runs/44677252620), source `b0d5f1f`, passed all 160 Core tests, runtime parsing, speech frontend checks and the benchmark. Both native methods failed at `app.launch()` with background-assertion acquisition timeouts, before navigation/search assertions. Only their initial English launches were attempted; French iterations were not reached. The [failure excerpt](medication-search/verification-b0d5f1f-initial.txt) preserves that outcome. It is not passing native evidence for the expanded matcher.

[Run 44279114912, job 134714795439](https://github.com/harbour-health/harbour/actions/runs/44279114912/job/134714795439) tested synthetic merge `6c78227a12e1529099cec08a9fd72701d211b50a`, with PR head `dd09de7db82d560c9099fc49f17ef8f44c643286`. All **159 HarbourCore tests passed**, including all six medication-search methods. Both `MedicationSearchUITests` methods passed: bilingual no-match/stale-result/manual-entry checks (98.266 seconds) and bilingual transposition-selection/product-confirmation checks (48.971 seconds). Each native method exercised English and Canadian French without model inference or speech downloads. The native destination was an iPhone 17 Pro simulator running iOS 26.4.1, built with Xcode 26.6 (17F113).

The **overall workflow failed** because other selected native UI test methods failed. The [verification excerpt](medication-search/verification-6c78227.txt) preserves the focused pass results together with other failed-method lines and the final failed-test status; use the linked full job for diagnostics. These results do not certify later source changes or label the full suite green.

The subsequent [run 44287969060](https://github.com/harbour-health/harbour/actions/runs/44287969060), head `df35c38`, again passed all 159 Core tests and both bilingual search UI methods. Its overall UI run failed in parent navigation/saved-record checks and simulator background-assertion errors; it is not recorded as a passing full workflow. The parent corrections are tracked in PR #17.

The [focused medication-search workflow 44295145945](https://github.com/harbour-health/harbour/actions/runs/44295145945), head `46de039`, completed successfully: 159 Core tests and both bilingual native search methods passed. The [excerpt](medication-search/verification-46de039-focused.txt) preserves the exact scope, source and native results. This was a passing focused workflow; the separate full smoke run at that head still failed in parent navigation checks.

After inheriting the final parent application fixes (`df38e19`), [focused workflow 44304344889](https://github.com/harbour-health/harbour/actions/runs/44304344889), head `75b051a`, also completed successfully: all 159 Core tests and both bilingual native search methods passed. Its [raw excerpt](medication-search/verification-75b051a-focused.txt) records the actual source and results. Full smoke validation remains a separate check; later evidence/check-name documentation edits do not change the tested application or test code.

### Expanded typo measurements (version 2)

[Focused run 44679170836](https://github.com/harbour-health/harbour/actions/runs/44679170836), source `9258a93fb0d9e00806c05ef1efc1d0a003062bc9`, passed Swift formatting, all 160 Core tests (including all seven medication-search methods), localization and the release benchmark. The [exact downloaded report](medication-search/expanded-9258a93.json) retains all 48 query/operation rows and 2,400 samples, using the same 8,299-entry vocabulary. Every median, p95 and maximum was recomputed from the samples. All 36 result-count checksums shared with version 1 are unchanged; the four new typo queries have no normal matches and return either three Metformin candidates or one Aleve candidate.

| Combined normal-then-fallback path | Median | p95 |
| --- | ---: | ---: |
| `netformin` | 25.5 ms | 33.1 ms |
| `emtformin` | 25.1 ms | 48.0 ms |
| `aleev` | 20.3 ms | 27.9 ms |
| `alvee` | 20.8 ms | 28.7 ms |

Across all sixteen queries, combined-path medians were 14.6–28.2 ms, the highest p95 was 61.8 ms, and the highest individual sample was 106.8 ms. First initialization took 305.4 ms. Suggestion work increased: for example, `metfomrin` suggestion median was 6.2 ms versus 2.9 ms in the earlier report. Retain the outliers; separate shared-runner executions do not isolate the matcher change or establish physical-iPhone responsiveness. The [evidence manifest](medication-search/evidence.json) pins the exact report hash and artifact provenance. Native UI verification is a separate check.

### Earlier release performance (version 1)

The [initial report](medication-search/baseline-a8e9729.json) is from source `a8e9729a4da21560d376874786657f40fa84f189`, [run 44275156006](https://github.com/harbour-health/harbour/actions/runs/44275156006). Its benchmark and Core steps succeeded before that duplicate push run was cancelled. Those observations motivated removing repeated medicine construction and display normalization during sorting. The [optimized report](medication-search/optimized-6c78227.json) comes from the completed benchmark step in run 44279114912, at the synthetic merge above. Its raw JSON was recovered from the printed job log; an artifact download was not required.

Both reports use the same 8,299-entry vocabulary dated 2026-11-02, release configuration, twelve queries, three operations and fifty samples per query/operation. All 36 result-count checksums match. Both report macOS 26.7.2 (25G332) and three processors; separate shared-runner executions are still not a controlled identical-host comparison. The merge includes other source changes, so these observations do not isolate one optimization's effect.

| Combined normal-then-fallback path | Initial observation | Optimized observation |
| --- | ---: | ---: |
| Median range across twelve queries | 16.4–59.5 ms | 17.0–27.3 ms |
| Highest query p95 | 68.8 ms | 65.5 ms |
| Highest individual sample | 94.1 ms | 107.5 ms |
| First vocabulary initialization | 435.1 ms | 307.6 ms |
| Broad prefix `met`: median / p95 | 59.5 / 68.8 ms | 17.0 / 22.2 ms |
| Typo `amoxcillin`: median / p95 | 23.8 / 33.9 ms | 27.3 / 65.5 ms |

The broad-prefix observation improved, while some other timings and the worst individual sample increased. Retain those outliers; no universal speedup or physical-iPhone responsiveness claim follows. The [evidence manifest](medication-search/evidence.json) records source/run provenance, report hashes, focused test results and comparison limits. Dataset expansion does not expand interaction-rule coverage or determine the correct treatment.
