import XCTest
@testable import HarbourCore

final class VisitExtractionPromptTests: XCTestCase {
    func testMedicineFirstOutputKeepsIndependentChangesAndFollowUpSourceInBothLanguages() throws {
        let saved = [try XCTUnwrap(Catalog.resolve("amlodipine")), try XCTUnwrap(Catalog.resolve("naproxen"))]
        let cases = [
            ("Increase amlodipine to 7.5 mg once daily at 09:15.", "amlodipine", "7.5 mg once daily at 09:15", "Discontinue naproxen.", "naproxen", "Return to the clinic in three weeks."),
            ("Augmentez amlodipine à 7,5 mg une fois par jour à 9 h 15.", "amlodipine", "7,5 mg une fois par jour à 9 h 15", "Cessez naproxène.", "naproxène", "Revenez à la clinique dans trois semaines.")
        ]
        for (update, name, instructions, stop, stoppedName, followUp) in cases {
            let source = [update, stop, followUp].joined(separator: " ")
            // Preferred generation order; the historical highlights-first shape stays supported.
            let preferred = """
            {"medicines":[{"quote":"\(update)","action":"update","name":"\(name)","instructions":"\(instructions)"},{"quote":"\(stop)","action":"stop","name":"\(stoppedName)","instructions":""}],"followUps":[{"quote":"\(followUp)"}],"appointments":[],"highlights":[]}
            """
            let summary = try VisitReview.parse(preferred, transcript: source, medicines: saved)
            XCTAssertEqual(summary.medicines.map(\.action), [.update, .stop], source)
            XCTAssertEqual(summary.medicines.map(\.medicine.id), ["amlodipine", "naproxen"], source)
            XCTAssertEqual(summary.medicines.first?.medicine.instructions, instructions, source)
            XCTAssertEqual(summary.medicines.first?.frequency, MedicationFrequency(count: 1, period: .day), source)
            XCTAssertEqual(summary.medicines.first?.times, [DoseTime(hour: 9, minute: 15)], source)
            XCTAssertEqual(summary.followUps.map(\.quote), [followUp], source)
            var visit = DoctorVisit(transcript: source)
            visit.summary = summary; visit.medicineBaseline = saved
            let applied = try VisitReview.applying(Set(summary.medicines.map(\.id)), from: visit, to: saved)
            XCTAssertEqual(applied.map(\.id), ["amlodipine"], source)
            XCTAssertEqual(applied.first?.instructions, instructions, source)
        }
        let grammar = VisitReview.outputGrammar()
        XCTAssertTrue(grammar.contains("root ::= medicine-first | original-order"))
        XCTAssertTrue(grammar.contains("original-order ::= ws"))
    }

    func testMedicineFirstShapeCannotBypassQualifiedSourceOrStoredDirectionRevalidation() throws {
        let medicine = try XCTUnwrap(Catalog.resolve("amlodipine"))
        for (source, shortQuote) in [
            ("Do not increase amlodipine to 7.5 mg once daily.", "increase amlodipine to 7.5 mg once daily."),
            ("Yesterday my doctor said increase amlodipine to 7.5 mg once daily.", "increase amlodipine to 7.5 mg once daily."),
            ("If symptoms return, increase amlodipine to 7.5 mg once daily.", "increase amlodipine to 7.5 mg once daily."),
            ("N'augmentez pas amlodipine à 7,5 mg une fois par jour.", "augmentez pas amlodipine à 7,5 mg une fois par jour."),
            ("Hier le médecin a dit augmentez amlodipine à 7,5 mg une fois par jour.", "augmentez amlodipine à 7,5 mg une fois par jour.")
        ] {
            let instructions = source.contains("7,5") ? "7,5 mg une fois par jour" : "7.5 mg once daily"
            let proposal: [String: Any] = ["medicines": [["quote": shortQuote, "action": "update", "name": "amlodipine", "instructions": instructions]], "followUps": [], "appointments": [], "highlights": []]
            let output = String(decoding: try JSONSerialization.data(withJSONObject: proposal), as: UTF8.self)
            XCTAssertTrue(try VisitReview.parse(output, transcript: source, medicines: [medicine]).medicines.isEmpty, source)
        }
        let source = "Increase amlodipine to 7.5 mg once daily at 09:15."
        let output = #"{"medicines":[{"quote":"Increase amlodipine to 7.5 mg once daily at 09:15.","action":"update","name":"amlodipine","instructions":"7.5 mg once daily at 09:15"}],"followUps":[],"appointments":[],"highlights":[]}"#
        var summary = try VisitReview.parse(output, transcript: source, medicines: [medicine])
        XCTAssertEqual(summary.medicines.count, 1)
        var change = try XCTUnwrap(summary.medicines.first)
        change.medicine.instructions = "7.5 mg once daily"
        summary.medicines = [change]
        var visit = DoctorVisit(transcript: source)
        visit.summary = summary; visit.medicineBaseline = [medicine]
        XCTAssertThrowsError(try VisitReview.applying(Set(summary.medicines.map(\.id)), from: visit, to: [medicine]))
    }
}
