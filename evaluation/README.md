# Model quality evaluation

This suite compares Small, Balanced, and Qwen3.5 2B through Harbour's production Swift prompt builders, validators, `LocalModel` actor, and pinned llama.cpp b10549. It uses fictional records. Evaluation generations run locally; the harness makes no hosted inference API calls. Save the fictional prompts, generated outputs, and provenance with the report.

The JSON fixture separates development cases from held-out cases. Expected answers are read by the scorer, never placed in a model prompt. Fixes may use development outputs. Freeze the source before evaluating held-out outputs; further tuning requires a new suite with untouched held-out cases. The explicitly labelled development regressions include the previously observed English/French record-access denials, French scheduling failures, and sky explanation.

The frozen v1 suite contains 121 cases: 59 development and 62 held out, with 60 English and 61 Canadian French inputs. Its SHA-256 is `7a013eae0da56e0d829513ebd4c33a54eccd45c4ce6e8da4ffa81857d42fb5d9`. Across all three models, Standard plus the 19-case Quick/Extended subset yields 477 unique quality runs. Two extra Standard repetitions for eight timing cases yield 525 final runs. Runtime boundary diagnostics are additional checks.

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
python3 evaluation/score.py \
  --rows build/eval-final/small.jsonl build/eval-final/balanced.jsonl build/eval-final/qwen35.jsonl \
  --efforts quick,standard,extended --repeats 3 \
  --baseline build/eval-baseline/score.json \
  --output build/eval-final/score.json \
  --review-queue build/eval-final/reviews.json
```

The download helper verifies pinned revisions, byte counts, and SHA-256 values. The runtime helper verifies its source archive and builds into an isolated prefix. The runner refuses to overwrite an output directory, evaluates models sequentially, and records source, executable, suite, prompt, runtime, and model provenance.

Prepare the baseline with `python3 scripts/prepare-eval-baseline.py --output-directory build/eval-baseline-workspace`. It exports the original Core builders and validators from `e8028af`, with the versioned compatibility adapter. Run that workspace's `scripts/evaluate-models.py` with `--baseline-prompts`; this flag alone does not restore old Core source. Use the same suite, models, host, native runtime, and sampling settings for both workspaces. One baseline repeat suffices for paired quality comparisons; repeat the representative final timing cases three times.

## Evidence and scoring

Standard runs every fixture. Quick and Extended run the fixtures explicitly marked `effortSubset`; only Standard's `timingSubset` receives repeated runs. Greedy repeats measure latency and determinism, rather than independent quality samples. Record cold load separately from warm requests, and retain failures and partial runs.

Cold load means the first actor request includes model loading. Hash verification may already have populated the operating system's file cache, so this is not an uncached disk-start benchmark. Warm requests retain the loaded model while the actor clears inference memory for each prompt. Visit extraction uses the app's fixed 650-token budget and titles use 48 English/96 French tokens at every effort setting; routing and conversational budgets vary with effort.

Scoring distinguishes raw routing intent, the action accepted by production validation, ordinary reply quality, and raw visit extraction. A valid JSON envelope or a safely discarded proposal does not establish correct model output. The scorer checks expected source facts, selected medicines, schedule times, negated or quoted write requests, and both raw and accepted visit proposals. Language detection is only a lexical signal.

The final visit path constrains medicine quotes and action alternatives to supported instructions in the transcript. All models use the same constraint; they still select entries and generate medicine names and directions, which production validation checks again. Missing changes and unsupported generated fields remain quality failures. These results compare the complete app behavior, rather than unconstrained model intelligence.

Review every required open-ended answer for relevance, factual grounding, language, and extraction fidelity. Each review records the reviewer, decision, explanation, suite digest, and exact output digest. The recorded Codex reviews are qualitative AI review, not human clinician labels. Re-run the scorer with `--manual-reviews` after filling the queue; pending reviews block the gate. Preserve the queue and reviewed decisions with the raw evidence.

A reviewer may adjudicate only a `required_fact_missing` lexical match when the answer faithfully states the expected fact in different words. The decision must identify that failure, criterion, and supporting answer text. Preserve the original automatic result beside the adjudicated result. Routing, unsafe actions, extraction fields, bounds, and unsupported numeric facts cannot be overridden this way.

The default-model gate requires at least 95% raw Standard routing, every critical grounding/extraction and guard/schedule case passing, safe accepted actions across all models, no paired French or grounding regressions, and no English routing miss on a matched case Balanced routes correctly. Complete matrices and required reviews are mandatory. Failed required Qwen3.5 reviews block readiness; ordinary Small/Balanced quality misses remain visible in the report.

These are purposive engineering regression cases, not population accuracy estimates or clinical safety validation. Linux CPU timing and memory do not predict physical iPhone Metal performance. Native simulator tests separately check app integration and confirmation flows.
