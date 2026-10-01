# Navigation and actions

## What it is

A shared set of navigation and action conventions for the four main destinations, record forms, and floating drawers. The controls have stable locations, consistent touch targets, and one visual priority per workflow.

## How it works

| Context | Leading action | Trailing action |
| --- | --- | --- |
| Today and Records browser | Native title | Settings |
| Chat | New chat | Settings |
| Visits | Add notes | Settings |
| Record lists | Native Back | Add record |
| Saved visit or recorder | Native Back | Visit options, when applicable |
| Editing drawers | Cancel | Save or Review |
| Read-only drawers | Native Back, when pushed | Done |

Settings is accessible directly from every main destination. Record lists and visit destinations hide their parent's root actions so navigation does not accumulate controls. Chat's title remains centred; its draft survives opening Settings or Models. Models uses its own Done action only when opened directly from Chat. When pushed from Settings, native Back returns to Settings and the inherited Done action closes that drawer.

The chat composer keeps the model selector directly left of the microphone. `ViewThatFits` prefers the complete model name and effort, then uses the shorter Small/Balanced label when space is tight. Its final layout stacks model and effort within the same button rather than reducing the microphone/send targets or pushing them off-screen. The accessible value always includes the full model title and effort.

Today groups the reading summary and two equal shortcuts with the existing 14-point gap. It omits the duplicate latest-reading row and shows the Readings section only when other reading types exist. Interactions, visits, and appointment notes are separate whole-row actions with dividers. Recent symptoms have a chevron to show navigation.

Visits' Add notes action opens the editor immediately. A new visit is held in view state until Save succeeds; Cancel creates no empty history entry. Blank new transcripts cannot be saved. Existing transcript editing retains its previous persistence and summary invalidation behaviour. Saving new notes opens their detail screen.

Primary in-content actions use a dark capsule in light mode and a light capsule in dark mode. Secondary actions use the neutral surface. Preparing a first summary is primary. Once medicine changes exist, Review is primary and Refresh summary is secondary. Medicine confirmations and emergency choices share a trailing selection indicator, keeping multiline text aligned. Save remains gated by the existing acknowledgements.

Appointment note is a selectable, generated preview of the saved records. It has Copy and Share actions below the scrollable text and Done at the upper right. It no longer presents an editable text field whose changes would be discarded silently.

## How to change it

`Harbour/InterfaceComponents.swift` contains `AppLayout`, `ToolbarGlyph`, `SelectionIndicator`, and `ActionButtonStyle`. Use these for new peer controls. Keep icon-only controls' accessible labels on the Button, rather than the decorative glyph. The selection indicator is hidden from accessibility; the parent button reports selection or its value.

`HarbourApp.swift`, `ChatView.swift`, `RecordsView.swift`, and `VisitsView.swift` own destination toolbars. `ModelsView.standalone` distinguishes an independent modal from a pushed destination. `VisitTranscriptEditor.isNew` enables saving an unsaved draft, and its `onSave` callback opens the saved visit. Do not create records merely to navigate to an editor.

## Configuration

`AppLayout` defines a 24-point content inset, 28-point section spacing, 44-point icon target, and 760-point content width limit. In-content capsule actions have 14-point vertical padding and a minimum 24-point label area. System text styles grow with Dynamic Type; shared press animation observes Reduce Motion. Floating drawer heights remain configured separately in [Floating drawers](floating-drawers.md).

## Dependencies

SwiftUI, SF Symbols, the semantic `Palette`, and the existing `AppStore` persistence methods. No new external dependencies or remote assets.
