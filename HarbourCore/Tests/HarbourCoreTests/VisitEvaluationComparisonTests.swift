import XCTest
@testable import HarbourCore

final class VisitEvaluationComparisonTests: XCTestCase {
    private func output(source: String, instructions: String) throws -> String {
        let value: [String: Any] = ["highlights": [], "followUps": [], "appointments": [], "medicines": [["quote": source, "action": "start", "name": "aspirin", "instructions": instructions]]]
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    func testOptionalSentencePeriodComparisonKeepsTheOriginalVerdictAndSourceGrounding() throws {
        let source = "Start aspirin 81.5 mg daily."
        let fixture = VisitSummaryEvaluationCase(name: "Independent period control", transcript: source, expectedJSON: "", expectedMedicineID: "aspirin", expectedInstructions: "81.5 mg daily")
        let exact = try output(source: source, instructions: "81.5 mg daily")
        let withPeriod = try output(source: source, instructions: "81.5 mg daily.")
        XCTAssertTrue(fixture.matches(exact))
        XCTAssertFalse(fixture.matches(withPeriod))
        XCTAssertFalse(fixture.matches(withPeriod, allowTerminalPeriodEquivalence: false))
        XCTAssertTrue(fixture.matches(withPeriod, allowTerminalPeriodEquivalence: true))
        let unanchored = try output(source: source, instructions: "82.5 mg daily.")
        XCTAssertFalse(fixture.matches(unanchored, allowTerminalPeriodEquivalence: true))
        XCTAssertFalse(fixture.matches(try output(source: source, instructions: ""), allowTerminalPeriodEquivalence: true))
        for existing in Evaluation.visitSummaryCases {
            XCTAssertEqual(existing.matches(existing.expectedJSON), existing.matches(existing.expectedJSON, allowTerminalPeriodEquivalence: false), existing.name)
        }
    }

    func testPeriodEquivalencePreservesOtherPunctuationWordingAndStructuredFields() throws {
        let expected = "81.5 mg daily"
        for directions in ["81.5 mg daily...", "81.5 mg daily!", "81.5 mg daily?.", "81.5 mg Daily.", "82.5 mg daily.", "81,5 mg daily.", "81.5 mg with food daily."] {
            let source = "Start aspirin " + directions
            let fixture = VisitSummaryEvaluationCase(name: "Independent directions control", transcript: source, expectedJSON: "", expectedMedicineID: "aspirin", expectedInstructions: expected)
            XCTAssertFalse(fixture.matches(try output(source: source, instructions: directions), allowTerminalPeriodEquivalence: true), directions)
        }
        let source = "Start aspirin 81.5 mg twice daily at 8 am and 8 pm."
        let directions = "81.5 mg twice daily at 8 am and 8 pm."
        let fixture = VisitSummaryEvaluationCase(name: "Independent schedule control", transcript: source, expectedJSON: "", expectedMedicineID: "aspirin", expectedInstructions: String(directions.dropLast()), expectedFrequency: MedicationFrequency(count: 2, period: .day), expectedTimes: [DoseTime(hour: 8, minute: 0), DoseTime(hour: 20, minute: 0)])
        let generated = try output(source: source, instructions: directions)
        XCTAssertTrue(fixture.matches(generated, allowTerminalPeriodEquivalence: true))
        var wrongFrequency = fixture; wrongFrequency.expectedFrequency = MedicationFrequency(count: 1, period: .day)
        XCTAssertFalse(wrongFrequency.matches(generated, allowTerminalPeriodEquivalence: true))
        var wrongTimes = fixture; wrongTimes.expectedTimes = [DoseTime(hour: 9, minute: 0)]
        XCTAssertFalse(wrongTimes.matches(generated, allowTerminalPeriodEquivalence: true))
        let negatedSource = "Do not " + source
        var negated = fixture; negated.transcript = negatedSource
        XCTAssertFalse(negated.matches(try output(source: negatedSource, instructions: directions), allowTerminalPeriodEquivalence: true))
    }
}
