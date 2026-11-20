# Simple and caregiver interfaces

Simple is the default, larger-control interface for independent older adults. Caregiver exposes the existing detailed records, visits and settings using the same local data.

## How it works

`AppInterface` persists `interfaceMode` (`simple` or `caregiver`) in UserDefaults. Simple home offers Talk, Message, Record a visit and a three-page visual guide. Its controls are at least 60 points high. The normal home fits without scrolling; short displays and accessibility text sizes can scroll instead of clipping controls. Long conversations and medical records remain scrollable.

Talk opens the existing full-screen voice conversation. Message opens the same agentic chat, with a Home action and without model/topic controls. The mic dictates into the composer; the empty-message action starts conversation. Neither home actions nor selected topics replace model-selected tool routing.

Record a visit immediately starts the shared recorder in a full-screen view. Returning Home leaves an active visit available through Resume visit and disables Talk to avoid competing audio sessions. Saved visits and source-confirmed medicine changes use the existing review flow.

Settings → Interface switches layouts. Caregiver preserves four-page navigation, records, technical preferences and Developer tools. This is a presentation preference, **not a second user, permission boundary, remote caregiver account or data isolation mechanism**. App lock protects both layouts equally. Switching returns Home without deleting records or changing the selected model. Recording Live Activity links reopen the shared recorder as a Simple full-screen view; an expired recording link returns Home instead of starting a new visit.

The interface picker explains in English and Canadian French that both layouts show and edit the same person's health records on this iPhone. It does not select another person or infer the record owner's identity from the phone. Each choice is one accessible button with a translated name, description and selected state; the decorative symbol and checkmark are hidden from accessibility. The picker scrolls when larger text needs more room.

The existing ChatView stays mounted when the layout changes. Returning Home and switching layouts preserve an unsent typed message; ending a voice session restores its pre-voice draft only when such a backup exists. The mode preference and saved records persist across app relaunches. Unsent chat drafts are view state and are not promised to survive termination. Both layouts continue using the same editors and confirmation gates.

See [caregiver interface verification](evaluation/caregiver-interface-verification.md) for the exact native test coverage, pending run evidence and the physical-iPhone VoiceOver checklist. Automated accessibility metadata audits are separate from actual VoiceOver testing.

## How to change it

Edit `SimpleHomeView` for the main actions/guide, `AppInterface` for choices, and `RootView` in `HarbourApp` for navigation. Keep one manual editor per record type; chat opens those same editors. Advanced records remain in caregiver mode. Add both language catalog entries and native UI assertions for every new action.

## Configuration and dependencies

`interfaceMode` defaults to `simple`. The developer/test variable `HARBOUR_INITIAL_INTERFACE=simple|caregiver` seeds that persisted value at launch; remove it before relaunching to test persistence. It does not override later in-app choices. `startVoiceOnOpen` is a consumed voice-entry request. Uses SwiftUI, the shared AppStore, VisitRecorder, VoiceService, local model manager and existing floating drawers. No new service or network account.
