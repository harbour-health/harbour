import XCTest
@testable import HarbourCore

@MainActor private final class RequestSignal {
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

@MainActor private final class RequestBarrier {
    let entered = RequestSignal()
    private let released = RequestSignal()
    func wait() async { entered.signal(); await released.wait() }
    func release() { released.signal() }
}

@MainActor final class ChatRequestLifecycleTests: XCTestCase {
    func testCancellationBlocksNewAdmissionAndEffectsUntilOutstandingWorkReturns() async throws {
        let requests = ChatRequestLifecycle(), work = RequestBarrier(), drained = RequestSignal()
        var effects = 0, starts = 0, completions: [Bool] = [], observedCancellation = false
        let id = try XCTUnwrap(requests.start(operation: { id in
            starts += 1
            await work.wait() // Deliberately does not automatically resume on cancel.
            observedCancellation = Task.isCancelled
            if requests.canApplyResult(for: id) && !Task.isCancelled { effects += 1 }
        }, onCompletion: { accepted in completions.append(accepted); drained.signal() }))
        await work.entered.wait()
        XCTAssertEqual(requests.state, .running(id))
        XCTAssertTrue(requests.cancel())
        XCTAssertEqual(requests.state, .cancelling(id))
        XCTAssertFalse(requests.canApplyResult(for: id))
        XCTAssertNil(requests.start(operation: { _ in starts += 1 }))
        XCTAssertEqual(starts, 1)
        XCTAssertTrue(requests.state.isBusy)
        XCTAssertTrue(completions.isEmpty)
        work.release(); await drained.wait()
        XCTAssertTrue(observedCancellation)
        XCTAssertEqual(effects, 0)
        XCTAssertEqual(completions, [false])
        XCTAssertEqual(requests.state, .idle)
    }

    func testStopBeforeScheduledTaskStartsSkipsStartupButWaitsForTaskCleanup() async throws {
        let requests = ChatRequestLifecycle(), drained = RequestSignal()
        var started = false, completion: Bool?
        let id = try XCTUnwrap(requests.start(operation: { _ in started = true }, onCompletion: {
            completion = $0; drained.signal()
        }))
        // No yield between admission and Stop: the queued operation has not begun.
        requests.cancel()
        XCTAssertEqual(requests.state, .cancelling(id))
        XCTAssertNil(requests.start(operation: { _ in XCTFail("A retry started before drain") }))
        await drained.wait()
        XCTAssertFalse(started)
        XCTAssertEqual(completion, false)
        XCTAssertEqual(requests.state, .idle)
    }

    func testRepeatedStopBackgroundAndDisappearCancellationIsIdempotent() async throws {
        let requests = ChatRequestLifecycle(), startup = RequestBarrier(), drained = RequestSignal()
        var completionCount = 0
        let id = try XCTUnwrap(requests.start(operation: { _ in await startup.wait() }, onCompletion: { _ in
            completionCount += 1; drained.signal()
        }))
        await startup.entered.wait()
        XCTAssertTrue(requests.cancel())
        XCTAssertFalse(requests.cancel())
        XCTAssertFalse(requests.cancel())
        XCTAssertEqual(requests.state, .cancelling(id))
        startup.release(); await drained.wait()
        XCTAssertEqual(completionCount, 1)
        XCTAssertFalse(requests.cancel())
        XCTAssertEqual(requests.state, .idle)
    }

    func testSynchronousStateObserverCanCancelBeforeStartup() async throws {
        let requests = ChatRequestLifecycle(), drained = RequestSignal()
        var started = false, accepted: Bool?
        requests.onStateChange = { state in
            if case .running = state { requests.cancel() }
        }
        defer { requests.onStateChange = nil }
        XCTAssertNotNil(requests.start(operation: { _ in started = true }, onCompletion: {
            accepted = $0; drained.signal()
        }))
        XCTAssertTrue(requests.state.isCancelling)
        await drained.wait()
        XCTAssertFalse(started)
        XCTAssertEqual(accepted, false)
        XCTAssertEqual(requests.state, .idle)
    }

    func testNormalCompletionPublishesReadinessAndAllowsRetry() async throws {
        let requests = ChatRequestLifecycle(), work = RequestBarrier(), firstDone = RequestSignal(), secondDone = RequestSignal()
        var states: [ChatRequestLifecycle.State] = [], completions: [Bool] = []
        requests.onStateChange = { states.append($0) }
        let first = try XCTUnwrap(requests.start(operation: { _ in await work.wait() }, onCompletion: {
            completions.append($0); firstDone.signal()
        }))
        await work.entered.wait()
        XCTAssertNil(requests.start(operation: { _ in XCTFail("Overlapping work admitted") }))
        work.release(); await firstDone.wait()
        XCTAssertEqual(requests.state, .idle)
        let second = try XCTUnwrap(requests.start(operation: { _ in }, onCompletion: {
            completions.append($0); secondDone.signal()
        }))
        await secondDone.wait()
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(states, [.running(first), .idle, .running(second), .idle])
        XCTAssertEqual(completions, [true, true])
    }

    func testCancelledTokenCannotApplyAfterNewChatAndNextRequest() async throws {
        let requests = ChatRequestLifecycle(), firstWork = RequestBarrier(), secondWork = RequestBarrier()
        let firstDone = RequestSignal(), secondDone = RequestSignal()
        let first = try XCTUnwrap(requests.start(operation: { _ in await firstWork.wait() }, onCompletion: { _ in firstDone.signal() }))
        await firstWork.entered.wait(); requests.cancel()
        XCTAssertFalse(requests.canApplyResult(for: first))
        firstWork.release(); await firstDone.wait()
        let second = try XCTUnwrap(requests.start(operation: { _ in await secondWork.wait() }, onCompletion: { _ in secondDone.signal() }))
        await secondWork.entered.wait()
        XCTAssertFalse(requests.canApplyResult(for: first))
        XCTAssertTrue(requests.canApplyResult(for: second))
        secondWork.release(); await secondDone.wait()
        XCTAssertFalse(requests.canApplyResult(for: second))
    }

    func testHandledGenerationErrorStillDrainsAndAllowsNextRequest() async throws {
        enum Failure: Error { case generation }
        let requests = ChatRequestLifecycle(), work = RequestBarrier(), failed = RequestSignal(), retried = RequestSignal()
        var errorWasHandled = false
        requests.start(operation: { _ in
            do { await work.wait(); throw Failure.generation }
            catch { errorWasHandled = true }
        }, onCompletion: { _ in failed.signal() })
        await work.entered.wait(); work.release(); await failed.wait()
        XCTAssertTrue(errorWasHandled)
        XCTAssertEqual(requests.state, .idle)
        XCTAssertNotNil(requests.start(operation: { _ in }, onCompletion: { _ in retried.signal() }))
        await retried.wait()
        XCTAssertEqual(requests.state, .idle)
    }

    func testSharedOwnerBlocksReplacementViewAdmissionAndPublishesDrain() async throws {
        // ModelManager owns this same coordinator across ChatView recreation.
        let owner = ChatRequestLifecycle(), work = RequestBarrier(), drained = RequestSignal()
        owner.start(operation: { _ in await work.wait() }, onCompletion: { _ in drained.signal() })
        await work.entered.wait(); owner.cancel()
        let replacementViewOwner = owner
        var replacementObserved: [ChatRequestLifecycle.State] = []
        owner.onStateChange = { replacementObserved.append($0) }
        XCTAssertTrue(replacementViewOwner.state.isCancelling)
        XCTAssertNil(replacementViewOwner.start(operation: { _ in XCTFail("Replacement view bypassed cancellation") }))
        work.release(); await drained.wait()
        XCTAssertEqual(replacementObserved, [.idle])
        XCTAssertFalse(replacementViewOwner.state.isBusy)
    }

    func testCompletionCanStartNextRequestWithoutOldCleanupClearingIt() async throws {
        let requests = ChatRequestLifecycle(), nextWork = RequestBarrier(), allDone = RequestSignal()
        var nextID: UUID?
        requests.start(operation: { _ in }, onCompletion: { accepted in
            XCTAssertTrue(accepted)
            nextID = requests.start(operation: { _ in await nextWork.wait() }, onCompletion: { _ in allDone.signal() })
        })
        await nextWork.entered.wait()
        let id = try XCTUnwrap(nextID)
        XCTAssertEqual(requests.state, .running(id))
        nextWork.release(); await allDone.wait()
        XCTAssertEqual(requests.state, .idle)
    }

    func testTaskOwnershipIsReleasedAfterCancellationDrains() async throws {
        var owner: ChatRequestLifecycle? = ChatRequestLifecycle()
        weak var releasedOwner = owner
        let work = RequestBarrier(), drained = RequestSignal()
        owner?.start(operation: { _ in await work.wait() }, onCompletion: { _ in drained.signal() })
        await work.entered.wait()
        owner?.cancel(); owner = nil
        XCTAssertNotNil(releasedOwner) // Outstanding task deliberately retains ownership.
        work.release(); await drained.wait(); await Task.yield()
        XCTAssertNil(releasedOwner)
    }
}
