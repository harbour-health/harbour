import XCTest
@testable import HarbourCore

final class VisitMinimumGroundingTests: XCTestCase {
    private func requirement(_ source: String, saved: [Medicine] = []) -> VisitMedicineChange? {
        VisitSourceGrounding.requiredMedicineProposal(source, medicines: saved, candidates: VisitSourceGrounding.candidates(source))?.validatedChange
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

    func testRequiredDecoderBindsSourceFieldsWithoutRelaxingFinalValidation() throws {
        let source = "Start aspirin 81 mg once daily. Book laboratory tests next month."
        XCTAssertTrue(requiresOne(source))
        let wrong: [String: Any] = ["highlights": [], "followUps": [], "appointments": [], "medicines": [
            ["quote": "Start aspirin 81 mg once daily.", "action": "start", "name": "aspirin", "instructions": "100 mg twice daily"]
        ]]
        let output = String(decoding: try JSONSerialization.data(withJSONObject: wrong), as: UTF8.self)
        XCTAssertTrue(try VisitReview.parse(output, transcript: source, medicines: []).medicines.isEmpty)
        // The required branch constrains decoder output to independent source
        // literals; it does not insert a medicine if model output is rejected.
        let grammar = VisitReview.outputGrammar(transcript: source)
        let rule = try XCTUnwrap(grammar.components(separatedBy: "\n").first { $0.hasPrefix("source-medicine-0-start ::=") })
        XCTAssertTrue(rule.contains(#""\"aspirin\"""#))
        XCTAssertTrue(rule.contains(#""\"81 mg once daily\"""#))
        XCTAssertFalse(rule.contains(#"ws ":" ws name"#))
        XCTAssertFalse(rule.contains(#"ws ":" ws instructions"#))
        XCTAssertTrue(try VisitReview.parse(#"{"highlights":[],"medicines":[],"followUps":[],"appointments":[]}"#, transcript: source, medicines: []).medicines.isEmpty)
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

    func testRequiredSourceFieldsKeepFrenchAliasesCaseAndMultiwordSpelling() throws {
        let cases = [
            ("Commencez metformine 850 mg trois fois par jour.", "metformine", "850 mg trois fois par jour", "metformin"),
            ("Débutez IBUPROFÈNE 200 mg deux fois par jour.", "IBUPROFÈNE", "200 mg deux fois par jour", "ibuprofen"),
            ("Commencez acide acétylsalicylique 81 mg une fois par jour.", "acide acétylsalicylique", "81 mg une fois par jour", "aspirin"),
        ]
        for (source, name, directions, identity) in cases {
            let bound = try XCTUnwrap(VisitSourceGrounding.requiredMedicineProposal(source, medicines: [], candidates: VisitSourceGrounding.candidates(source)), source)
            XCTAssertEqual(bound.quote, source)
            XCTAssertEqual(bound.name, name)
            XCTAssertEqual(bound.instructions, directions)
            XCTAssertEqual(bound.validatedChange.medicine.id, identity)
            XCTAssertNotEqual(bound.name, bound.validatedChange.medicine.name)
            let rule = try XCTUnwrap(VisitReview.outputGrammar(transcript: source).components(separatedBy: "\n").first { $0.hasPrefix("source-medicine-0-start ::=") })
            XCTAssertFalse(rule.contains(#"ws ":" ws name"#))
            XCTAssertFalse(rule.contains(#"ws ":" ws instructions"#))
            XCTAssertTrue(rule.contains(name), source)
            XCTAssertTrue(rule.contains(directions), source)
        }
    }

    func testCopiedFieldsDoNotMakeChangedDirectionsOrCanonicalizedNamesValid() throws {
        let source = "Commencez metformine 850 mg trois fois par jour."
        let bound = try XCTUnwrap(VisitSourceGrounding.requiredMedicineProposal(source, medicines: [], candidates: VisitSourceGrounding.candidates(source)))
        for (name, directions) in [
            (bound.name, "850 mg, trois fois par jour"),
            (bound.name, "850 mg deux fois par jour"),
            (bound.name, "500 mg trois fois par jour"),
            ("Metformin", bound.instructions),
        ] {
            let raw: [String: Any] = ["highlights": [], "followUps": [], "appointments": [], "medicines": [
                ["quote": bound.quote, "action": bound.action.rawValue, "name": name, "instructions": directions]
            ]]
            let output = String(decoding: try JSONSerialization.data(withJSONObject: raw), as: UTF8.self)
            XCTAssertTrue(try VisitReview.parse(output, transcript: source, medicines: []).medicines.isEmpty, output)
        }
        XCTAssertEqual(bound.name, "metformine")
        XCTAssertEqual(bound.instructions, "850 mg trois fois par jour")
    }

    func testRequiredStopAndUpdateUseSavedIdentityButNeverItsCanonicalSpellingOrOldDirections() throws {
        var metformin = try XCTUnwrap(Catalog.medicines.first { $0.id == "metformin" })
        metformin.instructions = "500 mg twice daily"
        let update = "Prenez metformine 850 mg trois fois par jour."
        let updated = try XCTUnwrap(VisitSourceGrounding.requiredMedicineProposal(update, medicines: [metformin], candidates: VisitSourceGrounding.candidates(update)))
        XCTAssertEqual(updated.name, "metformine")
        XCTAssertEqual(updated.instructions, "850 mg trois fois par jour")
        XCTAssertNotEqual(updated.instructions, metformin.instructions)
        let stop = "Cessez la metformine aujourd'hui."
        XCTAssertNil(VisitSourceGrounding.requiredMedicineProposal(stop, medicines: [], candidates: VisitSourceGrounding.candidates(stop)))
        let stopped = try XCTUnwrap(VisitSourceGrounding.requiredMedicineProposal(stop, medicines: [metformin], candidates: VisitSourceGrounding.candidates(stop)))
        XCTAssertEqual(stopped.name, "metformine")
        XCTAssertEqual(stopped.instructions, "")
        XCTAssertEqual(stopped.validatedChange.medicine.id, metformin.id)
    }

    func testOptionalSourcesRetainFreeFieldRulesRatherThanSourceFieldLiterals() throws {
        for source in [
            "Start CustomMedicine 10 mg once daily.",
            "Start aspirin and ibuprofen 100 mg once daily.",
            "My doctor says: \"Start aspirin 81 mg once daily.\"",
            "Start aspirin 81 mg once daily with another tablet.",
        ] {
            XCTAssertNil(VisitSourceGrounding.requiredMedicineProposal(source, medicines: [], candidates: VisitSourceGrounding.candidates(source)), source)
            let grammar = VisitReview.outputGrammar(transcript: source)
            let rule = try XCTUnwrap(grammar.components(separatedBy: "\n").first { $0.hasPrefix("source-medicine-0-start ::=") }, source)
            XCTAssertTrue(rule.contains(#"ws ":" ws name"#), source)
            XCTAssertTrue(rule.contains(#"ws ":" ws instructions"#), source)
            XCTAssertTrue(grammar.components(separatedBy: "\n").first { $0.hasPrefix("medicines ::=") }?.contains("})?") == true, source)
        }
    }
}
