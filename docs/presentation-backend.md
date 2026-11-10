# Backend architecture animations

The presentation adds six animated explanations beside genuine native footage. They describe the current implementation with illustrative input values; they are not live runtime telemetry, extra model evaluations or recordings of successful speech/summary extraction.

## How it works

`presentation/backend-flows.json` holds stages, timed beats, examples and source references. `backend.js` renders a flat processing rail with a moving packet, active stage, structured data and explanation. Each beat changes the displayed payload and highlights the processing stage. Reduced Motion keeps the explanatory sequence without packet movement.

`player.js` inserts model selection and voice after the Simple home scene, chat routing during the explicitly shortened inference wait (or before the result when there is no long wait), medicine identity after the medicine editor, and recording/transcription plus summary extraction before visit review. Actual UI elements still lift as complete cards/rows/drawers. The Backend menu can replay each explanation independently; Close or Escape stops it. Changing slides cancels the active explanation.

The export script requires all six UI scenes and all six backend explanations. The original native MP4 remains unaccelerated; the composite discloses its omitted request-to-result wait. Diagram durations describe presentation pacing, never execution time.

## Implementation mapping

| Explanation | Owning implementation | Important distinction |
| --- | --- | --- |
| Model selection | `ModelManager.automaticModel`, `visitModel`, `ensure`, `generate`; `LocalModel` | The device policy uses memory, power mode and thermal state, not a benchmark. Simulator selects Sam automatically; the recorded chat manually selected Alex. Camille remains manual. Missing assets download before local inference. |
| Chat routing | `ToolPlanner.prompt/parse/validate`, `ModelManager.chatDecision`, `ChatView.send/execute` | The LLM chooses the tool. Deterministic source checks validate proposals; they do not replace the router. Read tools return records, write tools open review UI, and reply generates conversation. |
| Voice | `VoiceService`, `ChatView` voice lifecycle, `KokoroSpeechEngine` | On-device speech produces the next text turn. The ordinary chat pipeline runs, then Kokoro synthesizes the reply. Dictation only fills the composer. |
| Medicine intent | `ToolPlanner`, `MedicationVocabulary`, `MedicineEditor` in `RecordsView.swift` | Action selection and medicine identity lookup are separate. Similar names remain candidates until deliberately selected; they do not rewrite a transcript automatically. |
| Recording | `VisitAudioWriter`, `ModernVisitSpeech`, `LegacyVisitSpeech`, `VisitTranscription`, session activities | Audio is saved while speech receives buffers. Live iOS 26 speech uses AnalysisContext medication hints; saved-file retranscription is a separate path. Recognition failure can retain audio for retry. |
| Summary | `VisitsView.summarise`, `VisitExtractionPass`, `VisitReview.parse`, `AppStore.saveVisitSummary` | Three sequential passes per 1,800-character chunk extract medicines, follow-ups/appointments and highlights. They are not draft/critic/repair rounds. Parsed proposals merge, then medication changes require separate confirmation. |

The code's validation is bounded. It does not prove clinical accuracy or guarantee that every instruction is extracted. Unknown identities, malformed outputs, unsupported fields and stale medication baselines can require review or block application. Keep these limits in the presentation.

## How to change it

Edit content and timing in `backend-flows.json`, animation in `backend.js`, layout in `styles.css`, and insertion points in `player.js`. Update source references after implementation changes. Source captions are repo paths/symbols so the offline bundle needs no remote service. Keep example payloads labelled as illustrative, especially when describing the authored visit fixture.

Rebuild using `scripts/build-presentation.py --recording /path/to/passed-capture`, inspect every beat for wrapping and overlaps, then run `scripts/export-presentation-video.cjs` and `scripts/package-presentation.py`. The portable bundle includes all source JSON/JS/CSS. It reuses the existing passed native capture; no iOS rebuild or new model download is required for explanatory changes.

## Configuration

Each flow has `title`, `subtitle`, four `stages`, `sources` and `beats`. Each beat has a zero-based `stage`, `title`, `detail`, structured example `code`, and `seconds`. Optional `visual` branch/pass diagrams show selected model/tool paths, concurrent audio consumers, and sequential extraction passes with moving data packets. Stage selection animates the packet and the rail; the small beat markers show progress through repeated passes at the same stage. The nine-slide speaker timing remains 600 seconds in `slides.json`.

## Dependencies

The existing Touying/Typst build, browser Web Animations API, local JSON/JS/CSS, and the already captured native PNG/MP4 assets. Export uses the existing Playwright/Chrome and ffmpeg workflow. No new app/runtime dependency, hosted LLM, analytics service or model weights are introduced.

## Verification

Browser review covered all 26 beats at 1920 × 1080, with no content/progress overlap, slide navigation cancelling an active explanation, and packet movement disabled under Reduced Motion. The exporter also requires every expected beat callback before accepting its video. These are presentation checks, not backend inference or speech accuracy evaluations.
