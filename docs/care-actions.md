# Care actions

## What it is

Reminders, daily medicine schedules, dose logs, refill dates, searchable health history, and saved appointment questions share the existing four main sections. Chat reaches the same editors, with original-message validation before any mutation.

## How it works

| Action | UI owner | Chat tool |
| --- | --- | --- |
| Add/edit a reminder, choose a quoted visit follow-up | Today → Coming up | `create_reminder` |
| Read reminders | Today → Coming up | `list_reminders` |
| Set medicine times/refill date | Records → Medicines → medicine editor | `schedule_medication` |
| Log Taken, Skipped, or Remind later | Today → scheduled dose | `log_dose` |
| Search history | Today → Timeline | `search_timeline` |
| Scan a medicine label | Records → Medicines → medicine editor | `scan_medication` |
| Save questions and share an appointment note | Visits → Appointment preparation | `save_question`, `copy_note` |

Today displays every incomplete reminder and keeps completed reminders in a disclosure section. The dashboard shortcuts navigate to the Records lists. Capture buttons live in those lists; empty states have no duplicate capture button. Interaction checking belongs to the medicine list. Visit recording and manual transcript entry remain distinct operations.

`Archive.care` is optional, so older archives decode with empty care data. Atomic updates save a medicine and its schedule together. Each dose log uses medicine ID plus scheduled time as its stable key; changing the recorded status replaces that slot rather than counting two doses. Each saved log also snapshots the medicine name, original clock time and timezone. Validation of historical logs uses those snapshots, so changing a schedule, renaming or removing a medicine does not erase or invalidate dose history. Existing logs gain snapshots before medicine changes. New dose actions still require a current medicine and schedule. Unsourced orphan logs and partial or inconsistent snapshots are rejected during import. Future-dose logging is blocked. Remind later records a snooze, not a Taken event.

A follow-up reminder keeps the visit ID and exact quoted follow-up. Saving rechecks both the transcript and extracted summary. Choosing a follow-up never guesses the date; the user selects and confirms it. Deleting its visit, editing the transcript, or replacing its summary detaches a source association that no longer validates and preserves the reminder text. Quote matching normalizes whitespace in the transcript, consistent with summary extraction. A stale editor cannot restore an invalid source association. Existing medicines do not gain invented historical creation dates; the timeline starts tracking medicine changes from this feature onward.

Medicine saves enforce the backup's name bounds and normalized name uniqueness. A duplicate name under another ID is rejected before writing; the user edits the existing medicine. This keeps schedules tied to stable IDs and prevents an app-created backup from failing its own importer. New reminder drafts, including chat drafts with a title, always require explicit date confirmation. Only reminders already present in the store reuse their confirmed date.

Appointment questions have one editor inside preparation. That view also assembles current medicines, latest symptoms, recent readings, and saved questions into a copyable/shareable note. Multi-row deletion snapshots question IDs before changing the collection. The timeline searches the underlying records and visit transcript, while displaying a short preview of long text.

## How to change it

Change portable types, constraints, timeline composition, and literal time extraction in `HarbourCore/Care.swift`. Change atomic persistence in `AppStore.swift`, views in `CareViews.swift`, schedule fields in `MedicineScanner.swift`, and routes in `ToolPlanner.swift`/`ChatView.swift`. Keep schedule times grounded in explicit user input or their prescription; the model must not prescribe timing or dosage. Continue using the same UI editor for corresponding chat tools.

Export now uses a version 2 `CareBackup` with records, care data, and visit text. It excludes audio and chat. Import accepts the original version 1 Records payload too, rebuilds ingredients from the catalog, validates care data, and merges without overwriting existing records. A medicine already saved under the same name retains its local ID and instructions; imported schedules and dose keys are remapped to that ID. An ID collision with a different medicine is rejected before writing. Duplicate incoming IDs, invalid dates, invalid dose snapshots, and follow-ups whose source conflicts with a saved visit are also rejected atomically. Historical dose snapshots are self-contained imported user records; the JSON is unsigned and does not authenticate medical facts. Imports are limited to 5 MB. Export dates use ISO 8601 second precision.

## Configuration

At most eight explicit daily clock times per medicine; duplicate/out-of-range times are rejected. A structured frequency can record a count per day, week, or month. Frequency without explicit clock times creates no dose slots or timed notifications. The editor checks that explicit daily times agree with a saved daily frequency. New reminder drafts start one hour in the future; the user must review their actual date. Past historical reminders remain valid. Reminder titles are limited to 500 characters and appointment questions to 1,000. The timeline displays the newest 300 matching entries; chat returns the newest 20. The current device calendar and time zone determine daily dose slots. Spring daylight-saving gaps move a nonexistent time forward; repeated autumn times produce one slot.

## Dependencies

SwiftUI, Foundation, `HarbourCore`, `AppStore`, `CareNotifications`, existing visits and chat routing. No additional account or remote service.
