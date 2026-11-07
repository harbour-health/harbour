# Chat request lifecycle

The app keeps ownership of a chat request until its asynchronous work actually returns. Pressing Stop invalidates its results immediately but does not allow a second request to overlap inference or model startup.

## How it works

`ModelManager` owns `ChatRequestLifecycle`, so replacing `ChatView` during locking/background transitions cannot reset a running request to idle. The lifecycle moves from idle to running to cancelling, and returns to idle only after its task drains. A request token protects message, tool and title updates. Composer clearing and user-message insertion happen only after admission succeeds.

`chatRequestState` publishes these transitions to SwiftUI. During cancellation, Stop is disabled and the existing translated waiting message replaces the thinking label. A cancelled completion cannot restart voice playback.

## Changing it

Keep operation admission before composer mutations. Check `canApplyResult(for:)` after asynchronous boundaries and before applying results. Cancellation must remain cooperative: do not publish idle merely because `Task.cancel()` returned. `ChatRequestLifecycleTests` uses controlled suspension to exercise delayed cancellation, immediate Stop, repeated Stop, stale tokens, errors and replacement consumers.

## Configuration and dependencies

No flags or environment variables. Depends on Foundation concurrency, `HarbourCore`, and the app-owned `ModelManager`. It changes request ownership only; model selection, prompts and generated responses are unchanged.
