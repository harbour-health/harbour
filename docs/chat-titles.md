# Chat titles

## What it is

Chat starts with “New chat” and receives a short title from the selected local model after its first message. The title persists with the conversation.

## How it works

The first user message immediately supplies a six-word, 60-character fallback heading. After the normal validated tool response, a separate local inference asks for a neutral JSON title. It receives at most 500 characters of the first message, JSON-encoded with ChatML delimiter escaping. English retains its 48-token output cap. Canadian French uses a French instruction, a 96-token cap, and `TitleOutputGrammar` to constrain output to one `title` key with 1–60 escaped JSON character units. The prompt contains no example title to copy. Title generation is serialized with the tool request rather than competing for the runtime.

The grammar controls the response structure, not its language or meaning. Decoded validation remains necessary, and a short French title still needs actual model verification. French prompt experiments exposed both mixed-language titles and copying of a literal example; grammar permits the key without putting a candidate title in the prompt.

Only a nonempty, single-line title of at most 60 characters and eight words is accepted. This metadata never enters tool validation or executes an action. Errors or invalid output retain the fallback. Deterministic emergency guidance appears immediately and skips title inference; naming never delays the emergency response or triggers a download for it.

The operation ID, cancellation state, and first-message UUID must still match before persisting a generated title. New chat clears both the messages and title. Leaving chat or locking the app cancels the task. If cancelled after the response, the response remains and the fallback title is used. The optional `Archive.chatTitle` field decodes older archives without a schema-version change. Record export still contains records only.

## How to change it

`ModelManager.title(for:)` owns the title prompt and validation; `ChatView.send` schedules it after tool handling; `AppStore.chatTitle`, `nameChat`, and `newChat` own fallback, persistence, and reset. `HarbourRuntime/TitleOutputGrammar.swift` owns the French output grammar, with regression cases in `TitleOutputGrammarTests.swift`. Keep titles separate from clinical text and action selection. If title generation moves to a background task, add explicit runtime scheduling so it cannot collide with the next message.

`HarbourDashboardTests` uses actual local Qwen inference to check that the result differs from the fallback, survives relaunch, and resets to “New chat.” It also verifies equal shortcut dimensions, absence of the native labelled tab bar, and that the model selector sits above the dock and remains tappable.

## Configuration

The title uses the model resolved by the existing model selector. Its fixed language-specific cap is independent of the user's tool-routing effort setting. `ModelManager.generate` accepts either allowed tool names or an explicit response grammar, never both. `TitleOutputGrammar.maximumCharacters` bounds French JSON string content; the app also checks the decoded title. Context and model download verification remain controlled by the normal runtime. No network title service is used.

## Dependencies

`ModelManager`, `HarbourRuntime`, the installed Qwen model, `AppStore` protected archive, and SwiftUI's navigation heading. It adds no package or remote dependency.
