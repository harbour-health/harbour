# Offline medication vocabulary

Harbour bundles a compact English/French name vocabulary derived from Health Canada's marketed human-drug DPD extract. This improves name lookup, search and speech context; it does not add interaction rules or prescribe doses.

## How it works

The importer joins drug and ingredient files by drug code, excludes veterinary/disinfectant/radiopharmaceutical classes and retains salt-qualified ingredient identities. It emits generic ingredients and brands whose marketed products share one ingredient composition. Brands with multiple compositions are excluded. The manifest records source date, URLs, SHA-256, byte sizes and counts. Strength, formulation and route are not resolved by this name-only index.

The 2026-11-02 source produces 8,299 entries (1,738 ingredients and 6,561 brands) in approximately 1.46 MB of JSON. JSON is a build resource, loaded once in HarbourCore; raw ZIP files remain outside Git. Runtime dictionaries and normalized aliases cost more memory than the file itself; no resident-memory claim is implied by file size.

`Catalog` preserves saved/curated identities before database lookup. Exact aliases identify records; ambiguous aliases are removed. When the same exact alias and composition appear on a generic and brand entry, the generic identity wins so its official French name remains available. Unchanged database labels can display in French; custom user labels are preserved. Mention extraction uses bounded longest matching rather than splitting names at arbitrary punctuation. The explicit familiar-name alias levothyroxine maps to DPD ingredient 5325 (levothyroxine sodium); the salt remains in its ingredients. Source: [Health Canada Synthroid listing](https://produits-sante.canada.ca/dpd-bdpp/info?code=19595&lang=eng).

Phonetic suggestions combine a conservative letter fold and edit distance. They are shown only as **Similar names** when normal search finds nothing. Choosing a candidate opens the existing medicine editor with confirmation reset. Validators never use phonetic suggestions and the original transcript/directions are never rewritten. There is no claim that spelling proximity identifies the correct treatment.

Speech uses a maximum of 100 short phrases, saved medicine names first, followed by a limited set of difficult common names. It does not load the entire database into recognition. Legacy on-device `SFSpeechRecognitionRequest.contextualStrings` and iOS 26 `SpeechAnalyzer` AnalysisContext receive the hints. Apple describes these as likelihood hints, not guaranteed recognition: [contextualStrings](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings), [AnalysisContext](https://developer.apple.com/documentation/speech/analysiscontext).

## How to change it

Run `python3 scripts/import-medication-vocabulary.py --source-date YYYY-MM-DD --cache /path/to/cache` after checking the official [extract publication page](https://www.canada.ca/en/health-canada/services/drugs-health-products/drug-products/drug-product-database/what-data-extract-drug-product-database.html). A populated cache is deliberately reused; use a fresh cache when updating. Review manifest changes and aliases. Do not generically strip chemical suffixes. The [schema](https://www.canada.ca/en/health-canada/services/drugs-health-products/drug-products/drug-product-database/read-file-drug-product-database-data-extract.html) defines input columns.

`MedicationVocabulary` owns exact lookup, search, suggestions, mentions and hints. `Records.swift` integrates the catalog; `RecordsView` shows confirmed suggestions; `DeviceServices` and `VisitRecorder` apply hints. Run core tests, localization audit, bilingual native review and model-name probes after changes. Acoustic accuracy requires recorded speech evidence separately.

## Configuration and dependencies

Importer: Python standard library, official HTTPS ZIP sources, writable cache (default ignored `build/dpd`). App: Foundation/SwiftPM resource bundle and Apple Speech; no runtime database request, external recognition service or downloaded model required for vocabulary lookup. Existing interaction coverage remains the small sourced fixture; unknown pairs remain unassessed.

## Editor and review state

Selecting a database candidate dismisses the keyboard and opens the shared confirmation form. Initial values are loaded once per editor instance, so drawer resizing cannot reset the selected product. Camera/photo controls appear during selection and return through Choose another medicine. Previously unresolved named visit items can now resolve exactly (for example, salbutamol); genuinely unknown products retain empty, unconfirmed ingredients. A catalog match never substitutes for the user's product check.
