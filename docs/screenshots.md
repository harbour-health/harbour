# Screenshots

## What it is

[The screenshot gallery](screenshots/index.html) contains genuine captures of the installed SwiftUI app on the Harbour QA iPhone simulator. Records shown are fictional test inputs. Each original PNG is available separately and the overview sheets provide a quick review.

## How it works

`HarbourUITests` navigates the native app and saves numbered XCTest screenshot attachments. `scripts/export-screenshots.py` exports those attachments from Xcode result bundles, preserves their device/test/timestamp provenance in `screenshots/manifest.json`, and generates a local HTML viewer. Images are not mockups or generated designs.

## How to change it

Add a numbered capture to the UI screenshot flow and its title to `TITLES` in the export script. Wait for the destination screen before capturing. Pass multiple result bundles to combine flows; a later capture with the same name replaces the earlier version. Inspect the actual PNGs after export, especially keyboards, long forms, share sheets, and download progress.

## Configuration

```sh
python3 scripts/export-screenshots.py /tmp/harbour-gallery-final.xcresult
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs/screenshots
```

Open `http://127.0.0.1:8765/` to review the gallery. The viewer supports left/right keys and Escape. `--output` changes the export directory. Result bundles must come from the current native build; the directory path is not proof that the capture test passed.

## Dependencies

Xcode's `xcresulttool`, Python 3, and actual XCTest screenshot attachments. Pillow is optional for overview sheets. The viewer uses local HTML, CSS, and JavaScript without external dependencies.
