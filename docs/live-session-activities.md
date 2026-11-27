# Live session activities

## What it is

Visit recording and live chat voice sessions have ActivityKit Live Activities, including compact, minimal, expanded Dynamic Island, and Lock Screen presentations. They display only a generic session label, phase, and recording timer; health details and transcripts never enter the activity payload.

## How it works

`SessionActivities` serializes requests, updates, and endings so cancellation cannot leave a late activity running. Recording has recording/paused states and a periodic heartbeat. Voice reflects listening, finishing, thinking, speaking, or paused. Opening system UI routes through `harbour://recording` or `harbour://chat`; opening a recording activity returns to the existing session, never starts another microphone session.

Recording continues in the background under the audio background mode. Only the currently open audio file uses `completeUnlessOpen` protection so it can continue while the phone is locked; closing restores `complete`. The health archive retains complete protection, and checkpoints wait for protected data. Voice stops microphone/speech playback when leaving the foreground and presents a paused activity rather than pretending it remains live.

Activities are optional: denied authorization, a disabled preference, or system dismissal cannot block recording. Orphan activities are ended on launch. Stale system displays instruct the user to open Harbour. No push token/server is required.

## How to change it

Shared Codable attributes live in `Shared/HarbourActivityAttributes.swift`; app orchestration is `Harbour/SessionActivities.swift`; presentation is the `HarbourActivity` widget extension. Change the shared schema in both targets together. `scripts/generate-project.py` owns extension embedding and target generation. Do not include patient data in activity attributes or deep links. Keep native timer text rather than issuing per-second activity updates.

## Configuration and dependencies

Requires ActivityKit, WidgetKit, SwiftUI, the embedded `.appex`, `NSSupportsLiveActivities`, the `harbour` URL scheme, and `UIBackgroundModes=audio`. Settings uses `liveActivitiesEnabled` (default true). Recording remains limited to 90 minutes. System authorization and device capabilities determine available presentations.

Native simulator checks cover one-tap recording, background return, pause/resume controls, audio persistence, and the visible Dynamic Island timer. iOS file-protection attributes and recording across a physical device lock still require a device; simulator success is not encryption-policy acceptance.
