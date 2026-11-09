# Message and review flows

Both interfaces share the same agent and saved records. The diagrams show where model inference, deterministic source checks and human confirmation occur.

```mermaid
flowchart TD
  A[Talk or type] --> B[Original message retained]
  B --> C[Local LLM selects tool]
  C --> D{Read or write?}
  D -->|Read| E[Fetch saved data]
  E --> F[Concise native result in chat]
  D -->|Write| G[Validate against original message and records]
  G -->|Valid| H[Existing editor or confirmation]
  G -->|Missing or ambiguous| I[Ask for clarification]
  H -->|User confirms| J[Persist and update UI]
  H -->|Cancel| K[No record change]
```

```mermaid
flowchart TD
  A[Visit recording] --> B[On-device recognition with limited medicine hints]
  B --> C[Original transcript]
  C --> D[Existing source-grounded summary pipeline]
  D --> E[Summary and proposed medicine changes]
  E --> F[Review each proposal]
  F -->|Accept| G[Shared medicine editor and saved records]
  F -->|Dismiss| H[Records unchanged]
  C --> I[Name search]
  I --> J[Exact dictionary results]
  I --> K[Similar names if exact search is empty]
  K --> L[User chooses candidate and confirms]
```

## How to change it

Update diagrams with tool routing, confirmation or recording changes. Keep original input separate from candidate suggestions. Never add a parallel manual record editor for Simple mode: use the shared one. Visit processing details remain in [summary extraction](visit-summary-extraction.md); name hints are documented in [vocabulary](medication-vocabulary.md).

## Configuration and dependencies

Uses AppStore, ToolPlanner, source validators, ModelManager, Apple Speech and native SwiftUI editors. Interface selection changes entry points, not tool permissions or stored data.
