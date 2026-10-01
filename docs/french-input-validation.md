# French input validation

## What it is

HarbourCore accepts a bounded set of French phrases for symptom cues, dose records, literal schedule times, label instructions and source-grounded visit medicine proposals. This is prototype heuristic coverage, not a diagnosis, a complete clinical language model or evidence that an unrecognized description is safe.

## How it works

`InputLanguage.folded` removes case and accents and normalizes curly apostrophes only for matching. The original symptom, question, OCR instruction and visit quote remains the source of record. Model arguments never replace the user's medicine, numeric reading, schedule time or symptom facts.

`HealthRules.emergencyCue` recognizes French equivalents of the existing emergency examples: persistent severe chest pain, difficulty breathing, loss of consciousness, new confusion and pain not relieved by medicine. Local explicit prefix negation such as `pas de`, `aucune` or `sans` suppresses that cue; a later affirmative cue still matches. History and third-person mentions remain conservative matches because the heuristic cannot establish who is affected now. The app presents conditional emergency guidance. Explicitly selected emergency signs always retain escalation, even when free text is negated.

The model selects French app actions from the full tool catalog, using the same conversation pipeline as English. `ToolPlanner` validates source facts after selection and resolves medicine names through `Catalog`; it does not select or filter tools by French keywords. Negated and hypothetical French medicine mutation proposals remain rejected by the source validator. A dose proposal requires one saved medicine and exactly one explicit status. French `pris`, `sauté` and `rappelle plus tard` map to existing dose statuses without changing their serialized values.

`CareRules.times` accepts literal `8 h`, `20h30`, `20 h 30` and `20:30` times alongside existing English `am`/`pm` syntax. It does not infer a schedule from `le matin`, `deux fois par jour` or other frequency descriptions. OCR directions are copied from bounded French instruction lines; recognizing a label does not prescribe a regimen.

`VisitReview` requires an exact transcript quote, source medicine name and exact instruction substring. French start/update/stop verbs must occur directly before the source medicine name, with only bounded articles or regimen phrases between them. The containing source sentence is checked for negation, questions, hypotheses, history and third-person reports even when the model supplies a shorter quote. Unknown medicines remain transcript highlights without model-created ingredients. Selecting proposed changes, checking the unchanged medicine baseline and revalidating against the saved transcript are still required before applying a change. Revalidation uses the medicine spelling present in the quote, so a French alias survives review while its canonical identifier and ingredients stay unchanged.

## How to change it

Extend cue patterns in `HealthRules.swift`, source/status validators in `ToolPlanner.swift`, literal time/question/label parsing in `Care.swift`, or source instruction/context patterns in `Visits.swift`. Keep the phrase list bounded and add positive, negated and contradictory fixtures in `FrenchInputTests.swift`. In particular, negation inside a breathing cue such as `je ne peux pas respirer` expresses inability to breathe and must not suppress the cue.

Add spelling aliases through `Catalog.names(for:)` and `Catalog.resolve(_:saved:)` in `Records.swift`. An alias may refer only to an existing canonical catalog medicine. Keep custom saved medicine names literal, and never add ingredient or interaction claims from model output.

Core remains an English-output library for existing consumers; localize error messages, guidance, timeline labels and generated appointment-note sections at the app display/export boundary described in [Canadian French localization](localization.md). Preserve original user content, exact source quotes, tool names, enum raw values and the existing Core appointment-note `Questions` delimiter. The app rebuilds localized notes from structured records rather than splitting translated prose.

The focused verification command is `swift test --package-path HarbourCore --jobs 2 --filter FrenchInputTests`. Run the full HarbourCore suite with `swift test --package-path HarbourCore --jobs 2` to check English behavior as well. Fixtures test deterministic validation and do not establish French speech recognition accuracy, on-device model extraction accuracy or clinical completeness.

## Configuration

There is no new environment variable or persisted language flag. Matching uses the fixed `fr_CA` locale for case/accent folding. Existing limits remain in force: at most eight distinct valid schedule times, 12 visit proposals per extraction, bounded quotes and instructions, and the existing catalog. System language selection and translations belong to the app localization layer.

## Dependencies

The implementation uses Foundation regex/string handling, HarbourCore `Catalog`/`Records`, `CareRules` and `VisitReview`. It adds no service, package or network dependency. Existing emergency source links and the narrow interaction catalog remain unchanged.
