# Care notifications

## What it is

Native local notifications for saved follow-ups, daily medicine times, refill dates, and snoozed doses. Permission is requested only when the user saves an action with notifications enabled or chooses Remind later.

## How it works

`CareNotificationPlan` creates portable plans. `CareNotifications` checks authorization, reconciles only requests prefixed `harbour-care-`, then submits calendar triggers. Dose times repeat daily; follow-ups, refills, and snoozes fire once. Completed/past reminders and orphan medicine schedules are excluded. Taken and Skipped logs remove matching delivered dose notifications; they do not cancel future daily reminders.

Lock-screen messages contain only “Harbour” and a generic reminder, with no medicine, symptom, question, or visit details. Records still save when notification permission is denied; the editor shows the permission status. Reconciliation runs when care data or saved medicine IDs change and when the app becomes active. A single reconciliation worker processes the latest queued snapshot. Generation guards stop superseded work at await boundaries, and the worker waits for an in-flight add to finish before reconciling the newer snapshot. This removes obsolete requests even when a save or delete occurs during an asynchronous add. Delivered notifications for removed or completed actions are removed; a dose log only clears a daily delivered reminder from the same day.

## How to change it

The app reconciles notifications when either care data or saved medicine IDs change, and when it becomes active. Keep both dependencies: restoring a medicine can make a historical snooze eligible without changing the care object.

Adjust planning in `HarbourCore/Care.swift` and native scheduling in `CareNotifications.swift`. Keep the app-owned prefix so other requests are untouched. Any new reminder type should have a stable identifier and cancellation path. `CareNotificationDelivery` allows a suspended add in unit tests to reproduce the save/delete race. The native center regression uses a unique injected prefix and checks actual pending requests, private content, completion cancellation and preservation of unrelated requests. It skips explicitly if permission is unavailable; it never opens a permission prompt. Daily schedules are time-zone-relative rather than fixed UTC timestamps; reassess dose-log identity if adding travel/time-zone scheduling options.

## Configuration

The next 60 requests are submitted, leaving room below the operating system limit. Excess requests show a status message; completing/removing an earlier reminder or opening the app lets later requests enter the queue. Missed historical notifications are not fired on launch. Notification delivery timing is controlled by iOS and user Focus/notification settings.

## Dependencies

Apple UserNotifications, Foundation calendars, persisted `CareData`. No push notification service or background network job.
