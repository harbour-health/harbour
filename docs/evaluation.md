# Evaluation

## What it is

Reproducible native checks for the fixed health harness, validated tool calls, saved records, SwiftUI flows, and real on-device-runtime inference. This is an engineering feasibility suite; it does not establish clinical benefit or complete symptom/interaction coverage.

## How it works

The core package has 18 XCTest methods. The runtime package adds four regression tests for complete outer JSON, nested arguments, string braces, escapes, and incomplete output. One method also evaluates 29 named fixture checks, covering each emergency checklist item, affirmative/negated phrases, unknown and duplicate ingredients, sourced pairs, combination ingredients, numeric extraction, invalid measurements, prompt-token escaping, aliases, and rejection of invented actions or clinical replies. Additional tests verify original-text anchoring, pair symmetry, ambiguous medicine requests, Codable round trips, and confirmed-fact appointment notes.

Native UI tests cover manual symptom/reading entry and persistence across relaunch; topic hints preserving the draft; model selection/effort; real Qwen chat for a sourced interaction, heart rate, and symptom review; and medicine confirmation/export. The model test uses the actual download and native runtime, not a mock. UIKit exposes SwiftUI links differently from a web link: test them by accessibility identifier rather than assuming the `Link` query role.

The in-app Evaluation screen runs the fixed checks and twelve fictional routing prompts at one or all three effort settings for the selected model. Each run exports the expected/observed tool, raw output, pass/fail, model, effort, elapsed time, OS version, thermal state, and device memory. Timing includes a download and model load if required for the first case; later cases reuse the loaded model. Device memory is total physical memory, not peak application memory. Failure is recorded rather than discarded.

## How to change it

Raw model output is retained even when parsing or original-message validation rejects it. This distinguishes a routing failure from an accepted action; rejected calls do not modify records.

Add cases in `HarbourCore/Evaluation.swift` and targeted invariants in `HarbourCoreTests.swift`. New clinical rules need independent source review and labelled reference cases; agreement with the implementation itself is not enough. Keep model prompts fictional and repeat the same fixtures across models, effort settings, and devices. Add model aliases only for known equivalent tools and retain original-message validation.

## Configuration

```sh
swift test --package-path HarbourCore
xcodebuild -project Harbour.xcodeproj -scheme Harbour \
  -destination 'platform=iOS Simulator,name=Harbour QA' test
bash scripts/evaluate-simulator.sh SIMULATOR_UUID
```

The simulator evaluation script requires an installed current Harbour app. It prints progress after each fixture. Reports are written atomically after each case, with `complete` marking a finished run; interrupted reports are retained as partial evidence. It runs Small and Balanced across Quick/Standard/Extended (72 total routing cases), downloads missing weights, and copies fictional-case reports into `docs/results/`. The command can take several minutes. `--evaluate-model`, `--evaluate-all-efforts`, and `--evaluate-balanced` are developer-only launch flags. These evaluations do not modify health records or send prompts externally.

## Observed results

On this Mac on 30 September 2026:

- Core: 18 tests passed; all 29 fixed checks passed. Runtime: four complete-JSON regression tests passed.
- Native simulator and unsigned physical-iPhone targets compiled with Xcode 27.0 / iOS 27 SDK, iOS 18 deployment target.
- Runtime preparation succeeded from an empty output directory, including source checksum, simulator compilation, and XCFramework assembly.
- Final Mac native Metal probe: 12/12 routing cases passed on each model. Small first case 0.82 seconds, later cases 0.08–0.21 seconds; Balanced first case 1.13 seconds, later cases 0.24–0.32 seconds. These are Mac measurements, not phone benchmarks.
- Signed simulator UI: all six full-suite flows passed. The additional Health permission capture also passed in a subsequent two-flow run, reaching the native Allow button without granting access. The final delete-cancellation flow also passed and preserved the medicine list. Eight distinct UI test flows are covered across these runs. Xcode result-bundle cleanup can take substantially longer than the test run itself.
- Actual in-app Qwen Small download and sourced Advil/warfarin result were visually inspected. The completed model UI test confirmed a heart-rate reading and symptom record through native confirmation sheets.

### September 30 presentation update

The richer interface was checked with actual simulator interaction. `HarbourAppearanceTests` verified Light/Dark selection across relaunch, optional topics preserving a typed draft, record forms/review, export, and model controls. `HarbourRichResultsTests` (originally grouped with the appearance flow) exercised actual local Qwen tool calls for medicine lists, readings, and sourced interactions in both appearances. `HarbourDetailRefreshTests` captured emergency review, saved symptoms, blood pressure/temperature entry, unconfirmed medicines, and the keyboard. `HarbourNavigationTests` verified the dashboard medicine shortcut, native effort slider snapping, and System appearance with the simulator set to Dark.

All four presentation flows passed across the final capture/navigation runs. The signed simulator and unsigned iPhone targets compiled. Original vector artwork, light/dark screenshots, and the structured result displays were visually inspected. The inference runtime, grounding checks, and clinical rules were not changed, so the earlier 72-case routing matrix remains the model evidence rather than a newly rerun result.

### Model matrix and prompt experiments

The first full simulator matrix passed 33/36 cases on each model. All six failures were the medicine-list request being misrouted to readings and rejected by validation. The original reports are preserved as [Small baseline](results/baseline-small.json) and [Balanced baseline](results/baseline-balanced.json). A broader prompt rewrite regressed to 7/12 on the Mac Small probe and was discarded. Separating only the medicine/reading list descriptions improved tool choice, then exposed an early-generation-stop bug for nested argument objects. The corrected runtime waits for the completed outer JSON object; four independent regression tests cover it.

The current simulator reports are [Small](results/small.json) and [Balanced](results/balanced.json), with twelve prompts at each of Quick/Standard/Extended. Do not infer clinical correctness from tool-selection accuracy. These twelve fixtures informed the prompt repair, so they are regression cases rather than a held-out estimate of generalization.


| Model | Routing cases | Quick median | Standard median | Extended median |
| --- | ---: | ---: | ---: | ---: |
| Qwen Small | 36/36 | 4.51 s | 3.51 s | 2.56 s |
| Qwen Balanced | 36/36 | 14.88 s | 14.49 s | 14.87 s |

All 72 final simulator cases passed. These are CPU simulator measurements on this Mac, not measurements from an iPhone. Loading is included in each model’s first case; previously downloaded files were reused. Effort controls an output cap, so latency differences in this small sample do not establish a causal speed or reasoning-quality ranking. Mac workload and cache state also affect timing.

## Outstanding evidence

Physical-device signing/install, actual HealthKit populated-store and denial/revocation cases, on-device speech accuracy and permissions, offline relaunch, foreground/background cancellation, low-storage behaviour, thermal/battery/peak-memory measurements, iPad, VoiceOver, and largest text sizes remain to be tested. Small samples of correct tool choices do not establish broad LLM reliability. Medical source review and a maintained interaction dataset remain research requirements before any real-user claim.

## Dependencies

XCTest, Xcode/xcrun simctl, the core fixture suite, the native inference package, Qwen weights, and `scripts/prepare-runtime.sh`. No external inference or evaluation service is used.
