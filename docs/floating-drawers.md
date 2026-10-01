# Floating drawers

## What it is

Harbour's app-owned modal screens share a detached, rounded drawer. Small tasks open at a compact height instead of leaving an empty full-screen form.

## How it works

`FloatingDrawer` keeps SwiftUI's native sheet presentation, navigation, dismissal, keyboard avoidance, and modal accessibility. On iOS 26 and later, the native detached sheet supplies its side and bottom inset and drag handle. An opaque semantic canvas avoids putting a second rounded card inside the native glass frame. On iOS 18–25, a transparent presentation surrounds an explicitly padded panel with an internal handle. Native keyboard avoidance remains active and compact-height adaptation is disabled. Each drawer applies the persisted appearance choice directly, so changing themes also updates an already-presented drawer instead of leaving its UIKit presentation in the previous theme.

On iOS 26 and later, system sheets automatically adapt their corner curvature to the device, as documented by Apple's [corner-concentricity reference](https://developer.apple.com/documentation/swiftui/concentricrectangle). The app preserves those native corners rather than reading a private hardware radius. iOS 18–25 use a 54-point continuous rounded rectangle; exact hardware corner measurements are not publicly available on those versions.

Each screen supplies an initial height suited to its controls. Reading entry and Appearance use about 320 and 350 points, PIN entry uses 560, and larger forms use 500–690. A `drawerHeight` preference updates the enclosing drawer when a navigation destination or form state changes. Appearance and App lock therefore shrink inside Settings; returning restores Settings' height. Medicine search shrinks after choosing a product. Reading validation and model downloads request extra room when needed.

Topics, interaction results, and visit medicine changes measure their padded content and add space for navigation and the panel's margins. This avoids a fixed tall drawer when there is only one short result. Baseline heights scale with Dynamic Type; measured heights already include the active font sizes and are not scaled twice. Both are capped below the window's top safe area. Long content remains scrollable. Window bounds are read from the containing UIKit window and refreshed when they change, including rotation; no global screen-size assumption is used.

The existing privacy curtain still covers modal content when the app becomes inactive. App locking removes the underlying root and its drawers. In landscape, Harbour uses the explicitly inset compatibility panel on every iOS version, because system compact-height presentation can otherwise extend to the screen edge. The decision uses both the current window aspect ratio and vertical size class. It changes modifier values on a stable view hierarchy so rotating a drawer preserves its draft and navigation state. System share sheets, file importers, permission dialogs, alerts, and picker popovers retain their operating-system presentation.

## How to change it

Apply `.floatingDrawer(height:)` to the complete content passed to an app-owned `.sheet`, outside its `NavigationStack`. Keep `dismiss()` actions inside that stack; don't replace native sheet dismissal with unrelated navigation state.

Use `.drawerHeight(...)` on a destination to override its enclosing drawer's height. Add `.measuredDrawerHeight()` to a **non-lazy, intrinsically sized content stack inside** a scroll view for variable-length results. Do not measure a `Form`, `List`, `TextEditor`, or the enclosing scroll view itself: they fill the proposed height and can create a sizing feedback loop. `chrome` adjusts the measurement allowance when a destination's header changes.

The `--verify-drawers` UI-test launch argument exposes a transparent accessibility bounds probe behind the panel. It avoids measuring a scroll view's off-screen accessibility descendants as if they were the visible drawer; ordinary app launches have no probe.

`HarbourDrawerTests` checks compact heights, inset panel bounds, nested PIN entry, navigation back to Settings, reading entry/save with the keyboard, medicine confirmation gating, topic selection, and light/dark appearance. Inspect exported screenshots as well as test results; panel geometry alone cannot establish visual quality.

## Configuration

The compatibility panel defines 8-point horizontal padding, a 12-point bottom gap, and a 16-point content bottom inset. iOS 26 sheets use their native surrounding inset and adaptive corner shape instead, with a uniform `ConcentricRectangle` clip and 20-point bottom safe-area padding to keep content inside the rounded outline. The viewport cap reserves the top safe area plus 60 points. Baseline screen heights are supplied at presentation sites in `HarbourApp.swift`, `ChatView.swift`, `AppLock.swift`, and `VisitsView.swift`.

After adding a new top-level app source, regenerate the Xcode project with `python3 scripts/generate-project.py`.

## Dependencies

SwiftUI sheet APIs (iOS 18 minimum), UIKit window geometry, adaptive `Palette` colours, and the existing navigation and app-lock lifecycle. No third-party presentation library or private API is used.
