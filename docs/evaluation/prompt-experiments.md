# Prompt and structure experiments

The tested extra passes and larger output format did **not** improve the complicated-summary failures. They remain outside the app's active summary flow. These are small synthetic engineering studies without clinician review, not clinical accuracy measurements.

| Experiment, Balanced Qwen2.5 1.5B Q4_K_M | Exposed cases | Fresh cases | Decision |
| --- | ---: | ---: | --- |
| Existing focused extraction on audit set | 0/4 | 4/8 | Reference only |
| Same extraction plus generic model audit | 0/4 | 4/8 | Reject; audit erased partial facts |
| Typed plans, one negation example | — | 6/16 paired cases | Reject; scope/type/phase errors |
| Typed plans, balanced demonstrations | 3/16 | 0/8 paired cases | Reject; demonstrations regressed |

The audit's four passing fresh examples were negative controls. Its result cannot be described as successful fact recovery. The typed scorer has a different representation and denominator; do not compare its percentages directly with the 11/20 legacy holdout score.

Typed v1 produced source-valid JSON on 16/16 cases but only six met the semantic contract. It classified a conditional ramipril stop as a negated reminder and reduced a prednisone taper to one negated phase. Added demonstrations changed the errors: 11/16 exposed and 6/8 fresh outputs passed source validation, yet only 3/16 and 0/8 met the full contract. Rewritten French and phase quotations were rejected; even empty controls acquired proposals. Grammar and evidence references alone do not guarantee accuracy.

Inference used the existing Balanced weights with fixed prompts and frozen datasets. No weight edits, LoRA, source-scanning additions or expected answers were supplied. Fresh paired templates are related, not independent clinical samples. Scoring checks scope, plan count, phase count/links and required details; it is not a complete clinical grader.

V1 completed inference before the Python summarizer encountered a missing category field. Its manifest records summary reconstruction from preserved outputs and snapshots; outputs were not regenerated to improve scores. The runner now handles instruction-shaped reports.

Evidence: [audit protocol](audit-experiment/protocol.json), [audit data](audit-experiment/dataset.json), [typed v1 protocol](instruction-experiment/protocol.json), [typed v1 data](instruction-experiment/dataset.json), [typed v2 protocol](instruction-experiment/v2/protocol.json), [typed v2 data](instruction-experiment/v2/dataset.json). Run directories preserve raw output, timings, hashes and prompt snapshots.

Next, test a smaller per-instruction classifier/extractor and independent completeness check against a stronger model and fresh contrastive cases. Keep it gated until recall improves without unsafe additions. These results support collecting representative reviewed examples before deciding on an adapter; they do not establish that LoRA will solve the failures.
