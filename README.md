# Harbour for iOS

Native SwiftUI companion with local-model chat, voice conversation, editable dictation, follow-up reminders, medicine schedules and dose logs, refill reminders, label scanning, searchable history, saved appointment questions, symptom records, medicine comparison, readings, appointment notes, read-only Apple Health import, and doctor visit recording with editable transcripts and reviewed medicine changes. The app has no web view, inference server, analytics, or account requirement.

## Screenshots

Native iPhone simulator captures with fictional test records. Select an image to view it at full resolution.

### Light

| Today | Chat | Records | Settings |
| :---: | :---: | :---: | :---: |
| [<img src="docs/screenshots/01-today.png" alt="Today dashboard in light mode" width="220">](docs/screenshots/01-today.png) | [<img src="docs/screenshots/11-chat-empty.png" alt="New chat in light mode" width="220">](docs/screenshots/11-chat-empty.png) | [<img src="docs/screenshots/64-records.png" alt="Records browser in light mode" width="220">](docs/screenshots/64-records.png) | [<img src="docs/screenshots/16-settings.png" alt="Settings in light mode" width="220">](docs/screenshots/16-settings.png) |

### Dark

| Today | Chat | Records | Settings |
| :---: | :---: | :---: | :---: |
| [<img src="docs/screenshots/31-today-dark.png" alt="Today dashboard in dark mode" width="220">](docs/screenshots/31-today-dark.png) | [<img src="docs/screenshots/32-chat-dark.png" alt="New chat in dark mode" width="220">](docs/screenshots/32-chat-dark.png) | [<img src="docs/screenshots/65-records-dark.png" alt="Records browser in dark mode" width="220">](docs/screenshots/65-records-dark.png) | [<img src="docs/screenshots/38-settings-dark.png" alt="Settings in dark mode" width="220">](docs/screenshots/38-settings-dark.png) |

### Doctor visits

| Visits | Recorder | Visit summary | Medicine review |
| :---: | :---: | :---: | :---: |
| [<img src="docs/screenshots/67-visits.png" alt="Doctor visit history" width="220">](docs/screenshots/67-visits.png) | [<img src="docs/screenshots/68-visit-recorder.png" alt="Doctor visit recorder with a large start button" width="220">](docs/screenshots/68-visit-recorder.png) | [<img src="docs/screenshots/70-visit-summary.png" alt="Locally extracted visit summary and follow-up" width="220">](docs/screenshots/70-visit-summary.png) | [<img src="docs/screenshots/71-visit-medicine-review.png" alt="Review medicine changes before saving" width="220">](docs/screenshots/71-visit-medicine-review.png) |

See [doctor visits](docs/doctor-visits.md) for recording, transcript recovery, and medicine review. Physical-device speech accuracy still needs testing.

See [every screen below](#all-screens) and [capture details](docs/screenshots.md) for entry sheets, chat results, model downloads, and app lock.

## Run

Requires a Mac, Xcode with an iOS SDK, and CMake for the simulator inference library. Minimum app target: iOS 18.0.

```sh
bash scripts/prepare-runtime.sh
open Harbour.xcodeproj
```

Select the shared `Harbour` scheme and an iPhone simulator, then Run. The prepared runtime is already present in this working copy. On a real phone, choose your signing team in **Signing & Capabilities**, enable HealthKit for the bundle ID, and Run. No signing credentials are stored here.

Qwen Small downloads when the first chat message is sent, or from **Settings → Models**. The download is about 491 MB; Balanced is about 1.12 GB. Progress and cancellation are available. Verified models work without a network connection. Voice requires an available on-device recognizer for the app’s language; it never silently switches to server transcription.

English and Canadian French follow the iOS app language setting. French includes permission prompts, voice controls, notifications, structured notes, medicine search, decimal-comma readings, and bounded French chat/visit input. Original notes and source quotations keep their language. See [localization](docs/localization.md) for coverage and verification limits.

## Screens

- **Today:** recent readings, upcoming reminders and doses, refill dates, and searchable health history.
- **Chat:** typed or spoken messages; optional topic hints; model and effort controls beside the microphone; model-written replies with recent conversation context, model-selected tool calls, and locally generated conversation titles.
- **Records:** a large category browser leading to dedicated symptom, medicine, and reading lists, with native entry sheets and swipe deletion.
- **Visits:** a large recorder with pause/resume, saved audio, direct note entry, editable transcripts, source-quoted notes and follow-up, confirmed medicine changes, and appointment preparation with saved questions.
- **Settings:** appearance, optional Face ID or app PIN lock, model downloads, voice choice and preview, Apple Health import, record import/export, reset, and evaluation.

Settings is available at the upper right of every main screen. Forms use Cancel and Save/Review; read-only drawers use Done. See [navigation and actions](docs/navigation-and-actions.md) for the shared control conventions.

The current medicine catalog maps 11 names to ingredients and checks four cited pairs. Other pairs are unassessed. Symptom guidance uses fixed Ontario wording and does not establish a diagnosis. This is the existing honours-project scope carried into native code.

## Verification

```sh
swift test --package-path HarbourCore
swift test --package-path HarbourRuntime
xcodebuild -project Harbour.xcodeproj -scheme Harbour \
  -destination 'platform=iOS Simulator,name=Harbour QA' test
```

`testLocalModelChat` downloads Qwen Small if missing; budget network access and roughly 500 MB of free space. Other UI tests exercise manual entry, persisted records, draft preservation, and model controls. See [chat agent](docs/chat-agent.md) for conversation/tool handling and [evaluation](docs/evaluation.md) for measured model results and limits.

The Xcode project is checked in. If adding source files, regenerate with `python3 scripts/generate-project.py`; this resets generated project settings, so change the generator for persistent configuration changes.

## Documentation

For private iOS testing, see [the internal-only TestFlight workflow](docs/testflight.md). Generate the light-mode iPhone App Store image set with [the screenshot script](docs/app-store-screenshots.md).

See [docs/README.md](docs/README.md).

See the [native screenshot gallery](docs/screenshots/index.html) for the current interface and entry/confirmation sheets. Today uses a recorded-value summary and equally sized illustrated shortcuts; the floating dock has icon-only buttons with accessible names. Appearance can follow the phone or be set to Light or Dark. See [app lock](docs/app-lock.md) for authentication, PIN retry behaviour, and protection limits.

### Drawers

| Reading | Topics | Appearance | Medicine changes |
| --- | --- | --- | --- |
| [<img src="docs/screenshots/05-add-reading.png" width="220" alt="Compact floating reading drawer">](docs/screenshots/05-add-reading.png) | [<img src="docs/screenshots/12-topics.png" width="220" alt="Floating topic picker">](docs/screenshots/12-topics.png) | [<img src="docs/screenshots/41-appearance-dark.png" width="220" alt="Compact appearance drawer in dark mode">](docs/screenshots/41-appearance-dark.png) | [<img src="docs/screenshots/71-visit-medicine-review.png" width="220" alt="Floating visit medicine confirmation">](docs/screenshots/71-visit-medicine-review.png) |

<!-- screenshot-gallery:start -->
## All screens

145 native captures. Select any image to open the original PNG. Capture dates and workflow provenance are in [the screenshot manifest](docs/screenshots/manifest.json).

### Today

| | |
| :---: | :---: |
| <strong>Today</strong><br>[<img src="docs/screenshots/01-today.png" alt="Today" width="220">](docs/screenshots/01-today.png) | <strong>Today · Dark</strong><br>[<img src="docs/screenshots/31-today-dark.png" alt="Today · Dark" width="220">](docs/screenshots/31-today-dark.png) |
| <strong>System appearance · Dark</strong><br>[<img src="docs/screenshots/43-system-dark.png" alt="System appearance · Dark" width="220">](docs/screenshots/43-system-dark.png) | <strong>Floating navigation · scrolled</strong><br>[<img src="docs/screenshots/66-floating-navigation.png" alt="Floating navigation · scrolled" width="220">](docs/screenshots/66-floating-navigation.png) |
| <strong>Today · Largest text</strong><br>[<img src="docs/screenshots/116-today-large-text.png" alt="Today · Largest text" width="220">](docs/screenshots/116-today-large-text.png) |  |

### Chat

| | |
| :---: | :---: |
| <strong>Chat conversation</strong><br>[<img src="docs/screenshots/10-chat-conversation.png" alt="Chat conversation" width="220">](docs/screenshots/10-chat-conversation.png) | <strong>New chat</strong><br>[<img src="docs/screenshots/11-chat-empty.png" alt="New chat" width="220">](docs/screenshots/11-chat-empty.png) |
| <strong>Chat topics</strong><br>[<img src="docs/screenshots/12-topics.png" alt="Chat topics" width="220">](docs/screenshots/12-topics.png) | <strong>Selected topic</strong><br>[<img src="docs/screenshots/13-chat-topic.png" alt="Selected topic" width="220">](docs/screenshots/13-chat-topic.png) |
| <strong>Chat with keyboard</strong><br>[<img src="docs/screenshots/28-chat-keyboard.png" alt="Chat with keyboard" width="220">](docs/screenshots/28-chat-keyboard.png) | <strong>New chat · Dark</strong><br>[<img src="docs/screenshots/32-chat-dark.png" alt="New chat · Dark" width="220">](docs/screenshots/32-chat-dark.png) |
| <strong>Topics · Dark</strong><br>[<img src="docs/screenshots/36-topics-dark.png" alt="Topics · Dark" width="220">](docs/screenshots/36-topics-dark.png) | <strong>Interaction result · Dark</strong><br>[<img src="docs/screenshots/42-chat-result-dark.png" alt="Interaction result · Dark" width="220">](docs/screenshots/42-chat-result-dark.png) |
| <strong>Medicines in chat</strong><br>[<img src="docs/screenshots/44-chat-medicines.png" alt="Medicines in chat" width="220">](docs/screenshots/44-chat-medicines.png) | <strong>Medicines in chat · Dark</strong><br>[<img src="docs/screenshots/45-chat-medicines-dark.png" alt="Medicines in chat · Dark" width="220">](docs/screenshots/45-chat-medicines-dark.png) |
| <strong>Readings in chat</strong><br>[<img src="docs/screenshots/46-chat-readings.png" alt="Readings in chat" width="220">](docs/screenshots/46-chat-readings.png) | <strong>Readings in chat · Dark</strong><br>[<img src="docs/screenshots/47-chat-readings-dark.png" alt="Readings in chat · Dark" width="220">](docs/screenshots/47-chat-readings-dark.png) |
| <strong>Selected topic · Dark</strong><br>[<img src="docs/screenshots/53-selected-topic-dark.png" alt="Selected topic · Dark" width="220">](docs/screenshots/53-selected-topic-dark.png) | <strong>Generated chat title</strong><br>[<img src="docs/screenshots/58-generated-chat-title.png" alt="Generated chat title" width="220">](docs/screenshots/58-generated-chat-title.png) |
| <strong>Chat · Small phone</strong><br>[<img src="docs/screenshots/89-chat-small-phone.png" alt="Chat · Small phone" width="220">](docs/screenshots/89-chat-small-phone.png) | <strong>Chat · Compact loading mark</strong><br>[<img src="docs/screenshots/146-chat-loading.png" alt="Chat · Compact loading mark" width="220">](docs/screenshots/146-chat-loading.png) |

### Records

| | |
| :---: | :---: |
| <strong>Symptoms</strong><br>[<img src="docs/screenshots/02-symptoms.png" alt="Symptoms" width="220">](docs/screenshots/02-symptoms.png) | <strong>Medicines</strong><br>[<img src="docs/screenshots/03-medicines.png" alt="Medicines" width="220">](docs/screenshots/03-medicines.png) |
| <strong>Readings</strong><br>[<img src="docs/screenshots/04-readings.png" alt="Readings" width="220">](docs/screenshots/04-readings.png) | <strong>Saved symptom</strong><br>[<img src="docs/screenshots/22-symptom-detail.png" alt="Saved symptom" width="220">](docs/screenshots/22-symptom-detail.png) |
| <strong>Symptoms · Dark</strong><br>[<img src="docs/screenshots/33-symptoms-dark.png" alt="Symptoms · Dark" width="220">](docs/screenshots/33-symptoms-dark.png) | <strong>Medicines · Dark</strong><br>[<img src="docs/screenshots/34-medicines-dark.png" alt="Medicines · Dark" width="220">](docs/screenshots/34-medicines-dark.png) |
| <strong>Readings · Dark</strong><br>[<img src="docs/screenshots/35-readings-dark.png" alt="Readings · Dark" width="220">](docs/screenshots/35-readings-dark.png) | <strong>Records</strong><br>[<img src="docs/screenshots/64-records.png" alt="Records" width="220">](docs/screenshots/64-records.png) |
| <strong>Records · Dark</strong><br>[<img src="docs/screenshots/65-records-dark.png" alt="Records · Dark" width="220">](docs/screenshots/65-records-dark.png) |  |

### Entry and review

| | |
| :---: | :---: |
| <strong>Add a reading</strong><br>[<img src="docs/screenshots/05-add-reading.png" alt="Add a reading" width="220">](docs/screenshots/05-add-reading.png) | <strong>Medicine catalogue</strong><br>[<img src="docs/screenshots/06-medicine-catalog.png" alt="Medicine catalogue" width="220">](docs/screenshots/06-medicine-catalog.png) |
| <strong>Medicine confirmation</strong><br>[<img src="docs/screenshots/07-medicine-details.png" alt="Medicine confirmation" width="220">](docs/screenshots/07-medicine-details.png) | <strong>Symptom entry</strong><br>[<img src="docs/screenshots/08-symptom-intake.png" alt="Symptom entry" width="220">](docs/screenshots/08-symptom-intake.png) |
| <strong>Symptom review</strong><br>[<img src="docs/screenshots/09-symptom-review.png" alt="Symptom review" width="220">](docs/screenshots/09-symptom-review.png) | <strong>Medicine interactions</strong><br>[<img src="docs/screenshots/20-interactions.png" alt="Medicine interactions" width="220">](docs/screenshots/20-interactions.png) |
| <strong>Emergency review</strong><br>[<img src="docs/screenshots/21-emergency-review.png" alt="Emergency review" width="220">](docs/screenshots/21-emergency-review.png) | <strong>Blood pressure entry</strong><br>[<img src="docs/screenshots/23-blood-pressure.png" alt="Blood pressure entry" width="220">](docs/screenshots/23-blood-pressure.png) |
| <strong>Temperature entry</strong><br>[<img src="docs/screenshots/24-temperature.png" alt="Temperature entry" width="220">](docs/screenshots/24-temperature.png) | <strong>Unlisted medicine</strong><br>[<img src="docs/screenshots/25-manual-medicine.png" alt="Unlisted medicine" width="220">](docs/screenshots/25-manual-medicine.png) |
| <strong>Reading entry · Dark</strong><br>[<img src="docs/screenshots/48-add-reading-dark.png" alt="Reading entry · Dark" width="220">](docs/screenshots/48-add-reading-dark.png) | <strong>Medicine catalogue · Dark</strong><br>[<img src="docs/screenshots/49-catalog-dark.png" alt="Medicine catalogue · Dark" width="220">](docs/screenshots/49-catalog-dark.png) |
| <strong>Medicine confirmation · Dark</strong><br>[<img src="docs/screenshots/50-confirm-medicine-dark.png" alt="Medicine confirmation · Dark" width="220">](docs/screenshots/50-confirm-medicine-dark.png) | <strong>Symptom entry · Dark</strong><br>[<img src="docs/screenshots/51-symptom-entry-dark.png" alt="Symptom entry · Dark" width="220">](docs/screenshots/51-symptom-entry-dark.png) |
| <strong>Symptom review · Dark</strong><br>[<img src="docs/screenshots/52-symptom-review-dark.png" alt="Symptom review · Dark" width="220">](docs/screenshots/52-symptom-review-dark.png) | <strong>Reading drawer · Landscape</strong><br>[<img src="docs/screenshots/79-reading-landscape.png" alt="Reading drawer · Landscape" width="220">](docs/screenshots/79-reading-landscape.png) |
| <strong>Reading drawer · Keyboard</strong><br>[<img src="docs/screenshots/81-reading-keyboard.png" alt="Reading drawer · Keyboard" width="220">](docs/screenshots/81-reading-keyboard.png) | <strong>Reading drawer · Keyboard · Dark</strong><br>[<img src="docs/screenshots/82-reading-keyboard-dark.png" alt="Reading drawer · Keyboard · Dark" width="220">](docs/screenshots/82-reading-keyboard-dark.png) |
| <strong>Reading drawer · Large text</strong><br>[<img src="docs/screenshots/84-drawer-large-text.png" alt="Reading drawer · Large text" width="220">](docs/screenshots/84-drawer-large-text.png) | <strong>Interaction drawer · Dark</strong><br>[<img src="docs/screenshots/85-interactions-drawer-dark.png" alt="Interaction drawer · Dark" width="220">](docs/screenshots/85-interactions-drawer-dark.png) |
| <strong>Reading drawer · Small phone</strong><br>[<img src="docs/screenshots/90-reading-small-phone.png" alt="Reading drawer · Small phone" width="220">](docs/screenshots/90-reading-small-phone.png) |  |

### Doctor visits

| | |
| :---: | :---: |
| <strong>Visits</strong><br>[<img src="docs/screenshots/67-visits.png" alt="Visits" width="220">](docs/screenshots/67-visits.png) | <strong>Visit recorder</strong><br>[<img src="docs/screenshots/68-visit-recorder.png" alt="Visit recorder" width="220">](docs/screenshots/68-visit-recorder.png) |
| <strong>Visit notes</strong><br>[<img src="docs/screenshots/69-visit-notes.png" alt="Visit notes" width="220">](docs/screenshots/69-visit-notes.png) | <strong>Local visit summary</strong><br>[<img src="docs/screenshots/70-visit-summary.png" alt="Local visit summary" width="220">](docs/screenshots/70-visit-summary.png) |
| <strong>Visit medicine confirmation</strong><br>[<img src="docs/screenshots/71-visit-medicine-review.png" alt="Visit medicine confirmation" width="220">](docs/screenshots/71-visit-medicine-review.png) | <strong>Visit transcript</strong><br>[<img src="docs/screenshots/72-visit-transcript.png" alt="Visit transcript" width="220">](docs/screenshots/72-visit-transcript.png) |
| <strong>Recording · audio-only simulator</strong><br>[<img src="docs/screenshots/73-visit-recording.png" alt="Recording · audio-only simulator" width="220">](docs/screenshots/73-visit-recording.png) | <strong>Paused · audio-only simulator</strong><br>[<img src="docs/screenshots/74-visit-paused.png" alt="Paused · audio-only simulator" width="220">](docs/screenshots/74-visit-paused.png) |
| <strong>Playback · audio-only simulator</strong><br>[<img src="docs/screenshots/75-visit-audio.png" alt="Playback · audio-only simulator" width="220">](docs/screenshots/75-visit-audio.png) | <strong>Visits · Dark</strong><br>[<img src="docs/screenshots/76-visits-dark.png" alt="Visits · Dark" width="220">](docs/screenshots/76-visits-dark.png) |
| <strong>Visit recorder · Dark</strong><br>[<img src="docs/screenshots/77-visit-recorder-dark.png" alt="Visit recorder · Dark" width="220">](docs/screenshots/77-visit-recorder-dark.png) | <strong>Visit summary · Dark</strong><br>[<img src="docs/screenshots/78-visit-summary-dark.png" alt="Visit summary · Dark" width="220">](docs/screenshots/78-visit-summary-dark.png) |
| <strong>Visit notes drawer</strong><br>[<img src="docs/screenshots/83-visit-notes-drawer.png" alt="Visit notes drawer" width="220">](docs/screenshots/83-visit-notes-drawer.png) | <strong>New visit notes</strong><br>[<img src="docs/screenshots/87-new-visit-notes.png" alt="New visit notes" width="220">](docs/screenshots/87-new-visit-notes.png) |
| <strong>New visit notes · Dark</strong><br>[<img src="docs/screenshots/88-new-visit-notes-dark.png" alt="New visit notes · Dark" width="220">](docs/screenshots/88-new-visit-notes-dark.png) | <strong>Visit medicine confirmation · Dark</strong><br>[<img src="docs/screenshots/142-visit-medicine-review-dark.png" alt="Visit medicine confirmation · Dark" width="220">](docs/screenshots/142-visit-medicine-review-dark.png) |

### Settings, models, and notes

| | |
| :---: | :---: |
| <strong>Models and effort</strong><br>[<img src="docs/screenshots/14-models.png" alt="Models and effort" width="220">](docs/screenshots/14-models.png) | <strong>Model download</strong><br>[<img src="docs/screenshots/15-model-download.png" alt="Model download" width="220">](docs/screenshots/15-model-download.png) |
| <strong>Settings</strong><br>[<img src="docs/screenshots/16-settings.png" alt="Settings" width="220">](docs/screenshots/16-settings.png) | <strong>Export records</strong><br>[<img src="docs/screenshots/18-export.png" alt="Export records" width="220">](docs/screenshots/18-export.png) |
| <strong>Appointment note</strong><br>[<img src="docs/screenshots/19-appointment-note.png" alt="Appointment note" width="220">](docs/screenshots/19-appointment-note.png) | <strong>Delete confirmation</strong><br>[<img src="docs/screenshots/27-delete-confirmation.png" alt="Delete confirmation" width="220">](docs/screenshots/27-delete-confirmation.png) |
| <strong>Models · Dark</strong><br>[<img src="docs/screenshots/37-models-dark.png" alt="Models · Dark" width="220">](docs/screenshots/37-models-dark.png) | <strong>Settings · Dark</strong><br>[<img src="docs/screenshots/38-settings-dark.png" alt="Settings · Dark" width="220">](docs/screenshots/38-settings-dark.png) |
| <strong>Appointment note · Dark</strong><br>[<img src="docs/screenshots/39-note-dark.png" alt="Appointment note · Dark" width="220">](docs/screenshots/39-note-dark.png) | <strong>Appearance · Light</strong><br>[<img src="docs/screenshots/40-appearance-light.png" alt="Appearance · Light" width="220">](docs/screenshots/40-appearance-light.png) |
| <strong>Appearance · Dark</strong><br>[<img src="docs/screenshots/41-appearance-dark.png" alt="Appearance · Dark" width="220">](docs/screenshots/41-appearance-dark.png) | <strong>Import records</strong><br>[<img src="docs/screenshots/60-import-records.png" alt="Import records" width="220">](docs/screenshots/60-import-records.png) |

### App lock

| | |
| :---: | :---: |
| <strong>App lock</strong><br>[<img src="docs/screenshots/54-app-lock-settings.png" alt="App lock" width="220">](docs/screenshots/54-app-lock-settings.png) | <strong>Set PIN</strong><br>[<img src="docs/screenshots/55-pin-setup.png" alt="Set PIN" width="220">](docs/screenshots/55-pin-setup.png) |
| <strong>Locked app</strong><br>[<img src="docs/screenshots/56-pin-lock.png" alt="Locked app" width="220">](docs/screenshots/56-pin-lock.png) | <strong>PIN retry delay</strong><br>[<img src="docs/screenshots/57-pin-retry-delay.png" alt="PIN retry delay" width="220">](docs/screenshots/57-pin-retry-delay.png) |
| <strong>Confirm current PIN</strong><br>[<img src="docs/screenshots/59-current-pin.png" alt="Confirm current PIN" width="220">](docs/screenshots/59-current-pin.png) | <strong>PIN mismatch</strong><br>[<img src="docs/screenshots/61-pin-mismatch.png" alt="PIN mismatch" width="220">](docs/screenshots/61-pin-mismatch.png) |
| <strong>Face ID unavailable</strong><br>[<img src="docs/screenshots/62-face-id-unavailable.png" alt="Face ID unavailable" width="220">](docs/screenshots/62-face-id-unavailable.png) | <strong>PIN drawer · Dark</strong><br>[<img src="docs/screenshots/80-pin-drawer-dark.png" alt="PIN drawer · Dark" width="220">](docs/screenshots/80-pin-drawer-dark.png) |

### Health permissions

| | |
| :---: | :---: |
| <strong>Apple Health access</strong><br>[<img src="docs/screenshots/26-health-access.png" alt="Apple Health access" width="220">](docs/screenshots/26-health-access.png) | <strong>Apple Health permission</strong><br>[<img src="docs/screenshots/30-health-permission.png" alt="Apple Health permission" width="220">](docs/screenshots/30-health-permission.png) |
| <strong>Apple Health access reminder</strong><br>[<img src="docs/screenshots/63-health-access-reminder.png" alt="Apple Health access reminder" width="220">](docs/screenshots/63-health-access-reminder.png) |  |

### Evaluation

| | |
| :---: | :---: |
| <strong>Evaluation</strong><br>[<img src="docs/screenshots/17-evaluation.png" alt="Evaluation" width="220">](docs/screenshots/17-evaluation.png) | <strong>Evaluation results</strong><br>[<img src="docs/screenshots/29-evaluation-results.png" alt="Evaluation results" width="220">](docs/screenshots/29-evaluation-results.png) |
| <strong>Evaluation drawer · Dark</strong><br>[<img src="docs/screenshots/86-evaluation-drawer-dark.png" alt="Evaluation drawer · Dark" width="220">](docs/screenshots/86-evaluation-drawer-dark.png) |  |

### Reminders, schedules, and preparation

| | |
| :---: | :---: |
| <strong>Recognized medicine label</strong><br>[<img src="docs/screenshots/91-label-scan.png" alt="Recognized medicine label" width="220">](docs/screenshots/91-label-scan.png) | <strong>Medicine schedule</strong><br>[<img src="docs/screenshots/92-medicine-schedule.png" alt="Medicine schedule" width="220">](docs/screenshots/92-medicine-schedule.png) |
| <strong>Reminder</strong><br>[<img src="docs/screenshots/93-reminder.png" alt="Reminder" width="220">](docs/screenshots/93-reminder.png) | <strong>Log a dose</strong><br>[<img src="docs/screenshots/94-dose-log.png" alt="Log a dose" width="220">](docs/screenshots/94-dose-log.png) |
| <strong>Today · Agenda</strong><br>[<img src="docs/screenshots/95-agenda.png" alt="Today · Agenda" width="220">](docs/screenshots/95-agenda.png) | <strong>Health timeline</strong><br>[<img src="docs/screenshots/96-timeline.png" alt="Health timeline" width="220">](docs/screenshots/96-timeline.png) |
| <strong>Search health history</strong><br>[<img src="docs/screenshots/97-timeline-search.png" alt="Search health history" width="220">](docs/screenshots/97-timeline-search.png) | <strong>Appointment preparation</strong><br>[<img src="docs/screenshots/98-appointment-preparation.png" alt="Appointment preparation" width="220">](docs/screenshots/98-appointment-preparation.png) |
| <strong>Agenda · Dark</strong><br>[<img src="docs/screenshots/99-agenda-dark.png" alt="Agenda · Dark" width="220">](docs/screenshots/99-agenda-dark.png) | <strong>Health timeline · Dark</strong><br>[<img src="docs/screenshots/100-timeline-dark.png" alt="Health timeline · Dark" width="220">](docs/screenshots/100-timeline-dark.png) |
| <strong>Appointment preparation · Dark</strong><br>[<img src="docs/screenshots/101-preparation-dark.png" alt="Appointment preparation · Dark" width="220">](docs/screenshots/101-preparation-dark.png) | <strong>Medicine schedule · Dark</strong><br>[<img src="docs/screenshots/102-schedule-dark.png" alt="Medicine schedule · Dark" width="220">](docs/screenshots/102-schedule-dark.png) |
| <strong>Remind later · Dark</strong><br>[<img src="docs/screenshots/103-dose-later-dark.png" alt="Remind later · Dark" width="220">](docs/screenshots/103-dose-later-dark.png) |  |

### Voice and care tools in chat

| | |
| :---: | :---: |
| <strong>Voice options</strong><br>[<img src="docs/screenshots/104-voice-options.png" alt="Voice options" width="220">](docs/screenshots/104-voice-options.png) | <strong>Chat · Reminder confirmation</strong><br>[<img src="docs/screenshots/105-chat-reminder-review.png" alt="Chat · Reminder confirmation" width="220">](docs/screenshots/105-chat-reminder-review.png) |
| <strong>Reminders in chat</strong><br>[<img src="docs/screenshots/106-chat-reminders.png" alt="Reminders in chat" width="220">](docs/screenshots/106-chat-reminders.png) | <strong>Chat · Schedule confirmation</strong><br>[<img src="docs/screenshots/107-chat-schedule-review.png" alt="Chat · Schedule confirmation" width="220">](docs/screenshots/107-chat-schedule-review.png) |
| <strong>Chat · Dose confirmation</strong><br>[<img src="docs/screenshots/108-chat-dose-review.png" alt="Chat · Dose confirmation" width="220">](docs/screenshots/108-chat-dose-review.png) | <strong>Health history in chat</strong><br>[<img src="docs/screenshots/109-chat-history.png" alt="Health history in chat" width="220">](docs/screenshots/109-chat-history.png) |
| <strong>Chat · Appointment question</strong><br>[<img src="docs/screenshots/110-chat-question-review.png" alt="Chat · Appointment question" width="220">](docs/screenshots/110-chat-question-review.png) | <strong>Chat · Label entry</strong><br>[<img src="docs/screenshots/111-chat-label-scan.png" alt="Chat · Label entry" width="220">](docs/screenshots/111-chat-label-scan.png) |
| <strong>Medicine label entry</strong><br>[<img src="docs/screenshots/112-label-entry.png" alt="Medicine label entry" width="220">](docs/screenshots/112-label-entry.png) | <strong>On-device voice unavailable</strong><br>[<img src="docs/screenshots/114-voice-input-error.png" alt="On-device voice unavailable" width="220">](docs/screenshots/114-voice-input-error.png) |
| <strong>Reminder notifications</strong><br>[<img src="docs/screenshots/115-notification-setting.png" alt="Reminder notifications" width="220">](docs/screenshots/115-notification-setting.png) | <strong>Model conversation and follow-up context</strong><br>[<img src="docs/screenshots/143-freeform-chat.png" alt="Model conversation and follow-up context" width="220">](docs/screenshots/143-freeform-chat.png) |
| <strong>Voice selection and preview</strong><br>[<img src="docs/screenshots/144-voice.png" alt="Voice selection and preview" width="220">](docs/screenshots/144-voice.png) |  |

### Canadian French

| | |
| :---: | :---: |
| <strong>Aujourd’hui · Français</strong><br>[<img src="docs/screenshots/117-french-today.png" alt="Aujourd’hui · Français" width="220">](docs/screenshots/117-french-today.png) | <strong>Conversation · Français</strong><br>[<img src="docs/screenshots/118-french-chat.png" alt="Conversation · Français" width="220">](docs/screenshots/118-french-chat.png) |
| <strong>Dossier · Français</strong><br>[<img src="docs/screenshots/119-french-records.png" alt="Dossier · Français" width="220">](docs/screenshots/119-french-records.png) | <strong>Consultations · Français</strong><br>[<img src="docs/screenshots/120-french-visits.png" alt="Consultations · Français" width="220">](docs/screenshots/120-french-visits.png) |
| <strong>Aujourd’hui · Français · Sombre</strong><br>[<img src="docs/screenshots/121-french-today-dark.png" alt="Aujourd’hui · Français · Sombre" width="220">](docs/screenshots/121-french-today-dark.png) | <strong>Conversation · Français · Sombre</strong><br>[<img src="docs/screenshots/122-french-chat-dark.png" alt="Conversation · Français · Sombre" width="220">](docs/screenshots/122-french-chat-dark.png) |
| <strong>Dossier · Français · Sombre</strong><br>[<img src="docs/screenshots/123-french-records-dark.png" alt="Dossier · Français · Sombre" width="220">](docs/screenshots/123-french-records-dark.png) | <strong>Consultations · Français · Sombre</strong><br>[<img src="docs/screenshots/124-french-visits-dark.png" alt="Consultations · Français · Sombre" width="220">](docs/screenshots/124-french-visits-dark.png) |
| <strong>Réglages · Français</strong><br>[<img src="docs/screenshots/125-french-settings.png" alt="Réglages · Français" width="220">](docs/screenshots/125-french-settings.png) | <strong>Apparence · Français</strong><br>[<img src="docs/screenshots/126-french-appearance.png" alt="Apparence · Français" width="220">](docs/screenshots/126-french-appearance.png) |
| <strong>NIP · Français</strong><br>[<img src="docs/screenshots/127-french-pin-draft.png" alt="NIP · Français" width="220">](docs/screenshots/127-french-pin-draft.png) | <strong>Recherche de médicaments · Français</strong><br>[<img src="docs/screenshots/128-french-medicine-search.png" alt="Recherche de médicaments · Français" width="220">](docs/screenshots/128-french-medicine-search.png) |
| <strong>Température · Français</strong><br>[<img src="docs/screenshots/129-french-reading-comma.png" alt="Température · Français" width="220">](docs/screenshots/129-french-reading-comma.png) | <strong>Symptôme · Français</strong><br>[<img src="docs/screenshots/130-french-symptom-draft.png" alt="Symptôme · Français" width="220">](docs/screenshots/130-french-symptom-draft.png) |
| <strong>Soins d’urgence · Français</strong><br>[<img src="docs/screenshots/131-french-emergency-review.png" alt="Soins d’urgence · Français" width="220">](docs/screenshots/131-french-emergency-review.png) | <strong>Sujets · Français</strong><br>[<img src="docs/screenshots/132-french-topics.png" alt="Sujets · Français" width="220">](docs/screenshots/132-french-topics.png) |
| <strong>Modèles · Français</strong><br>[<img src="docs/screenshots/133-french-models.png" alt="Modèles · Français" width="220">](docs/screenshots/133-french-models.png) | <strong>Notes de consultation · Français</strong><br>[<img src="docs/screenshots/134-french-visit-notes-draft.png" alt="Notes de consultation · Français" width="220">](docs/screenshots/134-french-visit-notes-draft.png) |
| <strong>Rappel · Français</strong><br>[<img src="docs/screenshots/135-french-reminder-draft.png" alt="Rappel · Français" width="220">](docs/screenshots/135-french-reminder-draft.png) | <strong>Préparation · Français</strong><br>[<img src="docs/screenshots/136-french-preparation-draft.png" alt="Préparation · Français" width="220">](docs/screenshots/136-french-preparation-draft.png) |
| <strong>Écrire un message · Français</strong><br>[<img src="docs/screenshots/137-french-chat-controls.png" alt="Écrire un message · Français" width="220">](docs/screenshots/137-french-chat-controls.png) | <strong>Médicaments et titre local · Français</strong><br>[<img src="docs/screenshots/138-french-model-medicines-title.png" alt="Médicaments et titre local · Français" width="220">](docs/screenshots/138-french-model-medicines-title.png) |
| <strong>Relevés dans la conversation · Français</strong><br>[<img src="docs/screenshots/139-french-model-readings.png" alt="Relevés dans la conversation · Français" width="220">](docs/screenshots/139-french-model-readings.png) | <strong>Symptôme dans la conversation · Français</strong><br>[<img src="docs/screenshots/140-french-model-symptom-review.png" alt="Symptôme dans la conversation · Français" width="220">](docs/screenshots/140-french-model-symptom-review.png) |
| <strong>Rappel dans la conversation · Français</strong><br>[<img src="docs/screenshots/141-french-model-reminder-review.png" alt="Rappel dans la conversation · Français" width="220">](docs/screenshots/141-french-model-reminder-review.png) | <strong>Voix et aperçu · Français</strong><br>[<img src="docs/screenshots/145-french-voice.png" alt="Voix et aperçu · Français" width="220">](docs/screenshots/145-french-voice.png) |

<!-- screenshot-gallery:end -->
