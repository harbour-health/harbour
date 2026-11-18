# Simple and caregiver interface verification

This records the verification scope for [issue #11](https://github.com/harbour-health/harbour/issues/11). Simple and Caregiver show one shared person's local health records. The interface picker now explains that changing the layout does not select another person. No participant information, additional patient profile or account is needed for these checks.

## Automated checks

Local source checks passed: `python -X utf8 scripts/audit-localization.py` checked 752 interface keys and six permission keys in each language, and `git diff --check` reported no whitespace errors. These source checks do not execute the iOS interface. Native tests and audits for this change remain pending.

`HarbourUITests/SimpleInterfaceUITests.swift` exercises the actual native screens without sending a message to a model, downloading speech assets or recording audio.

| Test | Assertions | Result for this change |
| --- | --- | --- |
| `testSimpleHomeHelpAndCaregiverSwitch` | Simple actions, guide and chat controls; switch to detailed Caregiver navigation. | Native rerun pending. |
| `testSimpleLargestTextKeepsPrimaryActionsReachable` | Largest accessibility text in English and Canadian French; scroll to Simple actions, open the guide, reach the interface choices and Caregiver record categories. | Native rerun pending. |
| `testFrenchSimpleHome` | Translated Simple home and guide labels. | Native rerun pending. |
| `testUnsentChatDraftSurvivesHomeAndBothModeSwitches` | Type a unique unsent message; return Home; switch Simple → Caregiver → Simple; reopen Chat and check the unchanged draft each time. | Native run pending. |
| `testModeSelectionPersistsAcrossRelaunchWithoutLaunchSeed` | Select each mode in Settings; terminate and relaunch with the initial-mode environment seed removed; check the retained layout and selected button. | Native run pending. |
| `testConfirmedRecordSurvivesModeSwitchesAndRelaunch` | Cancel a fictional appointment before date confirmation; verify no record exists; explicitly confirm and save it; check that the record survives both layout switches and relaunch. | Native run pending. |
| `testInterfaceAccessibilityMetadataInBothLanguages` | Exact translated shared-record notice, mode labels/descriptions and selected state; accessibility audits for sufficient element descriptions and traits on both home layouts and the picker in both selected states. | Native audit run pending. |

The mode-persistence test removes `HARBOUR_INITIAL_INTERFACE` before relaunch because `HarbourApp.init()` seeds the preference whenever that variable is supplied. It does not call `launchCaregiver()` to restore a layout, which would overwrite the preference under test. Saved-record checks use a unique fictional appointment on an isolated QA simulator. An unsent draft is checked across navigation and layout switches, not across process termination.

Run the suite on an isolated iPhone simulator with the app's prepared native dependencies:

```sh
xcodebuild test -project Harbour.xcodeproj -scheme Harbour \
  -destination 'platform=iOS Simulator,id=SIMULATOR-UDID' \
  -parallel-testing-enabled NO \
  -resultBundlePath build/Harbour-Interface.xcresult \
  -only-testing:HarbourUITests/SimpleInterfaceUITests \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

Record the tested commit, simulator model, iOS version, completed test outcomes and result-bundle/artifact link when this run completes. The test definitions and earlier interface screenshots do not establish that these new checks passed. The CI workflow selects this suite and uploads the native result bundle and attachments.

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
