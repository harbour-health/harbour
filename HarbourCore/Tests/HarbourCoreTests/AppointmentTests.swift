import Foundation
import XCTest
@testable import HarbourCore

final class AppointmentTests: XCTestCase {
    func testTranscriptFixturesAndRejectedHallucinations() {
        let negated = Evaluation.visitSummaryCases.first { $0.name == "Negated medication" }!
        XCTAssertFalse(negated.matches(#"{"highlights":[],"medicines":[{"action":"start","name":"metformin","instructions":"500 mg twice daily","quote":"start metformin 500 mg twice daily."}],"followUps":[]}"#))
        let appointment = Evaluation.visitSummaryCases.first { $0.name == "Appointment from recording" }!
        XCTAssertFalse(appointment.matches(#"{"highlights":[],"medicines":[],"followUps":[],"appointments":[]}"#))
    }
    func testAgentAppointmentArgumentsAreGroundedInOriginalInput() throws {
        let input = "Add a dentist appointment next Tuesday at 2 pm"
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .createAppointment, arg: "Friday at 4 pm"), original: input, records: Records()), .appointment(input))
        for input in ["Do not add an appointment", "Maybe book an appointment", "My knee is sore"] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createAppointment), original: input, records: Records()))
        }
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .listAppointments), original: "Show appointments", records: Records()), .appointments)
    }
    private func summary(_ transcript: String, quote: String? = nil) throws -> VisitSummary {
        let output = try JSONSerialization.data(withJSONObject: ["highlights": [], "medicines": [], "followUps": [], "appointments": quote.map { [["quote": $0]] } ?? []])
        return try VisitReview.parse(String(decoding: output, as: UTF8.self), transcript: transcript, medicines: [])
    }
    func testGroundedAppointmentDraftDoesNotInventTimeOrLocation() throws {
        let text = "Your follow-up appointment is next Tuesday."
        let parsed = try summary(text)
        XCTAssertEqual(parsed.appointments, [VisitQuote(quote: text)])
        let draft = AppointmentRules.draft(from: text)
        XCTAssertFalse(draft.includesTime); XCTAssertTrue(draft.location.isEmpty)
    }
    func testNegatedHypotheticalAndInventedAppointmentsRejected() throws {
        for text in ["Do not schedule an appointment tomorrow.", "Maybe book an appointment next week.", "Can I have an appointment on Friday?"] {
            XCTAssertTrue(try summary(text, quote: "appointment tomorrow").appointments?.isEmpty == true)
        }
        XCTAssertTrue(try summary("We discussed sleep.", quote: "Appointment Friday at 3 pm.").appointments?.isEmpty == true)
        XCTAssertTrue(try summary("Do not book an appointment Friday.", quote: "book an appointment Friday.").appointments?.isEmpty == true)
    }
    func testAppointmentSourceRevalidatedBeforeSaving() throws {
        let quote = "Follow-up appointment Friday at 3 pm."
        var visit = DoctorVisit(transcript: quote); visit.summary = try summary(quote)
        let draft = AppointmentRules.draft(from: quote, visitID: visit.id)
        XCTAssertNoThrow(try AppointmentRules.validate(draft, visits: [visit]))
        visit.transcript = "Cancelled."
        XCTAssertThrowsError(try AppointmentRules.validate(draft, visits: [visit]))
    }
    func testLiteralAndRelativeAppointmentDatesUseReferenceDate() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10)))
        let tomorrow = AppointmentRules.draft(from: "Dentist appointment tomorrow at 2 pm", now: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: tomorrow.date), 13)
        XCTAssertEqual(calendar.component(.hour, from: tomorrow.date), 14); XCTAssertTrue(tomorrow.includesTime)
        let literal = AppointmentRules.draft(from: "Appointment 2026-11-04", now: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: literal.date), 11)
        XCTAssertEqual(calendar.component(.day, from: literal.date), 4); XCTAssertFalse(literal.includesTime)
    }
    func testAbbreviationsKeepFullQuoteAndFrenchHedgesAreRejected() {
        let text = "Your appointment with Dr. Smith is Tuesday at 2 p.m. at the clinic."
        XCTAssertEqual(AppointmentRules.quotes(in: text), [VisitQuote(quote: text)])
        let draft = AppointmentRules.draft(from: text)
        XCTAssertTrue(draft.includesTime)
        for text in ["Je pourrais prendre rendez-vous mardi.", "On pourrait planifier un rendez-vous.", "We may book an appointment."] {
            XCTAssertFalse(AppointmentRules.isAppointment(text), text)
        }
    }
    func testLegacyRecordsDecodeAndCanonicalExportRoundTrip() throws {
        let legacy = Data(#"{"schemaVersion":1,"medicines":[{"id":"metformin","name":"Metformin","ingredients":[],"instructions":""}],"symptoms":[],"readings":[]}"#.utf8)
        var records = try JSONDecoder().decode(Records.self, from: legacy)
        XCTAssertTrue(records.appointments.isEmpty); XCTAssertEqual(records.medications.count, 1)
        records.appointments = [Appointment(title: "Check-up", location: "Clinic")]
        let data = try JSONEncoder().encode(records)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["medications"]); XCTAssertNil(object["medicines"])
        XCTAssertEqual(try JSONDecoder().decode(Records.self, from: data), records)
        let backup = CareBackup(records: records, care: CareData(), visits: [])
        XCTAssertEqual(try backup.merging(into: CareBackup(records: Records(), care: CareData(), visits: [])).records.appointments, records.appointments)
    }
    func testInvalidAppointmentAndDuplicateIDsRejectedOnImport() throws {
        var records = Records(); let appointment = Appointment(title: "Visit")
        records.appointments = [appointment, appointment]
        XCTAssertThrowsError(try CareBackup(records: records, care: CareData(), visits: []).validated())
        XCTAssertThrowsError(try AppointmentRules.validate(Appointment(title: " "), visits: []))
    }
}
