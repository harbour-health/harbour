# Visit summary extraction

## What it is

Visit review uses three focused local-model calls to produce medication proposals, follow-ups/appointments, and concise discussion highlights. The normal interface, share text, and visit report use structured summaries rather than a raw speech transcript.

## How it works

For each bounded source chunk, `VisitExtractionPass` requests medication orders, future tasks/appointments, and discussion highlights separately. The medication pass copies source evidence before its name/action/instructions fields. Few-shot examples are prompt guidance, not executable rules or canned answers. Each pass has a narrow JSON grammar. Candidates are merged only after source validation. A missing model fact stays missing: no source-scanning process fills in drugs, doses, follow-ups, or appointments.

Validation rejects unsupported quotes, borrowed doses, fabricated ingredients, negated/speculative changes, and invalid changes to existing medication. Unknown products remain review items instead of acquiring an invented ingredient mapping. Validation can reject correct-but-rewritten evidence; it is deliberately separate from raw model recall in evaluations.

Dose, frequency, food/timing, and duration are presented separately. Tapers, alternating schedules, and conditional regimens retain their full model-extracted directions rather than becoming invented clock reminders. Relative follow-up dates are interpreted from the visit date only after the model extracts the task. Saving still requires review; confirmed medication changes remove obsolete schedules and add only explicit representable schedules.

Summaries use at least Qwen Balanced: the measured 0.5B model omitted most medication orders even with focused prompts. This is a capability floor for this operation, not a claim of clinical reliability. Downloads remain local and show progress. Chat model selection remains independent. Old saved summaries remain until Refresh summary is requested; confirmed changes are never silently undone.

## How to change it

Prompts, source checks, and data structures live in HarbourCore's `VisitExtraction.swift`, `Visits.swift`, and `VisitDirections.swift`; grammars are in HarbourRuntime. `VisitsView` coordinates model calls/progress and review. `ModelManager.visitModel` chooses the minimum capable model. `VisitReport` and `AppStore.shareVisit` consume structured content.

Source-scanning recovery is retained only in `ModelProbe/LegacySourceRecovery.swift` for historical comparison. It is outside the app target. Do not reintroduce it into the runtime summary path or count it as model recall. `VisitExtractionTests.testOmittedModelFactsStayOmitted` enforces this boundary.

Keep development and holdout artifacts separate. Numeric agreement and source quotes do not prove paraphrase meaning or clinical correctness. Cross-sentence regimens, speaker attribution, conflicts, and complex conditions remain measured failure areas, not solved by the grammar.

## Configuration and dependencies

Each source chunk is at most 1,800 characters; each model call has a 4,096-token context. Medication/follow-up/highlight token limits are 1,536/1,024/768 and are independent of chat effort. Grammar categories allow up to 12 items; quotes are limited to 600 characters and directions to 480. Depends on HarbourCore, HarbourRuntime, local GGUF weights, and the protected archive. Speech accuracy and physical-device performance are outside the text benchmark.
