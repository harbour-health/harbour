import XCTest
@testable import HarbourCore

final class VisitSummaryEmptyTests: XCTestCase {
    func testAppointmentOnlySummaryIsNotEmptyAndSurvivesStorage() throws {
        for source in ["Appointment with Dr Smith next Tuesday at 3 PM.", "Rendez-vous avec le Dr Roy mardi à 15 h."] {
            var summary = VisitSummary()
            XCTAssertTrue(summary.isEmpty)
            summary.appointments = [VisitQuote(quote: source)]
            XCTAssertFalse(summary.isEmpty)
            XCTAssertFalse(try JSONDecoder().decode(VisitSummary.self, from: JSONEncoder().encode(summary)).isEmpty)
            var merged = VisitSummary()
            merged.merge(summary)
            XCTAssertFalse(merged.isEmpty)
        }
    }

    func testEveryDisplayedCategoryCountsAndMissingAppointmentsRemainCompatible() throws {
        let old = Data(#"{"highlights":[],"medicines":[],"followUps":[]}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(VisitSummary.self, from: old).isEmpty)
        var summary = VisitSummary()
        summary.appointments = []
        XCTAssertTrue(summary.isEmpty)
        summary.highlights = [VisitQuote(quote: "A mild cough.")]
        XCTAssertFalse(summary.isEmpty)
        summary.highlights = []
        summary.followUps = [VisitQuote(quote: "Return in two weeks.")]
        XCTAssertFalse(summary.isEmpty)
    }
}
