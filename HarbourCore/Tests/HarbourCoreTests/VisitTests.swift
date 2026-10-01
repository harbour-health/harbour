import XCTest
@testable import HarbourCore

final class VisitTests: XCTestCase {
    private let source = "Start metformin 500 mg twice daily. Book blood work in two weeks."
    private let output = #"{"highlights":[{"quote":"Start metformin 500 mg twice daily."}],"medicines":[{"action":"start","name":"metformin","instructions":"500 mg twice daily","quote":"Start metformin 500 mg twice daily."}],"followUps":[{"quote":"Book blood work in two weeks."}]}"#
    func testGroundingAndExplicitReview() throws {
        var visit = DoctorVisit(transcript: source)
        visit.summary = try VisitReview.parse(output, transcript: source, medicines: [])
        visit.medicineBaseline = []
        XCTAssertEqual(visit.summary?.medicines.count, 1)
        XCTAssertEqual(visit.summary?.followUps.first?.quote, "Book blood work in two weeks.")
        let changed = try VisitReview.applying([visit.summary!.medicines[0].id], from: visit, to: [])
        XCTAssertEqual(changed[0].instructions, "500 mg twice daily")
        XCTAssertEqual(changed[0].ingredients, ["metformin"])
        XCTAssertThrowsError(try VisitReview.applying([], from: visit, to: []))
    }
    func testInventedDoseQuoteAndMedicineAreRejected() throws {
        for modified in [output.replacingOccurrences(of: "500 mg twice daily\",\"quote", with: "900 mg\",\"quote"), output.replacingOccurrences(of: "metformin", with: "imaginarypill"), output.replacingOccurrences(of: "Start metformin 500 mg twice daily.", with: "Stop warfarin.")] {
            XCTAssertTrue(try VisitReview.parse(modified, transcript: source, medicines: []).medicines.isEmpty)
        }
        let invented = output.replacingOccurrences(of: "Book blood work in two weeks.", with: "Your results are normal.")
        XCTAssertEqual(try VisitReview.parse(invented, transcript: source, medicines: []).followUps.map(\.quote), ["Book blood work in two weeks."])
    }
    func testSpeculationNegationAndQuestionsAreRejected() throws {
        for quote in ["Do not start metformin 500 mg twice daily.", "Could we start metformin 500 mg twice daily?", "Consider metformin 500 mg twice daily.", "If needed, start metformin 500 mg twice daily."] {
            let modified = output.replacingOccurrences(of: "Start metformin 500 mg twice daily.", with: quote)
            XCTAssertTrue(try VisitReview.parse(modified, transcript: quote, medicines: []).medicines.isEmpty)
        }
    }
    func testConflictsStaleBaselineAndRepeatedApplicationAreRejected() throws {
        var visit = DoctorVisit(transcript: source)
        visit.summary = try VisitReview.parse(output, transcript: source, medicines: [])
        visit.medicineBaseline = []
        let first = visit.summary!.medicines[0]
        XCTAssertThrowsError(try VisitReview.applying([first.id], from: visit, to: [Medicine(name: "Warfarin")]))
        var second = first; second.id = UUID(); second.action = .update
        visit.summary!.medicines.append(second)
        XCTAssertThrowsError(try VisitReview.applying([first.id, second.id], from: visit, to: []))
        visit.appliedChanges = [first]
        XCTAssertThrowsError(try VisitReview.applying([first.id], from: visit, to: []))
    }
    func testTranscriptEditsInvalidateMutation() throws {
        var visit = DoctorVisit(transcript: source)
        visit.summary = try VisitReview.parse(output, transcript: source, medicines: []); visit.medicineBaseline = []
        visit.transcript = "Do not change medicines."
        XCTAssertThrowsError(try VisitReview.applying([visit.summary!.medicines[0].id], from: visit, to: []))
    }
    func testModelOmittedFollowUpIsPreservedFromSource() throws {
        let missing = output.replacingOccurrences(of: "\"followUps\":[{\"quote\":\"Book blood work in two weeks.\"}]", with: "\"followUps\":[]")
        XCTAssertEqual(try VisitReview.parse(missing, transcript: source, medicines: []).followUps.map(\.quote), ["Book blood work in two weeks."])
    }
    func testTruncatedNegationCannotBypassValidation() throws {
        let text = "Do not Start metformin 500 mg twice daily."
        XCTAssertTrue(try VisitReview.parse(output, transcript: text, medicines: []).medicines.isEmpty)
    }
    func testVisitRoundTripAndBoundedChunking() throws {
        var visit = DoctorVisit(transcript: source); visit.summary = try VisitReview.parse(output, transcript: source, medicines: [])
        XCTAssertEqual(try JSONDecoder().decode(DoctorVisit.self, from: JSONEncoder().encode(visit)), visit)
        let long = Array(repeating: source, count: 100).joined(separator: " ")
        let chunks = VisitReview.chunks(long)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= VisitReview.chunkCharacters })
        XCTAssertEqual(chunks.joined(separator: " "), long)
    }
}
