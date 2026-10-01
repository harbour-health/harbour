# Canadian French localization

## What it is

Harbour presents its native interface in Canadian French or English using bundled translations and the iOS app language setting. French input recognition is a separate, bounded Core feature described in [French input validation](french-input-validation.md) and [French record input](french-records.md).

## How it works

`Harbour/en.lproj` and `Harbour/fr-CA.lproj` contain matching `Localizable.strings` and `InfoPlist.strings` tables. English display text is the lookup key and English fallback. SwiftUI literal labels use normal bundle lookup; computed labels, enum display values, service status messages and errors use `L10n.string`. Runtime sentences use `L10n.format` with stable printf keys, for example `L10n.format("Refill %@", L10n.medicineName(medicine))`. Translations must preserve every argument's type and count, including escaped percent signs.

`L10n` selects `fr_CA` or `en_CA` from the bundle's preferred localization. `HarbourApp` supplies that locale to SwiftUI, and explicit formatting uses the same locale. `readingValue` displays a decimal comma in French; `ReadingParser.normalizedValue` restores the canonical decimal point when saving. `medicineName` translates a canonical catalog name only when both the medicine ID and original name match the catalog. Custom product names remain literal. Ingredient display labels are looked up independently from their stored identifiers.

`LocalizedHealthContent` in `CareViews.swift` builds appointment notes directly from `Records` and optional `CareData`. It translates section headings and known display values while preserving symptom descriptions, onset text, custom medicine names and saved questions. Its `timelineEntries` helper rebuilds generated metadata by the original record IDs, then searches the displayed entries. Native history and chat share this helper. Existing free-form medicine event titles, visit titles and transcripts retain their original text; no translation is inferred from arbitrary text prefixes.

Core continues to return its existing English strings and canonical machine values. The app localizes known guidance, interaction summaries and errors at its presentation boundary. Tool IDs, JSON keys, enum raw values, catalog IDs, severity selection tokens and accessibility identifiers remain stable. Evaluation fixtures, raw model output and source quotations retain their original language. A saved conversation may therefore contain messages from more than one app language.

`ModelManager` adds a Canadian French prose instruction to generation when French is selected. It explicitly preserves required machine formats, source quotes, medicine names and extracted instructions. This requests a language from the local model; it does not establish extraction accuracy. Download verification uses the separate `isVerifying` flag, so a translated status message cannot alter control flow.

`InfoPlist.strings` covers six native permission descriptions: microphone, speech, HealthKit read and update keys, Face ID and camera. Apple upload validation requires the HealthKit update description even though Harbour requests no write types; both languages accurately describe read-only import. Speech capture, visit transcription and response playback use the app language through `SpeechLanguage`. On-device recognition must be available for that language. Medicine OCR prefers the app language while including both Canadian French and English recognition languages.

## How to change it

Add each display key to both localization tables. Keep the English table's values equal to their keys, and translate the complete sentence rather than assembling a sentence from separately translated fragments. Use singular/plural keys where the number changes the wording. Retain the original English value for selection tags, comparisons and persisted data; translate only the label shown beside it.

Extend `L10n.swift` for presentation formatting and `LocalizedHealthContent` for structured generated notes/history. Add recognized source phrases to Core as described in the two French input documents. Keep user text and source evidence out of translation lookup. Update `InfoPlist.strings` in both languages when adding a native permission description. Run `python3 scripts/generate-project.py` after adding source or localization resources; it registers localized tables as Xcode variant groups and derives the known regions.

From `csi4900/ios`, run `python3 scripts/audit-localization.py` to check table syntax, duplicate keys, English/French key parity, nonempty translations, format arguments, permission coverage and recognized literal display keys. Review its interpolation findings manually: a source scan cannot verify every computed string or a rendered layout. `HarbourLocalizationTests` covers the packaged tables, permission descriptions, numeric display and stable persisted values. `HarbourFrenchScreensTests` defines a French launch and native draft workflows. Their presence is not evidence that the current native run or visual review has passed; record completed runs and inspected captures in [Evaluation](evaluation.md) and [Visual review](visual-review.md).

## Configuration

iOS chooses the app language from its supported localizations; there is no separate Harbour language preference or data migration. `Info.plist` declares `en` and `fr-CA`, and the generated project uses English as its development region. For a French test launch, use `-AppleLanguages (fr-CA)` and `-AppleLocale fr_CA` as separate launch argument pairs. Appearance remains controlled by the independent persisted System/Light/Dark setting.

Resource folder names use `fr-CA`; Foundation formatting uses `fr_CA`. Unsupported or missing translation keys fall back to their English key. Recheck text wrapping, keyboard layouts, large text, VoiceOver and both appearances after adding longer translations. Speech locale availability and permission UI still require native device verification.

## Dependencies

Foundation bundle lookup and locale formatting, SwiftUI localization, the app's bundled resources, and HarbourCore records/catalog/parsers. Speech, Vision, UIKit and native permission frameworks provide device services. Localization adds no translation service, remote API or new package.
