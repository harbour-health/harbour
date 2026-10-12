import XCTest
@testable import HarbourCore

final class VisitHistoryGroundingTests: XCTestCase {
    private func output(quote: String, action: MedicineChangeAction, name: String, instructions: String, highlight: String? = nil) throws -> String {
        let object: [String: Any] = [
            "highlights": highlight.map { [["quote": $0]] } ?? [], "followUps": [], "appointments": [],
            "medicines": [["quote": quote, "action": action.rawValue, "name": name, "instructions": instructions]]
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    func testPastReportsInBothLanguagesCannotCreateOrApplyMedicineChanges() throws {
        let aspirin = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        let cases: [(String, MedicineChangeAction, String, String)] = [
            ("Yesterday my doctor told me to start aspirin 81 mg daily; that was my old treatment.", .start, "aspirin", "81 mg daily"),
            ("I used to take aspirin 81 mg daily as past treatment.", .update, "aspirin", "81 mg daily"),
            ("My doctor once told me to stop aspirin.", .stop, "aspirin", ""),
            ("Previously, I was told to start aspirin 81 mg daily.", .start, "aspirin", "81 mg daily"),
            ("Last year my doctor prescribed that I start aspirin 81 mg daily.", .start, "aspirin", "81 mg daily"),
            ("Hier, mon médecin m'a dit de commencer aspirine 81 mg par jour.", .start, "aspirine", "81 mg par jour"),
            ("Le médecin m'avait demandé de prendre aspirine 81 mg par jour.", .update, "aspirine", "81 mg par jour"),
            ("Le patient avait pour consigne de prendre aspirine 81 mg par jour.", .update, "aspirine", "81 mg par jour"),
            ("Le médecin conseillait de prendre aspirine 81 mg par jour.", .update, "aspirine", "81 mg par jour"),
            ("Je prenais aspirine 81 mg par jour; c'était ma consigne de prendre aspirine 81 mg par jour.", .update, "aspirine", "81 mg par jour"),
            ("Mon médecin m'avait dit de cesser aspirine.", .stop, "aspirine", "")
        ]
        for (source, action, name, instructions) in cases {
            XCTAssertTrue(VisitSourceGrounding.candidates(source).isEmpty, source)
            XCTAssertTrue(VisitReview.outputGrammar(transcript: source).contains(#"medicines ::= "[" ws "]""#), source)
            let summary = try VisitReview.parse(output(quote: source, action: action, name: name, instructions: instructions, highlight: source), transcript: source, medicines: [aspirin])
            XCTAssertTrue(summary.medicines.isEmpty, source)
            XCTAssertEqual(summary.highlights.map(\.quote), [source], source)
            var proposedMedicine = aspirin; proposedMedicine.instructions = instructions
            let change = VisitMedicineChange(action: action, medicine: proposedMedicine, quote: source)
            var injected = VisitSummary(); injected.medicines = [change]
            var visit = DoctorVisit(transcript: source); visit.summary = injected; visit.medicineBaseline = [aspirin]
            XCTAssertThrowsError(try VisitReview.applying([change.id], from: visit, to: [aspirin]), source)
        }
    }

    func testShortenedQuotesCannotDiscardPastReportingContext() throws {
        let cases = [
            ("Yesterday my doctor told me to start aspirin 81 mg daily.", "start aspirin 81 mg daily.", "aspirin", "81 mg daily"),
            ("Hier, mon médecin m'a dit de commencer aspirine 81 mg par jour.", "commencer aspirine 81 mg par jour.", "aspirine", "81 mg par jour"),
            ("Last year the doctor said: \"Current plan: Start aspirin 81 mg daily.\"", "Start aspirin 81 mg daily.", "aspirin", "81 mg daily"),
            ("Last year the doctor said: \"Discuss exercise. Start aspirin 81 mg daily.\"", "Start aspirin 81 mg daily.", "aspirin", "81 mg daily"),
            ("Last year the doctor said: ‘Discuss exercise. Start aspirin 81 mg daily.’", "Start aspirin 81 mg daily.", "aspirin", "81 mg daily"),
            ("Hier, le médecin m'avait dit : « Discutez des analyses. Commencez aspirine 81 mg par jour. »", "Commencez aspirine 81 mg par jour.", "aspirine", "81 mg par jour")
        ]
        for (source, quote, name, instructions) in cases {
            XCTAssertTrue(try VisitReview.parse(output(quote: quote, action: .start, name: name, instructions: instructions), transcript: source, medicines: []).medicines.isEmpty, source)
            XCTAssertTrue(VisitSourceGrounding.candidates(source).isEmpty, source)
        }
    }

    func testExplicitHistoricalHeadersScopeFollowingInstructionsUntilCurrentPlan() throws {
        let cases = [
            ("These were instructions from my past treatment.", "Start aspirin 81 mg daily.", "Stop aspirin.", "aspirin", "81 mg daily"),
            ("Voici mes anciennes consignes.", "Commencez aspirine 81 mg par jour.", "Cessez aspirine.", "aspirine", "81 mg par jour")
        ]
        for (header, start, stop, name, instructions) in cases {
            let source = header + " " + start + " " + stop
            XCTAssertTrue(VisitSourceGrounding.candidates(source).isEmpty, source)
            XCTAssertEqual(VisitSourceGrounding.containingContext(quote: start, source: source), header + " " + start)
            XCTAssertEqual(VisitSourceGrounding.containingContext(quote: stop, source: source), source)
            XCTAssertTrue(try VisitReview.parse(output(quote: start, action: .start, name: name, instructions: instructions), transcript: source, medicines: []).medicines.isEmpty, source)
        }
    }

    func testPastSymptomsAndCurrentQuotedPrescriptionsRemainEligible() throws {
        let cases = [
            ("Yesterday I had knee pain. Start aspirin 81 mg daily.", "Start aspirin 81 mg daily.", "aspirin", "81 mg daily"),
            ("My old treatment caused nausea. Start aspirin 81 mg daily.", "Start aspirin 81 mg daily.", "aspirin", "81 mg daily"),
            ("Hier, j'avais mal au genou. Commencez aspirine 81 mg par jour.", "Commencez aspirine 81 mg par jour.", "aspirine", "81 mg par jour"),
            ("My doctor says: \"Start aspirin 81 mg daily.\"", "Start aspirin 81 mg daily.", "aspirin", "81 mg daily"),
            ("Le médecin dit : « Commencez aspirine 81 mg par jour. »", "Commencez aspirine 81 mg par jour.", "aspirine", "81 mg par jour"),
            ("My doctor says: \"Discuss exercise. Start aspirin 81 mg daily.\"", "Start aspirin 81 mg daily.", "aspirin", "81 mg daily"),
            ("My doctor says: ‘Discuss exercise. Start aspirin 81 mg daily.’", "Start aspirin 81 mg daily.", "aspirin", "81 mg daily"),
            ("Le médecin dit : « Discutez des analyses. Commencez aspirine 81 mg par jour. »", "Commencez aspirine 81 mg par jour.", "aspirine", "81 mg par jour")
        ]
        for (source, quote, name, instructions) in cases {
            XCTAssertEqual(VisitSourceGrounding.candidates(source).first?.actions, [.start], source)
            let summary = try VisitReview.parse(output(quote: quote, action: .start, name: name, instructions: instructions), transcript: source, medicines: [])
            let change = try XCTUnwrap(summary.medicines.first, source)
            var visit = DoctorVisit(transcript: source); visit.summary = summary; visit.medicineBaseline = []
            XCTAssertEqual(try VisitReview.applying([change.id], from: visit, to: []).first?.instructions, instructions, source)
        }
        let multiSentence = "Yesterday I had knee pain. Start aspirin 81 mg daily."
        XCTAssertEqual(try VisitReview.parse(output(quote: multiSentence, action: .start, name: "aspirin", instructions: "81 mg daily"), transcript: multiSentence, medicines: []).medicines.count, 1)
    }

    func testCurrentContinuedDirectionsCanReferToWhenTreatmentBegan() throws {
        let aspirin = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        for (source, name, instructions) in [
            ("Continue aspirin 81 mg daily, as you have since last year.", "aspirin", "81 mg daily"),
            ("Continuez aspirine 81 mg par jour depuis l'an dernier.", "aspirine", "81 mg par jour"),
            ("Continuez aspirine 81 mg par jour depuis hier.", "aspirine", "81 mg par jour"),
            ("The doctor told me to take aspirin 81 mg daily today.", "aspirin", "81 mg daily"),
            ("Le médecin m'a demandé de prendre aspirine 81 mg par jour.", "aspirine", "81 mg par jour")
        ] {
            XCTAssertEqual(VisitSourceGrounding.candidates(source).first?.actions, [.update], source)
            let summary = try VisitReview.parse(output(quote: source, action: .update, name: name, instructions: instructions), transcript: source, medicines: [aspirin])
            let change = try XCTUnwrap(summary.medicines.first, source)
            var visit = DoctorVisit(transcript: source); visit.summary = summary; visit.medicineBaseline = [aspirin]
            XCTAssertEqual(try VisitReview.applying([change.id], from: visit, to: [aspirin]).first?.instructions, instructions, source)
        }
    }

    func testDuplicateHistoricalDirectiveDoesNotHideAValidCurrentSection() throws {
        for (header, current, directive, name, instructions) in [
            ("Past treatment instructions.", "Current plan.", "Start aspirin 81 mg daily.", "aspirin", "81 mg daily"),
            ("Anciennes consignes.", "Traitement actuel.", "Commencez aspirine 81 mg par jour.", "aspirine", "81 mg par jour")
        ] {
            let source = header + " " + directive + " " + current + " " + directive
            XCTAssertEqual(VisitSourceGrounding.candidates(source).map(\.quote), [directive], source)
            XCTAssertEqual(VisitSourceGrounding.containingContexts(quote: directive, source: source), [header + " " + directive, directive], source)
            let summary = try VisitReview.parse(output(quote: directive, action: .start, name: name, instructions: instructions), transcript: source, medicines: [])
            let change = try XCTUnwrap(summary.medicines.first, source)
            var visit = DoctorVisit(transcript: source); visit.summary = summary; visit.medicineBaseline = []
            XCTAssertEqual(try VisitReview.applying([change.id], from: visit, to: []).first?.instructions, instructions, source)
        }
    }
}
