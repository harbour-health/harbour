# Confirmed application bugs: issues 2–4

All three claims are confirmed against production Core from commit `5158710fa518816ca14781ca4d7a4c3f459675b8`. Root ran the actual Swift package in an isolated copy: **16 characterization methods passed, including all 12 methods for these three issues**, with zero failures. Passing means the tests reproduced the current defects and their controls; no fix was applied. The execution receipt records all 45 canonical source files exact before and after. No model inference, production edit, evaluation change, or UI automation occurred.

Execution: `core-execution.json`, SHA256 `ba118f7a64e27e81389b031f9d00cb131624b0b93ab61da16f70c91092eec884`.
Original Swift log: `core-swift-test.log`, SHA256 `7d175a7a15bab3b29c461f9efe712c9a984388630729b15616c09e95f7f2a436`.

## Issue 2 — confirmed, narrowed to an incorrect appointment draft

**Input:** `Make a summary of my appointment.` or `Prépare un résumé de mon rendez-vous.`; selected tool `create_appointment`.

**Expected:** Documentation or clarification, without an appointment-creation proposal.

**Actual Swift result:** Both pass `WriteRequestValidation`, pass `AppointmentRules.isAppointment`, and return `.appointment(original)`. The same inputs correctly validate as `.note` when the selected tool is `copy_note`. No source reply fallback intercepts them. The wrong date-free draft is structurally valid and defaults to the reference day's start of day.

**Root cause:** The [documentation connector guard](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Sources/HarbourCore/WriteRequestValidation.swift#L92-L99) omits `of/de`. [Appointment validation](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Sources/HarbourCore/ToolPlanner.swift#L597-L602) then accepts the appointment noun via a general fact heuristic, without requiring an appointment-creation command.

**Controls verified:** `summary about`, `notes for`, appointment-summary word order, and `résumé pour` reject appointment creation; genuine EN/FR appointments and appointment creation with trailing summary text remain allowed; quoted, speculative and negated requests reject. Existing [documentation tests](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Tests/HarbourCoreTests/WriteRequestValidationTests.swift#L156-L177) omit the `of/de` forms.

**Not proved / impact limit:** This is not automatic saving. The [dispatch](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/Harbour/ChatView.swift#L198-L206) opens an appointment editor. Its [initial state](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/Harbour/AppointmentsView.swift#L21-L28) is date-unconfirmed, and its [Save gate](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/Harbour/AppointmentsView.swift#L47-L49) requires date confirmation and Save. These UI boundaries were inspected in source, not exercised on a device.

## Issue 3 — confirmed, narrowed to an unconditional removal confirmation

**Input:** `Remove Metformin if my doctor approves.` or `Retire la metformine si mon médecin approuve.`; selected tool `remove_medication`, with Metformin saved.

**Expected:** Preserve the approval condition; do not authorize a present unconditional removal.

**Actual Swift result:** Both pass the write validator and return `.remove(savedMetformin)`. The returned action contains only the saved medicine, without the condition. Equivalent leading-condition requests reject. Validation itself leaves the supplied records unchanged.

**Root cause:** The [hypothetical guard](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Sources/HarbourCore/WriteRequestValidation.swift#L102-L117) recognizes `if/si` at the start; its broader conditional check is skipped when an affirmative command is found. The [removal branch](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Sources/HarbourCore/ToolPlanner.swift#L637-L639) subsequently checks only one saved medicine's identity.

**Controls verified:** Direct EN/FR removal works. Leading approval conditions, negation, quotation and reported instructions reject. An unsaved medicine and two named saved medicines reject. The issue is condition placement, not a missing saved-identity check.

**Not proved / impact limit:** This is not automatic deletion. Chat displays an [explicit destructive confirmation](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/Harbour/ChatView.swift#L68) naming the medicine, with no retained condition. Only its Remove button calls [storage removal](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/Harbour/AppStore.swift#L102-L109). This persistence boundary was source-inspected, not clicked or executed.

## Issue 4 — confirmed false rejection of an authorized request

**Input:** `Could you record my dentist appointment Tuesday at 2 pm?` or `Peux-tu enregistrer mon rendez-vous mardi à 14 h ?`; selected tool `create_appointment`.

**Expected:** Prepare the requested appointment draft, with normal user confirmation before saving.

**Actual Swift result:** Both pass the explicit write-intent validator, but fail `AppointmentRules.isAppointment`, so `ToolPlanner.validate` throws `PlannerError.forbidden`. The ordinary source fallback is absent; after rejection the app fallback is `rejected_action_clarification`, a reply asking the user to rephrase.

**Root cause:** The earlier validator [recognizes polite commands](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Sources/HarbourCore/WriteRequestValidation.swift#L43-L47), but the shared [appointment-fact heuristic](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Sources/HarbourCore/Appointments.swift#L39-L42) excludes every `could` and question mark. It conflates a polite command with speculative transcript content.

**Controls verified:** `Could you…` without a question mark still rejects. `Can you…?` and `Peux-tu…?` reject because of the question mark. The corresponding direct requests and `Can you…` / `Peux-tu…` with a full stop pass. Genuine speculation, negation and quotation remain rejected. Thus this is not a general inability to parse the appointment, date, French verb, or polite prefix.

**Not proved / impact limit:** The Core rejection and generic fallback are reproduced; no actual model frequency, rendered chat, or appointment save is claimed. [ModelManager's dispatch](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/Harbour/ModelManager.swift#L205-L217) establishes the source-level reachability after a model selects the tool. Its `groundedReply` handles closed retrieval/count/history requests, not affirmative appointment booking.

## Scope retained

These are application bugs conditional on a supplied selected tool. They do not turn an incorrect raw model choice into a correct model prediction, do not estimate occurrence rates, and do not establish automatic mutation. All controls and observations use unchanged production Core, separately stored reproduction tests, and no evaluation exceptions. The earlier static notes and all three original test sources remain unchanged.
