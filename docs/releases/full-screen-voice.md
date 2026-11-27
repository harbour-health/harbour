# Full-screen voice release

## What it is

Version 0.1 (7) adds the full-screen voice conversation surface. App Store Connect showed Internal — Testing with the existing Harbour testing group selected on November 7, 2026. Build 6 remains unassigned; no public release or external beta review was requested.

## How it works

The animated surface reflects listening, waiting and playback while ordinary chat messages persist behind it. Ending voice restores the conversation. See [voice conversation](../voice-conversation.md) for lifecycle and audio ownership.

The release archive is `/private/tmp/harbour-testflight-20261107-build7/Harbour.xcarchive`; the adjacent source manifest records app-source hashes. The app record is Harbour Health, version 0.1 (7), bundle `com.matteopolak.harbour`. The build identifier is `28442d91-94d5-4b82-a679-6ef4dc6a49f4`.

## How to change it

Modify the voice feature and its UI/playback tests, then generate a new signed archive with a new build number. Do not distribute build 6. The final English, French/dark, landscape and largest-accessibility layouts were checked; real cached Kokoro playback metering and the native inhaler-summary regression passed. Screenshots 164–168 in the gallery show the updated surface.

The reported phone recording that produced only Notes remains unresolved. The same text passed locally; this release is not evidence of a summary-accuracy fix. Existing saved summaries require Refresh summary to rerun extraction.

## Configuration

Internal TestFlight export uses `testFlightInternalTestingOnly = true`, developer team `8SZZPTG649`, and the existing Harbour testing group. Device model auto-selection is unchanged. Linked-plan and Apple extraction experiments remain benchmark-only.

## Dependencies

Xcode signing, App Store Connect processing, the existing local model runtime and Kokoro assets. See [distribution](../testflight.md), [neural speech](../neural-speech.md), and [screenshots](../screenshots.md).
