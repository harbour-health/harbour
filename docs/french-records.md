# French record input

## What it is

The portable record parser accepts a bounded set of Canadian French reading labels and medication spellings. It returns the existing canonical record values so language changes do not change saved identifiers or ingredient mappings.

## How it works

`ReadingParser.parse` recognizes English labels plus `pouls`, `fréquence cardiaque`, `rythme cardiaque`, `tension`, `tension artérielle`, `pression artérielle` and `température`. Matching ignores case and accents. It searches only the next 36 characters on the same line, including a number touching the label or `de`: `Mon pouls est de72`, `tension120/80`, and `température36,8` produce `72`, `120/80`, and `36.8`.

`normalizedValue` converts a decimal comma to a decimal point and removes whitespace around a blood-pressure slash. The native `ReadingEditor` uses it before saving a manually entered value. French display and prefilled input use `L10n.readingValue`, including a `36,8` temperature example, while stored values use `36.8`. Validation keeps the existing numeric ranges, systolic greater than diastolic, and rejects malformed numbers, nonfinite values, negative values and scientific notation.

`Catalog.names(for:)` exposes exact product spelling aliases. `resolve(_:saved:)` matches a complete name and gives saved records precedence. `mentioned(in:saved:)` matches whole names in source text and deduplicates by ID. `search(_:)` supports partial product and ingredient name searches for the editor. French spellings map to the existing `warfarin`, `ibuprofen`, `aspirin`, `naproxen`, `acetaminophen` and `metformin` IDs. `AAS` and `acide acétylsalicylique` map to `aspirin`. Brands retain their names, and a generic ingredient mention does not imply a particular brand. Alias matching does not validate a product’s strength or formulation.

## How to change it

Edit `Records.swift` and add fixtures in `FrenchRecordsTests.swift`. Keep aliases attached to the known catalog; unknown products still need explicit confirmation and remain unconfirmed. Never translate `ReadingKind.rawValue`, medicine IDs, or the canonical ingredient arrays. Display names belong in the app’s localization table.

The app's `LocalizedHealthContent.appointmentNote(records:care:)` rebuilds notes from the structured records. It selects the latest symptom, composes localized concern/onset/severity/medicine/reading sections, and appends saved questions when `CareData` is supplied. With no care data, it retains the original generated question suggestions. Source text remains unchanged; labels, known severity values and empty-state messages are translated. Extend this helper instead of translating `Records.appointmentNote` and splitting it at an English `Questions:` marker; the portable Core output remains English. Its app keys include `Concern: %@`, `Started: %@`, `Severity: %@`, `Medicines entered: %@`, `Recent readings: %@`, `Questions`, `Not recorded`, `None entered`, and `No questions saved.`

See [Canadian French localization](localization.md) for catalog display names, structured timeline metadata, resource packaging and native verification commands. Keep record parsing independent of the selected app language so the same saved data works in either interface.

## Configuration

There are no environment variables or locale-dependent data formats. Parsing supports the listed English/French aliases regardless of UI language. The 36-character same-line bound and the existing valid ranges live in `ReadingParser`. Accent/case folding uses a fixed locale for reproducible recognition.

## Dependencies

Foundation string folding and regular expressions, existing `Medicine` and `Reading` models, and the internal catalog. No network service, model inference, or Core localization resources are used. Native presentation and number formatting depend on the app’s localization helper.
