# Report design

## What it is

The report export and its native configuration screen share Harbour's typography hierarchy, four-part mark, neutral surfaces, and blue/coral accents. PDFs use a fixed light appearance for printing, independently of the app's selected appearance.

## How it works

The template uses bundled Lato regular/bold, dark text, muted supporting text, restrained section rules, and rounded chart surfaces. Headings stay with following content. Longer reports repeat the document title in the header and show current/total page numbers in the footer. Personal text remains JSON data rather than executable Typst markup.

The native options use the existing `FeatureIcon` and `ActionButtonStyle`, with coloured section symbols and a full-width primary preview button. The redundant introductory paragraphs and report shortcut subtitle were removed. Trends use semantic reading/category symbols, while plots retain the established `Palette.blue`/`Palette.coral` colours.

## How to change it

Edit `HarbourReports/Sources/HarbourReports/Resources/visit-report.typ` for document hierarchy, spacing, and pagination. SVG chart labels and palette are in `VisitReportSnapshot.chart` in `Harbour/VisitReport.swift`; keep them aligned with the template. Section icons and selection controls live in that same Swift file. `Harbour/CareViews.swift` owns trend selectors and the preparation shortcut.

`Renderer/fonts` contains open-licensed Lato regular/bold and its OFL notice. Font bytes enter the renderer's font book in `Renderer/src/lib.rs`; changes require rebuilding the XCFramework with `scripts/prepare-reports.sh --force`, using the environment overrides in [Doctor visit reports](visit-reports.md). Template changes alone do not require a Rust rebuild. The preparation script fingerprints renderer source, dependencies, and fonts; an existing framework is reused only when its fingerprint matches, preventing an old font book from silently substituting a serif face. The license is also included in the Swift resource bundle as `Lato-OFL.txt`.

## Configuration

Document colours match Light `Palette`: ink `#181818`, muted `#606060`, surface `#F5F5F5`, blue `#365DCE`, coral `#B94831`, line `#E5E5E5`. Letter paper has 20 mm side margins. Body text is 10.5 pt, section headings 16 pt, and the report title 27 pt. No network or installed system font is required at runtime.

## Dependencies and review artifacts

Typst 0.13.1, the existing sandboxed Rust renderer, PDFKit, Lato under the SIL Open Font License, and shared SwiftUI components. [Font source](https://github.com/google/fonts/tree/main/ofl/lato).

[English PDF](report-design/english-preview.pdf) and [French PDF](report-design/french-preview.pdf) are fictional **style fixtures**, rendered through the rebuilt native Rust library with the production template. Their JSON inputs are stored alongside them. The simplified chart in these fixtures is authored demonstration data, not an output of the Swift reading chart generator or clinical evidence. Native report tests separately exercise actual reading SVGs, date/section filtering, literal user text, multipage output, preview, and sharing. No personal records are included in these artifacts.

## Verified native run

`harbour-report-design-reviewed.xcresult` passed all five report tests on November 6, 2026: three hosted renderer/snapshot tests and two native English/French preview and sharing flows, with no runtime warnings reported. Captures 147–150 are exported from that completed run and included in the README. The report configuration and both final PDF preview originals were visually inspected. A separate six-page literal-text fixture was rendered with the same library/template to review continuation headers and footers. Localization source audit passed (641 interface keys). Physical-device and every-screen Dark/Dynamic Type acceptance were not repeated in this focused report review.
