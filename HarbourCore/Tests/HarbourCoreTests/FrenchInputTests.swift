import XCTest
@testable import HarbourCore

final class FrenchInputTests: XCTestCase {
    private var metformin: Medicine { Catalog.medicines.first { $0.id == "metformin" }! }
    private func output(action: MedicineChangeAction = .start, name: String = "metformine", instructions: String = "500 mg deux fois par jour", quote: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["highlights": [], "followUps": [], "medicines": [["action": action.rawValue, "name": name, "instructions": instructions, "quote": quote]]])
        return String(decoding: data, as: UTF8.self)
    }

    func testFrenchEmergencyExamplesAndAccentInsensitiveMatching() {
        for text in ["J'ai une douleur thoracique intense et persistante.", "Douleur persistante et sévère à la poitrine.", "Douleur thoracique persistante et intense.", "J'ai des difficultés à respirer.", "Je ne peux pas respirer.", "Je n'arrive pas à respirer.", "Perte de connaissance.", "Perte de conscience.", "Nouvelle confusion.", "Confusion soudaine.", "Douleur intense non soulagée par les médicaments.", "Douleur qui n'est pas soulagée par les antidouleurs."] {
            XCTAssertTrue(HealthRules.emergencyCue(text), text)
            XCTAssertTrue(HealthRules.emergencyCue(InputLanguage.folded(text)), text)
            XCTAssertTrue(ToolPlanner.prompt(text).contains("capture_symptom"), text)
        }
    }

    func testFrenchLocalNegationAndLaterAffirmativeCue() {
        for text in ["Je n'ai pas de difficulté à respirer.", "Aucune difficulté respiratoire.", "Sans perte de connaissance.", "Pas de nouvelle confusion.", "Je n'ai plus de douleur thoracique intense et persistante.", "Je nie avoir une perte de conscience.", "Pas de douleur intense non soulagée par les médicaments.", "Aucune douleur intense non soulagée par les médicaments."] {
            XCTAssertFalse(HealthRules.emergencyCue(text), text)
        }
        XCTAssertTrue(HealthRules.emergencyCue("Pas de nouvelle confusion, mais difficulté à respirer."))
        let medicineCue = "Douleur intense non soulagée par les médicaments."
        for tool in Tool.allCases { XCTAssertTrue(ToolPlanner.prompt(medicineCue).contains(tool.rawValue), tool.rawValue) }
        let negatedThenAffirmative = "Pas de douleur intense non soulagée par les médicaments, mais difficulté à respirer."
        XCTAssertTrue(HealthRules.emergencyCue(negatedThenAffirmative))
        for tool in Tool.allCases { XCTAssertTrue(ToolPlanner.prompt(negatedThenAffirmative).contains(tool.rawValue), tool.rawValue) }
        XCTAssertTrue(HealthRules.emergencyCue("Pas seulement une difficulté à respirer."))
        XCTAssertTrue(HealthRules.isEmergency(Symptom(text: "Aucune difficulté respiratoire", signs: [.breathing])))
    }

    func testHistoryAndThirdPersonEmergencyMentionsRetainConditionalGuidance() {
        for text in ["Hier, j'avais une difficulté à respirer.", "Ma mère a une perte de connaissance.", "La note mentionne une nouvelle confusion."] {
            XCTAssertTrue(HealthRules.emergencyCue(text), text)
            XCTAssertTrue(HealthRules.guidance(Symptom(text: text)).hasPrefix("If this sign is happening now, call 911."))
        }
    }

    func testFrenchSourceTextWinsOverGeneratedMedicineAndSymptomArguments() throws {
        let added = try ToolPlanner.validate(.init(tool: .addMedicine, arg: "warfarine"), original: "Ajoute metformine", records: Records())
        XCTAssertEqual(added, .add(metformin))
        XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .addMedicine, arg: "metformine"), original: "Ajoute un médicament inconnu", records: Records()))
        XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .addMedicine), original: "Ajoute metformine et warfarine", records: Records()))
        let source = "J'ai mal au genou depuis mardi"
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .captureSymptom, arg: "Perte de connaissance"), original: source, records: Records()), .symptom(source))
        XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .addMedicine), original: "Ne prends pas metformine", records: Records()))
        XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .addMedicine), original: "Puis-je prendre metformine ?", records: Records()))
    }

    func testFrenchRequestsKeepAllToolsAndOriginalSearchQuestionText() throws {
        for (text, tool) in [("Scanne l'étiquette du médicament", Tool.scanMedicine), ("Vérifie les interactions entre metformine et warfarine", .interactions), ("Importe Apple Santé", .importReadings), ("Exporte mes données", .exportData), ("Efface toutes mes données", .clearData), ("Affiche mes médicaments", .listMedicines), ("Prépare mon rendez-vous", .appointmentNote)] {
            let prompt = ToolPlanner.prompt(text, records: Records())
            XCTAssertTrue(prompt.contains(tool.rawValue), text)
            for available in Tool.allCases { XCTAssertTrue(prompt.contains(available.rawValue), "\(text): \(available.rawValue)") }
        }
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .searchTimeline, arg: "invention"), original: "Cherche mon historique pour prise de sang", records: Records()), .timeline("prise de sang"))
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .saveQuestion, arg: "invention"), original: "Enregistre cette question pour mon médecin : Dois-je refaire une prise de sang ?", records: Records()), .question("Dois-je refaire une prise de sang ?"))
    }

    func testFrenchReadingListIntentCannotInventAMeasurement() throws {
        for original in ["Affiche mes relevés", "Affiche mon relevé", "Affiche mes releves"] {
            for tool in Tool.allCases { XCTAssertTrue(ToolPlanner.prompt(original, records: Records()).contains(tool.rawValue), tool.rawValue) }
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .listReadings), original: original, records: Records()), .readings)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .logReading, arg: "heart rate 72"), original: original, records: Records()))
        }
        for tool in Tool.allCases { XCTAssertTrue(ToolPlanner.prompt("relevespersonnels").contains(tool.rawValue), tool.rawValue) }
    }

    func testFrenchDoseStatusesRequireOneSavedMedicineAndOneAffirmativeStatus() throws {
        var records = Records(); records.medicines = [metformin]
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .logDose), original: "J'ai pris metformine", records: records), .dose(metformin, .taken))
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .logDose), original: "J'ai sauté ma dose de metformine", records: records), .dose(metformin, .skipped))
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .logDose), original: "Rappelle plus tard pour metformine", records: records), .dose(metformin, .later))
        for text in ["Je n'ai pas pris metformine", "J'ai pris et sauté metformine", "Si j'ai pris metformine", "Ma mère a pris metformine", "Hier, j'ai pris metformine", "J'ai pris warfarine"] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .logDose), original: text, records: records), text)
        }
        XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .logDose), original: "J'ai pris metformine", records: Records()))
    }

    func testFrenchTimesAndInstructionsAreLiteral() throws {
        let expected = [DoseTime(hour: 8, minute: 0), DoseTime(hour: 20, minute: 30)]
        XCTAssertEqual(CareRules.times(in: "Programme metformine à 8 h et 20 h 30"), expected)
        XCTAssertEqual(CareRules.times(in: "8h, 20:30, 8 am, 8:30 pm"), expected)
        for text in ["le matin et le soir", "28 h", "8 h 99", "20:99", "8h3"] { XCTAssertTrue(CareRules.times(in: text).isEmpty, text) }
        var records = Records(); records.medicines = [metformin]
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .scheduleMedicine, arg: "2 am"), original: "Programme metformine à 8 h et 20 h 30", records: records), .schedule(metformin, expected))
        let label = "METFORMINE\n500 mg\nPrendre avec de la nourriture\nPosologie : voir l'ordonnance"
        XCTAssertEqual(CareRules.labelCandidates(label), [metformin])
        XCTAssertEqual(CareRules.labelInstructions(label), "Prendre avec de la nourriture\nPosologie : voir l'ordonnance")
    }

    func testFrenchVisitMedicineProposalStaysGroundedThroughConfirmation() throws {
        let quote = "Commencez metformine 500 mg deux fois par jour."
        let source = quote + " Prenez rendez-vous pour une prise de sang."
        var visit = DoctorVisit(transcript: source)
        visit.summary = try VisitReview.parse(output(quote: quote), transcript: source, medicines: [])
        visit.medicineBaseline = []
        XCTAssertEqual(visit.summary?.medicines.count, 1)
        XCTAssertEqual(visit.summary?.followUps.map(\.quote), ["Prenez rendez-vous pour une prise de sang."])
        let changes = try XCTUnwrap(visit.summary?.medicines)
        XCTAssertEqual(try VisitReview.applying([changes[0].id], from: visit, to: []).first?.ingredients, ["metformin"])
        XCTAssertThrowsError(try VisitReview.applying([], from: visit, to: []))
        visit.transcript = "Ne commencez pas metformine."
        XCTAssertThrowsError(try VisitReview.applying([changes[0].id], from: visit, to: []))
    }

    func testFrenchVisitNegationHypothesesHistoryAndThirdPersonCannotCreateChanges() throws {
        for source in ["Ne commencez pas metformine 500 mg deux fois par jour.", "Si nécessaire, commencez metformine 500 mg deux fois par jour.", "Peut-être commencez metformine 500 mg deux fois par jour.", "Pourrais-je commencer metformine 500 mg deux fois par jour ?", "Hier, commencez metformine 500 mg deux fois par jour.", "Ma mère commence metformine 500 mg deux fois par jour.", "Je prends metformine 500 mg deux fois par jour."] {
            let action: MedicineChangeAction = source.hasPrefix("Je prends") ? .update : .start
            XCTAssertTrue(try VisitReview.parse(output(action: action, quote: source), transcript: source, medicines: [metformin]).medicines.isEmpty, source)
        }
        let quote = "commencez metformine 500 mg deux fois par jour."
        XCTAssertTrue(try VisitReview.parse(output(quote: quote), transcript: "Si nécessaire, " + quote, medicines: []).medicines.isEmpty)
    }

    func testFrenchVisitRejectsInventedInstructionsNamesAndWrongActions() throws {
        let quote = "Commencez metformine 500 mg deux fois par jour."
        XCTAssertTrue(try VisitReview.parse(output(name: "warfarine", quote: quote), transcript: quote, medicines: []).medicines.isEmpty)
        XCTAssertTrue(try VisitReview.parse(output(instructions: "900 mg", quote: quote), transcript: quote, medicines: []).medicines.isEmpty)
        XCTAssertTrue(try VisitReview.parse(output(action: .stop, instructions: "", quote: quote), transcript: quote, medicines: [metformin]).medicines.isEmpty)
        let unknown = "Commencez médicamentinconnu 10 mg par jour."
        let summary = try VisitReview.parse(output(name: "médicamentinconnu", instructions: "10 mg par jour", quote: unknown), transcript: unknown, medicines: [])
        XCTAssertTrue(summary.medicines.isEmpty)
        XCTAssertEqual(summary.highlights.map(\.quote), [unknown])
        let wrong = "Arrêtez warfarine et commencez metformine 500 mg deux fois par jour."
        XCTAssertTrue(try VisitReview.parse(output(action: .stop, instructions: "", quote: wrong), transcript: wrong, medicines: [metformin]).medicines.isEmpty)
    }
}
