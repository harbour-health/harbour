import XCTest
import Combine
import HarbourCore
@testable import Harbour

@MainActor final class ChatRequestObservationTests: XCTestCase {
    func testChatCancellationPublishesBusyUntilDrainAcrossViewConsumers() async throws {
        let manager = ModelManager()
        let entered = HostedChatSignal(), release = HostedChatSignal(), drained = HostedChatSignal()
        var observed: [ChatRequestLifecycle.State] = [], accepted: [Bool] = []
        let subscription = manager.$chatRequestState.sink { observed.append($0) }
        defer { subscription.cancel() }
        let id = try XCTUnwrap(manager.chatRequests.start(operation: { _ in
            entered.signal(); await release.wait()
        }, onCompletion: { accepted.append($0); drained.signal() }))
        await entered.wait()
        XCTAssertEqual(manager.chatRequestState, .running(id))
        manager.chatRequests.cancel()
        XCTAssertEqual(manager.chatRequestState, .cancelling(id))
        // A replacement ChatView reads the same app-owned manager, not a new
        // view-local idle flag. No model download/inference participates here.
        let replacementConsumer = manager
        XCTAssertNil(replacementConsumer.chatRequests.start(operation: { _ in XCTFail("Early admission") }))
        await Task.yield()
        XCTAssertTrue(replacementConsumer.chatRequestState.isBusy)
        XCTAssertTrue(replacementConsumer.chatRequestState.isCancelling)
        release.signal(); await drained.wait()
        XCTAssertEqual(manager.chatRequestState, .idle)
        XCTAssertEqual(observed, [.idle, .running(id), .cancelling(id), .idle])
        XCTAssertEqual(accepted, [false])
        XCTAssertFalse(manager.generating)
    }
}

@MainActor private final class HostedChatSignal {
    private var signalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if signalled { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func signal() {
        signalled = true
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

