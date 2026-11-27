# Flat record lists release

## What it is

Harbour Health 0.1 (9) removes contrasting cell backgrounds from Symptoms, Medications, Readings and Appointments. Read-only symptom details, appointment preparation and chat history now share the page canvas and retain native separators.

## How it works

Clear backgrounds are applied to each enclosing row (including NavigationLink and Button), rather than only the label inside it. Native disclosure, editing and swipe actions remain in place. See [interface](../interface.md#flat-record-lists) for extension guidance.

## How to change it

Use `RecordListAppearanceUITests` for populated light/dark review. The passing simulator test captured fourteen screens and exercised symptom navigation, medicine editing and saved-chat reopening; zero tests failed or skipped. Result bundle: `test_sim_2026-11-09T17-45-09-435Z_pid62996_ebead182.xcresult`. Screenshots 174–187 are included in the README. The localization audit passed with 680 interface keys and 6 permission keys per language. This release changes presentation, not medical extraction or stored records.

## Configuration

Version 0.1, build 9, bundle `com.matteopolak.harbour`, team `8SZZPTG649`. The signed archive is `/private/tmp/harbour-testflight-20261109-build9/Harbour.xcarchive`; its adjacent source manifest matches the app/core sources at feature commit `08da055`. The archive completed before the machine's active developer directory changed to Command Line Tools. Export/upload reused that archive with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; no global developer-directory setting was changed.

Internal export uses `testFlightInternalTestingOnly = true`, and distribution targets the existing Harbour testing group. No public release or external beta review is requested.

## Dependencies

SwiftUI's native List row traits, existing adaptive Palette colors, Xcode signing and App Store Connect processing. Existing model downloads, preferences, permissions and data schemas are unchanged.

## Distribution result

App Store Connect showed Build 9 Internal — Testing with Harbour testing selected on November 9, 2026. The build identifier is `976f01cb-8349-4e74-b911-6ac797c3c127`. Processing and internal group assignment were verified after upload; no public submission was made.
