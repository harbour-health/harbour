# Record layout and medication review release

## What it is

Harbour Health 0.1 (10) redesigns the record pages without horizontal rules and fixes unresolved visit-medication review and chat dose-correction workflows. It retains the existing app record, bundle identifier and internal testing group.

## How it works

Record rows share symmetric gutters and open spacing. The interaction action sits above medications; duplicate labels are omitted. Readings use day groups with time-only metadata. Chat history has a compact drawer. Unresolved visit medicines open the normal product confirmation/editor and save their accepted status atomically. Chat has an explicit recorded-dose correction tool, guarded deletion, a labelled alert and a visible pending status.

See [interface](../interface.md#open-record-lists), [visit medication review](../unconfirmed-medicine-review.md) and [chat corrections](../medication-chat-changes.md) for implementation and change points. The summary extraction model and three-pass meeting pipeline are unchanged.

## How to change it

Rerun the relevant native UI/model checks and `swift test --package-path HarbourCore`, plus the localization audit. Final core result: 146 passed, zero failed. Native tests exercised actual cached-Balanced routing, a real chat opening the dose editor, explicit removal/cancellation, unresolved visit acceptance, source persistence and stale-source rejection. The final generated clarification asked for the exact medicine name, without dosing advice. A broader fallback candidate failed and was rejected before release.

Visual review used actual light/dark simulator captures, with refinements to alignment, duplicate dates, empty drawer space, editor camera controls and pending-status overlap. Captures 188–208 are in the README; capture 205 documents the earlier real-chat integration with the previous editor layout. Catalogue audit: 686 interface keys and 6 permission keys in English and Canadian French. These targeted checks are not a broad clinical-accuracy or physical-device performance evaluation.

## Configuration

Feature commit `d844630`; bundle `com.matteopolak.harbour`; developer team `8SZZPTG649`; version 0.1, build 10. Final archive: `/private/tmp/harbour-testflight-20261109-build10-r2/Harbour.xcarchive`, with its adjacent source-hash manifest. The first local build-10 archive was not uploaded; r2 includes the final literal-dose validation. Export uses `testFlightInternalTestingOnly = true`. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` selects Xcode per command without changing the machine's global Command Line Tools setting.

Model auto-selection, existing downloads, app-lock settings, permissions and saved records are preserved. Reviewed visit items use an optional backward-compatible archive field. New demo data uses the same unresolved-item format as extractor output; older prose can still be reviewed with manual product selection.

## Dependencies

SwiftUI native lists/alerts, HarbourCore validation, ModelManager's existing local inference/grammar, AppStore protected atomic persistence, and App Store Connect signing/processing. There is no new network service or bundled model download.

## Distribution result

On November 9, 2026, App Store Connect showed Build 10 Internal — Testing with Harbour testing selected. Build ID: `fb3018cc-06ac-4ed9-9a0b-69263babbba2`. The final r2 source hashes matched the committed app/core sources. Upload acceptance, processing and assignment to the existing internal group were verified; no public submission or new tester access was created.
