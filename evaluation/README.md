# Model quality evaluation

This suite compares Small, Balanced, and Qwen3.5 2B through Harbour's production Swift prompt builders, validators, `LocalModel` actor, and pinned llama.cpp b10549. It uses fictional records. Evaluation generations run locally; the harness makes no hosted inference API calls. Save the fictional prompts, generated outputs, and provenance with the report.

The JSON fixture separates development cases from held-out cases. Expected answers are read by the scorer, never placed in a model prompt. Fixes may use development outputs. Freeze the source before evaluating held-out outputs; further tuning requires a new suite with untouched held-out cases. The explicitly labelled development regressions include the previously observed English/French record-access denials, French scheduling failures, and sky explanation.

The frozen v1 suite contains 121 cases: 59 development and 62 held out, with 60 English and 61 Canadian French inputs. Its SHA-256 is `7a013eae0da56e0d829513ebd4c33a54eccd45c4ce6e8da4ffa81857d42fb5d9`. Across all three models, Standard plus the 19-case Quick/Extended subset yields 477 unique quality runs. Two extra Standard repetitions for eight timing cases yield 525 final runs. Runtime boundary diagnostics are additional checks.

Development status: the original baseline and v9 candidate each completed 267 DEV runs with all required AI reviews. Later Standard-only focused comparisons contain 27 cases per model and retain their formal effort/matrix mismatch with that full baseline. At `790389f`, all 81 focused rows and 54 reviews are complete: Qwen3.5 21/27, Small 18/27, Balanced 18/27. The subsequent visit-policy rollback at `8b29359` passes 178 Core and 21 Runtime tests on its exact working-source snapshot, but its complete 12-output/12-review visit comparison scores Qwen0/4, Small2/4, Balanced0/4. Source-literal accepted medicines do not repair missing raw follow-ups. A same-revision Q6 precision diagnostic passes4/6 and still fails French factual checks. These are development results, not a complete final release comparison. Required quality gates remain blocked; held-out outputs are unopened. [Current results and immutable evidence](../docs/evaluation.md) preserve failed attempts, calibrated versus original historical grades, and explicit source/retention limits.

## Running

Use a Linux host or the isolated image. The default package configuration continues to use Apple's XCFramework; Linux CPU inference requires the explicit `HARBOUR_LINUX_RUNTIME=1` opt-in.

```sh
docker build -f scripts/model-eval/Dockerfile -t harbour-model-eval .
docker run --rm -it -v "$PWD:/workspace" harbour-model-eval
python3 scripts/evaluate-models.py \
  --models-directory /workspace/build/eval-models \
  --output-directory /workspace/build/eval-final \
  --efforts quick,standard,extended --repeats 3 \
  --context-checks --grammar-checks
python3 scripts/collect-model-evidence.py \
  --runs build/eval-final --output build/eval-final/run-manifest.json
python3 evaluation/score.py \
  --rows build/eval-final/small.jsonl build/eval-final/balanced.jsonl build/eval-final/qwen35.jsonl \
  --efforts quick,standard,extended --repeats 3 \
  --baseline build/eval-baseline/score.json \
  --run-manifest build/eval-final/run-manifest.json \
  --output build/eval-final/score.json \
  --review-queue build/eval-final/reviews.json
```

The download helper verifies pinned revisions, byte counts, and SHA-256 values. The runtime helper verifies its source archive and builds into an isolated prefix. The runner refuses to overwrite an output directory, evaluates models sequentially, and records source, executable, suite, prompt, runtime, and model provenance.

Prepare the baseline with `python3 scripts/prepare-eval-baseline.py --output-directory build/eval-baseline-workspace`. It exports the original Core builders and validators from `e8028af`, with the versioned compatibility adapter. Run that workspace's `scripts/evaluate-models.py` with `--baseline-prompts`; this flag alone does not restore old Core source. Use the same suite, models, host, native runtime, and sampling settings for both workspaces. One baseline repeat suffices for paired quality comparisons; repeat the representative final timing cases three times.

The baseline may run development and held-out phases separately using the identical preserved source and executable. Collect both directories with `collect-model-evidence.py --runs DEV_DIRECTORY HELDOUT_DIRECTORY --output MANIFEST_PATH`, then give all six JSONL streams and that manifest to the scorer. The collector rejects duplicate cases and changed run identities, and preserves each process's separate cold-load boundary. Capture the CPU, memory, affinity, and resource limits with `scripts/capture-eval-host.py --output HOST_SNAPSHOT_PATH`.

## Evidence and scoring

Standard runs every fixture. Quick and Extended run the fixtures explicitly marked `effortSubset`; only Standard's `timingSubset` receives repeated runs. Greedy repeats measure latency and determinism, rather than independent quality samples. Record cold load separately from warm requests, and retain failures and partial runs.

Cold load means the first actor request includes model loading. Hash verification may already have populated the operating system's file cache, so this is not an uncached disk-start benchmark. Warm requests retain the loaded model while the actor clears inference memory for each prompt. Visit extraction uses the app's fixed 650-token budget and titles use 48 English/96 French tokens at every effort setting; routing and conversational budgets vary with effort.

Scoring distinguishes raw routing intent, the action accepted by production validation, ordinary reply quality, and raw visit extraction. A valid JSON envelope or a safely discarded proposal does not establish correct model output. The scorer checks expected source facts, selected medicines, schedule times, negated or quoted write requests, and both raw and accepted visit proposals. Language detection is only a lexical signal.

The upstream appointment merge adds `create_appointment` and `list_appointments`, making the current catalog 21 rather than the baseline's 19. All 21 remain routing alternatives; frozen v1 still tests the original 19 intents and does not measure the two added appointment intents or appointment recall. As an explicit production-schema adaptation, the scorer accepts either the legacy three visit fields or those fields plus an appointments array of strict source-quote objects. It checks every raw/accepted appointment quote and reports raw, accepted, and fallback counts without treating source fallback as model recall. Original medicine and follow-up requirements and the fixture SHA remain unchanged. The separate main `Evaluation` routing cases and nine transcript cases run through `model-probe` on all three models for appointment intent/recall and medication frequency/time coverage; v1 results alone supply no coverage claim for those additions. Supplemental row counts derive from that source's fixtures, not a fixed count in this document.

The preserved `e8028af` baseline exposes 19 tools and the merged current pipeline exposes 21. Paired results therefore include the changed catalog, prompts, context, grammar, and validation; they do not isolate architecture or unrestricted model intelligence. Record both source identities and this comparability limit with the results.

For a single unambiguous current catalog instruction, the app can construct a source-verbatim proposal and validate its identity, dose directions and schedule before generation. Only that narrow branch requires an entry and constrains its copied name and instructions to exact transcript literals; optional or uncertain branches retain their existing field rules. These deterministically constrained fields measure app pipeline behavior, not independent model extraction or general intelligence. The model still generates the other summary categories, and final source validation remains mandatory; no parsed medicine fallback is inserted.

The final visit path constrains medicine quotes and action alternatives to supported instructions in the transcript. All models use the same constraints. Outside the prevalidated single-entry branch, models select entries and generate names and directions; within it, exact source literals constrain those fields. Production validation checks the emitted proposals again. Missing changes and unsupported generated fields remain quality failures. These results compare the complete app behavior, rather than unconstrained model intelligence.

Review every required open-ended answer for relevance, factual grounding, language, and extraction fidelity. Each review records the reviewer, decision, explanation, suite digest, and exact output digest. The recorded Codex reviews are qualitative AI review, not human clinician labels. Re-run the scorer with `--manual-reviews` after filling the queue; pending reviews block the gate. Preserve the queue and reviewed decisions with the raw evidence.

A reviewer may adjudicate only a `required_fact_missing` lexical match when the answer faithfully states the expected fact in different words. The decision must identify that failure, criterion, and supporting answer text. Preserve the original automatic result beside the adjudicated result. Routing, unsafe actions, extraction fields, bounds, and unsupported numeric facts cannot be overridden this way.

Before held-out evaluation, a scorer bug incorrectly labelled a source-anchored medicine instruction with one added terminal sentence full stop as an unexpected unsafe change. The generic instruction comparison now treats exactly that punctuation difference as equivalent for nonempty start/update directions. It preserves all wording, internal decimals, dose, frequency, clock times, negation and source anchoring; it does not normalize question marks, exclamation marks, ellipses, empty directions or stop instructions. Original raw outputs and pre-correction verdict artifacts remain available, and this changes neither fixture truth/digest nor a quality threshold. This comparator correction is separate from manual lexical adjudication.

The original Qwen default-promotion gate requires at least 95% raw Standard routing, every critical grounding/extraction and guard/schedule case passing, safe accepted actions across all models, no paired French or grounding regressions, and no English routing miss on a matched case Balanced routes correctly. Complete matrices and required reviews are mandatory. Failed required Qwen3.5 reviews block that promotion; ordinary Small/Balanced quality misses remain visible in the report. This frozen gate is unchanged and remains blocked. The user subsequently chose to keep Automatic and make 2B optional; the separately recorded [optional application scope](optional-model-scope-v1.json) retains all-model source-action safeguards, protected Automatic-model regressions, full comparisons/reviews and strict app/build validation without proposing Qwen default promotion.

Release scoring also requires a verified run manifest. It binds the scored streams to complete run metadata, exact file hashes, pinned model/runtime identities, and row prompt/grammar hashes. Baseline/final pairing checks comparable host, runtime, model, and budget identities while permitting the intentional prompt and validation changes. Partial development runs can be scored without a manifest, with readiness blocked.

These are purposive engineering regression cases, not population accuracy estimates or clinical safety validation. Linux CPU timing and memory do not predict physical iPhone Metal performance. Native simulator tests separately check app integration and confirmation flows.
