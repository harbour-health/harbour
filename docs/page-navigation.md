# Page navigation

Today, Chat, Records and Visits support horizontal swiping as well as the floating dock. Both inputs update one selection binding, so active icons and the compact chat dock remain synchronized.

## How it works

`RootView` retains a separate `NavigationStack` for each destination in a clipped, screen-width horizontal strip. All four stacks stay mounted, preserving scroll position and navigation state. Offscreen stacks are hidden from accessibility. A UIKit pan recognizer attaches to each root scrolling surface through `MainPageSwipes.swift`, not the tab/navigation container. It rejects vertical movement before recognition and cancels a row button’s tap when a horizontal navigation swipe begins. This keeps ordinary scrolling and row taps distinct from page navigation. The recognizer requires horizontal velocity 1.6 times the vertical velocity, and is disabled while a keyboard, root drawer or export is open. Once recognized, it updates the strip offset on every movement in stable window coordinates, revealing the actual adjacent page. On release, displacement plus 0.16 seconds of projected velocity chooses the destination with a 25% page-width threshold; a spring completes the movement or returns a cancelled/short drag. The outer pages resist outward drags. Nested editors, charts and native back gestures retain their own interactions. The selection binding is clamped to the four destinations. Reduce Motion disables settling animations; direct finger tracking remains. Chat explicitly cancels active input/output when selection moves away, since offscreen pages remain mounted.

The earlier page-style tab container produced stale pushed-screen appearance and missing keyboard accessories in simulator testing; it is no longer used.

The dock keeps a fixed UIKit canvas for smooth scale/position animation. On Chat it scales to about 183 × 45 points, moves 32 points lower and retains 44-point touch targets. While the keyboard is open the dock is removed from the view and accessibility hierarchies. It is rebuilt with the current selection when the keyboard closes. The root must not disable all transactions, which would suppress the dock's spring.

## How to change it

Today presents Trends and Timeline through explicit destination state rather than inline destination closures. This keeps pushed content attached to the current navigation/appearance environment. The dock's retained symbol image uses `UIImageView`; writing a UIView's backing `layer.contents` directly let later display passes erase icons during pushes.

Chat publishes its keyboard toolbar only while the composer is focused. Keeping an unfocused page's keyboard toolbar active caused accessory ownership to become stale after sheets and tab changes. Topic selection returns focus to the composer so the user can continue writing. Tests wait for the moving selector to become hittable; screenshot tests explicitly dismiss the keyboard through Done.

Today, Records and Visits put large root headings inside their scrolling content, with the shared screen inset. This avoids zero leading margins in offscreen page-style navigation stacks and a native Today title retaining black text after an in-app dark-mode switch. Their native toolbar remains inline for actions; nested destinations retain their own navigation titles.

Keep page order and dock indices aligned in `HarbourApp.swift` and `Dashboard.swift`. Preserve each navigation stack when adding destinations. Test swipes in both directions, tapping after swiping, keyboard show/hide and nested navigation before changing gesture behaviour. Do not add a simultaneous global `DragGesture` over editors or charts.

## Configuration and dependencies

Uses a SwiftUI horizontal strip with explicit page geometry and root-only UIKit pan gestures, UIKit dock rendering and the system Reduce Motion preference. No new package, network service or user setting. `HarbourNativeRefreshTests` covers selected dock state, compact geometry, touch target size and keyboard hiding.
