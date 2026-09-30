# Screenshots

## What it is

[The screenshot gallery](screenshots/index.html) contains genuine captures of the installed SwiftUI app on the Harbour QA iPhone simulator. Records shown are fictional test inputs. Each original PNG is available separately and the overview sheets provide a quick review.

## How it works

`HarbourAppearanceTests` exercises Light/Dark persistence and unchanged topic drafts; `HarbourRichResultsTests` exercises real local-model tool results; `HarbourDetailRefreshTests` covers the entry/review sheets. `HarbourDashboardTests` captures the equal-sized shortcuts, icon dock, and actual generated title. `HarbourLockTests` captures four-slot PIN setup, unlock, mismatch, current-PIN verification, and retry delay. `HarbourFreshScreensTests` uses a separate fresh simulator for genuine download progress, unavailable Face ID, Apple Health permissions/status, and the file picker. `HarbourEvaluationScreenTests` captures a completed selected-model evaluation. These XCTest flows navigate the native app and save numbered XCTest screenshot attachments.

`scripts/export-screenshots.py` exports attachments from Xcode result bundles, preserves their device/test/timestamp provenance in `screenshots/manifest.json`, and generates a local HTML viewer. Paired light/dark dashboard, chat, records, settings, model controls, and entry-sheet captures show the current appearance. `preview.jpg` uses dashboard, empty chat, and generated-title captures. Images are not mockups or generated designs.

## How to change it

The gallery currently contains 63 native captures. Main app screens and editors have paired appearance captures. Download and Health permission/status images were refreshed on a disposable simulator without removing existing models. PIN setup and retry captures show a fictional test credential, never a user's PIN. The Face ID capture shows the unavailable/enrollment error, not a successful biometric match.

Add a numbered capture to the UI screenshot flow and its title to `TITLES` in the export script. Wait for the destination screen before capturing. Pass multiple result bundles to combine flows; a later capture with the same name replaces the earlier version. Inspect the actual PNGs after export, especially keyboards, long forms, share sheets, and download progress.

## Configuration

```sh
python3 scripts/export-screenshots.py /tmp/harbour-dashboard-final.xcresult /tmp/harbour-chat-final.xcresult /tmp/harbour-fresh-final.xcresult /tmp/harbour-four-digit-pin.xcresult /tmp/harbour-layout-final.xcresult /tmp/harbour-system-final.xcresult
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs/screenshots
```

Open `http://127.0.0.1:8765/` to review the gallery. The viewer supports left/right keys and Escape. `--output` changes the export directory. Result bundles must come from the current native build when replacing updated screens; the directory path is not proof that the capture test passed. The main multi-flow capture was interrupted during the animation wait; its completed appearance, entry, and navigation flows passed. Later finished runs replace its chat captures. The four-digit run's PIN flow passed; its dashboard margin assertion was corrected in the subsequent dashboard run because decorative accessibility bounds include intentionally cropped artwork. Keep these boundaries distinct from the actual captures.

To repeat `HarbourFreshScreensTests`, create and boot a disposable iPhone simulator, then use its UUID as the Xcode destination. Do not reset an existing user's permissions or remove their downloaded models for screenshots. After exporting its attachments, shut down and delete that fixture simulator.

## Dependencies

Xcode's `xcresulttool`, Python 3, and actual XCTest screenshot attachments. Pillow is optional for overview sheets. The viewer uses local HTML, CSS, and JavaScript without external dependencies.
