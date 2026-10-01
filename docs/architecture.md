# Architecture

## What it is

Harbour is a SwiftUI iOS application. It ports the browser prototype's confirmed-record workflow into native UI and keeps health rules outside model output.

## How it works

`HarbourCore` is a platform-independent Swift package containing Codable records, the explicit product catalog, fixed symptom guidance, interaction lookup, reading validation, tool parsing, and evaluation fixtures. `HarbourRuntime` owns llama.cpp behind an actor; C pointers never leave that actor. `Harbour` contains UI, persistence, downloads, and Apple platform adapters.

A chat message first goes through the emergency phrase check. A matching phrase displays the fixed emergency guidance immediately, before downloading or running a model. Other messages enter a bounded Qwen prompt with an optional topic hint. Tool routing supplies an exact JSON grammar containing only currently allowed, source-valid tool names and an empty argument. Eligibility uses the same validator against current records before generation; the selected action is validated again afterward. For example, a list request without a measurement does not expose the measurement-writing tool. Clarification remains available. Title and visit generation omit this constraint. The model selects a JSON tool; `ToolPlanner` restricts the tool to the current message's allowed set, ignores model-supplied clinical facts, and extracts products/numbers from the original text. Known formatting aliases are normalised. An unknown or malformed tool is rejected.

Symptom, medicine, and reading calls open editable confirmation sheets. Interaction checks produce a sourced result without adding medicines to the list. Removal and full reset require confirmation. Generated prose cannot supply treatment or reassurance: `reply` currently produces a fixed capabilities/clarification response. The small model can choose the wrong tool; the records UI remains independently usable.

`AppStore` stores confirmed records and chat together in Application Support as versioned JSON, atomically written with complete file protection. A failed save leaves the visible state unchanged and surfaces an error. A failed decode blocks writes; a confirmed reset preserves the unreadable file before creating a new archive. There is no iCloud sync. iOS backup may include the protected record archive; downloaded weights are excluded from backup.

`LockShell` gates the navigation tree using the optional [app lock](app-lock.md), whose credential verifier lives separately in Keychain. Backgrounding replaces protected navigation and revokes pending authentication. A scene-level privacy curtain also covers presented sheets. This gate does not add PIN-derived archive encryption.

Records category navigation uses an optional in-memory destination inside its native navigation stack. The floating dock overlays the tab container; child destinations consume `floatingDockClearance` for scrolling or fixed-composer placement. Returning to the browser clears that destination; no record schema change is needed for this navigation redesign.

The optional archive field `chatTitle` stores [locally generated conversation metadata](chat-titles.md). Its absence in older version-1 archives uses a heading derived from the first message. Tool execution and emergency handling precede naming.

JSON export uses ISO-8601 dates. JSON import accepts legacy records or the version-2 care backup, validates every record and care item before an atomic merge, remaps matching medicine IDs, and rebuilds medicine ingredient mappings from the catalog. File-supplied ingredient claims are not trusted. Unknown names remain unconfirmed. Appointment notes use recorded facts and saved, editable questions. Visit audio and chats are excluded from the care backup.

The optional archive field `visits` and UUID-named AAC files store [doctor visits](doctor-visits.md). Recording checkpoints preserve recoverable partial transcripts. Extracted facts are exact quotes; medicine changes enter a separate confirmation flow and atomically update both medicines and the visit audit. Missing optional visit data preserves compatibility with older archives.

The optional `care` archive field contains reminders, medicine schedules, dose history, appointment questions, and dated medicine events. Dose logs retain a name, local time, and time-zone snapshot so later schedule changes do not erase their provenance. Local notifications reconcile serially from the latest confirmed snapshot. Label OCR and chat mutations enter the same confirmation editors. Live voice turns use the existing chat pipeline, with local speech recognition and system speech playback; interruptions and backgrounding stop audio ownership. See [Care actions](care-actions.md) and [Voice conversation](voice-conversation.md).

## How to change it

Add or alter tools in `HarbourCore/ToolPlanner.swift`, then update `ChatView.execute`, fixtures, and tests. Introduce a new record schema with an explicit migration; do not silently decode incompatible data as empty. Replace the narrow medication fixture with a versioned, clinically governed dataset before making broader interaction claims. The current negation-aware phrase matcher has limited coverage; a negative result never rules out an emergency.

When adding Swift app files, regenerate the project with `scripts/generate-project.py`. Changes to build settings belong in that generator. Package files are discovered by SwiftPM without regeneration.

## Configuration

`Records.schemaVersion` and `Archive.version` are currently `1`. Import size is limited to 5 MB. Prompt context is 2,048 tokens. The bundle identifier and iOS 18 target are in the project generator. Model choice and effort are stored in UserDefaults; records are not.

## Dependencies

SwiftUI, Foundation, UIKit share sheets, `HarbourCore`, and the local `HarbourRuntime` package. Platform services and model setup are documented separately. Reference: [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/).
