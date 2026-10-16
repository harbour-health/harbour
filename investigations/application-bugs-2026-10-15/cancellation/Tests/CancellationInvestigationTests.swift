import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HarbourCore
import HarbourRuntime
import llama
@testable import CancellationSubject

@MainActor final class CancellationInvestigationTests: XCTestCase {
    private func fixture(installed: Bool) throws -> (ModelManager, UserDefaults, URL, String) {
        let name = "cancellation-investigation-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let manager = ModelManager(defaults: defaults, directory: directory)
        manager.selection = .small
        if installed { try installPlaceholder(manager) }
        return (manager, defaults, directory, name)
    }
    private func installPlaceholder(_ manager: ModelManager) throws {
        // Marker/file existence intentionally selects the already-installed path.
        // The C ABI double never loads these bytes as model weights.
        try Data("NOT MODEL WEIGHTS".utf8).write(to: manager.file(.small))
        try Data("TEST ONLY".utf8).write(to: manager.file(.small).appendingPathExtension("verified"))
    }
    private func decision(_ manager: ModelManager) async throws -> ToolDecision {
        try await manager.chatDecision("Show my medications.", records: Evaluation.records)
    }
    private func assertBusy(_ manager: ModelManager, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await decision(manager); XCTFail("Overlapping request unexpectedly entered runtime", file: file, line: line) }
        catch {
            let error = error as NSError
            XCTAssertEqual(error.domain, "Inference", file: file, line: line)
            XCTAssertEqual(error.code, 1, file: file, line: line)
            XCTAssertTrue(manager.generating, file: file, line: line)
        }
    }
    func testStopDuringActualSwiftRuntimeCDecodeKeepsManagerBusyUntilDecodeReturns() async throws {
        let (manager, defaults, directory, name) = try fixture(installed: true)
        defer { llama_test_release_decode(); defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        llama_test_arm_decode_barrier()
        let first = Task { try await self.decision(manager) }
        let entered = await Task.detached { llama_test_wait_decode_entered(5000) }.value
        guard entered else { first.cancel(); return XCTFail("Real LocalModel did not reach the controlled C decode") }
        XCTAssertTrue(manager.generating)
        first.cancel()
        // No async yield has occurred since cancelling; actual C decode is held.
        XCTAssertTrue(manager.generating)
        await assertBusy(manager)
        XCTAssertEqual(llama_test_decode_calls(), 1)
        llama_test_release_decode()
        switch await first.result {
        case .success: XCTFail("Cancellation should be observed by real LocalModel after C returns")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(manager.generating)
        // Positive control: once the cancelled request drains, real manager accepts retry.
        let retry = try await decision(manager)
        XCTAssertEqual(retry.tool, .listMedicines)
        XCTAssertFalse(manager.generating)
    }
    func testNormalCompletionClearsBusyAndAllowsNextRequest() async throws {
        let (manager, defaults, directory, name) = try fixture(installed: true)
        defer { llama_test_release_decode(); defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        llama_test_arm_decode_barrier()
        let first = Task { try await self.decision(manager) }
        let entered = await Task.detached { llama_test_wait_decode_entered(5000) }.value
        guard entered else { first.cancel(); return XCTFail("Decode entry barrier timeout") }
        await assertBusy(manager)
        llama_test_release_decode()
        let completed = try await first.value
        XCTAssertEqual(completed.tool, .listMedicines)
        XCTAssertFalse(manager.generating)
        let second = try await decision(manager)
        XCTAssertEqual(second.tool, .listMedicines)
    }
    func testRealURLSessionDownloadCancellationHasAnImmediateRetryBusyWindow() async throws {
        let (manager, defaults, directory, name) = try fixture(installed: false)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        let start = expectation(description: "Actual URLSessionDownloadTask reached the held URLProtocol")
        DownloadBarrier.reset { start.fulfill() }
        let first = Task { try await self.decision(manager) }
        await fulfillment(of: [start], timeout: 5)
        XCTAssertEqual(DownloadBarrier.counts.starts, 1)
        XCTAssertTrue(manager.generating)
        XCTAssertEqual(manager.downloading, .small)
        first.cancel()
        // Delegate queue is .main: cancellation completion cannot clear the
        // manager's defer within this still-running MainActor turn.
        XCTAssertTrue(manager.generating)
        await assertBusy(manager)
        switch await first.result {
        case .success: XCTFail("The held download must not complete successfully")
        case .failure(let error):
            let native = error as NSError
            XCTAssertTrue(error is CancellationError || (native.domain == NSURLErrorDomain && native.code == NSURLErrorCancelled))
        }
        XCTAssertFalse(manager.generating)
        XCTAssertNil(manager.downloading)
        XCTAssertEqual(DownloadBarrier.counts.starts, 1)
        XCTAssertEqual(DownloadBarrier.counts.stops, 1)
        try installPlaceholder(manager)
        let retry = try await decision(manager)
        XCTAssertEqual(retry.tool, .listMedicines)
    }
    func testExactChatViewReferenceAdvertisesReadySynchronouslyOnStop() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ChatView.reference.swift", withExtension: "txt"))
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("private func cancel() { voiceMode = false; operationID = UUID(); task?.cancel(); task = nil; busy = false; voice.stop() }"))
        XCTAssertTrue(source.contains("Button { busy ? cancel() : send() }"))
        XCTAssertTrue(source.contains(".disabled(!busy && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)"))
        // Source-contract check only. This is deliberately NOT a SwiftUI/UI event test.
    }
}
