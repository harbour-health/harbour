# Record validation

Small validation rules prevent numeric punctuation from losing legitimate readings and prevent appointment-only visit summaries from appearing empty.

## How it works

`ReadingParser` accepts terminal sentence punctuation after values such as `81.` and French decimal input such as `37,1.`. Numeric boundaries still reject malformed decimals, scientific notation, invalid ranges and pressure triples. Dose and quantity units such as `mg` cannot become vital-sign measurements.

`VisitSummary.isEmpty` includes appointments alongside medicines, highlights and follow-ups. Older saved summaries may omit the optional appointments field; decoding and the empty state remain compatible. The visit detail screen uses this shared check.

## Changing it

Keep typed-reading bounds and units in `ReadingParser`. Extend the bilingual `ReadingParserTests` with accepted and rejected inputs together. Add any new displayed summary category to `VisitSummary.isEmpty` and cover both storage and merging in `VisitSummaryEmptyTests`.

## Configuration and dependencies

No additional configuration or external dependencies. These rules use Foundation and the existing Core records and visit types; they do not supply model-generated facts or route chat requests.

Appointment creation validation distinguishes explicit/polite booking requests from documentation requests such as “Make a summary of my appointment.” Clinical appointment-fact recognition remains unchanged. Medication removal rejects unresolved approval and timing conditions instead of stripping them from the confirmation. The model still selects the tool; these checks can only reject an unsupported write. `WriteBoundaryTests` covers English/French and quoted, negated, hypothetical and compound controls.
