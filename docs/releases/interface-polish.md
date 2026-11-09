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

Core regression checks: 147 passed. Native checks have exercised the named model picker, compact saved table, empty/typed composer controls, full-screen voice in English/French/landscape/large text, report compilation and switch/drawer/preview flows. Initial table-selector and nested-switch-style failures were corrected rather than accepted. The live Balanced request displayed the correct ten saved blood-pressure measurements in the native simulator; the final post-format check and internal distribution verification are pending.
