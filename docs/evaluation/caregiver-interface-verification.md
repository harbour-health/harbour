# Simple and caregiver interface verification

This records the verification scope for [issue #11](https://github.com/harbour-health/harbour/issues/11). Simple and Caregiver show one shared person's local health records. The interface picker now explains that changing the layout does not select another person. No participant information, additional patient profile or account is needed for these checks.

## Automated checks

Local source checks passed: `python -X utf8 scripts/audit-localization.py` checked 752 interface keys and six permission keys in each language, and `git diff --check` reported no whitespace errors. All seven interface methods passed together at stacked head `46de039`. Subsequent navigation corrections passed the focused checks at `4351e0a` and `df38e19`, as recorded below. Physical-iPhone VoiceOver acceptance remains pending.

`HarbourUITests/SimpleInterfaceUITests.swift` exercises the actual native screens without sending a message to a model, downloading speech assets or recording audio.

| Test | Assertions | Recorded native outcome |
| --- | --- | --- |
| `testSimpleHomeHelpAndCaregiverSwitch` | Simple actions, guide and chat controls; switch to detailed Caregiver navigation. | Passed. |
| `testSimpleLargestTextKeepsPrimaryActionsReachable` | Largest accessibility text in English and Canadian French; scroll to Simple actions, open the guide, reach the interface choices and Caregiver record categories. | Passed. |
| `testFrenchSimpleHome` | Translated Simple home and guide labels. | Passed. |
| `testUnsentChatDraftSurvivesHomeAndBothModeSwitches` | Type a unique unsent message; return Home; switch Simple → Caregiver → Simple; reopen Chat and check the unchanged draft each time. | Passed. |
| `testModeSelectionPersistsAcrossRelaunchWithoutLaunchSeed` | Select each mode in Settings; terminate and relaunch with the initial-mode environment seed removed; check the retained layout and selected button. | Passed. |
| `testConfirmedRecordSurvivesModeSwitchesAndRelaunch` | Cancel a fictional appointment before date confirmation; verify no record exists; explicitly confirm and save it; check that the same underlying UUID and label survive both layout switches and relaunch. | Passed. |
| `testInterfaceAccessibilityMetadataInBothLanguages` | Exact translated shared-record notice, mode labels/descriptions and selected state; accessibility audits for sufficient element descriptions and traits on both home layouts and the picker in both selected states. | Passed. |

All tabled results refer to [run 44295153556](https://github.com/harbour-health/harbour/actions/runs/44295153556), stacked head `46de039`; the [raw excerpt](caregiver-interface/native-46de039-stacked.txt) retains all seven passes and the separate older-smoke failures. This does not label that entire workflow as passing.

The mode-persistence test removes `HARBOUR_INITIAL_INTERFACE` before relaunch because `HarbourApp.init()` seeds the preference whenever that variable is supplied. It does not call `launchCaregiver()` to restore a layout, which would overwrite the preference under test. Saved-record checks use a unique fictional appointment on an isolated QA simulator. An unsent draft is checked across navigation and layout switches, not across process termination.

The first [native run](https://github.com/harbour-health/harbour/actions/runs/44278619602) compiled successfully and reported 45 hosted tests, six explicit asset/platform skips and zero failures. Its interface suite passed French home and failed six checks: the combined mode elements lacked a Button trait, and the saved-record test used a StaticText locator for a combined Button row. Those issues were corrected. Older smoke failures also exposed stale navigation/summary queries and a separate real recording-start format error; neither was counted as a passing interface result.

The separate [AAC diagnostic job](https://github.com/harbour-health/harbour/actions/runs/44287250160) reproduced that same `560226676` error while creating a writer with the old fixed 32,000-bit/s setting for 44.1-kHz and 48-kHz stereo input. Platform-default AAC settings successfully wrote, closed and decoded all six tested mono/stereo formats at 16, 44.1 and 48 kHz. The [raw report](visit-audio/aac-writer-probe-649fa27.json) records the runner OS and PR merge commit; the branch head was `649fa27`. This uses generated silence, so it is codec evidence only, not human speech or microphone evidence.

[Run 44287840773](https://github.com/harbour-health/harbour/actions/runs/44287840773), head `b911b25`, used Xcode 26.6 (17F113) and an iPhone 17 Pro simulator on iOS 26.4.1. All six actual `VisitAudioWriter` round trips and the recorder/background-return UI test passed. The hosted suite reported 51 tests, six skips and zero failures. The UI suite reported 25 tests and four failures: the saved-record query above, a lazy Evaluation row query, and missing Records/Visits root toolbars after returning from a destination. The [log excerpt](caregiver-interface/native-b911b25.txt) retains those failures alongside the passed interface and audio checks. The corrections were subsequently tested below; that full workflow failed.

Manual CI dispatch accepts `native_scope=interface`, `navigation` or `actions` for focused diagnosis. Push and PR runs retain the full smoke selection. The navigation group includes the saved-record test and the three failing older smoke methods; `actions` isolates the remaining main-actions method. Neither suppresses assertions.

The [focused navigation run 44294966489](https://github.com/harbour-health/harbour/actions/runs/44294966489), head `5163bad`, passed the saved-record round trip and the full Appearance/Evaluation method. The main-actions method passed the initial Records root-action checks, then failed while checking Done before the standalone Models sheet became hittable. The Visits method returned to the visible root content, but its navigation bar and Add notes were absent in the exported hierarchy. This focused run therefore reported four UI tests and two failures. Explicit Visits navigation-bar visibility, a scoped wait for the Models sheet and active-Back selection in the shared Records helper were added for the next run.

[Run 44295153556](https://github.com/harbour-health/harbour/actions/runs/44295153556), stacked head `46de039`, passed all seven interface methods together, both medication-search methods and the hosted suite (51 tests, six skips, zero failures). Its full UI selection still reported two failures in the older main-actions and Visits methods. [Focused run 44299354633](https://github.com/harbour-health/harbour/actions/runs/44299354633), head `4351e0a`, then passed Appearance, the complete Visits method and the saved-record round trip. Only the main-actions method failed: its later Records-root check still found no visible navigation bar after returning from Medications. The earlier successful initial Records checks did not establish that this later return path worked.

The final [actions workflow 44303650184](https://github.com/harbour-health/harbour/actions/runs/44303650184), head `df38e19`, completed successfully after explicit Records navigation-bar visibility and a bounded wait for the active bar were added. Its main-actions method passed in 396.348 seconds, including root Settings restoration across both themes, Models-sheet draft retention, and visit-note save/cancel/relaunch checks. The [raw excerpt](caregiver-interface/native-df38e19-actions.txt) records the exact scope and success. This is a passing focused workflow; full push/PR smoke runs remain separate. Focused manual jobs have distinct check names so they cannot be mistaken for the full smoke check.

Run the suite on an isolated iPhone simulator with the app's prepared native dependencies:

```sh
xcodebuild test -project Harbour.xcodeproj -scheme Harbour \
  -destination 'platform=iOS Simulator,id=SIMULATOR-UDID' \
  -parallel-testing-enabled NO \
  -resultBundlePath build/Harbour-Interface.xcresult \
  -only-testing:HarbourUITests/SimpleInterfaceUITests \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

When repeating the suite, record its commit, simulator model, iOS version, completed outcomes and result-bundle/artifact link. The CI workflow selects this suite and uploads the native result bundle and attachments. Test definitions and screenshots alone do not establish a passing result.

## Accessibility scope

The automated audit requests only `.sufficientElementDescription` and `.trait`. It checks accessibility metadata on the current surface; it is not a full contrast, text-clipping or every-screen accessibility audit. Large-text reachability is tested separately. There is no issue-suppression handler that converts reported audit problems into a pass.

Apple's [accessibility audit API](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/performaccessibilityaudit%28for%3A_%3A%29) supports these native checks. Apple's [accessibility testing guidance](https://developer.apple.com/documentation/accessibility/performing-accessibility-testing-for-your-app) requires a physical device for VoiceOver. A passing simulator audit does not demonstrate spoken output, focus order or VoiceOver gesture navigation.

## Physical-iPhone VoiceOver check — pending

No actual VoiceOver result is recorded for this change. A developer can perform the following with fictional records; this is separate from the deferred target-user session in [issue #13](https://github.com/harbour-health/harbour/issues/13).

Record the build/commit, iPhone model, iOS version, app language, text size, tester and evidence location. Repeat in English and Canadian French, with both Simple and Caregiver selected.

- [ ] With VoiceOver enabled, reach the Simple home actions and Settings in a useful order. Decorative artwork must not introduce extra stops.
- [ ] Open Interface and hear the shared-record explanation. Hear each mode's name, description and selected state as one actionable choice, without extra symbol/checkmark stops.
- [ ] Activate each mode and navigate back to Home. Reach Caregiver's Today, Chat, Records and Visits controls; verify that off-screen pages do not enter the focus sequence.
- [ ] Enter a fictional unsent chat draft, return Home and switch layouts. Reopen Chat and verify the draft remains available to read and edit.
- [ ] Open a fictional record editor. Find and activate Cancel, then reopen and deliberately confirm Save. Check that cancellation preserves the previous record state.
- [ ] Repeat at a larger accessibility text size. Scroll to the complete notice and both choices without losing the current focus or hiding an action.

| Build / commit | Device / iOS | Language / text size | Checks / observed result | Evidence |
| --- | --- | --- | --- | --- |
| Not recorded | Not recorded | Not recorded | Pending physical-device check | None |

Keep incomplete or failed checks visible and record corrective work before describing VoiceOver as verified. No participant usability or clinical-accuracy claim follows from this engineering checklist.
