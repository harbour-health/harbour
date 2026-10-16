import XCTest
@testable import HarbourCore

/// Characterizes HEAD 5158710, including the defect; passing is not a fix.
final class Issue004PoliteAppointmentReproductionTests: XCTestCase {
    func testPoliteBookingRequestsPassWriteIntentButAreRejectedAsAppointmentFacts() {
        let cases: [(String, ModelLanguage)] = [
            ("Could you record my dentist appointment Tuesday at 2 pm?", .english),
            ("Peux-tu enregistrer mon rendez-vous mardi à 14 h ?", .french)
        ]
        for (input, language) in cases {
            let records = Records()
            XCTAssertTrue(WriteRequestValidation.permits(input, tool: .createAppointment), input)
            XCTAssertFalse(AppointmentRules.isAppointment(input), input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createAppointment), original: input, records: records, language: language), input) { error in
                guard case PlannerError.forbidden = error else { return XCTFail("Unexpected error: \(error)") }
            }
            XCTAssertNil(ToolPlanner.replyFallback(original: input, records: records, language: language), input)
            let fallback = ToolPlanner.replyFallback(original: input, records: records, language: language, rejectedAction: true)
            XCTAssertEqual(fallback?.reason, "rejected_action_clarification", input)
            XCTAssertEqual(fallback?.decision.tool, .reply, input)
            XCTAssertTrue(records.appointments.isEmpty)
        }
    }

    func testCouldAndQuestionMarkEachIndependentlyCauseRejection() {
        for input in [
            "Could you record my dentist appointment Tuesday at 2 pm.",
            "Can you record my dentist appointment Tuesday at 2 pm?",
            "Peux-tu enregistrer mon rendez-vous mardi à 14 h ?"
        ] {
            XCTAssertTrue(WriteRequestValidation.permits(input, tool: .createAppointment), input)
            XCTAssertFalse(AppointmentRules.isAppointment(input), input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createAppointment), original: input, records: Records()), input)
        }
    }

    func testEquivalentDirectRequestsAndNonQuestionPoliteFormsRemainAllowed() throws {
        for input in [
            "Record my dentist appointment Tuesday at 2 pm.",
            "Enregistre mon rendez-vous mardi à 14 h.",
            "Can you record my dentist appointment Tuesday at 2 pm.",
            "Peux-tu enregistrer mon rendez-vous mardi à 14 h."
        ] {
            XCTAssertTrue(WriteRequestValidation.permits(input, tool: .createAppointment), input)
            XCTAssertTrue(AppointmentRules.isAppointment(input), input)
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .createAppointment), original: input, records: Records()), .appointment(input), input)
        }
    }

    func testSpeculationNegationAndQuotationRemainRejected() {
        for input in [
            "Maybe book an appointment Tuesday at 2 pm.",
            "Can I have an appointment on Friday?",
            "Je pourrais prendre rendez-vous mardi.",
            "Do not record my appointment Tuesday.",
            #"The note says "Record my appointment Tuesday.""#
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createAppointment), original: input, records: Records()), input)
        }
    }
}
