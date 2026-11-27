# Instruction-plan experiments

## What it is

A typed proposal format and reproducible probe for negation, conditional actions, ordered courses and follow-up timing. This is an experimental developer tool; the app continues using its existing focused visit extractor and reviewed tool flow.

## How it works

`InstructionPlans` numbers lexical source units. The model chooses relevant units, classifies scope (`affirmed`, `negated`, `conditional`, `historical`, `uncertain`), and extracts linked steps with exact conditions, timing, repetition and duration. A reference is evidence, not an instruction to infer missing facts. The validator rejects nonexistent references, invented quotations and forward/cyclic phase links. It cannot establish semantic completeness or correct classification. Empty output stays empty.

The probe retains raw JSON, validation outcomes, scope/phase/detail failures and latency. Bilingual pairs change one feature at a time. Negative instructions remain explicitly negated proposals, so grades are not comparable to the old flat summary's empty-result contract. No proposal authorizes a write. There is no deterministic fact recovery or training.

## How to change it

Edit `HarbourCore/InstructionPlans.swift` for the representation, prompt and grammar, and `ModelProbe/InstructionEvaluation.swift` for evaluation. Freeze executable, prompt snapshot, dataset and hashes before inference. Changing a prompt after viewing failures makes those cases development data; add a separately reported fresh group. Do not promote a candidate merely because its JSON validates. Both tested prompt variants failed the release gate; [results](evaluation/prompt-experiments.md) explain why.

## Configuration

```sh
swift build --package-path HarbourRuntime -c release --product model-probe
python3 scripts/evaluate-text-models.py --mode instructions \
  --model /path/model.gguf \
  --dataset docs/evaluation/instruction-experiment/v2/dataset.json \
  --output /tmp/instruction-run
```

Use separate output directories. Context is 4096 tokens, output budget 2048, temperature 0, seed 42 by default; flags permit controlled sampling studies. Input limits are 3600 characters/64 units, with at most 12 plans/eight steps each. The probe rejects longer inputs rather than truncating them; it does not implement long-visit reconciliation.

## Dependencies

HarbourCore normalization, HarbourRuntime/llama.cpp, verified local GGUF weights, Python 3 and Swift. No external inference service or LoRA training. Fixtures are synthetic engineering examples without clinician validation.
