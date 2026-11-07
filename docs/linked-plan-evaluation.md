# Linked-plan evaluation

See the measured [results](evaluation/linked-plan-study/results.md), [case matrix](evaluation/linked-plan-study/case-matrix.md) and [interpretation](evaluation/linked-plan-study/findings.md).

This is an experimental text-only comparison for difficult visit instructions. It tests whether splitting extraction into smaller model calls improves complete plans and conditional details; it does not change the app's active summary pipeline.

## How it works

First run the unchanged focused extractor on the original 20-case summary set with Qwen2.5 7B Q4_K_M. Its frozen executable and matching prompt snapshots preserve comparability with the earlier 1.5B and 3B results.

The new [bilingual dataset](evaluation/linked-plan-study/dataset.json) has 16 authored engineering cases in eight English/French pairs. It checks complete case agreement, phase count and links, initial action/scope where specified, required details and their structured condition/timing/frequency/duration fields. Translated pairs are related observations. Clinical correctness, all possible omissions, and real transcription errors are not comprehensively scored. Phase checks enforce counts and predecessor links; the original scorer does not comprehensively adjudicate the chronological meaning of every phase. Treat these as fixture-contract passes, not proof of a complete medical plan.

Compare these variants with the same 1.5B and 7B weights and greedy sampling:

1. Existing one-pass typed-plan prompt.
2. Model extraction for each numbered source passage, followed by model-selected grouping of instruction phases.
3. The same first-pass outputs plus an additive per-passage omission check, then grouping again. This preserves the initial extraction for a paired comparison. Coverage may add evidence-backed instructions or flag concerns, but cannot erase a wrong initial proposal.

The model selects instructions, qualifiers and phase grouping. Source numbering, deduplication and validation do not extract missing clinical facts. Grouping must use each proposed atom exactly once, with no duplicates or mixed subjects/kinds. Unsupported quotations are rejected. Correct quotations alone do not prove correct interpretation.

`needsReview` reflects model concerns or validation failures. It is not a reliable completeness detector until measured against failure cases. A flagged case receives no accuracy credit merely for abstaining. No app review UI or automatic medication mutations are enabled by this experiment.

## How to change it

`LinkedInstructionPlans.swift` owns prompts, grammars, evidence validation and grouping. `LinkedInstructionEvaluation.swift` runs inference and preserves every prompt/output. `InstructionEvaluation.swift` supplies the shared strict scorer. It matches independent follow-ups by required content rather than assuming output order. Optional structured-field expectations keep older fixtures readable while enforcing the new dataset's richer contract.

Freeze a new dataset and protocol before inspecting outputs. Do not overwrite prior runs, change gold to fit responses, or compare the typed-plan percentage directly with the old summary percentage. The old summary schema and new plan schema have different contracts. Raw artifacts explain errors separately from correctness totals.

## Configuration

Build with `swift build -c release --package-path HarbourRuntime --product model-probe`. Then:

```sh
python3 scripts/run-linked-plan-study.py \
  --model /path/qwen2.5-1.5b-instruct-q4_k_m.gguf \
  --model /path/qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf
```

Both 7B shards must be adjacent under their official filenames. The runner hashes all shards, Swift source files, dataset and executable, saves a protocol before inference, and refuses to overwrite an existing protocol. Use `--output` for a new comparison. Copied executables require the existing `llama.framework` beside them or an appropriate library search path.

Context is 4096 tokens. The one-pass output limit is 2048; per-passage extraction/coverage use 1536; grouping uses 512. Inputs that exceed context fail visibly. `--mode linked --audit` in `evaluate-text-models.py` runs both linked variants, reusing initial outputs. Coverage timing includes extraction and the first linking call; these are engineering costs, not controlled phone timings.

The preregistered gate requires at least three additional full-case passes versus one-pass for each model, at least 6/8 in each language, no new empty/conditional/negation failures and no excess plans. Even a gate pass only supports further review. An experiment that fails remains outside the active app.

## Dependencies

Local `llama.cpp` Metal runtime, existing Qwen GGUF files, Swift, Python standard library, `HarbourCore` and `ModelProbe`. No cloud inference, audio, LoRA or weight editing. Official 7B weights are from [Qwen](https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF), revision `bb5d59e06d9551d752d08b292a50eb208b07ab1f`. Temporary weights are removed after results and checksums are saved; pre-existing app caches are retained.

## Apple system-model comparison

`scripts/evaluate-apple-instructions.py` runs the same typed-plan task and scorer through `SystemLanguageModel.default`, with native `@Generable` Swift types. It requires macOS 26+ and local Apple Intelligence assets; this Mac reported `available` before evaluation. It uses greedy sampling, a 2048-token response limit and default guardrails. Errors/refusals count as failures, without retrying around safeguards. Framework-injected instructions and guided generation differ from llama's grammar, so this is a task comparison rather than identical inference conditions.

Run it after the Qwen comparison, using a freshly built `model-probe`. It preserves dataset, source and executable hashes plus OS version. Apple manages the model assets, so the probe does not claim a pinned weight hash or identical future results after OS/model updates. No Harbour provider setting is changed. See Apple's [Foundation Models documentation](https://developer.apple.com/documentation/FoundationModels/) and [acceptable-use requirements](https://developer.apple.com/support/terms/acceptable-use-requirements-for-the-foundation-models-framework).
