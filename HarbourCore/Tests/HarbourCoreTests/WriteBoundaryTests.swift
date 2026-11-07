import XCTest
@testable import HarbourCore

final class WriteBoundaryTests: XCTestCase {
    func testAppointmentDocumentationDoesNotBecomeBooking() {
        for input in ["Make a summary of my appointment.", "Prépare un résumé de mon rendez-vous.", "Create notes for my appointment."] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createAppointment), original: input, records: Records()), input)
        }
    }
    func testPoliteAppointmentRequestsPrepareDraftsWithoutChangingSourceFactRules() throws {
        for input in ["Could you record my dentist appointment Tuesday at 2 pm?", "Peux-tu enregistrer mon rendez-vous mardi à 14 h ?", "Please book an appointment next Tuesday."] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .createAppointment), original: input, records: Records()), .appointment(input))
        }
        XCTAssertFalse(AppointmentRules.isAppointment("Could you record my dentist appointment Tuesday at 2 pm?"))
    }
    func testQuotedNegatedConditionalAndCompoundBookingsStayRejected() {
        for input in ["Do not book an appointment.", "Could you book an appointment if my doctor approves?", "Peux-tu enregistrer un rendez-vous si mon médecin approuve ?", "Could you book an appointment and remove metformin?", "My brother said: ‘book an appointment.’", "Maybe book an appointment tomorrow."] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createAppointment), original: input, records: Records()), input)
        }
    }
    func testRemovalDoesNotDiscardApprovalOrTimingConditions() throws {
        var records = Records(); records.medicines = [try XCTUnwrap(Catalog.resolve("metformin"))]
        for input in ["Remove metformin if my doctor approves.", "Retire la metformine si mon médecin approuve.", "Remove metformin after my appointment.", "Remove metformin unless the doctor objects.", "If approved, remove metformin."] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .removeMedicine), original: input, records: records), input)
        }
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .removeMedicine), original: "Remove metformin.", records: records), .remove(records.medicines[0]))
    }
}
