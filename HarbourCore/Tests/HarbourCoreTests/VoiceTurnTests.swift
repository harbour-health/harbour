import XCTest
@testable import HarbourCore

final class VoiceTurnTests: XCTestCase {
    func testRevisedRecognitionTextIsDeliveredOnce() {
        var turn = VoiceTurn()
        let id = turn.begin()
        XCTAssertTrue(turn.partial("I have a head", id: id))
        XCTAssertTrue(turn.partial("  I have a headache.\n", id: id))
        XCTAssertEqual(turn.finish(id: id), "I have a headache.")
        XCTAssertTrue(turn.emitted)
        XCTAssertNil(turn.finish(id: id))
        XCTAssertFalse(turn.partial("late revision", id: id))
        XCTAssertEqual(turn.text, "I have a headache.")
    }

    func testRepeatedPartialsDoNotCountAsNewSpeech() {
        var turn = VoiceTurn()
        let id = turn.begin()
        XCTAssertTrue(turn.partial("Show my readings", id: id))
        XCTAssertFalse(turn.partial("Show my readings", id: id))
        XCTAssertFalse(turn.partial("  Show my readings\n", id: id))
        XCTAssertTrue(turn.partial("Show my recent readings", id: id))
        XCTAssertEqual(turn.finish(id: id), "Show my recent readings")
    }

    func testCancellationRejectsLatePartialAndCompletion() {
        var turn = VoiceTurn()
        let id = turn.begin()
        turn.partial("Save a reminder", id: id)
        turn.cancel()
        XCTAssertFalse(turn.partial("Save a reminder tomorrow", id: id))
        XCTAssertNil(turn.finish(id: id))
        XCTAssertEqual(turn.text, "")
        XCTAssertFalse(turn.emitted)
        XCTAssertFalse(turn.partial("callback with cancelled ID", id: turn.id))
    }

    func testOldTurnCannotCompleteOrOverwriteNewTurn() {
        var turn = VoiceTurn()
        let oldID = turn.begin()
        turn.partial("Old message", id: oldID)
        let newID = turn.begin()
        XCTAssertNotEqual(newID, oldID)
        turn.partial("New message", id: newID)
        XCTAssertFalse(turn.partial("Late old message", id: oldID))
        XCTAssertNil(turn.finish(id: oldID))
        XCTAssertEqual(turn.finish(id: newID), "New message")
    }

    func testEmptyFinalizationClosesTurnWithoutAUserMessage() {
        var turn = VoiceTurn()
        let id = turn.begin()
        XCTAssertFalse(turn.partial(" \n\t", id: id))
        XCTAssertNil(turn.finish(id: id))
        XCTAssertFalse(turn.emitted)
        XCTAssertFalse(turn.partial("Speech arriving after empty finalization", id: id))
        XCTAssertNil(turn.finish(id: id))
    }

    func testEmptyRecognitionCorrectionCannotSendPreviousText() {
        var turn = VoiceTurn()
        let id = turn.begin()
        turn.partial("Uncertain partial", id: id)
        XCTAssertTrue(turn.partial("", id: id))
        XCTAssertNil(turn.finish(id: id))
    }

    func testBeginningAfterCompletedTurnResetsTextAndCompletion() {
        var turn = VoiceTurn()
        let oldID = turn.begin()
        turn.partial("First question", id: oldID)
        XCTAssertEqual(turn.finish(id: oldID), "First question")
        let id = turn.begin()
        XCTAssertEqual(turn.text, "")
        XCTAssertFalse(turn.emitted)
        turn.partial("Second question", id: id)
        XCTAssertEqual(turn.finish(id: id), "Second question")
    }
}
