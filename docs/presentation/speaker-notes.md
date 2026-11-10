# Harbour — 10-minute presenter notes

## 1. Harbour · 25 seconds

Introduce the honours prototype. The question is whether local models plus explicit source checks can support everyday health-record tasks on a phone.

## 2. Interfaces · 40 seconds

Simple mode is the default for an independent older adult. A caregiver can expose records and review tools in Settings. Both modes use the same local account and records; this is not remote caregiver access.

## 3. Request processing · 55 seconds

The local LLM chooses the tool. The app validates the request against original input, resolves names from saved records and the database, and uses existing editors. It does not let generated text directly overwrite medications. Unknown interaction pairs remain unassessed; the medication-name vocabulary is not a comprehensive interaction dataset.

## 4. App walkthrough · 230 seconds

Play the actual native walkthrough. Complete cards, record rows and drawers lift together in 440 ms before callout text appears. Explain Simple voice/chat/recording, the complete saved-readings card, caregiver measurement/medicine/symptom cards, the four record categories, medication-name review and the complete visit-change drawer. The recording uses Alex with actual tool inference. Saved records and visit summaries are fictional authored fixtures; this is not speech or summary-accuracy evidence.

## 5. Medication names · 65 seconds

The extract includes 8299 generic and unambiguous brand entries, around 1.46 MB on disk. Salt-qualified ingredients are retained. Apple recognition hints prioritize saved names and a short common-name list, capped at 100 phrases. Acoustic improvement has not yet been measured.

## 6. Visit review · 75 seconds

Use the saved authored fixture to demonstrate the review UI, not to imply this example was correctly extracted live. More complex timing, negation and follow-up summaries need held-out evaluation.

## 7. Text evaluation · 55 seconds

This is the new 16-case medication-name subset, not the full medical evaluation. Both models scored 14/16; both failed the two negation routes, and validation blocked each attempted write. Diverse fictional names were paired across otherwise identical Canadian English/French requests. 153 deterministic core tests passed. A small fixture set is not demographic or clinical validation.

## 8. Further evaluation · 40 seconds

Priorities are actual older-adult usability, bilingual acoustic tests, held-out complex visit transcripts and real-device latency/memory. No fine-tuning benefit or clinical accuracy claim is established here.

## 9. Sources · 15 seconds

Health Canada DPD extract: https://www.canada.ca/en/health-canada/services/drugs-health-products/drug-products/drug-product-database/what-data-extract-drug-product-database.html ; Apple contextualStrings: https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings ; Apple AnalysisContext: https://developer.apple.com/documentation/speech/analysiscontext ; Local evidence: docs/evaluation/medication-names.md, docs/medication-vocabulary-manifest.json, docs/testing.md. The requested 10-minute version totals 600 seconds; the supplied course brief separately specifies a 13-minute final talk.