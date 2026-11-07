# Export presentation

## What it is

The system share sheet used by record exports and generated reports. Closing or finishing sharing must return to its existing parent editor without presenting the export again.

## How it works

`ShareView` wraps `UIActivityViewController`. Its completion handler invokes the hosting SwiftUI sheet's dismiss action on the main actor for both completed and cancelled activities. This synchronizes the SwiftUI presentation binding when UIKit closes its controller. The parent Settings drawer remains open.

## How to change it

Keep completion ownership inside `ShareView` in `HarbourApp.swift`; do not dismiss the parent drawer or clear unrelated navigation state. `ShareExportUITests` opens and closes the export twice and checks that Settings remains usable. The existing appearance smoke also continues past export dismissal.

## Configuration

No flags or service credentials. `ShareView.url` is the local export/report URL. Export contents, data validation and file lifetime remain owned by the caller.

## Dependencies

SwiftUI presentation state and UIKit's activity controller. System share extensions are outside Harbour's control; no external share destination is invoked by the dismissal regression test.
