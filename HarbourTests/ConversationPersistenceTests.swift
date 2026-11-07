import XCTest
import AVFoundation
import HarbourCore
@testable import Harbour

@MainActor final class ConversationPersistenceTests: XCTestCase {
    func testLaunchStartsFreshAndKeepsPreviousChatAvailable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = AppStore(folder: folder)
        first.append(ChatMessage(isUser: true, text: "A previous conversation"))
        first.append(ChatMessage(text: "A model response"))
        let reloaded = AppStore(folder: folder)
        XCTAssertTrue(reloaded.messages.isEmpty)
        XCTAssertEqual(reloaded.conversations.count, 1)
        let saved = try XCTUnwrap(reloaded.conversations.first)
        reloaded.openConversation(saved.id)
        XCTAssertEqual(reloaded.messages.count, 2)
        reloaded.newChat()
        XCTAssertEqual(reloaded.conversations.count, 1, "Reopening must not duplicate saved conversations")
    }
    func testToolResultIsPendingUntilModelNarratesAndCanBeRetried() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(folder: folder)
        store.appendToolEvent(ChatMessage(text: "an actual tool result"), status: "requires_confirmation")
        let pending = try XCTUnwrap(store.messages.last)
        XCTAssertEqual(pending.text, "")
        XCTAssertTrue(pending.toolPayload?.contains("requires_confirmation") == true)
        store.failToolEvent(pending.id)
        XCTAssertEqual(store.messages.last?.toolFailed, true)
        store.retryToolEvent(pending.id)
        store.finishToolEvent(pending.id, text: "Actual model-generated text")
        XCTAssertEqual(store.messages.last?.text, "Actual model-generated text")
    }
    func testReviewCommitsOutcomeAtomicallyAndRejectsStaleNarration() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(folder: folder)
        store.appendToolEvent(ChatMessage(text: "review reading"), status: "requires_confirmation")
        let draft = try XCTUnwrap(store.messages.last)
        store.add(Reading(kind: .heartRate, value: "72"))
        XCTAssertTrue(store.messages.last?.toolPayload?.hasPrefix("status=completed\n") == true)
        store.finishToolEvent(draft.id, text: "stale draft response", expectedPayload: draft.toolPayload)
        XCTAssertEqual(store.messages.last?.text, "")
        store.closeToolDraft()
        XCTAssertTrue(store.messages.last?.toolPayload?.hasPrefix("status=completed\n") == true)
    }
    func testClosingUnchangedReviewRecordsCancellation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(folder: folder)
        store.appendToolEvent(ChatMessage(text: "review reading"), status: "requires_confirmation")
        store.closeToolDraft()
        XCTAssertTrue(store.records.readings.isEmpty)
        XCTAssertTrue(store.messages.last?.toolPayload?.hasPrefix("status=cancelled\n") == true)
    }
    func testVisitSummaryUsesBalancedWithoutChangingChatSelection() {
        let models = ModelManager(); let previous = models.selection
        defer { models.selection = previous }
        models.selection = .small
        XCTAssertEqual(models.visitModel, .balanced)
        XCTAssertEqual(models.selection, .small)
    }
    func testActiveAudioProtectionIsRestoredWhenWriterCloses() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: path) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let writer = try VisitAudioWriter(url: path, format: format, speech: { _ in }, meter: { _ in }, failure: { _ in XCTFail("Audio write failed") })
        let activeProtection = try FileManager.default.attributesOfItem(atPath: path.path)[.protectionKey] as? String
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
        buffer.frameLength = 1600
        if let samples = buffer.floatChannelData { samples[0].initialize(repeating: 0, count: 1600) }
        writer.append(buffer); writer.close()
        XCTAssertGreaterThan(try Data(contentsOf: path).count, 0)
        let closedProtection = try FileManager.default.attributesOfItem(atPath: path.path)[.protectionKey] as? String
        #if targetEnvironment(simulator)
        if activeProtection == nil && closedProtection == nil { throw XCTSkip("Simulator does not expose iOS file-protection attributes. Audio writing passed; encryption policy requires a physical device.") }
        #endif
        XCTAssertEqual(activeProtection, FileProtectionType.completeUnlessOpen.rawValue)
        XCTAssertEqual(closedProtection, FileProtectionType.complete.rawValue)
    }
}
