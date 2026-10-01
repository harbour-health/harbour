import XCTest
@testable import HarbourCore

final class SpeechVoiceSelectionTests: XCTestCase {
    private func voice(_ id: String, _ language: String, _ quality: Int) -> SpeechVoiceCandidate {
        SpeechVoiceCandidate(identifier: id, name: id, language: language, quality: quality)
    }
    func testPremiumSameLanguageBeatsCompactCanadianVoice() {
        let voices = [voice("compact", "en-CA", 1), voice("enhanced", "en-CA", 2), voice("premium", "en-US", 3), voice("french", "fr-CA", 3)]
        XCTAssertEqual(SpeechVoiceSelection.selected(voices, locale: "en-CA", preferredIdentifier: "")?.identifier, "premium")
    }
    func testCanadianVoiceWinsQualityTieAndOrderingIsStable() {
        let voices = [voice("z", "fr-FR", 3), voice("b", "fr-CA", 3), voice("a", "fr-CA", 3)]
        XCTAssertEqual(SpeechVoiceSelection.ranked(voices, locale: "fr-CA").map(\.identifier), ["a", "b", "z"])
        XCTAssertEqual(SpeechVoiceSelection.ranked(voices.reversed(), locale: "fr-CA").map(\.identifier), ["a", "b", "z"])
    }
    func testExplicitChoiceIsRespectedAndRemovedVoiceFallsBackWithinLanguage() {
        let voices = [voice("saved", "fr-CA", 1), voice("better", "fr-FR", 3), voice("english", "en-CA", 3)]
        XCTAssertEqual(SpeechVoiceSelection.selected(voices, locale: "fr-CA", preferredIdentifier: "saved")?.identifier, "saved")
        XCTAssertEqual(SpeechVoiceSelection.selected(voices, locale: "fr-CA", preferredIdentifier: "removed")?.identifier, "better")
        XCTAssertEqual(SpeechVoiceSelection.selected(voices, locale: "fr-CA", preferredIdentifier: "english")?.identifier, "better")
        XCTAssertNil(SpeechVoiceSelection.selected([voice("english", "en-CA", 3)], locale: "fr-CA", preferredIdentifier: ""))
    }
    func testSpeedDefaultsAndInvalidSavedValuesAreBounded() {
        XCTAssertEqual(SpeechVoiceSelection.speed(nil), 1)
        XCTAssertEqual(SpeechVoiceSelection.speed(.nan), 1)
        XCTAssertEqual(SpeechVoiceSelection.speed(.infinity), 1)
        XCTAssertEqual(SpeechVoiceSelection.speed(0), 0.8)
        XCTAssertEqual(SpeechVoiceSelection.speed(100), 1.3)
        XCTAssertEqual(SpeechVoiceSelection.speed(1.1), 1.1)
    }
}
