# Visual review

## What it is

This review records visual inspection of Harbour's genuine native screenshots and the shared layout and motion refinements made on October 1, 2026. It distinguishes visible evidence from behavior that still needs a running app.

## How it works

The review inspected every image in `screenshots/overview-1.jpg` through `overview-10.jpg`, covering the original 90 numbered captures: Today, all record types and editors, chat and rich responses, settings, models, app lock, system permissions, visits, and drawer variants. The original PNGs for 01, 31, 79, 84, 89, and 90 were also opened individually to examine dashboard spacing, dark appearance, landscape, large text, and iOS 18 small-phone presentation.

The first care export was inspected individually at 91–96, 105, and 112. A second review opened `overview-11.jpg` through `overview-13.jpg`, covering all 23 additional captures in the 113-image gallery. It also opened the refreshed originals 92, 96, 98, 102, 103, 107, 110, 112, 114, and 115 individually. Together the overview reviews cover every image in this gallery; individual image inspection was concentrated on layout concerns and newly added flows.

The refreshed scanner images show the Camera and Label photo actions on separate lines, resolving the earlier word wrapping. The refreshed Timeline shows its search field immediately, and dates and details now align with their title column. Light/dark agenda, preparation, schedule, and dose content is legible at the captured default text size, with a consistent neutral palette and visible selection indicators. The dark schedule capture 102 shows Time 1 and Add time; chat schedule capture 107 shows both proposed time pickers. Reminder confirmation 105 and dose confirmation 108 retain the detached editing surface over the conversation.

Remaining findings at this review checkpoint:

- **Scanner touch areas:** the vertically stacked borderless source buttons in `MedicineScanButtons` still have intrinsic label-height content. The 16-point stack gap does not itself enlarge their hit areas. Give each source label a minimum 44-point frame and a full-row content shape, then check the rendered spacing. The fixture button should follow the same pattern when present.
- **Schedule capture:** the initial image 92 was blank. Its refreshed version is a valid medicine-editor image, but shows the label and instructions rather than the schedule. Recapture with Time 1, Add time, and the relevant schedule settings visible. The existing image must not be presented as complete schedule-layout evidence.
- **Evidence boundaries:** image 110 shows an unsaved appointment question; its note correctly still says no questions are saved. Image 98 shows the saved question included in the note. Image 114 shows the voice-input error state, which is useful recovery-state evidence but provides no successful speech-recognition evidence. Image 115 shows the reminder editor with Notify me off; it cannot establish notification authorization or delivery.

Check each screenshot's manifest provenance when using this review with subsequent exports. Repeated reminders and visits in the gallery are persisted fictional fixtures; they are not evidence of duplicate creation from one action.

Shared changes from this review:

- `ReadingSummary` scales its prominent value with Dynamic Type. Accessibility text sizes put the unit below the value, and the date/count footer falls back to two rows when its content does not fit horizontally.
- The floating dock retains four equal 68 × 48 point destinations, selected-state shapes, and VoiceOver labels. Each destination offers the native large-content viewer, and Reduce Transparency uses an opaque neutral backing.
- The original conversation illustration has one 0.32-second arrival, then rests. Reduce Motion bypasses its positional/opacity effect. The vector artwork remains decorative and excluded from hit testing and accessibility traversal.
- The detached drawer geometry is preserved, including native iOS 26 portrait presentation and the custom iOS 18/landscape fallback. The reviewed originals show rounded detached surfaces and legible content at the tested sizes.

The review follows Apple's guidance to adapt text and interactions to accessibility settings, keep animation brief and meaningful, and respect safe areas. Harbour uses a minimum 44-point touch target policy, matching Apple's default iOS control size. See [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Motion](https://developer.apple.com/design/human-interface-guidelines/motion), and [Layout](https://developer.apple.com/design/human-interface-guidelines/layout). Their official documentation JSON endpoints were read when the HTML required JavaScript.

## How to change it

Change shared metrics and action controls in `InterfaceComponents.swift`, the navigation dock and reading summary in `Dashboard.swift`, the artwork and arrival behavior in `Illustrations.swift`, and presentation geometry in `FloatingDrawer.swift`. Keep data rows on neutral surfaces; reserve colored panels for the existing primary shortcuts and meaningful selection states. Keep paired shortcuts equal in size, and use flexible stacks before shrinking important text.

After layout changes, capture and inspect actual destination screens in both appearances. Include the longest medicine name, blood-pressure values with units, accessibility text, small phones, keyboard presentation, and landscape where supported. Scroll to the final row to confirm that the floating dock leaves it reachable. Capture transient actions only after their destination controls appear; a white frame is not a successful visual check.

This review did not drive the simulator or run a build while another agent owned XCTest. The two modified Swift files passed a syntax parse; that alone does not establish SDK type checking or runtime layout. The care refresh supplies genuine native rendering of its captured destinations; the original 90 images retain their earlier build provenance. The final focused run adds an accessibility-size dashboard capture for the reading-summary refinement; see the final capture corrections below. Screenshot inspection cannot establish VoiceOver order, large-content viewer interaction, Reduce Motion transitions, notification delivery, or physical-device speech recognition. Those require focused runtime verification.

## Configuration

`AppLayout` defines the shared 24-point inset, 28-point section spacing, 44-point control size, and 760-point maximum content width. `Palette` supplies semantic light/dark colors; the persisted `appearance` preference selects System, Light, or Dark. Dynamic Type, Reduce Motion, and Reduce Transparency are read from SwiftUI's environment. No new preference or environment variable is introduced.

The illustration's `animated` argument enables its finite arrival only for the conversation artwork. Drawer content can publish an explicit or measured height; explicit heights scale with text, and the presentation is capped against the current window bounds and top safe area.

## Dependencies

SwiftUI, UIKit, Swift Charts, `HarbourCore.Reading`, and `VisitRecorder` supply layout, accessibility, readings, and the recording indicator. Original artwork is drawn locally in `Canvas` and adds no image download or service dependency. Screenshot evidence comes from XCTest attachments exported by `scripts/export-screenshots.py`; provenance and device details live in `screenshots/manifest.json`.

### Final capture corrections

The current selection styling supersedes the all-filled treatment: inactive symbols are dim outlines, and only the active symbol is filled white on a dark capsule. `harbour-dock-selection-final.xcresult` passed the paired main-screen flow and refreshed all eight roots. Light Today and dark Chat were inspected directly for selection contrast and the outline/fill change. The recording signal is now a coral dot so it does not replace the selected white color.

The latest semantic revision uses a filled home, conversation bubbles, medical clipboard, and two people. `harbour-navigation-symbols.xcresult` passed the paired main-screen flow and replaced all eight root captures. Light Today and dark Chat were inspected directly; all four symbols render with consistent spacing. The medical clipboard distinguishes health records, while the people represent a doctor meeting rather than only its recording function.

The following filled-icon update supersedes the outline choice: all four dock symbols now use their `.fill` variants in both selected and unselected states. `harbour-filled-dock.xcresult` passed the paired main-screen flow and refreshed all eight root-page captures. The light Today and dark Chat originals were visually inspected; selection remains visible through the capsule.

The subsequent corner/icon review inspected refreshed Appearance in both themes, Models, PIN setup, Today, and dark Chat from `harbour-uniform-corners.xcresult`. Applying the shared 54-point radius to the native presentation removes the smaller top curve; the panel now has matching continuous corners. The dock's sun, single bubble, document, and microphone are consistent outlines, with selection shown by the capsule. Both native drawer and settled main-screen tests passed. See [Floating drawers](floating-drawers.md) for the presentation change and [Interface](interface.md) for the symbol choices.

The later native care capture replaces 92 with the actual time, refill, and notification controls. Camera/photo actions now have explicit 44-point full-width hit areas. The notification UI flow now asserts the switch is enabled before saving; the native service test then passed actual private notification content, stable identifier, completion cancellation, and preservation of unrelated requests. The schedule screenshot was opened individually after export. The final native run passed the seven-tool chat confirmation flow. The largest-text dashboard/reading-entry/topic flow also passed and produced refreshed originals 116 and 84. Those originals were inspected; the dashboard footer continues below the initial viewport and requires scrolling. This does not establish every-screen accessibility or VoiceOver coverage. The final gallery has 115 captures. A final review found a missing Records glyph in one light Chat capture; the other roots and dark Chat have all four glyphs. The settled recapture restores all four dock glyphs without a navigation-code change. That check also exposed the third starter below the initial viewport; a smaller decorative illustration and top inset resolve it. `harbour-care-stable-paired.xcresult` passed all four dock targets and the final starter above the composer in both appearances, then exported all eight main-page captures.

## Canadian French and reference dock

The updated dock follows the supplied reference's 278 × 62 point charcoal capsule, 83 × 54 point black selection, white filled active symbol, and dim outlined inactive symbols. Native button targets and localized accessibility labels remain independent from symbol drawing. The keyboard temporarily hides the mounted dock and its accessibility targets.

The Canadian French review covered overview sheets 13–16 and individual main-page, PIN, medicine, decimal-comma reading, and rich-chat originals. Removing redundant horizontal padding lets the three French empty-chat starters fit above the composer. User-entered medicine instructions remain unchanged, including English text in French UI. The visit-notes toolbar uses native truncation for its longer French label; the editor retains its full field label. This review does not establish every-screen VoiceOver or physical-device acceptance.

Visual inspection raised concerns about intermittent glyph omission in chat screenshots even though navigation targets were hittable. Full-resolution pixel checks are also used to distinguish an actually missing icon from an image-preview artifact. The follow-up separates symbol drawing from button interaction and retains the dock through keyboard transitions. Inspect actual exported originals after the focused English and French runs rather than treating test success alone as proof of icon visibility.

The final `harbour-raster-dock.xcresult` passed both focused flows. Full-resolution English main pages and French rich chat results were inspected, and a pixel check confirmed a visible glyph in each of the four dock positions across eight English main pages, eight French main pages, and two French model-result screens. The earlier French main-page originals keep their separate producing-run provenance. The README contains all 140 numbered captures.
