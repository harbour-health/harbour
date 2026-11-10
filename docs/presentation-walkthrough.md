# Presentation and native walkthrough

A 10-minute honours-project presentation built from pinned Touying source, actual native app footage and a local HTML scene. UI parts lift out of the phone with leader lines; they are cropped pixels from real captures, not reconstructed controls.

## How it works

`presentation/harbour.typ` owns the slides. Touying 0.7.3 renders them to SVG, then `build-presentation.py` packages them with native screenshots, MP4, speaker notes and an HTML player. This avoids relying on experimental Typst HTML layout or PDF multimedia. The PDF backup has static app images; it does not play video.

`presentation/slides.json` holds notes and timings (600 seconds total). The supplied CSI4900 brief separately specifies a 13-minute final talk; this is the user's requested 10-minute demo version. The live walkthrough or exported composition can occupy the demo section.

`PresentationWalkthroughUITests` operates the real app: explicitly replace QA records with fictional data, switch to Simple, send a real local-model reading request, show the caregiver home cards and record categories, choose a medication-name suggestion and review a saved visit. It uses Alex for this capture. Saved visit summaries are authored fixtures, not live summary-accuracy evidence. No audio is captured or evaluated.

`record-presentation.py` records the simulator, verifies the native test passed, trims setup and exports an **unaccelerated** silent MP4. It retains original MOV, test result, log and `walkthrough.json` timestamps/actual accessibility bounds. It has no `drawtext` dependency. `--export-only` retries an export without rerunning inference or overwriting a passed test. Variable-frame-rate capture is resampled before trimming, then timestamps are reset to zero; the encoded duration is checked against the declared source trim.

`player.js` uses CSS clipping (no cross-origin canvas readback) to animate real cropped UI from its original phone position into the surrounding slide. All complete elements in a scene lift concurrently in 440 ms. Only after every lift finishes do the leader lines and explanation text fade in. Callouts explain Simple voice/chat/recording, the whole saved-readings card, caregiver home cards, all four record categories, database names and the visit-change drawer. The medicine and visit drawers each lift as one complete panel with several annotations; the table never splits into rows or text fragments. Crops are declared in logical points in `build-presentation.py`; some accessibility bounds include clipped decorative artwork, so tile edges are explicitly clipped to their genuine rounded boundaries. Most bounds come from the matched XCTest chapter. The builder rejects missing or offscreen element bounds and preserves the source aspect ratio. Update crops after UI changes and inspect every result.

## Rebuild and record

```sh
# Existing capture: no Xcode or model generation needed for this step.
python3 scripts/build-presentation.py --recording /path/to/passed-capture

# New QA capture; simulator must already be booted and Alex downloaded.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
python3 scripts/record-presentation.py --simulator-id UDID \
  --output /path/to/fresh-capture
```

Recording explicitly replaces the selected simulator's local records. Use a QA simulator containing no important data. Model/settings caches remain. `--skip-build` reuses a compatible build-for-testing; `--export-only` requires a retained successful `test.log` and original MOV.

Open `docs/presentation/index.html` directly for offline slides and video. Arrow keys change slides; Space plays/pauses; E explains a part; N toggles notes. Explain moves pixels outside the phone. It adds no focus outline or presenter controls to the actual app.

## Live guided use

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
python3 scripts/serve-presentation.py --simulator-id UDID
```

The server binds only `127.0.0.1:8766`. Simulator opens the actual native simulator. Operate the app there, return and choose Capture, then drag over a region of the genuine current screenshot. The selected pixels lift out for a spoken explanation. Capture is explicit; there is no continuous screenshot upload. Images stay in browser memory and temporary local files, which are removed after the response.

For embedded interaction, start the scoped `serve-sim` mirror described by the iOS simulator-browser skill and pass its exact local URL as `--mirror-url`. Live then embeds that actual simulator, while Capture freezes a real native frame for annotation. No lookalike app is drawn. The server does not boot devices or pick an arbitrary simulator, and rejects nonlocal mirror hosts. Capture/open routes require a same-origin custom header and expose no arbitrary command or filesystem endpoint.

The optional debug-only native bounds helper in `PresentationWalkthrough.swift` remains inactive unless `HARBOUR_PRESENTATION_CAPTURE=1`. Production builds disable it. The delivered walkthrough does not use it; recorded bounds come from XCTest, and live selections use actual captured pixels.

## Export the widescreen video

```sh
npm install --prefix presentation
# Use installed Chrome, or install Playwright Chromium and pass --browser chromium.
node scripts/export-presentation-video.cjs --url http://127.0.0.1:8766/ \
  --output docs/presentation/harbour-demo.mp4
```

The script records the real HTML composition at 1920 × 1080. The native source stays unaccelerated. For a request-to-result capture gap over 12 seconds, the exported composition keeps the first five seconds then uses a disclosed jump cut to the result. An on-screen note gives the original capture gap; this video must not be used as a real-time inference benchmark. It pauses the actual native footage for six deconstruction scenes, then resumes it. Each scene stays visible for 17 seconds (20 for the four record categories) so the explanatory text can be read. The exporter requires all six stops before declaring success. It exports H.264 MP4 with ffmpeg. Original browser footage remains under ignored `build/`. `HARBOUR_NODE_MODULES` can point to an existing Playwright dependency directory instead of installing locally.

## How to change it

Edit text in `.typ`, notes/timings in `slides.json`, crop rectangles/callouts in the builder, and animations in `player.js`/`styles.css`. Rebuild, review every slide and export again. Keep all source numbers tied to the evaluation JSON and source manifest. Do not present authored demo summaries as generated results, or a 16-case medication-name subset as the full medical evaluation.

## Configuration and dependencies

Typst 0.14.2+, pinned Touying 0.7.3, Arial, Python standard library; no hosted assets or CDN. Typst packages cache in ignored `build/typst-packages`. Native capture requires Xcode/Simulator/XCTest, the prepared app dependencies and cached Alex weights. Browser export uses Playwright 1.62.1, Chrome/Chromium and ffmpeg/libx264. DEVELOPER_DIR is local to commands; system Xcode selection is unchanged. Default generated output is `docs/presentation`.

References: [Touying exporter](https://touying-typ.github.io/docs/external/touying-exporter) documents SVG-based HTML export; [Typst HTML](https://typst.app/docs/reference/html/) describes the experimental native route. This project uses Touying SVGs plus a native HTML video element for playback.

## Portable bundle

After video export, run `python3 scripts/package-presentation.py`. The ignored `build/harbour-presentation.zip` contains the offline player, videos, PDF, notes and editable source with the actual source captures. Its README includes a rebuild command that works from the extracted bundle. No model weights, test result bundles or runtime logs are included.

## Verification for complete-element scenes

The native walkthrough waits for the reading reply to finish, scrolls into view and asserts that the complete table fits between the top controls and composer before capture. Its caregiver chapter captures the actual home cards before opening Records. The updated native test passed. Browser review checked all six scenes: lift animations share a start frame and last 440 ms, no explanatory text appears during the lift, labels fit the stage without overlap, and complete cards/rows/drawers retain their aspect ratios. The video exporter checks that all six scenes ran before producing a successful deliverable. Review the actual images again whenever native layout or fonts change; bounds alone do not prove visual completeness.

## Backend explanations

The video now inserts six source-traced architecture animations alongside the native scenes: model selection and runtime, chat routing, voice turns, medicine identity, recording/transcription, and focused summary extraction. Use the Backend menu to replay one during a live talk. See [backend animation configuration and implementation mapping](presentation-backend.md). They use labelled illustrative payloads; they do not claim that the authored visit fixture was extracted live. The export must include all six backend sequences in addition to the six complete-element UI scenes.
