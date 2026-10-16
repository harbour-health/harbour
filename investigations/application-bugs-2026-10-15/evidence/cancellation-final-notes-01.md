# Issue 8: confirmed cancellation lifecycle gap

**Four controlled native XCTest methods passed with zero failures. Actual manager calls can reject an immediate retry while the previous cancellation remains outstanding.** This confirms the lifecycle gap. It does not show that every Stop/Send fails, establish physical tap timing, or measure real-model cancellation latency. No production fix was applied.

Baseline: `5158710fa518816ca14781ca4d7a4c3f459675b8`. [Issue 8](https://github.com/matteopolak/harbour/issues/8).

## Actual code path

- [ChatView Stop](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/Harbour/ChatView.swift#L168) cancels the Task, discards its handle and sets `busy=false` synchronously without awaiting cancellation acknowledgement. The [button](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/Harbour/ChatView.swift#L131) switches back to Send.
- [ModelManager.generate](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/Harbour/ModelManager.swift#L171) keeps `generating=true` until the original call returns or throws through its defer. An intervening call throws NSError domain `Inference`, code 1 before another runtime call.
- [LocalModel](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/HarbourRuntime/Sources/HarbourRuntime/LocalModel.swift#L107) calls `llama_decode` synchronously. Cancellation is checked between C calls/token iterations; Task.cancel does not preempt an in-flight C call.
- If Send reaches the manager while that operation is outstanding, the [new user message is already appended](https://github.com/matteopolak/harbour/blob/5158710fa518816ca14781ca4d7a4c3f459675b8/Harbour/ChatView.swift#L169), and its uncancelled task can display “The model is already working on a request.” This is a retry/lifecycle issue, not an established unauthorized write or record-loss defect.

## Controlled result and controls

The actual manager and runtime Swift methods execute, rather than a copied manager state machine. Eight subject/reference files were independently checked against canonical Git blobs. ModelManager has only a conditional FoundationNetworking import added. Other canonical subjects are exact; earlier working copies differ only in CRLF/LF. The test bodies remain exact to the original prepared tests.

1. A synchronous C `llama_decode` ABI barrier holds the actual LocalModel actor in a C call. Cancelling leaves the real manager busy. Immediate actual chatDecision rejects with `Inference/1`, with no second decode. Releasing the barrier lets the actual cancellation check throw CancellationError; retry then succeeds.
2. Normal-completion control: overlap is rejected while held; completing the call clears the guard and permits the next request. The fixture does not simply leave the manager permanently busy.
3. Real Foundation URLSessionDownloadTask/cancellation/delegate code runs with a held URLProtocol and no HTTP response. Immediate same-MainActor API retry observes the busy window. After cancellation drains, downloading/generating clear and retry succeeds. Exactly one protocol start/stop is asserted.
4. The exact ChatView source-reference test checks Stop's busy reset and Send/Stop wiring. It is not a rendered SwiftUI or UI-event test.

Root's pinned Linux execution exited 0 in 21.7408 seconds including command/build overhead. XCTest reports four methods, zero failures in 0.381 seconds. These are harness timings, not model/device latency. The C provider loads no weights and implements no inference, tokenizer or grammar validation. Its fixed list-medications JSON is only a successful dispatch control. Linux observation/power/CryptoKit boundaries are not Apple UI, Combine or cryptographic tests; the CryptoKit placeholder traps if hashing is reached.

## Limits and retained safety

A physical Stop/Send interaction on iOS was not executed. The decode test establishes the failure conditional on an old call remaining in flight; it does not measure how often a real decode spans the next tap. The download claim is narrower: same-actor API retry before cancellation callback drain. A later physical tap might occur after Foundation has already finished cancellation. Do not describe downloads as inevitably continuing or failing to stop.

Existing cancellation checks before ChatView.execute and the operationID guard still protect against treating stale cancelled results as a new completed action. A later fix can retain a cancelling state or queue retry behind acknowledgement. Simply clearing the manager guard early would remove existing overlap protection and is not justified here.

## Exact evidence and attempt history

- Original preparation: `cancellation/preparation.json`, SHA256 `ace4f18b67ee8adc9146153a3212b9d361dc550a28d018feb11427abf7addc3a`.
- Canonical02 failed before tests because this isolated harness omitted the actual TitleOutputGrammar dependency. Log `cancellation-swift-test-02.log`, SHA256 `d64b65625d87c6b193751a0df1c6f325f63a32a2091b4efd36d5841020fcc37f`, is retained. This was a harness compile failure, not an app-production compile failure.
- Canonical03 adds exact TitleOutputGrammar, canonical SHA256 `88736de8b3ea4acf7014e72c96f7d375cb0c8639b35a20e97b522acc22792a1c`.
- Success log `cancellation-swift-test-03.log`: SHA256 `ee688b33dc98db6fedc44ba8887e84f7b1e60e861a0e80e836d3387803540249`.
- Actual execution `cancellation-execution-03.json`: SHA256 `f7532171c443e2fa1f4f3b9eef87983c5f1086f97bcbc42b8a1effe0e55194b8`.
- Independent source/result binding `cancellation-final-evidence-binding-01.json`: SHA256 `ca14345a097537f8947876ac126b1ae10d1bf97d6a20068dfb2b65624b18aaba`.

The original success log retains the Linux URLProtocol fixture's `UnavailableSendableConformance` warning. Lock-protected counters and test-only use do not make that warning a production finding or a general thread-safety guarantee. No warning or prior failed attempt was removed. The independent reviewer ran no additional test, model, scorer or production edit.

Reproduce from a checkout containing the isolated package and actual HarbourCore dependency:

```text
swift test --package-path build/application-bug-investigation-20261015/cancellation-canonical-03 --jobs 4 --filter CancellationInvestigationTests
```

Run tests serially; preserve stdout/stderr and exit status. The producer records pinned-image/no-network execution and unchanged inputs after the run. This stored-proof review does not independently attest the remote OS or network state.
