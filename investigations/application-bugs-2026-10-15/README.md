# Application bug investigations

Seven issues were investigated against application commit `5158710fa518816ca14781ca4d7a4c3f459675b8`. This directory contains reproduction tests and their actual results; it changes no production source, model weights, prompts, evaluation fixtures or release gates.

**All 20 characterization methods passed. Passing means the current defect and its controls were reproduced, not that a fix was made.**

| Issue | Finding | Evidence and limits |
| --- | --- | --- |
| [#2](https://github.com/harbour-health/harbour/issues/2) | Summary-of / résumé-de requests become appointment drafts | Actual Core execution in English and French, with genuine appointment and documentation controls. Saving still requires date confirmation and Save. |
| [#3](https://github.com/harbour-health/harbour/issues/3) | A trailing doctor-approval condition becomes an unconditional removal action | Actual Core execution; equivalent leading conditions reject. The app still requires destructive confirmation. |
| [#4](https://github.com/harbour-health/harbour/issues/4) | Affirmative polite appointment requests are rejected | Actual Core execution isolates `could` and `?`; direct forms work and genuine speculation remains rejected. |
| [#5](https://github.com/harbour-health/harbour/issues/5) | Thirteen valid staged highlights reject the entire summary | Actual staged extraction with correct controlled outputs. Twelve succeed; thirteen survive assembly but fail the final parser. No transcript or prior-summary deletion demonstrated. |
| [#6](https://github.com/harbour-health/harbour/issues/6) | Complete qualified quotations cannot pass unit ownership | Actual English/French staged extraction; full quotes pass the parser but are dropped by assembly. Shortened unsafe excerpts remain rejected. Warnings are retained. |
| [#7](https://github.com/harbour-health/harbour/issues/7) | Appointment-only summaries also satisfy the empty-state predicate | Actual parser-produced state and the exact source-bound UI conditions. No rendered SwiftUI or device claim. |
| [#8](https://github.com/harbour-health/harbour/issues/8) | Cancellation leaves a busy window while Chat enables Send | Actual manager/runtime Swift with controlled C ABI and URLSession boundaries; retry after completion succeeds. No physical tap, real-model decode duration or device-frequency measurement. |

The first six issues use 16 Core XCTest methods. The cancellation investigation uses four methods: three runtime/manager integration methods and one exact ChatView source-contract check. No model inference ran and the Docker executions disabled networking.

## Reproduce

Use this investigation commit, Python 3, Git and Swift. Run from the repository root, with a new absent output directory:

```sh
python3 investigations/application-bugs-2026-10-15/run-core.py --output /tmp/harbour-core-bug-reproduction
swift test --package-path investigations/application-bugs-2026-10-15/cancellation --jobs 4 --filter CancellationInvestigationTests
```

The Core runner materializes canonical Git source from the fixed application commit and adds only the isolated investigation tests. Its source manifest binds all 45 inputs. The cancellation package depends on this commit's unchanged `HarbourCore`; its copied manager/runtime files and their narrow platform boundary are bound in `cancellation/preparation.json` and the execution receipt.

The original standalone cancellation preparation used a scratch path. The command above targets the published package. The final tested package contains the actual `TitleOutputGrammar` dependency; the earlier missing-dependency compilation failure remains in the evidence.

## Evidence

- [Core tests](core-tests/), [actual Core log](evidence/core-swift-test.log), and [execution receipt](evidence/core-execution.json).
- [Validation findings](evidence/issues-002-004-actual-investigation.md) and [visit findings](evidence/findings-5-7-confirmed.md), including positive/negative controls and inspected persistence boundaries.
- [Cancellation package](cancellation/), [actual cancellation log](evidence/cancellation-swift-test-03.log), and [execution receipt](evidence/cancellation-execution-03.json).
- [Earlier harness compilation failure](evidence/cancellation-swift-test-02.log), which was a missing test-package dependency and is not an application build failure.

The cancellation subject uses actual application Swift code. Its C llama ABI implementation is a test double, not a real model. Linux platform shims and one additive `FoundationNetworking` import let the unchanged manager logic compile. A test URLProtocol prevents real downloads; the CryptoKit boundary must not be used for real hash verification. Windows materialized CRLF files were verified against Git, then the tested subject was rebuilt from canonical LF bytes. These boundaries are explicit so the controlled lifecycle result is not mistaken for an end-to-end iPhone test.

These findings do not establish how often a model selects the problematic action or explain a generation that was already empty before application filtering. Fixes and their desired-behavior regression tests remain separate work.
