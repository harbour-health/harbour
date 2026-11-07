import XCTest
@testable import HarbourCore

final class VisitDirectionsTests: XCTestCase {
    func testComplexSourceDirectionsRemainStructuredWithoutClockReminders() throws {
        let instructions = "500 mg at 8 am for seven days then 1000 mg at 8 am for seven days"
        let source = "Start metformin " + instructions + "."
        let item: [String: String] = ["action": "start", "name": "metformin", "instructions": instructions, "quote": source]
        let data = try JSONSerialization.data(withJSONObject: ["highlights": [], "medicines": [item], "followUps": [], "appointments": []])
        let change = try XCTUnwrap(VisitReview.parse(String(decoding: data, as: UTF8.self), transcript: source, medicines: []).medicines.first)
        XCTAssertTrue(VisitDirections(change.medicine.instructions).needsIndividualSchedule)
        XCTAssertNil(change.frequency); XCTAssertTrue(change.times.isEmpty)
    }
    func testFollowUpsUseVisitDateAndCalendarRatherThanSummaryGenerationDate() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let visit = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 10)))
        let expected = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))
        XCTAssertEqual(VisitFollowUp.dueDate(in: "Book blood work in two weeks.", relativeTo: visit, calendar: calendar), expected)
        XCTAssertEqual(VisitFollowUp.dueDate(in: "Prise de sang dans deux semaines.", relativeTo: visit, calendar: calendar), expected)
        XCTAssertNil(VisitFollowUp.dueDate(in: "Call the clinic if symptoms return.", relativeTo: visit, calendar: calendar))
    }
    func testDecimalDoseFormattingIsPreserved() {
        XCTAssertEqual(VisitDirections("2.5 mg once daily at bedtime").dose, "2.5 mg")
    }
}

extension VisitDirectionsTests {
    func testRejectsAnotherDrugDoseAndActionInSharedQuote() throws {
        let source = "Stop warfarin and start apixaban 5 mg twice daily."
        let bad = #"{"highlights":[],"medicines":[{"action":"start","name":"warfarin","instructions":"5 mg twice daily","quote":"Stop warfarin and start apixaban 5 mg twice daily."}],"followUps":[],"appointments":[]}"#
        let summary = try VisitReview.parse(bad, transcript: source, medicines: [Catalog.resolve("warfarin")!])
        XCTAssertTrue(summary.medicines.isEmpty)
    }
    func testNegatedMedicineInstructionIsNotAFollowUpTask() throws {
        let source = "Do not start metformin 500 mg twice daily."
        let output = #"{"highlights":[],"medicines":[],"followUps":[{"quote":"Do not start metformin 500 mg twice daily.","text":"Do not start metformin."}],"appointments":[]}"#
        XCTAssertTrue(try VisitReview.parse(output, transcript: source, medicines: []).followUps.isEmpty)
    }
}

extension VisitDirectionsTests {
    func testExistingTakeInstructionCannotBecomeDuplicateStart() throws {
        let source = "Take warfarin 2.5 mg on Monday then 5 mg on other days."
        let output = #"{"highlights":[],"medicines":[{"action":"start","name":"warfarin","instructions":"2.5 mg on Monday then 5 mg on other days","quote":"Take warfarin 2.5 mg on Monday then 5 mg on other days."}],"followUps":[],"appointments":[]}"#
        let medicines = [Catalog.resolve("warfarin")!]
        let summary = try VisitReview.parse(output, transcript: source, medicines: medicines)
        XCTAssertTrue(summary.medicines.isEmpty)
        let corrected = output.replacingOccurrences(of: "\"start\"", with: "\"update\"")
        let accepted = try VisitReview.parse(corrected, transcript: source, medicines: medicines)
        XCTAssertEqual(accepted.medicines.map(\.action), [.update])
    }
}
