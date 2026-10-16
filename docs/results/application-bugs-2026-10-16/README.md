# Seven application regression fixes

Validated application and test source: [`cb3809e5f8662b9dbc342c147faa05efe0fa0c53`](https://github.com/harbour-health/harbour/commit/cb3809e5f8662b9dbc342c147faa05efe0fa0c53). This report and its evidence are publication-only additions after that code. PR #1 remains Draft because the model-quality gates remain blocked. Automatic remains the default and Qwen3.5-2B remains optional.

## Fixes and regression coverage

| Issue | Resulting behavior | Regression coverage |
| --- | --- | --- |
| [#2](https://github.com/harbour-health/harbour/issues/2) | Requests for a summary **of/de/du** an appointment cannot create an appointment draft, including qualified appointment names. A real booking can retain a trailing notes/summary payload. | English/French documentation negatives, genuine booking positives, nested summary in booking notes and a long qualified documentation target. |
| [#3](https://github.com/harbour-health/harbour/issues/3) | Removing a medicine cannot discard a trailing approval or time condition, including a quoted condition. | English/French conditions before/after the command, direct removals including quoted medicine names and courtesy, reported/negated requests, missing/ambiguous saved identity. Explicit removal confirmation remains required. |
| [#4](https://github.com/harbour-health/harbour/issues/4) | Affirmative polite appointment commands can prepare a draft. The transcript appointment-fact heuristic is unchanged. | English/French outer modals and terminal question marks, separate speculative/conditional/reported/quoted/documentation/compound-action negatives. Original user input remains the draft source. |
| [#5](https://github.com/harbour-health/harbour/issues/5) | The staged visit pipeline retains more than 12 valid details across independent stages. | 12/13/24 actual staged highlights in both languages. Public single-call parser remains capped at 12; each stage remains capped at 12; unit count is 1–24 and aggregate cap is 12 × actual unit count. Forged bounds and 289 objects are rejected. |
| [#6](https://github.com/harbour-health/harbour/issues/6) | Documentation can retain an exact related context spanning source units, preserving speaker/history/qualifiers. | Complete English/French historical quotations survive. Shortened qualified quotes and unrelated facts are rejected. Context expansion applies only to documentation; medicine ownership and final grounding checks remain unchanged. Oversized retained context fails before generation. |
| [#7](https://github.com/harbour-health/harbour/issues/7) | An appointment-only summary shows its appointment without the false empty-summary warning. | Parser-produced appointment-only summaries, all four emptiness categories, merge/round-trip, plus a rendered English/French UI test using a parser-generated fixture. |
| [#8](https://github.com/harbour-health/harbour/issues/8) | Stop immediately invalidates results and keeps chat busy until the previous task returns. Early Send preserves the draft and does not append a message. | Ten Core lifecycle tests with controlled asynchronous barriers, including pre-start cancellation, repeated Stop, stale tokens, errors, reentrant follow-up, view replacement and ownership cleanup. One hosted test observes the actual ModelManager publication across view consumers. |

The desired-behavior tests are in [AppointmentAndRemovalIntentTests](../../../HarbourCore/Tests/HarbourCoreTests/AppointmentAndRemovalIntentTests.swift), [VisitStagedSummaryRegressionTests](../../../HarbourCore/Tests/HarbourCoreTests/VisitStagedSummaryRegressionTests.swift), [ChatRequestLifecycleTests](../../../HarbourCore/Tests/HarbourCoreTests/ChatRequestLifecycleTests.swift), [HarbourTests](../../../HarbourTests/HarbourTests.swift) and [HarbourUITests](../../../HarbourUITests/HarbourUITests.swift). Both Apple workflows explicitly select the new rendered appointment-summary test.

## Fresh Linux and xtool verification

- **274 Core tests pass**, including 23 added regression methods.
- **22 Runtime tests and 66 Python tests pass.**
- Localization audit passes: **599 catalog keys**, six permission keys, no errors.
- **xtool 1.21.0 / cached Apple SDK 27 Release build passes** in 92.97 seconds. The build helper validates the arm64 app/framework, bundle metadata, privacy manifests and localizations; 25 bundle files are recorded.
- The canonical Git source manifest contains 350 files, excluding historical `docs/results` archives. Source bytes are verified before and after each run.

Core/Runtime used pinned Linux image `sha256:4e2d836d1252e502c2c5ac92bc73e675d5d9a1780a82ad4c4127624e5792d756` with the cached pinned llama runtime. xtool used `ghcr.io/xtool-org/xtool:1.21.0@sha256:032d20a18c8015e49fa99fddfc4ba236795731fd8543d69971ff76d388e8430f`. The actual commands, exit codes, durations and raw-log digests are in [local execution](local/execution.json) and [xtool execution](local/xtool-execution.json). The [source manifest](source-manifest.json) pins the tested Git bytes. Raw logs accompany those receipts.

Fresh Apple simulator workflow results are linked in [PR #1](https://github.com/harbour-health/harbour/pull/1) after their completion. They exercise the hosted observation and rendered UI tests, which Linux and xtool cannot execute.

## Initial failure and correction

The [initial run](initial/execution.json) at `8e9def5` found four failed assertions in one new test; the other 273 Core tests passed. The test incorrectly called an exact retained complete quotation context unrelated. The correction adds explicit assertions proving that relationship and its valid acceptance, then separately proposes the standalone outside fact and asserts rejection. The existing unrelated combined-sentence negative remains. No production grounding rule was loosened in this correction. The original [failed log](initial/core.log) is preserved, alongside the final passing run.

## Scope

These are deterministic application regressions with controlled model proposals and task barriers. They do not measure cancellation latency inside a real decode, physical iPhone operation, or on-device Metal speed, memory or thermal behavior. xtool verifies cross-compilation and packaging; simulator tests provide separate app/UI evidence.

No model inference was performed in these local regression runs, and no weights were changed. The earlier 789 model-quality observations and 33-task diagnostic keep their original source bindings and scores. They have not been rerun or regraded as evidence of these fixes. Application fixes do not establish that the remaining model-quality gates pass.
