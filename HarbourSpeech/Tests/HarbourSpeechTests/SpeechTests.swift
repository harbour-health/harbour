import XCTest
@testable import HarbourSpeech

final class SpeechTests: XCTestCase {
    func testOnlyTwoVoicesAndFemaleDefault() {
        XCTAssertEqual(KokoroVoice.allCases.map(\.rawValue), ["af_heart", "am_liam"])
        XCTAssertEqual(KokoroVoice.restored(nil), .female)
        XCTAssertEqual(KokoroVoice.restored("com.apple.voice.old-selection"), .female)
        XCTAssertEqual(KokoroVoice.restored("am_liam"), .male)
    }

    func testChunkingPreservesEveryWordAndDecimalDose() {
        let text = "An example dose is 2.5 mg. This is sample text for voice testing."
        let chunks = KokoroText.chunks(text, maximumCharacters: 30)
        XCTAssertEqual(chunks.joined(separator: " "), text)
        XCTAssertTrue(chunks.first?.contains("2.5 mg.") == true)
    }

    func testNativePronunciationSupportsEnglishAndFrenchNumbers() async throws {
        let english = try await KokoroSpeechEngine.shared.phonemes(
            "Tuesday at three thirty. Take 2.5 milligrams.",
            language: .english
        )
        let french = try await KokoroSpeechEngine.shared.phonemes(
            "Bonjour. Le rendez-vous est mardi à quinze heures.",
            language: .french
        )
        XCTAssertFalse(english.isEmpty)
        XCTAssertFalse(french.isEmpty)
        XCTAssertNotEqual(english, french)
        XCTAssertTrue(english.contains("."))
        XCTAssertTrue(french.contains("."))
    }

    func testRealKokoroVoicesWhenAssetsAreProvided() async throws {
        guard
            let model = ProcessInfo.processInfo.environment["HARBOUR_KOKORO_MODEL"],
            let voices = ProcessInfo.processInfo.environment["HARBOUR_KOKORO_VOICES"]
        else {
            throw XCTSkip("Supply temporary local model and voice paths for neural synthesis.")
        }

        for voice in KokoroVoice.allCases {
            for (language, text) in [
                (KokoroLanguage.english, "Your appointment is on Tuesday at three thirty."),
                (.french, "Bonjour. Le rendez-vous est mardi à quinze heures.")
            ] {
                let samples = try await KokoroSpeechEngine.shared.synthesize(
                    text,
                    language: language,
                    model: URL(fileURLWithPath: model),
                    voiceFile: URL(fileURLWithPath: voices).appendingPathComponent(voice.rawValue + ".bin")
                )
                XCTAssertGreaterThan(samples.count, 2400)
                XCTAssertTrue(samples.allSatisfy(\.isFinite))
                XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.01)
            }
        }
        await KokoroSpeechEngine.shared.unload()
    }

}
