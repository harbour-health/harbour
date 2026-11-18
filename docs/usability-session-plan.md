# Prepared usability session plan

**Prepared plan; not conducted.** Execution is tracked by [#13](https://github.com/harbour-health/harbour/issues/13), which is deferred pending a real-user trial. No participant outcomes, recording permission or usability success are recorded here.

## Setup and session record

Use an isolated test build and fictional health records, including a saved medication and a short fictional visit with a follow-up. Confirm the selected build supports the tasks before the session. Do not copy a participant's real health information into the fixture.

| Field | Value to record when a session occurs |
| --- | --- |
| Date / facilitator | Not recorded |
| Build / commit / distribution method | Not recorded |
| Physical iPhone / iOS version | Not recorded |
| App language / interface / accessibility setup | Not recorded |
| Participant role | Older adult or caregiver; not recorded |
| Phone familiarity | Optional self-description; not recorded |
| Fixture / starting records | Fictional dataset identifier; not recorded |
| Recording and quotation choices | Not requested / not recorded |

Explain: this is a product usability session, participation is voluntary, assistance is available, and the person can skip a task or stop. Ask separately about audio, video, screen recording and quotations before collecting any. Written observation without recording is a valid choice. Store any approved recordings/consent separately with agreed access and retention; do not commit identifying material to Git.

## Selected tasks

Use neutral prompts without showing the steps first. Record independent completion before offering assistance. The facilitator can stop a task when continuing is uncomfortable or unproductive.

| Task | Neutral prompt | Stories / observation focus |
| --- | --- | --- |
| T1 — Orient and choose layout | “Show me how you would ask Harbour for help. Find the other layout, then return to the one you prefer.” | MODE-01: discoverability, labels, shared-record understanding, selected state. |
| T2 — Find a medication and cancel | “Find this fictional medication using the supplied misspelling. Review a candidate, then leave without adding it.” | MED-01: search/suggestions, product check, Cancel and unchanged records. |
| T3 — Add a reading or reminder | “Record a pulse of 72,” or “Create a reminder to book blood work at a time you choose.” | READ-01 / REM-01: value/date review, correction and deliberate Save. |
| T4 — Speak and recover | “Try asking by voice. Show how you would correct the words or continue by typing if voice is unavailable.” | VOICE-01: Talk versus dictation, visible errors, editing, interruption recovery. |
| T5 — Review a fictional visit | “Find the follow-up in this saved visit. Review a proposed medication change and dismiss it.” | VISIT-01: source/summary distinction, finding follow-ups, confirmation boundaries. |

Use the same wording and starting fixture for comparable sessions. Record which T3 alternative was used and whether unavailable speech was a naturally observed condition or a planned permission/setup condition. Do not simulate a successful recognition and record it as real speech evidence.

Optional later tasks: correct a saved medication (MED-02), log an eligible dose (DOSE-01), or add/cancel a symptom (SYM-01). Keep the first session short enough for the participant.

## Observation sheet — blank until execution

| Task | Independent completion | Assistance / prompts | Errors or confusion | Participant comment | Time, if useful | Follow-up |
| --- | --- | --- | --- | --- | --- | --- |
| T1 | Not observed | — | — | — | — | — |
| T2 | Not observed | — | — | — | — | — |
| T3 | Not observed | — | — | — | — | — |
| T4 | Not observed | — | — | — | — | — |
| T5 | Not observed | — | — | — | — | — |

Check actual record state after Cancel/Save, and distinguish spontaneous completion from facilitator-led completion. Record failures and stopped/skipped tasks. Do not convert an empty field into a pass.

## Debrief and follow-up

Ask which action felt easiest, where the person expected something different, whether record ownership and confirmation were clear, and what they would change first. Invite disagreement with the interface choices.

After the session, summarize observations with the tested build/device/locale and limitations. Separate direct comments (permission permitting) from facilitator interpretation. Prioritize follow-up issues by blocked task/data-integrity problem, repeated need for assistance, and smaller comprehension/layout problems. Link each issue to its story/task and evidence; do not infer population-level usability or clinical effectiveness from one session.

Update #13 only after a session actually occurs. This prepared plan and the automated presentation walkthrough are separate artifacts.
