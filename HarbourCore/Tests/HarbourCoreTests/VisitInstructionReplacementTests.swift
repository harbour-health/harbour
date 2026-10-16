import XCTest
@testable import HarbourCore

final class VisitInstructionReplacementTests: XCTestCase {
    private func output(_ source: String, name: String, directions: String, action: String = "update") throws -> String {
        let value: [String: Any] = ["medicines": [["quote": source, "name": name, "instructions": directions, "action": action]], "followUps": [], "appointments": [], "highlights": []]
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    func testExplicitInstructionObjectsUpdateOnlyTheirSavedMedicineWithCompleteDirections() throws {
        let saved = [try XCTUnwrap(Catalog.resolve("metformin")), try XCTUnwrap(Catalog.resolve("aspirin"))]
        let cases: [(String, String, String, String, [DoseTime], Int)] = [
            ("Replace the directions for metformin: 750 mg at 06:55 once per day.", "metformin", "metformin", "750 mg at 06:55 once per day", [DoseTime(hour: 6, minute: 55)], 1),
            ("Remplace les instructions de la metformine : 750 mg à 6 h 55 une fois par jour.", "metformine", "metformin", "750 mg à 6 h 55 une fois par jour", [DoseTime(hour: 6, minute: 55)], 1),
            ("Update the instructions for metformin: 500 mg at 06:55 and 18:55 twice per day.", "metformin", "metformin", "500 mg at 06:55 and 18:55 twice per day", [DoseTime(hour: 6, minute: 55), DoseTime(hour: 18, minute: 55)], 2),
            ("Modifiez la posologie de l'aspirine : 81 mg à 9 h une fois par jour.", "aspirine", "aspirin", "81 mg à 9 h une fois par jour", [DoseTime(hour: 9, minute: 0)], 1)
        ]
        for (source, name, id, directions, times, count) in cases {
            let summary = try VisitReview.parse(output(source, name: name, directions: directions), transcript: source, medicines: saved)
            let change = try XCTUnwrap(summary.medicines.first, source)
            XCTAssertEqual(summary.medicines.count, 1, source)
            XCTAssertEqual(change.action, .update, source)
            XCTAssertEqual(change.medicine.id, id, source)
            XCTAssertEqual(change.medicine.instructions, directions, source)
            XCTAssertEqual(change.times, times, source)
            XCTAssertEqual(change.frequency, MedicationFrequency(count: count, period: .day), source)
            var visit = DoctorVisit(transcript: source)
            visit.summary = summary; visit.medicineBaseline = saved
            let applied = try VisitReview.applying([change.id], from: visit, to: saved)
            XCTAssertEqual(applied.first(where: { $0.id == id })?.instructions, directions, source)
            XCTAssertEqual(applied.first(where: { $0.id != id }), saved.first(where: { $0.id != id }), source)
            XCTAssertTrue(try VisitReview.parse(output(source, name: name, directions: directions), transcript: source, medicines: []).medicines.isEmpty, source)
            XCTAssertTrue(try VisitReview.parse(output(source, name: name, directions: directions, action: "start"), transcript: source, medicines: saved).medicines.isEmpty, source)
        }
        // The narrow single-direction requirement also uses the same marker.
        for (source, _, _, directions, _, _) in cases.prefix(2) {
            let candidates = VisitSourceGrounding.candidates(source)
            let required = try XCTUnwrap(VisitSourceGrounding.requiredMedicineProposal(source, medicines: saved, candidates: candidates), source)
            XCTAssertEqual(required.instructions, directions)
            XCTAssertEqual(required.action, .update)
        }
    }

    func testInstructionReplacementCannotLoseSourceAuthorityOrBorrowOtherActionDirections() throws {
        let medicine = try XCTUnwrap(Catalog.resolve("metformin"))
        let directions = "750 mg at 06:55 once per day"
        for source in [
            "Do not replace the directions for metformin: 750 mg at 06:55 once per day.",
            "If needed, replace the directions for metformin: 750 mg at 06:55 once per day.",
            "Yesterday, replace the directions for metformin: 750 mg at 06:55 once per day.",
            "My father said replace the directions for metformin: 750 mg at 06:55 once per day.",
            #"The poster says "Replace the directions for metformin: 750 mg at 06:55 once per day.""#,
        ] {
            XCTAssertTrue(try VisitReview.parse(output(source, name: "metformin", directions: directions), transcript: source, medicines: [medicine]).medicines.isEmpty, source)
        }
        let frenchDirections = "750 mg à 6 h 55 une fois par jour"
        for source in [
            "Ne remplace pas les instructions de metformine : 750 mg à 6 h 55 une fois par jour.",
            "Si nécessaire, remplace les instructions de metformine : 750 mg à 6 h 55 une fois par jour.",
            "Hier, remplace les instructions de metformine : 750 mg à 6 h 55 une fois par jour.",
            "Mon père demande de remplacer les instructions de metformine : 750 mg à 6 h 55 une fois par jour.",
            "« Remplace les instructions de metformine : 750 mg à 6 h 55 une fois par jour. »"
        ] {
            XCTAssertTrue(try VisitReview.parse(output(source, name: "metformine", directions: frenchDirections), transcript: source, medicines: [medicine]).medicines.isEmpty, source)
        }
        for (source, name, tail) in [
            ("Replace metformin with aspirin.", "metformin", "with aspirin"),
            ("Remplace metformine par aspirine.", "metformine", "par aspirine")
        ] {
            XCTAssertTrue(try VisitReview.parse(output(source, name: name, directions: tail), transcript: source, medicines: [medicine]).medicines.isEmpty, source)
        }
        for (source, name, full, partial) in [
            ("Replace the directions for metformin: 750 mg at 06:55 once per day with food.", "metformin", "750 mg at 06:55 once per day with food", "750 mg at 06:55 once per day"),
            ("Remplace les instructions de metformine : 750 mg à 6 h 55 une fois par jour avec nourriture.", "metformine", "750 mg à 6 h 55 une fois par jour avec nourriture", "750 mg à 6 h 55 une fois par jour")
        ] {
            var summary = try VisitReview.parse(output(source, name: name, directions: full), transcript: source, medicines: [medicine])
            XCTAssertEqual(summary.medicines.count, 1, source)
            XCTAssertTrue(try VisitReview.parse(output(source, name: name, directions: partial), transcript: source, medicines: [medicine]).medicines.isEmpty, source)
            var changed = try XCTUnwrap(summary.medicines.first)
            changed.medicine.instructions = partial; summary.medicines = [changed]
            var visit = DoctorVisit(transcript: source)
            visit.summary = summary; visit.medicineBaseline = [medicine]
            XCTAssertThrowsError(try VisitReview.applying([changed.id], from: visit, to: [medicine]), source)
        }
        for (source, name, full, borrowed) in [
            ("Replace the directions for metformin: 750 mg once per day; book a blood test at 16:10.", "metformin", "750 mg once per day", "750 mg once per day; book a blood test at 16:10"),
            ("Remplace les instructions de metformine : 750 mg une fois par jour; planifiez une prise de sang à 16 h 10.", "metformine", "750 mg une fois par jour", "750 mg une fois par jour; planifiez une prise de sang à 16 h 10")
        ] {
            let summary = try VisitReview.parse(output(source, name: name, directions: full), transcript: source, medicines: [medicine])
            XCTAssertEqual(summary.medicines.first?.medicine.instructions, full, source)
            XCTAssertEqual(summary.medicines.first?.times, [], source)
            XCTAssertEqual(summary.medicines.first?.frequency, MedicationFrequency(count: 1, period: .day), source)
            XCTAssertTrue(try VisitReview.parse(output(source, name: name, directions: borrowed), transcript: source, medicines: [medicine]).medicines.isEmpty, source)
        }
    }
}
