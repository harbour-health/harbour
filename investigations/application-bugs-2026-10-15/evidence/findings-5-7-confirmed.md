# Confirmed visit application defects: issues #5–#7

Baseline: `5158710fa518816ca14781ca4d7a4c3f459675b8`.

Root compiled the isolated copy of the production Core and ran the combined investigation with controlled generation stubs. The command exited 0: all 16 selected methods passed, including all four visit methods. The execution receipt records 45 canonical source files unchanged before and after. These characterization tests assert the current defective behavior; their success does not mean the bugs are fixed. No model inference ran.

## Issue #5 — Combining valid extraction stages rejects the whole summary at 13 items

**Expected:** A valid chunk whose selected units each produce one exact, individually valid highlight should retain those facts, within a coherent aggregate bound. It should not reject every fact solely because independently allowed stages together exceed the parser's legacy per-array bound.

**Actual:** The same controlled source/stub structure succeeds with 12 highlights and fails with 13. All 13 exact highlights survive staging into `assembledOutput`, but the combined parser throws `invalidOutput`; the run records `assembled_validation_failed`, `completed` is false and `acceptedSummary` is nil.

```text
VISIT_ISSUE_5 boundary=12 assembled=12 completed=true accepted=12
VISIT_ISSUE_5 boundary=13 assembled=13 completed=false accepted=-1
```

The test uses 13 short, distinct clinical-source sentences (left/right knee, shoulder, elbow, wrist and ankle pain, plus neck/back/jaw pain). The whole transcript is below the 1,800-character chunk limit. Each source sentence is separately accepted by the actual parser. The actual source unit count equals 12 or 13, below the 24-unit limit; each correct extraction stage returns exactly one highlight.

Code: [per-stage array bound](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Sources/HarbourCore/VisitExtraction.swift#L201), [combined parse](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Sources/HarbourCore/VisitExtraction.swift#L223), [combined parser's 12-item bound](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Sources/HarbourCore/Visits.swift#L196).

The summary caller requires `completed` and a non-nil accepted summary before merging or saving ([VisitsView.swift:283](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/Harbour/VisitsView.swift#L283)). That caller consequence is established by source inspection, not a rendered-UI or storage mutation test. The test does not show loss of the saved transcript or deletion of an earlier summary.

Existing coverage checks 60-sentence grouping into at most 24 units, but does not exercise aggregation above 12 accepted objects ([VisitExtractionTests.swift:45](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Tests/HarbourCoreTests/VisitExtractionTests.swift#L45)).

## Issue #6 — Unit ownership rejects a valid complete contextual quote

**Expected:** A legitimate historical/other-person fact must keep its complete speaker and historical context. A quote which passes final source validation should have a representable owning source unit when that context spans sentences.

**Actual:** Both English and French source examples form three units. The complete historical quotation passes `VisitReview.parse`, and the selected units contain that full quotation in their `contexts`. Correct extractor stubs return that same complete quote, but every selected stage drops it because it is not wholly inside `unit.text`. The run completes with zero accepted highlights and `unrelated_quote.unit.<id>.highlights` warnings. This is warned information loss, not an unwarned success.

English source:

```text
Yesterday my brother said: "I had a cough. It is worse at night."
```

French source:

```text
Hier, mon frère a dit : « J'avais une toux. Elle est pire la nuit. »
```

```text
VISIT_ISSUE_6 language=english units=3 fullQuoteValid=true retainedHighlights=0
VISIT_ISSUE_6 language=french units=3 fullQuoteValid=true retainedHighlights=0
```

Controls passed: shortened per-unit excerpts are rejected by final scope validation; the original complete quotes returned by the stubs each pass direct parsing; English/French single-sentence historical quotes and ordinary independent clinical sentences pass the staged path. Thus the defect is specifically the mismatch between cross-sentence contextual scope and sentence-unit ownership, not a request to admit unrelated output or remove historical/negation protections.

Code: [sentence-unit construction](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Sources/HarbourCore/VisitExtraction.swift#L83), [strict ownership check](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Sources/HarbourCore/VisitExtraction.swift#L205), [complete contextual quote requirement](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Sources/HarbourCore/VisitSourceGrounding.swift#L192).

Existing tests exercise retained historical context while rejecting an invalid current medicine action, and correctly reject an unrelated whole-paragraph medicine quote. They do not test retaining a legitimate complete contextual highlight across units ([VisitExtractionTests.swift:103](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Tests/HarbourCoreTests/VisitExtractionTests.swift#L103), [VisitExtractionTests.swift:142](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Tests/HarbourCoreTests/VisitExtractionTests.swift#L142)).

## Issue #7 — An appointment-only summary also satisfies the empty-summary UI predicate

**Expected:** An accepted summary containing an appointment should not say “No details extracted.”

**Actual:** The real parser produces an appointment-only summary from `Appointment tomorrow at 3 pm.` and `Rendez-vous demain à 15 h.`. This occurs both with four empty raw arrays (existing appointment recovery) and with a correct raw appointment object. Highlights, follow-ups and medicines remain empty, while appointments contains the exact source quote. The test reads the actual `VisitsView.swift`, verifies the exact predicate text and confirms the same state satisfies both the appointment-display condition and the empty-warning condition.

```text
VISIT_ISSUE_7 parserAppointmentOnlyReachable=true actualUIPredicateBound=true simultaneousAppointmentAndEmptyBranches=true
```

Code: [appointment display](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/Harbour/VisitsView.swift#L206), [empty predicate omitting appointments](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/Harbour/VisitsView.swift#L222), [appointment recovery](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Sources/HarbourCore/Visits.swift#L221).

Controls passed: a genuinely empty summary satisfies the empty predicate, while an ordinary recovered follow-up suppresses it. This proves parser-state reachability and the contradictory source-bound branch conditions. It does not claim that a SwiftUI screen was rendered, accessibility inspected or a device exercised. Existing appointment tests validate recovery/dates/source rules, but not this empty-state predicate ([AppointmentTests.swift:24](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourCore/Tests/HarbourCoreTests/AppointmentTests.swift#L24)).

## Reproduction and limits

The executed command was:

```sh
HARBOUR_INVESTIGATION_SOURCE_ROOT=/investigation/source \
swift test --package-path /investigation/source/HarbourCore --jobs 4 --filter ReproductionTests
```

The isolated test file was `VisitApplicationBugReproductionTests.swift`, SHA-256 `94aa72c478ea2ff59d02a9fa2a0884ed71b49fb55444bd76b6e1e9f80da6cfd1`. Root included it alongside the other investigation classes; these visit methods passed with zero failures. The execution image was `sha256:4e2d836d1252e502c2c5ac92bc73e675d5d9a1780a82ad4c4127624e5792d756`.

The full log SHA-256 is `7d175a7a15bab3b29c461f9efe712c9a984388630729b15616c09e95f7f2a436`; its visit evidence is at lines 66–81. The companion binding records the original preparation, actual execution and source bytes. Preparation remains immutable and explicitly predates execution.

These tests confirm deterministic application defects independent of model weights. They do not establish their frequency with real recordings, constitute fixes, or explain extractor generations that were already literal empty arrays before application assembly/filtering. No new inference, production edits, frozen evaluation changes or additional test execution occurred during this final evidence review.
