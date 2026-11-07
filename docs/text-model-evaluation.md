# Text model evaluation

## What it is

A local, text-only comparison of chat routing, ordinary conversation, tool-result narration, and fictional visit extraction. It records raw generations separately from source validation. Current focused extraction has no missing-fact recovery; a benchmark-only legacy comparison retains the historical completeness pass. Exact-field and regular-expression checks measure these fixtures; they do not establish clinical accuracy.

## How it works

`HarbourRuntime`'s `model-probe --text-suite` uses the same local inference library and prompts as the app. Routing, conversation, and tool-result cases run at all three chat effort budgets. Visit summaries have a fixed budget, so repeating them for every effort would duplicate identical runs. The old generation protocol (prompt, grammar, 650-token budget at commit `7b3a2e0`) is compared with the revised protocol (1,536 tokens). Both use current validators; this is not an end-to-end replay of the old app.

Each case checkpoints its raw output, errors, latency, expected facts, validated facts, and final pipeline facts. Catalog aliases are scored by catalog identity. Unknown products must become review items rather than invented ingredient mappings. Stopping medication requires that medication to exist in the fixture's saved records.

## Running and changing it

```sh
swift build --package-path HarbourRuntime -c release
python3 scripts/evaluate-text-models.py --model /path/small.gguf --model /path/larger.gguf
```

Use `--dataset`, `--output`, or `--executable` to override paths. Runs are serial to avoid competing for the GPU. The wrapper hashes models, the executable, dataset, and relevant sources, and preserves source snapshots alongside results. It never deletes model files. Temporary downloads must be removed explicitly after the process exits; pre-existing application caches must be retained.

The original `docs/evaluation/text-suite-v1.json` has now been inspected during development and must be treated as development data. Author new held-out fixtures separately, freeze prompt/sampling decisions first, and preserve the original grades after inspecting outputs. Define expected medication actions, complete instructions, follow-up source evidence, and appointment evidence. Add `savedMedicineIDs` when testing changes to existing medication. Conversation checks are deliberately modest pattern checks; inspect the actual replies for quality and safety beyond those checks.

## Configuration and dependencies

Requires macOS, Swift, the bundled `llama.xcframework`, local GGUF weights, Python 3, and HarbourCore. Metal inference uses a 4,096-token context. Greedy decoding is the default; nonzero temperature tests are explicit and seeded. Host timing includes model initialization on the first case; it is not an iPhone benchmark. Download provenance and licensing must be checked before shipping any candidate model. No speech, microphone, cloud inference, training, or weight editing is involved.


## Focused passes, sampling and matrices

Use `--mode focused` for the current three-pass visit protocol, `--mode narration` for result/status prose, and `--mode titles` for the shared production title prompt and parser. `--mode text` retains the historical monolithic comparison. Focused pass budgets are 1,536 medicine, 1,024 follow-up/appointment and 768 highlight tokens per 1,800-character chunk. These are independent of chat effort.

```sh
python3 scripts/evaluate-text-models.py --mode focused --model /path/balanced.gguf \
  --dataset /path/new-fixtures.json --output /path/new-run --temperature 0 --seed 42
python3 scripts/summarize-text-evals.py
```

The wrapper records `--temperature` and `--seed`. Nonzero sampling uses fixed top-k 40/top-p 0.95. If an older frozen executable is reused after editing sources, snapshots are located by executable hash rather than incorrectly claiming that current source bytes produced it. Do not overwrite evidence from an earlier run.

[Results and limitations](evaluation/results.md), [task matrix](evaluation/matrix.md) and [119-case matrix](evaluation/case-matrix.md) separate model proposals, accepted facts, development data, independent holdouts, effort and sampling. The corrected routing files fix a scoring-only error without regenerating or changing other scores. Historical rule-assisted summary scores must not be presented as current model accuracy.
