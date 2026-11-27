# Condensed doctor visit reports

## What it is

Doctor visit PDFs default to a concise record summary rather than listing every historical reading. Full history is an explicit report option; current medication directions are included in either mode.

## How it works

`VisitReportSnapshot` filters the requested date range before building either version. Condensed readings have one item per type: valid-reading count, latest saved value/time, and numerical range. Blood pressure reports systolic and diastolic ranges separately, never as a fabricated paired measurement. Existing charts use all valid readings in the period. No LLM interprets these values or labels them healthy/unhealthy.

Symptoms show the five most recent entries, visits the three most recent saved summaries, and questions the first ten saved questions. When condensed, each section explicitly reports the omitted-entry count or shown count and explains Full history. There is no silent deletion or truncation of stored records. Current medications and their instructions/schedules are never limited. Full history restores all entries using the same date filters. Raw visit transcripts are not substituted for missing summaries.

## How to change it

Edit the `detailed` branch in `VisitReportSnapshot` and the `reportFullHistory` switch in `VisitReportView`. Keep counts, bounds and omission notices consistent. Change visual PDF styling in the bundled Typst template rather than constructing new layout in Swift. Regression tests render the fictional 126-reading demo dataset, bound its condensed page count, check retained medicine directions, and retain the complete-history literal-text/render tests.

## Configuration

Default `detailed = false`. Limits: five symptoms, three visits, ten questions. All-time/date-range and section-selection controls still apply. Statistics are descriptive recorded values, not clinical assessments. English/Canadian French strings are bundled with the app. The existing compiler size and cancellation limits remain in effect.

## Dependencies

HarbourCore records/care/visit summaries, `ReadingParser` numeric validation, `L10n`, the existing HarbourReports Typst compiler and PDFKit preview. No model download or remote service is needed to prepare a condensed report.
