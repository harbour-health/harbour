import XCTest
@testable import HarbourCore

final class TypedReadingConnectorTests: XCTestCase {
    func testExplicitTypedMeasurementConnectorsCannotBecomeSymptomDrafts() throws {
        for (input, kind, value, language) in [
            ("Record my pulse as 83 bpm.", ReadingKind.heartRate, "83", ModelLanguage.english),
            ("Log the blood pressure as 127/79 mmHg.", .bloodPressure, "127/79", .english),
            ("Save my temperature as 36.6 °C.", .temperature, "36.6", .english),
            ("Note mon pouls comme 77 bpm.", .heartRate, "77", .french),
            ("Enregistre ma température comme 36,7 °C.", .temperature, "36.7", .french)
        ] {
            let fallback = try XCTUnwrap(ToolPlanner.replyFallback(original: input, records: Records(), language: language), input)
            XCTAssertEqual(fallback.reason, "reading_draft", input)
            guard case .reading(let reading) = fallback.action else { return XCTFail(input) }
            XCTAssertEqual(reading.kind, kind, input)
            XCTAssertEqual(reading.value, value, input)
            guard case .reading(let validated) = try ToolPlanner.validate(fallback.decision, original: input, records: Records(), language: language) else { return XCTFail(input) }
            XCTAssertEqual(validated.kind, reading.kind, input)
            XCTAssertEqual(validated.value, reading.value, input)
            XCTAssertEqual(validated.source, reading.source, input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .captureSymptom), original: input, records: Records(), language: language), input)
        }
    }

    func testConnectorDoesNotAuthorizeQuotedConditionalOrCompoundMeasurements() {
        for input in [
            "What if I record my pulse as 83 bpm?", "Do not record my pulse as 83 bpm.",
            "She said: save my temperature as 36.6 °C.", "Record my pulse as 83 bpm and erase my medicines.",
            "Si je le demande, note mon pouls comme 77 bpm.", "N'enregistre pas ma température comme 36,7 °C.",
            "« Note mon pouls comme 77 bpm. »", "Record my pulse as 83 mg."
        ] {
            XCTAssertNil(ToolPlanner.replyFallback(original: input, records: Records()), input)
        }
    }
}
