import Foundation
import XCTest
@testable import HarbourCore

/// Characterizes HEAD 5158710, including the defect; passing is not a fix.
final class Issue002AppointmentSummaryReproductionTests: XCTestCase {
    func testSummaryOfAndResumeDeCurrentlyOpenAppointmentDrafts() throws {
        let cases: [(String, ModelLanguage)] = [
            ("Make a summary of my appointment.", .english),
            ("Prépare un résumé de mon rendez-vous.", .french)
        ]
        for (input, language) in cases {
            let records = Records()
            XCTAssertTrue(WriteRequestValidation.permits(input, tool: .createAppointment), input)
            XCTAssertTrue(AppointmentRules.isAppointment(input), input)
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .createAppointment), original: input, records: records, language: language), .appointment(input), input)
            XCTAssertNil(ToolPlanner.replyFallback(original: input, records: records, language: language), input)
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .appointmentNote), original: input, records: records, language: language), .note, input)
        }
    }

    func testExistingDocumentationConnectorsStillRejectAppointmentCreation() {
        for input in [
            "Make a summary about my appointment.",
            "Prepare notes for my appointment.",
            "Create appointment summaries for the clinic.",
            "Prépare un résumé pour la consultation.",
            "Crée une note pour mon rendez-vous."
        ] {
            XCTAssertFalse(WriteRequestValidation.permits(input, tool: .createAppointment), input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createAppointment), original: input, records: Records()), input)
        }
    }

    func testActualAppointmentsRemainAllowedAndQuotedOrSpeculativeRequestsRejected() throws {
        for input in [
            "Add my dentist appointment Tuesday at 2 pm.",
            "Enregistre mon rendez-vous mardi à 14 h.",
            "Add my appointment Tuesday; summary: bring my test results."
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .createAppointment), original: input, records: Records()), .appointment(input), input)
        }
        for input in [
            #"The example says "Make a summary of my appointment.""#,
            "Maybe make a summary of my appointment.",
            "Do not add my appointment."
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createAppointment), original: input, records: Records()), input)
        }
    }

    func testWrongDraftIsStructurallyValidButValidationDoesNotPersistIt() throws {
        let input = "Make a summary of my appointment."
        let records = Records()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!
        let action = try ToolPlanner.validate(.init(tool: .createAppointment), original: input, records: records)
        guard case .appointment(let text) = action else { return XCTFail("Expected current erroneous appointment draft") }
        let draft = AppointmentRules.draft(from: text, now: now, calendar: calendar)
        XCTAssertEqual(draft.title, input)
        XCTAssertEqual(draft.date, calendar.startOfDay(for: now))
        XCTAssertFalse(draft.includesTime)
        XCTAssertNil(draft.visitID)
        XCTAssertNil(draft.quote)
        XCTAssertNoThrow(try AppointmentRules.validate(draft, visits: []))
        XCTAssertTrue(records.appointments.isEmpty, "Core returns a draft; persistence requires the app editor's date confirmation and Save")
    }
}
