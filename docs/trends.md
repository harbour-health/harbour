# Health trends

## What it is

Trends presents saved readings and symptom frequency with large, labelled controls and a single chart surface. It does not classify readings as healthy or derive clinical risk.

## How it works

Readings and Symptoms use labelled icon tabs with an underline. Time ranges are separate large buttons. Readings opens on the most recent measurement type; older saved data falls back to All time when the initial month is empty. The latest value/date sits above the plot. A single reading uses a shorter plot with explicit nonzero axis domains instead of a large empty surface. Blood-pressure series stay separate. Symptoms shows entry counts and the most frequent recorded symptom descriptions.

## How to change it

`HealthTrendsView` in `CareViews.swift` owns filtering, chart domains, and layout. Keep count/date aggregation in HarbourCore and display wording in localization catalogs. Test sparse data, one reading, blood pressure, and an empty range before changing axis formatting. `HarbourTrendsTests` and `HarbourNativeRefreshTests` cover the rendered navigation and chart states.

## Configuration and dependencies

Ranges are 7, 30, 90 days, and All time. Multiple-reading charts are 220 points high; a single-reading chart is 110. Uses Swift Charts, SwiftUI, HarbourCore, and the existing archive; no network service is involved.
