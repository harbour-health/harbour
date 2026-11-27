# Interpretation and next steps

## Original summary contract

The unchanged focused extractor scored 16/20 with 7B, compared with the recorded 11/20 for 1.5B and 12/20 for 3B. This is an improvement on the same synthetic fixture contract. It is not a clinician-adjudicated estimate or a physical-iPhone benchmark.

The four remaining 7B failures have different causes:

- `existing-update-plus-stop`: the raw output contains a stop, but rewrites the source name `aspirin` as `aspirin / asa`; evidence validation rejects it. The metformin dose is also missing the gold's `to`, an exact-contract mismatch despite similar dose meaning.
- `topical-product-review`: the model treats `hydrocortisone 1% cream` as the product name instead of putting `1% cream` into directions. The unknown-product review contract differs from the expected fields. This is not simply a missing sentence.
- `specific-tests-and-conditional-call`: the test and conditional call are both present but merged into one follow-up entry, failing the expected separate actions.
- `long-discussion-and-orders`: the medication is extracted, but its sentence is also included in the follow-up item with the blood-work instruction, mixing categories.

The 7B model passed the original same-sentence switch, taper and cross-sentence insulin cases. Original grades and raw output remain unchanged. Do not reclassify wording differences as clinical errors or dismiss the rejected source-name substitution as harmless for a write operation.

## What the new comparison tests

The new bilingual set uses a richer typed-plan contract, including phase counts/links and explicit condition, timing, repetition and duration fields. Compare its three variants within this set. Do not compare its percentage directly with the old 20-case summary score.

A review flag, valid JSON or exact quotation is not proof that a complete plan was understood. Phase predecessor checks do not comprehensively adjudicate chronology. The fixtures are authored engineering references and contain related translations, not independent blinded clinical examples.

## Next implementation hypothesis

Where recorded errors show cross-passage extraction or mixed-subject grouping, tighten the generation contract before considering more prompt examples. A per-passage grammar can allow only that passage's source ID; grouping constraints can exclude cross-subject combinations. These constraints restrict the model's choices, rather than adding omitted clinical facts through source scanning. They still cannot establish correct scope, complete conditions or phase interpretation.

Keep a separate review signal for unsupported or incomplete proposals, preserve accepted source evidence, and measure how many real failures that signal misses. Unknown medicines and unresolved plans must stay review items. Do not infer frequency, clock times or permission to stop a medicine.

Run any next constrained-generation candidate on a newly frozen set, retaining these cases as development/regression data. A targeted adapter becomes a reasonable experiment after the representation is stable and representative corrected examples exist. No fine-tuning or weight editing was performed in this study.

The active app extractor and device-based model selection remain unchanged by these experiments. See [results](results.md) for measured gates and the Apple system-model comparison when complete.

## Measured candidate outcomes

On the 16-case typed-plan set, one-pass/linked/linked-plus-coverage scored 0/1/1 for 1.5B and 4/3/3 for 7B. Both new variants failed the preregistered gates. Coverage added no full-case passes. Among failed cases, review flags covered only 9/15 for 1.5B and 9/13 for 7B; four to six failures remained unflagged. It would be unsafe to interpret an absent review flag as proof of completeness.

Apple's initial native-schema adapter scored 0/16: 12 outputs failed predecessor-sequence validation and four failed source-evidence checks. These were local validation failures, not framework refusals or unavailable-model errors. For example, the first step used `after: 0` instead of null; the same response also misclassified a stop as negated and omitted its replacement. This result tests the initial adapter, not the best achievable Apple-specific implementation.

No candidate was promoted to the active app, and no device-based model-selection policy was changed. Temporary 7B shards were checksum-verified and removed; see `cleanup.json`. Existing app model caches and Apple-managed assets were retained.
