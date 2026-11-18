# User stories and acceptance paths

These stories describe the intended experience for an independent older adult and a caregiver helping on the same iPhone. Both interfaces use one local record set and the same editors and confirmation rules. A caregiver layout does not select another patient or create remote access.

## Status and evidence

- **Current:** the entry point or feature exists in the linked implementation documentation.
- **Acceptance path:** the user-visible outcome to check; illustrative messages are not recorded model results.
- **Unvalidated hypothesis:** a design assumption requiring observation.
- **Proposed:** a future change or verification task with an issue reference.

Current features can still have incomplete accessibility or model-quality evidence. See [testing](testing.md) and [evaluation](evaluation.md). Interface preservation/accessibility work is tracked by [#11](https://github.com/harbour-health/harbour/issues/11); speech studies by [#9](https://github.com/harbour-health/harbour/issues/9) and [#10](https://github.com/harbour-health/harbour/issues/10). The observed user trial [#13](https://github.com/harbour-health/harbour/issues/13) is deferred.

## People, goals and assumptions

| Role | Goal | Unvalidated hypothesis |
| --- | --- | --- |
| Independent older adult | Ask for help and review a small number of clear actions. | Talk, Message and Record a visit are distinguishable without explanation. |
| Person using large text or VoiceOver | Reach and understand the same actions and confirmation controls. | Layout adaptation and labels work with the person's preferred accessibility setup. |
| Caregiver helping on the same phone | Find detailed records and make deliberate corrections for the same person. | The shared-record explanation prevents interpreting a layout change as a patient change. |
| Canadian French speaker | Complete the same tasks in French while retaining original recorded facts. | Translated instructions and speech errors are understandable in ordinary use. |

These are product roles, not validated participant personas. Fictional names in fixtures do not establish demographic fairness.

## Medication management

### MED-01 — Find and add a medication

**Current:** [vocabulary and suggestions](medication-vocabulary.md), [label scanning](medicine-labels.md), [shared editors](navigation-and-actions.md).

**Role/goal:** Either person records the exact product being used.

**Preconditions:** The person can check the product label; no candidate is already authorized to save.

**Acceptance path:**
1. Enter a medication name through Message, the Caregiver editor, or label scanning.
2. Show available normal matches; approximate suggestions require deliberate selection.
3. Open the shared editor with the chosen name and recorded instructions visible.
4. Require the product/ingredient check and explicit Save. A name match does not establish strength or formulation.
5. Show the saved record after successful persistence.

**Recovery/cancel:** Ambiguous names require a choice or restatement. Unknown products can remain unconfirmed. Correct the draft before Save; Cancel makes no record change.

**Language/evidence:** English/French aliases support lookup; original label text is retained. Acoustic recognition and fuzzy-search completion remain tracked separately in #9/#14.

### MED-02 — Correct a saved medication

**Current:** [medication corrections](medication-chat-changes.md).

**Role/goal:** Either person corrects recorded information without losing unrelated directions.

**Preconditions:** One saved medication and one explicit recorded dose are identified; chat correction keeps the existing unit. Complex edits require clarification or manual editing.

**Acceptance path:** Open its shared review/editor, show the revised value, retain other recorded directions and schedule, and require confirmation before persistence.

**Recovery/cancel:** If the name or requested value is uncertain, ask for a complete restatement. A question about a saved dose is a read request. Cancel preserves the original record. Removal has its own explicit confirmation.

**Language/evidence:** English/French requests share the source checks. This records stated facts and does not choose a treatment.

## Reminders and doses

### REM-01 — Create a follow-up reminder

**Current:** [care actions](care-actions.md), [notification behavior](care-notifications.md).

**Role/goal:** Either person remembers a task such as booking blood work.

**Preconditions:** A task is identified; the person can review the date/time.

**Acceptance path:** Open a reminder draft, display its title, choose or confirm the due date/time, then Save. Explain notification permission or scheduling errors without claiming delivery.

**Recovery/cancel:** Edit the draft before saving. Cancel creates no reminder. A request to remember to book an appointment does not book one.

**Language/evidence:** Display dates in the app locale. Natural-language frequency alone does not establish explicit clock times.

### DOSE-01 — Record a scheduled dose outcome

**Current:** [dose history and scheduling](care-actions.md).

**Role/goal:** Either person records what happened for an existing medication and eligible scheduled dose.

**Preconditions:** A saved medication and unambiguous dose slot exist.

**Acceptance path:** Choose Taken, Skipped or Remind later, inspect the selected medication/slot, and deliberately confirm. Preserve the historical name/time snapshot.

**Recovery/cancel:** Ask for clarification when the slot or medication is uncertain. Cancel leaves the outcome unchanged. Remind later must not become Taken, and future doses must not be marked completed accidentally.

**Language/evidence:** Translate display labels while keeping canonical saved statuses. Notification availability and observed adherence are separate.

## Readings and symptoms

### READ-01 — Save a reading

**Current:** [care records](care-actions.md), [French values](french-records.md).

**Role/goal:** Either person records a stated heart rate, blood pressure or temperature.

**Preconditions:** A supported reading type and complete value are supplied.

**Acceptance path:** Open a review showing type, value and unit; allow correction; reject malformed/out-of-range values; Save only after review.

**Recovery/cancel:** Missing or invalid facts require correction rather than an invented measurement. Cancel preserves the previous record set.

**Language/evidence:** French decimal display may use a comma; stored values remain canonical. Imported HealthKit readings use their own permission/duplicate checks.

### SYM-01 — Save a symptom description

**Current:** [source validation](french-input-validation.md), [manual record actions](navigation-and-actions.md).

**Role/goal:** Either person records a symptom in the person's own words.

**Preconditions:** A description is available; severity, onset and signs require explicit review.

**Acceptance path:** Preserve the original description, let the person review/add details and selected emergency signs, then Save. Keep any fixed guidance distinct from the saved facts.

**Recovery/cancel:** A health question is not automatically a record. Uncertain details remain unset. Cancel creates nothing; edit incorrect details before saving.

**Language/evidence:** Keep original-language descriptions and quotations. Keyword checks and model output do not establish clinical completeness.

## Voice and visits

### VOICE-01 — Talk or dictate

**Current:** [voice conversation](voice-conversation.md), [speech services](health-and-voice.md).

**Role/goal:** Either person can use speech and recover through typing.

**Preconditions:** Required permissions, on-device language assets and microphone availability are checked.

**Acceptance path:** Talk shows the listening/thinking/speaking state and an End action. Completed conversation turns enter the ordinary chat pipeline. Dictation leaves an editable composer draft until Send. Record changes still open the shared review.

**Recovery/cancel:** Show an actionable error for unavailable recognition or denied permission; typing remains usable. Interruptions stop the unfinished turn. End/Cancel releases audio ownership. Confirm that an unsent typed draft survives ordinary navigation and layout switches (#11).

**Language/evidence:** English/Canadian French recognition availability is device-dependent. Text fixtures, synthesis playback and simulator metadata audits are separate from acoustic accuracy.

### VISIT-01 — Record and review a visit

**Current:** [doctor visits](doctor-visits.md), [summary extraction](visit-summary-extraction.md).

**Role/goal:** Either person retains a visit and checks extracted follow-ups and proposed changes.

**Preconditions:** The person deliberately starts recording or enters notes and understands what will be saved.

**Acceptance path:** Make recording/paused state visible; retain transcription for processing; separate summary, follow-ups and proposed medication changes. Typed notes remain editable. For supported medication proposals, select changes, acknowledge checking the prescription/notes, and explicitly apply the atomic update. Unconfirmed items use the common medication editor.

**Recovery/cancel:** If recognition is unavailable, explain audio-only capture or use typed notes. Correct typed notes or retry transcription from saved audio before rerunning extraction. Normal recorded-visit screens show structured results rather than an editable raw transcript. Dismissing a proposal leaves existing records unchanged. A saved recording or generated summary does not itself authorize medication changes.

**Language/evidence:** Keep source quotations in their original language. Recorded facts, extracted proposals and final confirmed records are distinct.

## Interface selection

### MODE-01 — Choose Simple or Caregiver

**Current:** [interface behavior](simple-and-caregiver.md); remaining clarification/preservation/accessibility checks are in #11.

**Role/goal:** The same person or helper chooses a useful layout.

**Acceptance path:** Explain the single shared record set; persist the selected mode; allow switching back; retain saved records and unsent drafts; keep confirmation behavior consistent.

**Recovery/cancel:** Return Home without deleting data. Larger text can scroll to complete controls. Actual VoiceOver navigation requires its own device check.

## Open design questions and proposed work

| Question | Current position | Owner / next evidence |
| --- | --- | --- |
| Do people understand Talk versus editable dictation? | Both entry points exist; comprehension is unvalidated. | #13 task T4 and debrief. |
| Are Simple/Caregiver labels and shared-record wording clear? | One local record set; no multi-person account model. | #11 engineering checks; #13 task T1. |
| Can people distinguish similar medication candidates? | Manual selection/confirmation; strength/formulation need a product check. | #14 search validation; #13 task T2. |
| Are errors and recovery steps understandable? | Recognition and validation errors are visible. | #13 tasks T3/T4. |
| Which tasks need fewer steps or clearer explanations? | No observed target-user evidence yet. | #13 completion/assistance notes. |
| Would multiple patient profiles or remote access help? | Proposed future scope only; neither is supplied by a mode switch. | Separate product decision after observation. |

The selected [usability session plan](usability-session-plan.md) maps tasks to these stories. It is prepared documentation, not a conducted study.

## Maintaining the design

When behavior changes, update the story, [screen/message flows](message-flows.md), relevant feature documentation, and test/evidence links together. Label proposed behavior and unresolved assumptions explicitly. Do not convert scripted examples into accuracy or usability evidence.
