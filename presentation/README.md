# Presentation source

`harbour.typ` is the pinned Touying slide source. `slides.json` defines the nine sections, 600-second timing and source-backed presenter notes. `player.js` and `styles.css` animate genuine native UI crops outside the phone; no app widgets are re-created.

Build with `python3 scripts/build-presentation.py --recording /path/to/passed-native-capture` from the repo root. The builder copies SVG slides, native images, video and notes into `docs/presentation`. Use `scripts/serve-presentation.py` for live capture, `scripts/export-presentation-video.cjs` for the widescreen MP4, and `scripts/package-presentation.py` for a portable bundle with editable source.

See [the complete developer guide](../docs/presentation-walkthrough.md) for configuration, dependencies, recording and evidence limits. The app source remains in the original repository; rebuilding this deck from an existing capture needs only Typst and Python.

Backend architecture sequences are authored in `backend-flows.json` and animated by `backend.js`; use the Backend menu to replay them. They illustrate the source implementation, rather than reporting live backend telemetry.
