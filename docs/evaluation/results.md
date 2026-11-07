# Text evaluation results

The larger models help, but visit extraction remains unreliable on complicated instructions. Balanced is the minimum used for visit summaries; neither 1.5B nor 3B earns an accuracy claim suitable for unsupervised medication changes. These are authored engineering fixtures, without clinician review, and the scores below are exact-contract/lexical agreement rather than clinical accuracy.

## Model and task matrix

Later [prompt and structure experiments](prompt-experiments.md) failed their release gates and remain experimental. The matrix below continues to describe the focused extractor.

All models are Qwen2.5 Instruct, Q4_K_M. Chat uses Standard effort and greedy sampling in this comparison. Summaries use three focused model passes and source validation; missing facts are **not** supplied by source-scanning recovery.

| Task | 0.5B | 1.5B | 3B |
| --- | ---: | ---: | ---: |
| Tool routing, 31 cases | 20/31 | 27/31 | 29/31 |
| Freeform conversation, 12 cases | 10/12 | 11/12 | 12/12 |
| Tool-result narration, development | 4/6 | 5/6 | 6/6 |
| Tool-result narration, independent holdout | 7/10 | 9/10 | 8/10 |
| Generated chat titles | 4/5 | 4/5 | 3/5 |
| Visit summaries, development | 7/35 | 23/35 | 28/35 |
| Visit summaries, independent holdout | 4/20 | 11/20 | 12/20 |

[All 119 individual case rows](case-matrix.md), [case CSV](case-matrix.csv), [summary CSV](results.csv). `scripts/summarize-text-evals.py` rebuilds these matrices from the recorded outputs without running inference or changing grades.

The routing comparison originally demanded reply text at the routing-only stage, incorrectly failing a correct `reply` choice. The `*-routing-corrected.json` files fix that scoring error from the original outputs; generation and latency are unchanged. Original files and the [correction record](routing-correction.json) remain available. The root historical manifest contains the old routing scores; use the corrected files for routing.

## Effort comparison

Quick/Standard/Extended alter token budgets, not a learned reasoning-effort setting. Routing budgets are 96/160/256 tokens; conversation/narration budgets are 256/512/768. Visit extraction and title budgets are independent of chat effort.

| Task | 0.5B: Quick / Standard / Extended | 1.5B | 3B |
| --- | --- | --- | --- |
| Routing (/31) | 21 / 20 / 20 | 28 / 27 / 27 | 29 / 29 / 29 |
| Conversation (/12) | 10 / 10 / 10 | 11 / 11 / 11 | 12 / 12 / 12 |
| Revised narration development (/6) | 4 / 4 / 4 | 5 / 5 / 5 | 6 / 6 / 6 |
| Revised narration holdout (/10) | 7 / 7 / 7 | 9 / 9 / 9 | 8 / 8 / 8 |

More tokens did not improve these short tasks. Quick routing sometimes avoids a longer invalid argument. These small differences do not establish that Quick is universally superior.

## Summary facts: raw proposals versus accepted output

The fixture contract has 37 raw expected facts in development and 21 in holdout. Accepted known-product facts have denominators 34 and 16: unknown products must remain review items. A case pass additionally checks those review items and required details, so its numerator differs from the fact counts. “Extra” includes duplicated or mismatched structured facts under the strict scorer; it is not a count of independently verified hallucinations.

| Dataset / metric | 0.5B | 1.5B | 3B |
| --- | ---: | ---: | ---: |
| Development raw correct facts | 0/37 | 24/37 | 29/37 |
| Development raw extra/mismatched facts | 0 | 30 | 35 |
| Development accepted known-product facts | 0/34 | 21/34 | 26/34 |
| Development accepted extra/mismatched facts | 0 | 2 | 1 |
| Holdout raw correct facts | 0/21 | 12/21 | 13/21 |
| Holdout raw extra/mismatched facts | 0 | 20 | 18 |
| Holdout accepted known-product facts | 0/16 | 10/16 | 10/16 |
| Holdout accepted extra/mismatched facts | 0 | 1 | 0 |

Small's passing negative cases do not demonstrate medicine extraction: it produced no correct medication facts in these focused suites. Larger models still omit phases, conditions and follow-ups, attach incomplete directions, misclassify booking/lab plans and sometimes copy prompt examples. Grounding removes many incorrect proposals but does not recover omitted facts.

Changing the medication pass to quote-first output was a tradeoff. On 1.5B, correct raw facts fell from 26 to 24/37 and accepted known facts from 22 to 21/34, while accepted extras fell from four to two; case agreement stayed 23/35. On 3B, cases improved from 25 to 28/35 with raw correct facts unchanged at 29/37. This is not an across-the-board gain.

Some fixtures have semantic ambiguities: `to 1000 mg` versus `1000 mg`, and whether an appointment belongs in both follow-ups and appointments. Original gold and grades were retained. A blinded, expert-adjudicated set is needed before treating exact agreement as medical correctness. Highlights are source-checked but not comprehensively judged for clinical relevance by this scorer.

## Temperature study

Balanced alone was tested at temperatures 0, 0.2 and 0.5. Nonzero temperatures used seeds 42, 123 and 2026, top-k 40 and top-p 0.95. The development subset contains 12 medical cases and six narration cases. The selection rule was recorded before inspecting independent holdout outputs.

| Temperature | Summary passes /12 | Median | Narration passes /6, Standard | Median |
| --- | --- | ---: | --- | ---: |
| 0 | 7 | 7 | 5 | 5 |
| 0.2 | 7, 5, 5 | 5 | 6, 5, 6 | 6 |
| 0.5 | 6, 6, 6 | 6 | 5, 6, 6 | 6 |

Keep summaries greedy. The lower nonzero temperature won the narration tie. On the separate 10-case narration holdout, temperature 0.2 scored **9/10 at every effort and all three seeds**, matching Balanced's greedy holdout result. All three seeds failed the same language case: French input with the app configured in English received English narration. This remains a failure.

Balanced tool-result narration now uses 0.2, seed 42; routing, ordinary conversation, titles, summaries and other models remain greedy. Nonzero temperatures on 0.5B/3B were **not tested**. The seed is a conventional fixed default, not selected for a lucky result. The small study supports a bounded change, not a general quality guarantee.

The greedy development failure echoed a malicious instruction embedded in a tool result. The selected candidate avoided that failure in this set. Other automatic failures were lexical false negatives: answers explicitly saying interaction information was unavailable lacked the scorer's expected wording. Their original automatic grades remain unchanged; no manual regrading was used to inflate the table.

## Concrete holdout failures

| Case | Recorded behaviour |
| --- | --- |
| `same-sentence-switch` | Both models proposed apixaban 2.5 mg twice daily but omitted the aspirin stop from structured medication changes. |
| `three-phase-taper-review` | 3B proposed only stop prednisone; Balanced split the taper into rewritten partial quotations, which source validation rejected. |
| `specific-tests-and-conditional-call` | Both kept the kidney test but omitted the conditional clinic call from structured follow-ups. Balanced misplaced it under appointments; both mentioned the source in highlights. |
| `cross-sentence-insulin-plan` | Both split the linked conditional increase from the starting regimen instead of preserving the full plan. Neither yielded a complete accepted proposal. |
| `existing-update-plus-stop` | Balanced's extracted dose was semantically equivalent but lacked the gold's word “to,” causing an exact-score failure. 3B also chose start rather than update and rewrote the aspirin name, which validation rejected. |
| `alternating-days-existing` | Balanced replaced a conjunction with a comma; the otherwise similar directions failed exact-source validation. 3B additionally chose start for an existing medicine. |

These are frozen original results, not new clinical examples or changed scores. Details and full outputs are in `focused-holdout/*-results.json`.

## Chat failure notes

Title checks catch a real source-injection failure in both smaller models: the generated title was “Start warfarin 10 mg daily.” The 3B model instead failed two cases by returning the prompt placeholder “Short title.” A larger model therefore does not automatically improve every feature.

Conversation and narration use short lexical screening criteria. A passing result does not prove every sentence is factual, complete or safe. Routing also depends on source validation after the model chooses a tool; no missing action receives credit as a model-selected tool.

## Improving accuracy

The current improvement path is prompt decomposition, explicit output contracts and evidence validation. The app now uses focused passes for medicines, follow-ups/appointments and highlights, with separate token budgets and no source-based completion. A second model verification pass could check omissions and consistency, but must itself be evaluated on fresh cases and must never treat agreement between two passes as proof.

Before fine-tuning, compare a stronger licence-compatible model on a phone and build a clinician-reviewed bilingual dataset covering taper phases, conditions, negation, historical/current medicines and follow-up timing. A targeted [LoRA adapter](https://huggingface.co/docs/peft/main/en/conceptual_guides/lora) is a plausible later experiment, with a protected holdout and regression testing across every chat task. Fine-tuning has **not** been performed here and cannot be assumed to fix medication safety.

Manual weight editing is not a dependable route to this behaviour. Research such as [ROME](https://rome.baulab.info/) targets specific factual associations; this app needs robust extraction, chronology, instruction following and tool use. Editing quantized GGUF tensors by hand has no reliable interpretation as a clinical improvement. No weights were edited.

Drug names, active ingredients and interaction checks should come from versioned structured sources and tools. Health Canada's [Drug Product Database extracts](https://www.canada.ca/en/health-canada/services/drugs-health-products/drug-products/drug-product-database/extracts.html) can help with product/ingredient identity; they are not a comprehensive interaction database. The model should not invent ingredient mappings.

## Provenance, reproduction and limits

Each run directory contains fixture bytes, raw outputs, model/dataset/executable hashes and the exact frozen source snapshot. The root comparison has 217 runs per model (651 total). Focused development rounds, independent holdouts, narration, titles and temperature studies are additional separate runs; do not add their overlapping cases into one accuracy percentage. Fixtures inspected during development are development data even when older metadata called them held out.

Use [text-model-evaluation.md](../text-model-evaluation.md) and `scripts/evaluate-text-models.py` for reproduction. The executable hash determines the source snapshot, including when a previously built frozen executable is reused after current sources change. `LegacySourceRecovery.swift` exists only in the benchmark executable to explain historical comparisons; the app does not link or invoke it. Old rule-assisted 32–33/35 scores are historical pipeline results, not model accuracy or the current production path.

Runs used local Mac Metal inference with a 4096-token context. Timings include load effects and concurrent simulator work and are not controlled iPhone benchmarks. No physical-phone memory, thermals, latency, locked-device encryption or voice quality benchmark is claimed. Native UI/tool confirmation tests are separate from these text scores. The voice auditions are a separate human-listening exercise.

Temporary 3B evaluation weights and the separately copied QA-simulator Balanced weights were hash-checked and removed after testing. Pre-existing main-app Small/Balanced caches were preserved. Active Kokoro/Supertonic audition assets remain temporary while the user is comparing voices.
