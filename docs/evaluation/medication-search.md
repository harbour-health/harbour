# Medication search verification

This protocol covers [#14](https://github.com/harbour-health/harbour/issues/14). The app searches the bundled official English/French vocabulary plus its curated familiar products. Source date, scope, counts and hashes remain in the [vocabulary manifest](../medication-vocabulary-manifest.json).

## Behavior and verification matrix

| Area | Expected result | Evidence |
| --- | --- | --- |
| Normal ranking | Exact name, exact ingredient, name prefix, ingredient prefix, name substring, then ingredient substring; ties are stable. All normal matches precede approximate suggestions. | Core medication-search tests. |
| Minor typos | Phonetic folding plus optimal string alignment handles adjacent transpositions, deletion, insertion, substitution and spacing variants for generic and curated familiar brand names. | Published query tables in the Core tests. |
| Ambiguity | Preserve distinct candidates; a suggestion never enables exact resolution or a validated write. | Custom-entry alias-conflict and confirmation tests. |
| English/French | Case/diacritic folding and official aliases behave consistently. | Core fixtures and bilingual native UI checks. |
| No matches | Clear no-match text appears when both normal and similar-name lists are empty; manual unconfirmed entry remains possible. | Native no-match/stale-result tests. |
| Confirmation | Selecting a similar name resets product confirmation and leaves Save disabled until checked. | Native candidate-selection test and existing confirmation tests. |
| Responsiveness | Measure normal, approximate and combined UI search against the full vocabulary in release mode. | Benchmark JSON/log for the tested CI commit. |

Test definitions are not a claim that the new checks have passed. The PR's CI run contains their actual outcomes.

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

The benchmark first initializes the actual bundled vocabulary and records the entry count/publication date. It then measures twelve fixed query categories with fifty samples each for normal search, suggestions, and the UI's normal-then-fallback path. The matrix includes exact generic/brand names, broad/ambiguous prefixes, French accents/aliases, generic/brand typos and unrelated input.

Each operation is warmed once. The report retains raw milliseconds, median, p95, maximum and a result-count checksum. First initialization is measured separately; it is not an uncached-disk claim. JSON includes compiled debug/release configuration, source commit when run in CI, OS and processor count. The CLI refuses to overwrite an existing result file.

CI publishes `harbour-medication-search` and prints the JSON in its job log, so results remain inspectable if artifact downloads are unavailable. Inspect the **release** report for the exact tested commit before treating responsiveness as verified. A narrow shared-runner latency threshold would be flaky; the observed values and outliers must be reviewed instead.

Mac/simulator results measure the full dataset and actual matching code; they do not establish physical-iPhone frame time or battery use. If the measured path stalls interactive typing, fix or move the work before closing the issue. No iPhone timing or acoustic-accuracy result is invented here.

## Evidence review

The [initial release measurements](medication-search/baseline-a8e9729.json) cover all 8,299 entries: first initialization 435 ms; combined-path medians 16–59 ms and worst p95 69 ms across the fixed query matrix. The benchmark and Core tests completed successfully in [run 44275156006](https://github.com/harbour-health/harbour/actions/runs/44275156006) before that redundant push run was cancelled; PR validation was retained. These values motivated removing repeated display normalization and medicine construction during sorting. The [evidence manifest](medication-search/evidence.json) records the baseline source and candidate-report location. Shared-runner timing comparisons are descriptive, not controlled identical-host experiments.

The PR description should link the passing Core/native runs and the benchmark log, summarizing measured latency and any failures. Preserve remaining device limits and candidate ambiguity. Dataset expansion does not expand interaction-rule coverage or determine the correct treatment.
