import XCTest
@testable import HarbourCore

final class VisitMinimumGroundingTests: XCTestCase {
    private func requirement(_ source: String, saved: [Medicine] = []) -> VisitMedicineChange? {
        VisitSourceGrounding.requiredMedicineProposal(source, medicines: saved, candidates: VisitSourceGrounding.candidates(source))
    }

    private func requiresOne(_ source: String, saved: [Medicine] = []) -> Bool {
        VisitReview.outputGrammar(transcript: source, medicines: saved).contains(#"medicines ::= "[" ws (medicine (ws "," ws medicine){0,0}) ws "]""#)
    }

    func testKnownDirectStartRequiresOneOnlyAfterSourceParseAndScheduleValidation() throws {
        for (source, directions) in [("Start aspirin 81.5 mg twice daily.", "81.5 mg twice daily"), ("Commencez aspirine 81 mg deux fois par jour.", "81 mg deux fois par jour")] {
            let proposal = try XCTUnwrap(requirement(source), source)
            XCTAssertEqual(proposal.action, .start)
            XCTAssertEqual(proposal.medicine.id, "aspirin")
            XCTAssertEqual(proposal.medicine.instructions, directions)
            XCTAssertEqual(proposal.frequency, MedicationFrequency(count: 2, period: .day))
            XCTAssertTrue(requiresOne(source), source)
            var visit = DoctorVisit(transcript: source)
            var summary = VisitSummary(); summary.medicines = [proposal]
            visit.summary = summary; visit.medicineBaseline = []
            XCTAssertEqual(try VisitReview.applying([proposal.id], from: visit, to: []).first?.instructions, directions)
        }
    }

    func testKnownDirectStopRequiresSavedIdentityAndStillValidatesAtApplying() throws {
        let aspirin = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        for source in ["Stop aspirin today.", "Arrêtez aspirine aujourd'hui."] {
            XCTAssertNil(requirement(source))
            XCTAssertFalse(requiresOne(source))
            let proposal = try XCTUnwrap(requirement(source, saved: [aspirin]), source)
            XCTAssertEqual(proposal.action, .stop)
            XCTAssertEqual(proposal.medicine.instructions, "")
            XCTAssertTrue(requiresOne(source, saved: [aspirin]))
            var visit = DoctorVisit(transcript: source)
            var summary = VisitSummary(); summary.medicines = [proposal]
            visit.summary = summary; visit.medicineBaseline = [aspirin]
            XCTAssertTrue(try VisitReview.applying([proposal.id], from: visit, to: [aspirin]).isEmpty)
        }
    }

    func testDirectDoseUpdateRequiresSavedIdentityAndConsistentLiteralSchedule() throws {
        let aspirin = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        for source in ["Continue aspirin 81 mg once daily at 08:00.", "Continuez aspirine 81 mg une fois par jour à 8 h."] {
            XCTAssertNil(requirement(source))
            let proposal = try XCTUnwrap(requirement(source, saved: [aspirin]), source)
            XCTAssertEqual(proposal.action, .update)
            XCTAssertEqual(proposal.frequency, MedicationFrequency(count: 1, period: .day))
            XCTAssertEqual(proposal.times, [DoseTime(hour: 8, minute: 0)])
            XCTAssertTrue(requiresOne(source, saved: [aspirin]))
            try CareRules.validate(MedicineSchedule(medicineID: proposal.medicine.id, times: proposal.times, frequency: proposal.frequency), medicines: [proposal.medicine])
        }
    }

    func testUncertainSourcesRemainOptionalEvenWhenTheyHaveAnEligibleCandidate() throws {
        let aspirin = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        let sources = [
            "Start CustomMedicine 10 mg daily.",
            "Start aspirin and ibuprofen 100 mg daily.",
            "Stop aspirin and start ibuprofen 100 mg daily.",
            "Start aspirin 81 mg daily. Stop aspirin today.",
            "Start aspirin 81 mg daily. Do not start aspirin.",
            "My doctor said today: \"Start aspirin 81 mg daily.\"",
            "Yesterday my doctor told me to start aspirin 81 mg daily.",
            "Le médecin m'avait demandé de prendre aspirine 81 mg par jour.",
            "Do not start aspirin 81 mg daily.",
            "If symptoms worsen. Start aspirin 81 mg daily.",
            "Consider starting aspirin 81 mg daily.",
            "My mother should start aspirin 81 mg daily.",
            "Please tell the assistant to start aspirin 81 mg daily.",
            "I take aspirin 81 mg daily.",
            "Continue aspirin unchanged.",
        ]
        for source in sources {
            XCTAssertNil(requirement(source, saved: [aspirin]), source)
            XCTAssertFalse(requiresOne(source, saved: [aspirin]), source)
        }
    }

    func testUncertainNameResolutionAndSavedIdentityNeverRequireAnEntry() throws {
        let aspirin = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        let source = "Start aspirin 81 mg daily."
        let aliasCollision = Medicine(id: "custom-aspirin", name: "aspirin", ingredients: [])
        let alteredIdentity = Medicine(id: "aspirin", name: "Aspirin / ASA", ingredients: ["unverified ingredient"])
        for saved in [[aliasCollision], [alteredIdentity], [aspirin, aspirin]] {
            XCTAssertNil(requirement(source, saved: saved))
            XCTAssertFalse(requiresOne(source, saved: saved))
        }
        let custom = Medicine(id: "custom", name: "CustomMedicine", ingredients: [])
        XCTAssertNil(requirement("Start CustomMedicine 10 mg daily.", saved: [custom]))
    }

    func testMissingAmbiguousOrInvalidDirectionsRemainOptional() throws {
        let aspirin = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        for source in [
            "Start aspirin.", "Start aspirin as directed.", "Start aspirin 81 mg.",
            "Start aspirin 81 mg as needed.", "Start aspirin 81 mg daily after discharge.",
            "Start aspirin 81 mg 0 times per day.", "Start aspirin 81 mg 32 times per day.",
            "Start aspirin 81 mg 32 times per day at 08:00.",
            "Start aspirin 81 mg twice daily at 08:00.", "Start aspirin 81 mg daily at 25 h.",
            "Start aspirin 81 mg daily at 8 am and 25 h.", "Start aspirin 81 mg daily and weekly.",
            "Start aspirin 81 mg once daily and this other tablet 100 mg once daily.",
            "Start aspirin 81 mg once daily followed by a tablet 100 mg once daily.",
            "Start aspirin 81 mg once daily 100 mg once daily.",
            "Start aspirin 81 mg once daily with another tablet.",
            "Commencez aspirine 81 mg une fois par jour puis un autre comprimé 100 mg par jour.",
            "Start aspirin -81 mg daily.", "Stop aspirin if dizzy.",
        ] {
            XCTAssertNil(requirement(source, saved: [aspirin]), source)
            XCTAssertFalse(requiresOne(source, saved: [aspirin]), source)
        }
    }

    func testMinimumDoesNotPrepopulateOrRelaxModelFieldsAndSourceValidation() throws {
        let source = "Start aspirin 81 mg once daily. Book laboratory tests next month."
        XCTAssertTrue(requiresOne(source))
        let wrong: [String: Any] = ["highlights": [], "followUps": [], "appointments": [], "medicines": [
            ["quote": "Start aspirin 81 mg once daily.", "action": "start", "name": "aspirin", "instructions": "100 mg twice daily"]
        ]]
        let output = String(decoding: try JSONSerialization.data(withJSONObject: wrong), as: UTF8.self)
        XCTAssertTrue(try VisitReview.parse(output, transcript: source, medicines: []).medicines.isEmpty)
        // The grammar requires one model-generated object, retaining independent
        // name/instruction generation and the mandatory final source checks.
        let grammar = VisitReview.outputGrammar(transcript: source)
        XCTAssertTrue(grammar.contains(#"ws ":" ws name"#))
        XCTAssertTrue(grammar.contains(#"ws ":" ws instructions"#))
        XCTAssertFalse(grammar.contains(#"name ::= "\"aspirin\"""#))
    }

    func testLongSourcesAndHistoricalDuplicateScopesStayOptional() {
        let directive = "Start aspirin 81 mg daily."
        let historicalDuplicate = "Old instructions. " + directive + " Current plan. " + directive
        XCTAssertNil(requirement(historicalDuplicate))
        XCTAssertFalse(requiresOne(historicalDuplicate))
        let beyondBound = String(repeating: "Background note. ", count: 120) + directive
        XCTAssertNil(requirement(beyondBound))
        XCTAssertFalse(requiresOne(beyondBound))
    }

    func testAccentedOuterVerbsPreserveOriginalUnicodeSourceAndApostrophes() throws {
        let aspirin = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        let cases: [(String, MedicineChangeAction, String)] = [
            ("Arrêtez l'aspirine aujourd'hui.", .stop, ""),
            ("Arre\u{0302}tez l’aspirine aujourd’hui.", .stop, ""),
            ("Débutez l'aspirine 81 mg deux fois par jour.", .start, "81 mg deux fois par jour"),
            ("De\u{0301}butez l’aspirine 81 mg deux fois par jour.", .start, "81 mg deux fois par jour"),
        ]
        for (source, action, directions) in cases {
            let proposal = try XCTUnwrap(requirement(source, saved: [aspirin]), source)
            XCTAssertEqual(proposal.quote, source)
            XCTAssertEqual(proposal.action, action)
            XCTAssertEqual(proposal.medicine.instructions, directions)
            XCTAssertTrue(requiresOne(source, saved: [aspirin]))
            var visit = DoctorVisit(transcript: source)
            var summary = VisitSummary(); summary.medicines = [proposal]
            visit.summary = summary; visit.medicineBaseline = [aspirin]
            let applied = try VisitReview.applying([proposal.id], from: visit, to: [aspirin])
            XCTAssertEqual(applied.count, action == .stop ? 0 : 1)
            if action != .stop { XCTAssertEqual(applied.first?.instructions, directions) }
        }
    }
}
