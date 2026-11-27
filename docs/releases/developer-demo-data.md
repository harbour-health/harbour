# Developer demo data release

## What it is

Harbour Health 0.1 (8) adds Settings → Developer → Replace with demo data. The dataset is authored fiction and does not claim model-generated accuracy.

## How it works

The feature replaces the saved archive and removes old visit recordings after explicit destructive confirmation. Three visits include preset transcripts and summaries without audio, alongside readings, trends, medicines, schedules, dose history, reminders, questions, appointments and chat history. Existing model downloads, settings and app lock remain intact. See [developer demo data](../demo-data.md) for reset boundaries and failure handling.

The signed archive is `/private/tmp/harbour-testflight-20261109-build8/Harbour.xcarchive`. The adjacent source manifest matches the app/core sources at feature commit `5421f89`. Bundle identifier remains `com.matteopolak.harbour`, team `8SZZPTG649`. App Store Connect build ID: `6ff8dbe7-2f30-4772-96f1-88d8bf8e3748`.

## How to change it

Change the fixture and Developer view, then rerun the targeted tests and localization audit. Five tests passed, zero failed/skipped, on the iOS 26.5 QA simulator. All 680 interface keys and 6 permission keys passed the catalogue audit in both languages. Native screenshots 169–173 were reviewed and included in the README gallery. The archive/upload succeeded; distribution status is recorded below after processing.

## Configuration

Build number 8, internal TestFlight only (`testFlightInternalTestingOnly = true`), existing Harbour testing group. No new public release, external beta review, credentials or tester permissions.

## Dependencies

Existing Xcode signing and App Store Connect processing, AppStore/HarbourCore persistence and validation, SwiftUI, and English/French localization. The demo itself needs neither network access nor downloaded inference/voice models.

## Distribution result

On November 9, 2026, App Store Connect showed Build 8 Internal — Testing with Harbour testing selected. The processed build is assigned to the existing internal group. Upload acceptance alone was not used as the completion signal. The update does not automatically replace any device's records; testers must explicitly confirm replacement in Settings.
