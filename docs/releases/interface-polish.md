# Chat, settings and report refinements

## What it is

Build 12 refines switch contrast, Settings drawer transitions, voice preview, chat controls/data presentation, meeting follow-ups and doctor visit reports. It also adds the requested maintained Swift formatting workflow.

## How it works

Switches apply the same blue native-control modifier directly, including report options. The drawer retains one native custom detent and animates changes, respecting Reduce Motion. Its UIKit resize probe is transparent to hit testing. Voice preparation, downloads, percentages and cancellation stay inside one fixed-height preview button. The Home demo-data badge is removed, while Developer reset/provenance remains.

Alex (0.5B), Sam (1.5B) and Camille (7B) are the model display names; dim subtitles identify their underlying Qwen model and quantization. Free-form conversation gets distinct wording preferences only; source checks, routing and clinical limits are retained. Automatic device selection and verified on-demand downloads are unchanged.

Chat's leading buttons share a compact group. The microphone dictates directly; an empty draft uses the primary action for full-screen voice, typed content uses Send, and active generation uses Stop. The material composer overlays scrolling content with measured bottom clearance and an opaque Reduce Transparency fallback. Reading tools render a compact table from saved values, not generated numerical prose. Explicit source types filter a model-selected read-only tool; broader/negated queries are not reinterpreted as writes. Follow-ups put reminder actions opposite text and date.

Reports default to descriptive per-type statistics, all-point charts and bounded recent history, with an explicit Full history option. Current medication instructions are preserved. See [condensed reports](../report-summary.md), [interface](../interface.md), [drawers](../floating-drawers.md), [local models](../local-models.md) and [formatting](../swift-formatting.md) for details.

## How to change it

Use the shared switch modifier and native drawer bridge rather than custom control drawings. Preserve the fixed preview footprint, accessible labels, canonical table values and model/action separation. The formatting-only commit is separate from functionality and is listed in `.git-blame-ignore-revs`; frozen evaluation source snapshots are excluded from bulk formatting.

## Configuration

Existing bundle `com.matteopolak.harbour`, developer team `8SZZPTG649`, version 0.1/build 12, existing internal TestFlight group. No new service, bundled weights or public submission. English and Canadian French catalogs are updated. SwiftFormat is pinned to 0.64.6 with a verified official binary and compiler-aware spacing; local Git blame uses the standard ignore file.

## Dependencies

SwiftUI, UIKit's native sheet animation API, existing local model/speech services, HarbourCore validation, HarbourReports/PDFKit, Python/Git/Xcode for formatting and the existing internal distribution script.

## Validation and distribution

Core regression checks after formatting: **147 passed**. The final signed-simulator result `/private/tmp/harbour-polish-post-format-20261109.xcresult` passed **14 hosted/UI checks**, including the real Balanced blood-pressure request, explicit filter and source-backed table, named-model composer, switch interaction in both themes, compact drawer navigation, inline preview geometry, English/French/landscape/large-text voice mode, model asset invariants and PDF compilation. No skips or failed checks remain in that final run. The live CPU-only model request took about 285 seconds while the Release archive compiled; this is simulator evidence, not an iPhone latency benchmark.

Initial accessibility-selector and nested-switch-style failures were corrected, followed by the final successful run. The 126-reading fictional report now renders in **two pages**, with all current medicine directions retained; Full history is separately checked. Native video showed intermediate drawer top positions during shrink and expansion (rather than a single position jump), and the UI test confirmed unchanged preview-button placement while preparing speech.

Functional changes: `9d566af`. Formatting only: `9fbc3a0a5893eb6889bde41bd5af011acf93ac3b`, registered in `.git-blame-ignore-revs`; local blame is configured to use it. A final format check reports 117 maintained Swift files checked, zero changes required. Compiler-parsed string literals in the planner, model manager and runtime were compared before/after formatting and remained identical. The localization audit passes with 697 interface keys and 6 permission keys per language. Frozen evaluation snapshots and pre-existing report/TestFlight documentation edits were preserved.

Build 12 archive: `/private/tmp/harbour-testflight-20261109-build12/Harbour.xcarchive`, with an adjacent 102-file source/resource checksum manifest. The bundle/build identity and internal-only export flag were checked. Upload was accepted by Apple at approximately 15:46 EST on November 9, 2026. Internal-group assignment is pending processing. Final app captures and the two rendered PDF pages are in the README/gallery. No new physical-device performance or clinical-accuracy claim is made.
