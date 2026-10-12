import XCTest
@testable import HarbourCore

final class ReadingParserTests: XCTestCase {
    func testTypedMeasurementsAllowSentencePunctuationAndFrenchDecimals() throws {
        let cases: [(String, ReadingKind, String)] = [
            ("Please record my heart rate of 81.", .heartRate, "81"),
            ("Enregistre mon pouls de 81.", .heartRate, "81"),
            ("Could you record my pulse of 81?", .heartRate, "81"),
            ("Peux-tu noter mon pouls de 81 ?", .heartRate, "81"),
            ("My temperature is 37.1.", .temperature, "37.1"),
            ("Ma température est de 37,1.", .temperature, "37.1"),
            ("Blood pressure 118/76.", .bloodPressure, "118/76"),
            ("Tension artérielle 118 / 76 ?", .bloodPressure, "118/76"),
            ("My pulse is 81, measured this morning.", .heartRate, "81")
        ]
        for (original, kind, value) in cases {
            let reading = try XCTUnwrap(ReadingParser.parse(original), original)
            XCTAssertEqual(reading.kind, kind, original)
            XCTAssertEqual(reading.value, value, original)
        }
    }

    func testSentencePunctuationDoesNotRelaxNumericBoundsOrUnits() {
        for original in [
            "Pulse 12345.", "Pouls 301.", "Temperature 60.",
            "Temperature 37.1.2.", "Température 37,1,2.",
            "Pulse 81..", "Pouls 81e2.", "Pulse -81.",
            "Blood pressure 118/76/90.", "Tension 76/118.",
            "Pulse 81 mg.", "Pouls 81mg.", "Température 37,1 milligrammes.",
            "Temperature 37.1 micrograms.", "Blood pressure 118/76 mg.",
            "I take 81 mg of medicine.", "Je prends un médicament de 81 mg."
        ] { XCTAssertNil(ReadingParser.parse(original), original) }
    }
}
