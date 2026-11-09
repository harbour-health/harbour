# Developer demo data

## What it is

Settings → Developer → Replace with demo data replaces the device's saved records, chat history and visit recordings with an authored fictional dataset. It is available in TestFlight/Release as well as Debug; it never loads automatically.

## How it works

A destructive confirmation precedes replacement. The fixture contains three medicines, six weeks of daily readings for all reading types, symptoms, schedules, dose logs, reminders, appointment questions, past/upcoming appointments, a saved chat and three visits with completed summaries. A pending medicine change exercises the ordinary review workflow; another visit illustrates an unknown medicine under Needs review. Visit transcripts and summaries are preset, not model generations. Demo visits have no audio file and explicitly label that fact; playback and retranscription are not faked.

Dates are relative to the load time and current calendar. English or Canadian French content is chosen at load time. The Home badge and Developer status identify the fictional dataset. Existing demo records stay in their original language if app language later changes; reload the demo to replace them in the new language.

`AppStore.loadDemoData` stages existing visit audio beside its original directory, writes the replacement archive atomically through the normal protected store, then removes old audio. A rejected write restores the original audio directory. Unreadable archives are not overwritten; export/recover them or use the existing explicit clear workflow first. Cleanup failures surface an error; after a successful archive write the demo may already be installed even if old-file cleanup fails.

Notifications are disabled on all seeded schedules/reminders. The normal root notification reconciler removes obsolete Harbour requests. Downloaded models, appearance, language, voice choice, app-lock credentials, and operating-system permissions are retained. This feature resets health/conversation records, not application installation settings or Apple Health's source data. Existing record/text exports and generated report directories in the app temporary directory are removed; copies a user shared elsewhere cannot be revoked.

## How to change it

Edit `Harbour/DemoData.swift` to extend the archive fixture; retain valid source quotes, baseline medicines and linked visit IDs. New types should be covered in `DemoDataTests` with actual validators, persistence and replacement tests. `DeveloperSettingsView` owns confirmation and disables loading during recording, model generation or Health import. The generated Xcode project must include any new Swift files (`python3 scripts/generate-project.py`). Do not connect canned demo conversations to live agent responses or represent authored summaries as successful extraction evaluations.

## Configuration

No network, model inference, permission request or additional download is needed. `DemoData.make(now:french:calendar:)` supplies controllable dates/language for tests. The optional `Archive.demoData` marker is backward compatible with existing archives and is removed by Delete all records and chat. Re-loading replaces rather than duplicates the fixture.

## Dependencies

HarbourCore's records, visits, appointments and care data; the normal AppStore persistence and root notification reconciliation; SwiftUI Settings and the English/French localization catalogues. Hosted and UI tests exercise replacement, cancellation, retained data after relaunch and visit-summary presentation.

## Verification

Five targeted hosted/UI tests passed on the Harbour QA iPhone simulator (iOS 26.5), with no skips. They cover English/French source validation and medicine review, old-record/audio removal and relaunch, unreadable-file preservation, cancellation and confirmation, and rendered visit summaries. The result bundle is `test_sim_2026-11-09T17-26-26-310Z_pid62996_08a8eb0c.xcresult`. Captures 169–173 are included in the README/gallery. These authored data checks do not measure LLM summary accuracy.
