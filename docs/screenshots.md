# Screenshots

## What it is

[The screenshot gallery](screenshots/index.html) contains genuine captures of the installed SwiftUI app on the Harbour QA iPhone simulator. Records shown are fictional test inputs. Each original PNG is available separately and the overview sheets provide a quick review.

## How it works

`HarbourAppearanceTests` exercises Light/Dark persistence and unchanged topic drafts; `HarbourRichResultsTests` exercises real local-model tool results; `HarbourDetailRefreshTests` covers the entry/review sheets. These XCTest flows navigate the native app and saves numbered XCTest screenshot attachments. `scripts/export-screenshots.py` exports those attachments from Xcode result bundles, preserves their device/test/timestamp provenance in `screenshots/manifest.json`, and generates a local HTML viewer. Paired light/dark dashboard, chat, records, settings, model controls, and entry-sheet captures show the new appearance. `preview.jpg` is generated from the current dashboard and chat captures. Images are not mockups or generated designs.

## How to change it

The gallery currently contains 52 native captures. Main app screens and editors have paired appearance captures; three earlier model-download/Health captures remain explicitly labelled.

Add a numbered capture to the UI screenshot flow and its title to `TITLES` in the export script. Wait for the destination screen before capturing. Pass multiple result bundles to combine flows; a later capture with the same name replaces the earlier version. Inspect the actual PNGs after export, especially keyboards, long forms, share sheets, and download progress.

## Configuration

```sh
python3 scripts/export-screenshots.py /tmp/harbour-redesign-final.xcresult /tmp/harbour-navigation-final.xcresult /tmp/harbour-contrast-final.xcresult /tmp/harbour-rich-final.xcresult
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs/screenshots
```

Open `http://127.0.0.1:8765/` to review the gallery. The viewer supports left/right keys and Escape. `--output` changes the export directory. Model-download and Apple Health permission/status captures retained from the earlier build are labelled in the gallery; their original provenance remains in the manifest. Result bundles must come from the current native build when replacing updated screens; the directory path is not proof that the capture test passed.

## Dependencies

Xcode's `xcresulttool`, Python 3, and actual XCTest screenshot attachments. Pillow is optional for overview sheets. The viewer uses local HTML, CSS, and JavaScript without external dependencies.
