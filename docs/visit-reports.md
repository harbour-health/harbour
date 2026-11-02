# Doctor visit reports

Open **Visits → Doctor visit report**, or use the link inside appointment preparation. Choose inclusive start/end dates and select readings, symptoms, current medications, visit notes, and saved questions. Preview the PDF before using the system share sheet.

Dates filter readings, symptoms, and visit transcripts using the device calendar. Future records are excluded. Medication instructions/schedules and questions represent the current saved lists, explicitly labelled in the report. Visit notes include saved transcript text, not audio or model-generated medicine proposals. Empty selected sections say that no records are available. No records are silently truncated; reports larger than the renderer's 5 MB input limit fail with an actionable message.

The report is a snapshot of recorded information, with reading charts and the underlying values and sources. Charts connect recorded values without interpolating measurements or classifying clinical risk. Blood pressure has separate systolic and diastolic series. English and Canadian French follow the app language.

## Renderer and privacy

`HarbourReports` wraps a Rust static library using Typst 0.13.1. The fixed template reads a virtual `report.json`; personal text is JSON data and never evaluated as Typst code. The renderer's `World` rejects all other files, packages, and imports, and does not expose the clock. Fonts are embedded. Compilation is serialized on a Swift actor away from the main actor. No server, command-line process, or runtime font download is used on iOS.

PDFs are written atomically with complete file protection into unique temporary folders. Dismissing the report flow or backgrounding the app removes its temporary PDF. A cancelled/backgrounded render cannot present or write a later result. The app privacy curtain covers previews while inactive. Copies explicitly shared by the user are owned by their destination.

## Build

Install Rust/Cargo from the official Rust distribution, then run:

```sh
bash scripts/prepare-reports.sh
```

The script installs official iOS Rust targets and builds an XCFramework for arm64 iPhone, arm64/x86_64 simulator, and arm64 Mac. Generated libraries and Cargo build output are ignored. The source, Cargo lockfile, template, and font notices are versioned. Use `bash scripts/prepare-reports.sh --force` to rebuild after changing renderer code or dependencies. The old framework is replaced only after the new package is ready.

When adding app files, regenerate the Xcode project with `python3 scripts/generate-project.py`.

## Verification

Hosted `VisitReportTests` cover inclusive dates, future exclusion, selected sections, chart data, multipage output, literal template-like personal text, and invalid/oversized input. `VisitReportUITests` exercise report configuration, PDF preview, and sharing with fictional fixtures. Inspect rendered PDF pages as well as extracted text when changing the template.
