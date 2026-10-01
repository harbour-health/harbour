# Chat agent

## What it is

An ordinary local-model conversation with optional app tools. Replies are generated text, rather than a fixed capabilities message, and action selection is performed by the model.

## How it works

`ModelManager.chatDecision` first asks the selected Qwen model to choose `reply` or one of the complete tool catalog. The same tools are exposed for every request: there is no keyword-based intent router or pre-generation eligibility filter. A topic chip is optional prompt context, not an action.

When the model chooses `reply`, a second inference uses an ordinary ChatML conversation without a JSON grammar. It runs until the model ends its response or reaches the selected chat output budget. `LocalModel.generate(stopAtJSON: false)` prevents braces in ordinary prose from prematurely ending a response. `ToolPlanner.validate` accepts nonempty generated replies up to 4,000 characters; it does not claim to verify their clinical correctness.

Both stages receive the last six messages, bounded to 500 characters each, and a limited snapshot of confirmed medicines, symptoms, and readings. Rich-result text enters history through `ChatMessage.spokenText`. History is bounded context, not permanent model memory. The complete current request is preserved; a request exceeding the runtime token budget raises an error rather than silently dropping its end. ChatML delimiters are escaped in user content, record data, and topic hints.

Tool JSON still contains an empty argument. Medicine names, measurements, literal times, and dose facts are extracted from the original current message and checked against saved records/catalog data. These are fact validators, not tool-choice rules. Existing mutation validation also rejects explicit negated/hypothetical proposals in English and French. If a proposed tool lacks valid source facts, the conversation path lets the model answer or ask for clarification. A follow-up such as “save that” does not automatically copy an earlier measurement into a record; restating the fact or using its editor is required. Record changes still open their existing confirmation screens. Read-only tools render structured results; no fabricated tool result is added to history.

The pre-inference emergency phrase check is separate from action routing and retains its conditional fixed guidance. Generated prose is governed by the model prompt, not a clinical advice verifier. Small models can select the wrong tool or give inaccurate explanations; changing the conversation implementation does not establish clinical reliability.

## How to change it

Change model-selection instructions/examples in `ToolPlanner.prompt`, conversational instructions in `conversationPrompt`, and the orchestration in `ModelManager.chatDecision`. Add a tool to `Tool`, its prompt description, and `ChatView.execute`; keep its fact validator and confirmation requirements in sync. Do not restore a keyword intent gate to improve a routing score.

`ChatReplyTests` covers generated English/French text, whole-object parsing, source validation, history bounds, and delimiter escaping. `HarbourConversationTests` exercises actual local conversation, follow-up context, and a measurement review in SwiftUI. The model probe and in-app evaluation expose all tools and retain routing failures rather than substituting deterministic selections.

## Configuration

The runtime has a 4,096-token context. Chat reply budgets are Quick 256, Standard 512, and Extended 768 tokens; routing retains the existing 96/160/256 budgets. Titles and visit summaries use their existing explicit budgets/formats. These settings control output length, not reasoning quality. The app language instruction applies to ordinary replies as well as existing generated text.

## Dependencies

`HarbourCore`, `HarbourRuntime`, native llama.cpp, verified local Qwen weights, `AppStore`, and the existing confirmation editors. Voice conversation uses the same pipeline; no prompt or health record is sent to a remote inference service.
