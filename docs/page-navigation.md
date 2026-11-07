# Page navigation

Today, Chat, Records and Visits support horizontal swiping as well as the floating dock. Both inputs update one selection binding, so active icons and the compact chat dock remain synchronized.

## How it works

`RootView` uses SwiftUI's native `PageTabViewStyle` without page dots. Each destination retains its own `NavigationStack`. Native paging supplies interactive drag tracking and cooperates with vertical scroll views and controls; there is no app-wide custom drag recognizer intercepting every touch. Dock selections animate the same page transition. Reduce Motion disables the explicit selection animation.

The dock keeps a fixed UIKit canvas for smooth scale/position animation. On Chat it scales to about 183 × 45 points, moves 32 points lower and retains 44-point touch targets. While the keyboard is open the dock is removed from the view and accessibility hierarchies. It is rebuilt with the current selection when the keyboard closes. The root must not disable all transactions, which would suppress the dock's spring.

## How to change it

Records and Visits put their large root headings inside their scrolling content, with the shared screen inset. This avoids the zero leading margin seen on native large titles in offscreen page-style navigation stacks. Their native toolbar remains inline for actions; nested destinations retain their own navigation titles.

Keep destination tags and dock indices aligned in `HarbourApp.swift` and `Dashboard.swift`. Preserve each navigation stack when adding destinations. Test swipes in both directions, tapping after swiping, keyboard show/hide and nested navigation before changing gesture behaviour. Do not add a simultaneous global `DragGesture` over editors or charts.

## Configuration and dependencies

Uses SwiftUI's native page style, UIKit dock rendering and the system Reduce Motion preference. No new package, network service or user setting. `HarbourNativeRefreshTests` covers selected dock state, compact geometry, touch target size and keyboard hiding.
