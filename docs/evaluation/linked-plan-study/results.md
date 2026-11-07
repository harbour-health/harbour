# Linked-plan study results

These are strict synthetic text-fixture results, not clinical accuracy or iPhone performance. All candidate prompts and expected fields were frozen before candidate inference. Paired French/English cases are related examples.

## Unchanged focused summary baseline

| Model | Complete cases /20 |
| --- | ---: |
| 1.5B | 11/20 |
| 3B | 12/20 |
| 7B | 16/20 |

The original summary contract and the new typed-plan contract differ. Their percentages must not be treated as one comparable accuracy scale.

## New bilingual comparison

| Model | Variant | Complete /16 | English /8 | French /8 | Valid output /16 | Review flags | Median seconds |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1.5B | One pass | 0/16 | 0/8 | 0/8 | 10/16 | 0 | 2.0 |
| 1.5B | Linked | 1/16 | 0/8 | 1/8 | 7/16 | 9 | 2.1 |
| 1.5B | Linked + coverage | 1/16 | 0/8 | 1/8 | 7/16 | 9 | 4.2 |
| 7B | One pass | 4/16 | 2/8 | 2/8 | 14/16 | 0 | 7.4 |
| 7B | Linked | 3/16 | 2/8 | 1/8 | 7/16 | 9 | 7.3 |
| 7B | Linked + coverage | 3/16 | 2/8 | 1/8 | 7/16 | 9 | 14.5 |

Coverage reuses the linked first-pass generations. Its timing includes initial extraction and linking; it is not a separately timed rerun. Valid output means the parser/evidence checks passed, which does not establish semantic correctness.

## Preregistered engineering gates

| Model | Candidate | Gain ≥3 cases | ≥6/8 each language | No new control/scope failure | No excess plans | Gate |
| --- | --- | --- | --- | --- | --- | --- |
| 1.5B | Linked | Fail | Fail | Pass | Pass | Fail |
| 1.5B | Linked + coverage | Fail | Fail | Pass | Pass | Fail |
| 7B | Linked | Fail | Fail | Fail | Pass | Fail |
| 7B | Linked + coverage | Fail | Fail | Fail | Pass | Fail |

No failed experiment should replace the active extractor. An engineering gate pass supports further review only, not medication writes or a clinical accuracy claim.

## Review-flag performance

| Model | Variant | Failed cases flagged | Passing cases flagged |
| --- | --- | ---: | ---: |
| 1.5B | Linked | 9/15 | 0/1 |
| 1.5B | Linked + coverage | 9/15 | 0/1 |
| 7B | Linked | 9/13 | 0/3 |
| 7B | Linked + coverage | 9/13 | 0/3 |

A model concern or validator rejection is only a review signal. Unflagged failed cases show why this signal cannot guarantee completeness.

See [all candidate cases](case-matrix.md), [protocol](comparison/protocol.json), [dataset](comparison/dataset.json) and raw outputs under `comparison/`. The 7B frozen-baseline first launch failed because the copied executable lacked its adjacent framework; `7b-launch-failure/` preserves that error. The completed baseline followed after restoring the existing dependency. No failed launch is counted as an inference result.

Rebuild this report with `python3 scripts/summarize-linked-plan-study.py`. No grades are changed.

## Apple on-device system model

| Backend | Contract passes | English | French | Parser/evidence valid | Errors or validation failures |
| --- | ---: | ---: | ---: | ---: | ---: |
| SystemLanguageModel.default | 0/16 | 0/8 | 0/8 | 0/16 | 16 |

This is the one-pass typed-plan task with native `@Generable` output and default guardrails, not the focused-summary baseline or the linked pipeline. Apple adds its own system instructions and schema. Its OS-managed model is not pinned to a GGUF checksum. Refusals, API errors and local evidence/sequence validation failures all count as failures; raw errors distinguish them. No safeguard bypass or retries were used. See [Apple manifest](apple/manifest.json) and [raw outputs](apple/apple-results.json). This initial generic adapter is not a conclusion about the best achievable quality with an Apple-specific prompt/schema.
