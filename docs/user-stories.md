# User stories and acceptance paths

These stories define the simplified patient experience, shared caregiver tools and demo evidence. They describe intended behavior, not clinical validation or a remote caregiver service.

| Person | Goal | Acceptance path |
| --- | --- | --- |
| Independent older adult | Ask for help without navigating a dashboard | Simple launches to three large actions. Message is freeform; Talk opens full-screen voice. |
| Older adult using large text | Reach every action | Normal home needs no scrolling; accessibility/short-screen fallback scrolls and preserves full labels and hit targets. |
| French-speaking Canadian | Use the same features in French | System French chooses translated interface, locale-aware dates and French medication aliases/context. |
| Amira Hassan (fictional) | Add hydrochlorothiazide | Model selects add medication; exact source lookup opens the common editor; nothing saves before confirmation. |
| Jean-François Nguyen (fictional) | Find a poorly transcribed medicine | Similar names offers candidates for manual review; no automatic transcript substitution or guessed dose. |
| Independent patient | Review the last doctor visit | The shared visit summary separates medication changes and follow-ups; proposed record edits require review. |
| Caregiver using the same phone | Manage detailed records | Settings → Interface → Caregiver exposes records and visits without deleting patient data. |
| Presenter | Explain real app behavior | Developer walkthrough highlights and magnifies actual UI; inspector shows actual selected model and most recent tool. |

## How to change these stories

Add a story when a feature changes a user's goal or confirmation boundary. Link automated checks and observed limitations in the associated feature/evaluation docs. Use fictional identities; a small diverse-name fixture is a regression check, not evidence of population-wide fairness.

## Configuration and dependencies

Stories use the existing offline model, saved records, native editor/review flow and local speech services. No environment settings; see [interfaces](simple-and-caregiver.md), [message flows](message-flows.md), [vocabulary](medication-vocabulary.md) and [walkthrough](presentation-walkthrough.md).
