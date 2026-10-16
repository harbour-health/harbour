# Stop / immediate Send investigation

This is a standalone XCTest package. It does not change the app, download weights,
run inference or reproduce an evaluation grade.

Run from the repository root on Linux or macOS with Swift6:

```text
swift test --package-path build/application-bug-investigation-20261015/cancellation --filter CancellationInvestigationTests
```

Keep the package at that repository-relative location: its only package dependency
is the actual repository `HarbourCore`. Capture the Swift version, full build/test
output and exit code. Do not run with parallel tests; the controlled C barrier is
shared process state. A build failure or a Foundation implementation limitation
is not evidence that the app bug was reproduced.

The four tests exercise actual copied ModelManager, ModelDownload and LocalModel
Swift methods. LocalModel's four source files are byte-exact. ModelManager has
only an additive conditional FoundationNetworking import, whose exact bytes are
recorded in preparation.json. No manager/control-flow body is copied into a
second implementation.

The C `llama` ABI provider deliberately supplies a synchronous, controllable
`llama_decode` call. It neither loads the placeholder file nor implements a model.
This proves the real Swift caller/cancellation path when the underlying C call
has not returned; it does not establish real-device cancellation latency or model
output behavior. The JSON returned by this test double is a fixed list request
used only to confirm that the actual manager accepts a new request after draining.

The download test uses real Foundation URLSessionDownloadTask, real task
cancellation and the actual ModelDownload URLSession delegate. A configuration
facade supplies a held URLProtocol so no external request is sent. Success is
never delivered, and hash verification must never be reached. Linux's CryptoKit
compile boundary traps if it is reached. On Apple, real CryptoKit and Combine
are used. Linux observation/power-property boundaries are not SwiftUI tests.

The ChatView test checks the exact source reference, not a running SwiftUI view:
Stop clears `busy` synchronously, and the Send button is enabled again. The manager
tests establish whether its actual busy guard remains set during the controlled
cancellation interval. A complete physical UI reproduction is a distinct test,
and must not be claimed from this package alone.

The original claim should therefore be stated conditionally: immediate Send can
hit the manager's still-busy guard while cancellation is outstanding. It is not a
claim that every Stop / Send fails, that an in-flight C decode is preemptible, or
that model quality caused this application lifecycle defect.
