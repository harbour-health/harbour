# Evaluation

## Qwen3.5 2B local validation — October 12, 2026

The new default was exercised locally on Windows 11 with the same pinned llama.cpp `b10549` as the app, using the verified Unsloth Q4_K_M file, a 4,096-token context, 512-token batches, four CPU threads, greedy sampling, and the canonical non-thinking assistant prefix. The temporary runner used raw `/completion` requests, extracted Harbour's prompt templates and routing fixtures, and supplied the complete nineteen-tool GBNF grammar. It did not send records to a hosted inference service. See [runtime, model, and source provenance](results/qwen35-local/provenance.json).

- [English routing](results/qwen35-local/routing-results.json): 23/23 expected tool selections with valid empty-argument JSON. Median routing latency was 7.98 seconds, with prompt reuse disabled and the model already loaded, on an Intel Core i7-11700K. Download and model-load time are excluded. The observed [server peak working set](results/qwen35-local/memory.json) was about 2.46 GB, including server overhead. These are desktop CPU measurements, not iPhone performance measurements.
- [Additional checks](results/qwen35-local/extended-results.json): 12/14 structural and routing checks passed. Four of five French requests selected the expected tool; a French medication-scheduling request selected `reply`. A [retry using the exact saved medicine name](results/qwen35-local/canonical-name-retry.json) also selected `reply`. English/French prose and titles met the output bounds; those checks do not establish factual accuracy. The English visit produced the required grounded schema. The French visit returned highlight strings instead of quote objects, so Harbour's parser rejects that summary.
- Manual output review found an English reply incorrectly denying access to the supplied saved-record snapshot and a weak French sky-scattering explanation with unrelated health wording. Those outputs remain in the additional-check report.

The Core suite passed 87/87 tests and the portable runtime suite passed 16/16 tests in an isolated Swift container on the connected Linux host. The runtime check copies the portable format/grammar/envelope sources and extracts the production `ModelError`; it excludes the Apple-only llama binary target and native load test. Production Swift validators accepted all 23 English routes including actual reply prose, four of five French routes, all six bounded prose outputs, both titles, and the English visit; the French visit was rejected for its invalid schema. See [Swift validation scope and results](results/qwen35-local/swift-validation.json) and [production validator details](results/qwen35-local/swift-production-outputs.json). The [additional French reply](results/qwen35-local/french-negation-reply.json) also incorrectly denied access to supplied saved records. Full app, hosted-test, and UI-test sources passed Swift syntax parsing, and the subsequent xtool build compiled and linked the complete app as described below. Hosted preference and UI regressions are included in the change, but builds of the Xcode project, those native tests, Metal inference, physical iPhone memory/latency, and a complete French model matrix remain unverified on this Windows workspace.

Qwen3.5 is selected for fresh or unrecognized preferences. Saved Small, Balanced, and Automatic selections are retained; Automatic uses the new model only under the existing memory, power, and thermal criteria. These results justify that the integration loads and runs with the pinned runtime; they do not establish clinical answer accuracy or resolve the observed French failures.

## xtool build validation — October 12, 2026

The final Release arm64 iOS build passed through the [xtool workflow](xtool.md) on the connected Linux host with xtool 1.21.0, Swift 6.4, and the Xcode 27 SDK. The wrapper exited 0 after 53.48 seconds; Swift build reported 39.03 seconds. The resulting `xtool/Harbour.app` passed validation for its arm64 app executable and llama framework, generated metadata, both privacy manifests, and English/French main-bundle resources. See the [commands, provenance, and validation scope](results/xtool/validation.json).

`--prepare-only` had also passed on Windows, preparing the verified iPhone-only llama runtime and app metadata while retaining version `0.1`/build `1`, iOS 18 minimum, device families, both localizations, and all six permission descriptions. The full Xcode runtime was not modified. Root and runtime `swift package dump-package` checks passed with `HARBOUR_DEVICE_RUNTIME=1`, confirming the Harbour library dependencies and `llama` device binary target.

Local WSL startup failed with `HCS_E_HYPERV_NOT_INSTALLED`; the local Docker daemon was unavailable. Initially, verified xtool 1.21.0 on the connected Linux host reported `Not installed` for its Darwin SDK. The first direct arm64 build stopped before planning or compilation, and the wrapper exited with its missing-SDK diagnostic. The user then completed Apple Account authentication, and stable Xcode 27 downloaded from Apple and was transferred to the isolated Linux task cache with matching observed size and SHA-256. That checksum verifies local transfer integrity; it is not an Apple-published checksum.

SDK extraction/installation completed successfully in the isolated environment after 546 seconds, providing the iPhoneOS, iPhoneSimulator, and MacOSX 27.0 SDKs. The first native build compiled HarbourCore and HarbourRuntime but failed on `PhotosPicker`/`PhotosPickerItem` resolution because the SwiftBuild backend omitted the cross-import overlay flag. Adding `-Xfrontend -enable-cross-import-overlays` to the Harbour target resolved the failure, and the complete app build and bundle validation then passed.

Only a local ad-hoc entitlement signature was applied. No Apple account provisioning or development/distribution signing, device installation, or upload was performed. Native XCTest/XCUITest execution, on-device Metal inference, and actual iPhone memory/latency measurements remain unperformed. The existing Xcode/TestFlight workflow and earlier Windows model-inference measurements remain separate.

## What it is

Reproducible native checks for the fixed health harness, validated tool calls, saved records, SwiftUI flows, and real on-device-runtime inference. This is an engineering feasibility suite; it does not establish clinical benefit or complete symptom/interaction coverage.

## How it works

The core package currently has 87 XCTest methods, including care-data, import, notification-plan, voice-turn, and bounded French input regressions. The runtime package currently has seventeen regression tests, including tool/title grammar and input rejection; its original four checks cover complete outer JSON, nested arguments, string braces, escapes, and incomplete output. One method also evaluates 29 named fixture checks, covering each emergency checklist item, affirmative/negated phrases, unknown and duplicate ingredients, sourced pairs, combination ingredients, numeric extraction, invalid measurements, prompt-token escaping, aliases, and rejection of invented actions and empty replies. Additional tests verify original-text anchoring, pair symmetry, ambiguous medicine requests, Codable round trips, and confirmed-fact appointment notes.

Native UI tests cover manual symptom/reading entry and persistence across relaunch; topic hints preserving the draft; model selection/effort; real Qwen chat for a sourced interaction, heart rate, and symptom review; and medicine confirmation/export. The model test uses the actual download and native runtime, not a mock. UIKit exposes SwiftUI links differently from a web link: test them by accessibility identifier rather than assuming the `Link` query role.

The in-app Evaluation screen runs the fixed checks and twenty-three fictional routing prompts at one or all three effort settings for the selected model. Each run exports the expected/observed tool, raw output, pass/fail, model, effort, elapsed time, OS version, thermal state, and device memory. Conversational fixtures generate an ordinary-text reply after selecting `reply`; reports preserve both the routing JSON and generated prose. Timing includes a download and model load if required for the first case; later cases reuse the loaded model. Device memory is total physical memory, not peak application memory. Failure is recorded rather than discarded.

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

The simulator evaluation script requires an installed current Harbour app. It prints progress after each fixture. Reports are written atomically after each case, with `complete` marking a finished run; interrupted reports are retained as partial evidence. It runs Small, Balanced, and Qwen3.5 2B across Quick/Standard/Extended, downloads missing weights, and copies fictional-case reports into `docs/results/care-tools/` by default. Pass a second output-directory argument to preserve an experiment separately. The command can take several minutes. `--evaluate-model`, `--evaluate-all-efforts`, `--evaluate-balanced`, and `--evaluate-qwen35` are developer-only launch flags. These evaluations do not modify health records or send prompts externally.

## Observed results

On this Mac on 30 September 2026:

- Core at the September 30 baseline: 18 tests passed; all 29 fixed checks passed. Runtime: four complete-JSON regression tests passed.
- Native simulator and unsigned physical-iPhone targets compiled with Xcode 27.0 / iOS 27 SDK, iOS 18 deployment target.
- Runtime preparation succeeded from an empty output directory, including source checksum, simulator compilation, and XCFramework assembly.
- Final Mac native Metal probe: 12/12 routing cases passed on each model. Small first case 0.82 seconds, later cases 0.08–0.21 seconds; Balanced first case 1.13 seconds, later cases 0.24–0.32 seconds. These are Mac measurements, not phone benchmarks.
- Signed simulator UI: all six full-suite flows passed. The additional Health permission capture also passed in a subsequent two-flow run, reaching the native Allow button without granting access. The final delete-cancellation flow also passed and preserved the medicine list. Eight distinct UI test flows are covered across these runs. Xcode result-bundle cleanup can take substantially longer than the test run itself.
- Actual in-app Qwen Small download and sourced Advil/warfarin result were visually inspected. The completed model UI test confirmed a heart-rate reading and symptom record through native confirmation sheets.

### September 30 presentation update

The richer interface was checked with actual simulator interaction. `HarbourAppearanceTests` verified Light/Dark selection across relaunch, optional topics preserving a typed draft, record forms/review, export, and model controls. `HarbourRichResultsTests` (originally grouped with the appearance flow) exercised actual local Qwen tool calls for medicine lists, readings, and sourced interactions in both appearances. `HarbourDetailRefreshTests` captured emergency review, saved symptoms, blood pressure/temperature entry, unconfirmed medicines, and the keyboard. `HarbourNavigationTests` verified the dashboard medicine shortcut, native effort slider snapping, and System appearance with the simulator set to Dark.

All four presentation flows passed across the final capture/navigation runs. The signed simulator and unsigned iPhone targets compiled. Original vector artwork, light/dark screenshots, and the structured result displays were visually inspected. The inference runtime, grounding checks, and clinical rules were not changed, so the earlier 72-case routing matrix remains the model evidence rather than a newly rerun result.

### September 30 dashboard, chat titles, and app lock

The final `HarbourDashboardTests` flow passed: equal shortcut dimensions, visible content margins, the hidden native tab bar, a usable composer above the icon dock, an actual local-model title, title persistence after relaunch, and resetting to New chat. `HarbourNavigationTests` subsequently passed with System appearance following the simulator's Dark setting. Decorative artwork has intentionally cropped bounds; margin assertions inspect visible headings rather than the artwork's larger accessibility rectangle.

`HarbourLockTests` passed with the four-digit keypad: four masked slots without a text field, confirmation mismatch, deletion, automatic verification, wrong/correct credentials, locking with an open editor on background, five-attempt retry delay surviving relaunch, and current-PIN verification before disabling the lock. The PIN flow passed in its original capture bundle; that bundle's separate dashboard assertion was corrected and the final dashboard flow passed separately.

The refreshed appearance and entry flows passed before the main capture run was interrupted during a chat animation wait. The subsequent completed chat run passed real medicine, reading, and interaction tool results in both appearances. Repeating illustrations now stop when their views disappear, and tests wait for both tool execution and title generation before starting another chat.

The completed Evaluation screen showed 36/36 selected-model routing cases across three efforts. This is a new UI result capture, not a rerun of both models' earlier 72-case matrix. A separate fresh simulator flow passed genuine download progress/cancellation, the unavailable Face ID error without enabling a lock, native Health permission denial and its reminder, and opening/cancelling the record import picker. That fixture simulator was deleted after capture.

The final signed simulator and unsigned physical-iPhone builds compiled. The gallery contains 63 genuine native captures, including the new PIN screens. Physical biometric matching and device-passcode fallback were not exercised.

### Later September 30 layout refinement

Records now has a category browser and dedicated list destinations. The refreshed appearance, entry/review, and navigation flows passed, including category changes via the native back button, Add record sheets, and the dashboard's direct Medicines shortcut. The final dashboard flow also passed equal shortcut dimensions, content margins, a two-line draft area with a larger distance to its controls, model-selector access above the dock, and actual local chat-title persistence/reset. PIN lifecycle and retry checks passed again with the neutral palette.

An initial capture run revealed that a parent composer accessibility identifier replaced its children's identifiers; removing that parent identifier restored independently addressable controls. A subsequent size assertion incorrectly expected the inner accessibility text view to include its containing writing area's reserved space. The final check measures its two lines and the distance to the model control separately. These failures were resolved rather than counted as successful runs.

The final rich-result flow passed actual local medicine-list, reading-list, and sourced interaction requests in both appearances. The updated dashboard, category browser, composer, keyboard, and entry screens were visually reviewed. Six distinct updated UI flows passed across the corrected capture and final runs. The unsigned iPhone target compiled. Earlier model-routing reports remain unchanged; this visual refinement does not add clinical coverage or physical-device performance evidence.

### Floating navigation and inline capture

The dock now overlays the tab content rather than occupying an opaque full-width row. The refreshed appearance, dashboard, entry/review, and real local-model chat flows passed. `HarbourFloatingDockTests` also passed lower-action reachability, composer/dock separation, keyboard-driven hiding/restoration, and adding a reading after scrolling to the end of its list. Its supplementary flow captured the unavailable Face ID error and native import picker. The current unsigned iPhone target compiled.

Material is confined to the capsule. Each scrolling destination consumes the bottom clearance so its last controls can move above the overlay; Chat reserves it beneath the fixed composer. Actual Today and reading-list captures were inspected to confirm content is visible around and behind the dock. Captures are embedded directly for mobile review, since the localhost gallery is limited to the development computer.

### Model matrix and prompt experiments

The first full simulator matrix passed 33/36 cases on each model. All six failures were the medicine-list request being misrouted to readings and rejected by validation. The original reports are preserved as [Small baseline](results/baseline-small.json) and [Balanced baseline](results/baseline-balanced.json). A broader prompt rewrite regressed to 7/12 on the Mac Small probe and was discarded. Separating only the medicine/reading list descriptions improved tool choice, then exposed an early-generation-stop bug for nested argument objects. The corrected runtime waits for the completed outer JSON object; four independent regression tests cover it.

The September 30 simulator reports are [Small](results/small.json) and [Balanced](results/balanced.json), with twelve prompts at each of Quick/Standard/Extended. Do not infer clinical correctness from tool-selection accuracy. These twelve fixtures informed the prompt repair, so they are regression cases rather than a held-out estimate of generalization.


| Model | Routing cases | Quick median | Standard median | Extended median |
| --- | ---: | ---: | ---: | ---: |
| Qwen Small | 36/36 | 4.51 s | 3.51 s | 2.56 s |
| Qwen Balanced | 36/36 | 14.88 s | 14.49 s | 14.87 s |

All 72 September 30 simulator cases passed. These are CPU simulator measurements on this Mac, not measurements from an iPhone. Loading is included in each model’s first case; previously downloaded files were reused. Effort controls an output cap, so latency differences in this small sample do not establish a causal speed or reasoning-quality ranking. Mac workload and cache state also affect timing.

## October 1 care and voice verification

The portable package passed 54/54 tests. Coverage includes medicine-ID remapping, conflict rejection before import writes, historical dose provenance after schedule edits/removal, stale visit reminders, DST-aware schedules, literal OCR instructions, and speech-turn finalization/cancellation. The native service target additionally checks actual protected persistence, Vision OCR, notification reconciliation, and speech synthesis. A prompt experiment restricting descriptions to the allowed tools regressed to 11/19 Small/Standard cases and was discarded. Its raw outputs are preserved in [the experiment report](results/care-prompt-experiments/filtered-small-standard.json). A subsequent exact tool-output grammar prevents malformed envelopes and disallowed names; it does not prove correct tool selection. `harbour-care-final-source.xcresult` passed all 13 native service tests and all three care UI flows. These cover protected persistence and corrupt-file preservation; atomic dose/schedule changes; historical dose export/import; duplicate medicine/name-bound rejection before writing; stale visit sources; real Vision OCR; native notification privacy, IDs and cancellation; latest-snapshot reconciliation under a suspended add; actual speech-synthesis completion/cancellation; and spoken structured responses. No native service test skipped in this run.

The native chat flow completed all seven new tools with the actual local Small model and shared review editors. A new prefilled reminder was verified unsavable until its date was confirmed. The manual flow saved and reopened OCR-derived medicine data, a schedule, a dose, a reminder, a searchable history entry, and an appointment question. The matching light/dark capture flow passed. Earlier failures from an offscreen lazy Form control were corrected by waiting for the pinned editor toolbar and scrolling to the control; the completed flow supplies the final evidence.

`harbour-care-large-text.xcresult` passed the largest accessibility text size for the dashboard, reading entry/save, and topic selection. Captures 116 and 84 were inspected; the simulator was restored to its normal text size. The previous notification/voice-availability UI flow passed with Notify me asserted enabled, and the native service run subsequently verified real pending notifications. The simulator lacks the required on-device speech recognizer; capture 114 records that error rather than successful ASR.

### Care routing baseline

The first grammar-only care matrix passed Small 57/57 and Balanced 54/57. Balanced chose `log_reading` for “Show my readings” at every effort; validation rejected the missing measurement. The complete raw reports remain in [Small baseline](results/care-tools-baseline-grammar/small.json) and [Balanced baseline](results/care-tools-baseline-grammar/balanced.json). The final routing path filters available tools through the existing original-text validator before generation, so an invalid measurement-writing tool is unavailable for that list request. The selected tool is validated again after generation.

### Final care routing matrix

The final routing-source run passed **114/114** cases: nineteen fictional prompts at Quick, Standard, and Extended on each model. Complete raw outputs and timings are preserved in [Small](results/care-tools/small.json) and [Balanced](results/care-tools/balanced.json).

| Model | Routing cases | Quick median | Standard median | Extended median |
| --- | ---: | ---: | ---: | ---: |
| Qwen Small | 57/57 | 3.60 s | 3.57 s | 3.09 s |
| Qwen Balanced | 57/57 | 25.13 s | 25.01 s | 20.71 s |

The run reused the installed verified weights and serialized the two models on the iOS simulator. These are CPU simulator timings on the development Mac, including model loading in the first case; they are not iPhone benchmarks. Host workload and cache state affect timing. Effort sets an output cap, and this fixed JSON is short enough for every cap; the timings do not establish a reasoning-quality or causal speed ranking. The fixtures informed the repair, so the result is regression evidence rather than a held-out reliability estimate or clinical validation.

## Outstanding evidence

Physical-device signing/install, Face ID matching and device-passcode fallback, actual HealthKit populated-store and revocation cases, on-device speech accuracy and permissions, offline relaunch, voice/inference cancellation on physical hardware, low-storage behaviour, thermal/battery/peak-memory measurements, iPad, VoiceOver, large text across every screen, and legacy six-digit credential migration remain to be tested. Native Health denial/reminder and PIN background locking were exercised on the simulator. Small samples of correct tool choices do not establish broad LLM reliability. Medical source review and a maintained interaction dataset remain research requirements before any real-user claim.

## Dependencies

XCTest, Xcode/xcrun simctl, the core fixture suite, the native inference package, Qwen weights, and `scripts/prepare-runtime.sh`. No external inference or evaluation service is used.

## Doctor visit verification

`swift test --package-path HarbourCore` includes source-quote validation, invented dose/name rejection, speculative/negated changes, omitted-negation attacks, model-omitted follow-up recovery, stale medicine baselines, conflicting/repeated application, transcript edits, Codable persistence, and bounded chunking. The doctor-visit update brought the core suite to 26 tests; care/voice reached 54, and French coverage brings the current package to 70.

`HarbourVisitTests` exercises the native recorder's start/pause/resume/finish and audio playback/persistence; real Qwen extraction from typed fictional visit notes; medicine selection/acknowledgement, cancel, atomic save, and relaunch; sharing; and light/dark captures of the four main destinations and visit screens. A focused audio-ownership regression switches to Chat and back during recording and verifies competing dictation is disabled. The QA simulator's native AAC recordings can be opened with AVAudioFile. It lacks on-device English speech support, and the recorder correctly reports audio-only capture. These checks do not establish medical speech accuracy or long appointment endurance.

The final visit suite passed all three flows in `harbour-visits-release-check.xcresult`; `harbour-visits-audio-ownership.xcresult` passed the focused audio regression after the shared-session cleanup change. An unsigned generic iPhone build also succeeded; it verifies compilation rather than actual device behaviour.

The first microphone attempt stalled while using the async permission API. Callback-based permission waiters fixed the simulator path and allow explicit cancellation with generation invalidation. Later completed native flows supersede those failed attempts. Do not treat the early incomplete result bundles as final evidence. Use `-collect-test-diagnostics never` for targeted simulator runs when verbose diagnostic collection stalls after a failure; preserve the actual test outcomes.

Remaining device acceptance: 30–90-minute sessions, iOS 18 legacy rollover and saved-audio chunk retry, iOS 26 live/file analysis with downloaded/installed speech assets, noise and overlapping speakers, actual medicine/dose transcription errors, phone calls, storage exhaustion, abrupt process death during AAC writing, screen lock/background protection, and clinically reviewed extraction recall/precision. Speaker attribution and clinical correctness are not established by source quotes.

## Floating drawer verification

The iPhone 17 Pro / iOS 26.5 simulator completed `HarbourDrawerTests` and `HarbourDrawerDetailTests` in `harbour-drawers-complete.xcresult`. These exercise compact panel bounds, Settings destination resizing, nested PIN entry, keyboard entry/save, medicine confirmation gating, topics, and draft retention/save after rotation. A test-only bounds probe measures the actual panel; a scroll container's accessibility frame can include content outside its visible outline.

The existing PIN lifecycle/throttle test passed in `harbour-drawers-final.xcresult`, including background locking while a symptom drawer was open. The existing real local-model visit summary/medicine-confirmation workflow passed in `harbour-drawers-ready.xcresult`. Other flows in those two intermediate bundles failed during layout refinement; only the named completed flows are cited as evidence. Finished drawer runs and exported manifest entries supersede the earlier failing captures.

Older iOS compatibility presentation is compiled and its panel is exercised in landscape on iOS 26.5. The subsequent small-phone flow also verified floating reading entry/save on an iPhone SE (3rd generation) simulator running iOS 18.6. Other older-device layouts, exact hardware corner radii, VoiceOver navigation, and physical-device rendering remain unverified.

The subsequent `harbour-drawers-themes.xcresult` completed both the paired-theme drawer flow and remaining-drawer capture flow. Visual review caught and fixed stale light appearance in a dark drawer by applying the appearance preference directly to each presentation. `harbour-drawers-accessibility-final.xcresult` passed reading entry/save and topic selection at the largest accessibility text size, with the simulator restored to its original size afterward. The test scrolls the Records category above the floating dock before selecting it. This covers those two workflows at that size, rather than all screens or VoiceOver. An unsigned physical-iPhone build succeeded in `harbour-drawers-device-complete.log`.

`harbour-drawers-gallery-final.xcresult` passed the remaining-drawer flow after increasing Settings to 640 points so its final Evaluation row is fully visible. The complete README gallery was checked against the screenshot directory: all 86 numbered PNGs are embedded exactly once in the generated gallery, and every image path exists.

## Navigation and action consistency

`harbour-streamline-signed.xcresult` passed all four selected flows: paired appearance persistence, drawer navigation/confirmation, main navigation with chat-draft retention and new-visit cancellation/save/relaunch, and actual local-model visit extraction with confirmed medicine updates. Cancelling new visit notes left the history row count unchanged; saving opened the new detail and its transcript survived relaunch. Copy feedback and upper-right Done placement were verified in the generated appointment note.

`harbour-streamline-gallery.xcresult` passed the two final capture flows on iOS 26.5, including six actual local-model requests for medicine lists, reading lists, and sourced interaction results across Light/Dark appearances. `harbour-streamline-compact.xcresult` passed composer and reading-entry checks on an iPhone SE (3rd generation), iOS 18.6. It used Balanced/Extended in the 375-point composer, verified separate hittable controls without overlap, and saved a reading through the detached compatibility drawer. No inference request or model download was required on that fixture phone.

An initial run built with `CODE_SIGNING_ALLOWED=NO` could not read the simulator's Keychain settings and correctly displayed the locked error state. Those four failed launches did not exercise the UI. Rebuilding with normal simulator code signing restored protected-storage access without resetting the Keychain; the signed runs above provide the completed evidence. Use an unsigned build only for generic-device compilation, rather than simulator app-lock acceptance.

Final visual review found the date label wrapping on the small phone. After shortening it to Date, `harbour-streamline-compact-final.xcresult` and `harbour-streamline-drawers-final.xcresult` passed the focused small-phone and paired-drawer flows. The complete README gallery was verified against all 90 numbered PNGs with no missing or duplicate entries.

## Final presentation gate

`harbour-care-stable-paired.xcresult` passed the settled main-screen check in both appearances, including all four dock targets and the last empty-chat starter above the composer. It supersedes an initial capture with a transient missing glyph. The later layout correction changes only decorative empty-state geometry and accessibility identifiers; the routing prompt, eligibility, validation, runtime and fixtures measured in the final model matrix remain unchanged. The complete README gallery contains all 115 numbered PNGs exactly once.

The final unsigned generic-iPhone build succeeded in `harbour-care-device-paired.log`. This verifies the device compilation path, including Metal runtime linkage, without claiming a signed physical-device install or microphone test.

## Uniform drawer corners and dock symbols

`harbour-dock-selection-final.xcresult` passed the paired main-screen test with dim inactive outlines and a white filled active symbol. All four destinations remained hittable in both appearances. Light Today and dark Chat originals were visually checked. An initial compilation attempt was corrected before this successful run; no captures from the failed build were exported. The recording badge state was not exercised by this main-screen flow.

`harbour-navigation-symbols.xcresult` then passed the same paired main-screen flow with the final home, conversation, medical-clipboard, and doctor-meeting symbols. Refreshed native screenshots were inspected in both appearances. The owned build/test runner exited and no simulator remained booted afterward.

The later `harbour-filled-dock.xcresult` passed the existing paired main-screen test after switching all four navigation symbols to filled variants. It captured all roots in Light and Dark and verified each dock target remained hittable. No navigation or drawer behavior changed in this update.

`harbour-uniform-corners.xcresult` passed both selected native UI tests on the iPhone 17 Pro / iOS 26.5 simulator: the paired-theme drawer flow and settled main-screen flow. These exercised Settings resizing, PIN cancellation, reading keyboard/save, medicine confirmation, topics, models, and all four dock destinations in Light and Dark. Genuine refreshed Appearance, Models, and PIN captures were inspected for matching top/bottom curves; Today and Chat captures were inspected for the new outline symbols. The shared radius also applies to the older-system compatibility panel, whose rendering was not recaptured in this run. The README still contains all 115 numbered images exactly once; historical captures retain their producing-run provenance.

## Canadian French verification

The final Swift package runs passed 70 Core tests and 12 Runtime tests. French fixtures cover catalog aliases, emergency negation and later affirmative cues, comma-decimal readings, original-text preservation, and bounded care/visit intent validation. The title grammar tests cover its exact JSON key and 60-character bound.

`harbour-french-release.xcresult` passed five hosted localization tests and three UI flows: French draft workflows, four real Small/Standard French chat requests, and paired English main destinations. The earlier English hosted run passed all 13 native care-service tests plus five localization tests. Localized tables contain 522 display keys and five permission keys per language. Packaged-resource, formatting, canonical-data, and user-text-preservation checks passed.

The actual French requests displayed saved medicines and readings, opened symptom and reminder review drafts, and generated a French chat title distinct from the source-message fallback. Both mutation reviews were cancelled and saved record counts remained unchanged. Earlier title attempts produced mixed-language text or copied an example; French prompt wording and the bounded JSON grammar corrected those failures. This is a small integration sample, not a full French model matrix or clinical reliability result. French on-device speech recognition, recognition accuracy, and physical-device behavior remain unverified.

Dock screenshot inspection caught missing glyphs despite passing accessibility reachability assertions. Those captures are not visual acceptance evidence. The final dock renders symbols separately from its accessible buttons and remains mounted during keyboard transitions; its producing run and inspected originals are recorded in the visual review.

`harbour-raster-dock.xcresult` passed both focused UI flows after the final native dock change: four actual French model requests and all eight English main-page captures. The final run used the cached Small model, with no model downloads. The exported full-resolution dock regions were checked separately from accessibility targets.

## Light navigation and medicine-review capture refresh

`harbour-light-dock.xcresult` passed the paired main-screen flow on Harbour QA, covering all four destinations in Light and Dark, dock reachability, and empty-chat starter placement. The eight exported roots show the adaptive dock: pale grey/white with dark active icons in Light, and the existing charcoal/black with white active icons in Dark. This change uses the current SwiftUI color scheme when resolving native colors, including the in-app appearance override.

The first medicine-review capture attempt used Small/Standard and produced the source sentence as a note without a medicine proposal. Its UI test failed while waiting for the review action; it did not exercise the visit-review drawer and is not a successful extraction result. The second attempt with cached Balanced/Extended returned an unusable summary and also failed to reach review. Neither result is successful extraction evidence. The final geometry flow uses a Debug-only fixed fictional review, validated through `VisitReview.parse`, without model inference or downloads. Its temporary visit is identified by the fixture title; medicine proposals are cancelled rather than applied. This UI check does not address the observed extraction limitations.

`harbour-medicine-drawer-fixture.xcresult` passed the focused medicine editor/review flow in both themes. It verified disabled Save before acknowledgement, enabled Save after selection/acknowledgement, bottom separation from the screen, cancellation, and removal of its fixture visit. Captures 7, 50, 71, and 142 were exported and visually inspected. The visit summary in 71/142 is a fixed fictional fixture, not model-extraction evidence. The complete README gallery now contains all 141 numbered captures.

## October 1 ordinary conversation and unfiltered tools

The keyword intent filter and fixed capabilities reply were removed. Every routing request exposes the complete catalog of nineteen entries, including the normal reply option. `reply` then runs ordinary text generation with conversation history. The final Core run passed 87 tests and Runtime passed 14 tests. A Foundation JSON parsing edge case accepting a trailing comma was caught and corrected before the passing Core run.

Fresh Mac Metal probes with the full catalog passed 15/23 cases on Small and 22/23 on Balanced. Both use the same final prompt, 4,096-token context, 160-token routing budget, and 512-token reply budget. [Small output](results/freeform-chat/small.json) and [Balanced output](results/freeform-chat/balanced.json) retain failures, actual replies, and elapsed time. Balanced misselected medicine scheduling for a reminder request; the missing named medicine prevents execution and the app uses normal conversation instead. Small made additional routing errors, including selecting reset for a negated request. The subsequent source guard rejects that proposal; the app uses normal conversation instead. No change is committed. These checks do not establish clinical answer accuracy, phone speed, French conversational quality, or a complete model/effort matrix.

The original constrained routing results above are historical evidence for the older filter. They are not accuracy results for the new agent. Generated explanation content is not checked for medical correctness by the JSON grammar or fact validator.

`harbour-conversation-voice-final.xcresult` passed both native UI tests. Real cached Balanced inference answered an arithmetic question, recalled the user's favourite colour from the prior message, and opened a heart-rate review with value 72; the review was cancelled. English and French voice pages exposed Automatic, speed, and preview controls; each preview entered Speaking and could be stopped. The first run failed a 90-second inference timeout and found preview controls below the long voice list. Moving those controls above the list and allowing up to 240 seconds per simulator operation resolved the test failures. The final combined flow took approximately seven minutes on the CPU simulator, so this is functional evidence, not a claim of fast phone inference. Physical-device voice naturalness and real speech-recognition accuracy remain unverified.

The optional post-test diagnostic collector delayed completion after both UI flows had passed. Only that owned `simctl diagnose` process was stopped; Xcode then finalized `harbour-conversation-voice-final.xcresult` and returned `TEST SUCCEEDED`. The screenshots were exported and visually reviewed from that completed bundle. Voice selection is functional on the simulator's Standard-only inventory; more natural Premium/Enhanced playback still requires those assets on the phone.
