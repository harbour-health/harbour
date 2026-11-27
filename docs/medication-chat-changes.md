# Medication corrections and chat confirmations

## What it is

The agent has an explicit `update_medication` tool for correcting a saved dose. Removal and clearing data have separate positive-intent checks and labelled modal alerts rather than an action-sheet popover anchored to the chat container.

## How it works

The LLM selects the tool using the ordinary chat prompt and saved-record context. Validation then checks the original user text. A dose-only correction must identify exactly one saved medicine, one explicit dose and the same unit as its single saved dose. The replacement preserves other instructions and the existing schedule. Changes involving several doses, conversions, new schedules or uncertain names request a generated clarification; the app does not infer a prescription.

A model-generated remove/clear decision cannot proceed merely because a medicine is mentioned. Removal needs an affirmative deletion command and rejects dose/update language and conditional requests. Clear additionally needs an all-records/data target. These are execution-boundary checks, not keyword dispatch replacing the model. In particular, a typo cannot silently select another product via a model-supplied argument.

Failed medicine writes use `medicineClarificationPrompt`, with the attempted tool and saved names only. The original numeric dose and prescription directions are not replayed to that question-generation pass. It asks the user to restate the edit using an exact saved name. Validation remains tied to the current explicit request, so users should restate the full correction rather than answering with a name alone. This is tool-error feedback, not a replacement action inferred by keyword matching. A broader generic fallback prompt was rejected during native testing after it produced an unsupported clinical statement.

The editor opens as the normal confirmation draft; no dose is changed until the user verifies and saves. Destructive actions record a pending tool event before showing the alert. While LLM narration is pending, chat renders a Review requested change status, so the transcript is not blank. The Thinking spinner and insertion/reflow animation are suppressed while a confirmation is open, preventing overlapping status text behind a modal alert. Cancelling closes the pending draft and preserves data.

## How to change it

Keep Tool cases, descriptions, structured-output grammar and routing evaluations aligned. Validation belongs in `ToolPlanner.validate`; use original source text instead of a model's reconstructed write arguments. Chat presentation is in `ChatView.execute` and MessageView. Tests cover incorrect destructive decisions, precise dose preservation, uncertainty, native model selection and real chat/editor/alert flows.

## Configuration

Model auto-selection is unchanged. The cached Balanced model enables the optional native regression; missing verified weights produce an explicit skip rather than a download. Dose correction currently supports one dose with an unchanged unit and deliberately defers complex edits to clarification/manual review.

## Dependencies

HarbourCore ToolPlanner, Catalog and CareRules; ModelManager's existing local inference and grammar; AppStore mutation/pending-event tracking; the ordinary MedicineEditor and SwiftUI alerts.

## Verification

The full core suite passed: 146 tests, zero failures. Native cached-Balanced tests verified the real agent selects the dose-correction tool for the exact-name request and that a misspelled name reaches a generated question. The final question was “Could you please specify the exact medicine name you want to change?” No dose or clinical opinion was included. These are targeted regressions, not a broad medical-accuracy evaluation.

`harbour-chat-review-20261109.xcresult` verified a real chat request opens the 400mg editor, retains breakfast/dinner directions, requires confirmation and preserves Metformin after cancelling. `harbour-review-completion-20261109.xcresult` verified the final alert with a visible review status and no overlapping Thinking spinner, cancellation, the compact existing editor, timeline, the visit review workflow and the final generated clarification. The earlier broad fallback candidate in `harbour-final-records-20261109.xcresult` failed and was rejected; its passing UI captures are presentation evidence only.

The model checks ran on the CPU-only simulator and do not establish physical-phone latency, Small-model accuracy, or clinical acceptance. The changed clarification pass uses a fixed 96-token output budget; source dose validation rejects negative quantities, compound units and trailing schedule directives rather than partially accepting them.
