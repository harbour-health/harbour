import XCTest
@testable import HarbourCore

final class VisitSourceGroundingTests: XCTestCase {
    private func proposal(quote: String, names: [String], instructions: [String], actions: [String]? = nil) throws -> String {
        let changes = names.indices.map { index in
            ["quote": quote, "name": names[index], "instructions": instructions[index], "action": actions?[index] ?? "start"]
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: ["highlights": [], "followUps": [], "appointments": [], "medicines": changes]), as: UTF8.self)
    }

    func testMedicineDirectionsKeepEverySourceDoseFrequencyClockAndQualifierForTheirOwnMedicine() throws {
        let cases = [
            ("Start metformin 500 mg at 8 am and 8 pm.", "metformin", "500 mg at 8 am and 8 pm", ["8 am and 8 pm.", "500 mg", "500 mg at 8 am"]),
            ("Commencez aspirine 81,5 µg deux fois par jour à 8 h et 20 h avec nourriture.", "aspirine", "81,5 µg deux fois par jour à 8 h et 20 h avec nourriture", ["8 h et 20 h avec nourriture.", "81,5 µg", "81,5 µg deux fois par jour à 8 h et 20 h"]),
            ("Start aspirin 81.5 μg twice daily with food.", "aspirin", "81.5 μg twice daily with food", ["twice daily with food.", "81.5 μg", "81.5 μg twice daily"])
        ]
        for (source, name, full, partials) in cases {
            let summary = try VisitReview.parse(proposal(quote: source, names: [name], instructions: [full]), transcript: source, medicines: [])
            XCTAssertEqual(summary.medicines.map(\.medicine.instructions), [full], source)
            for partial in partials {
                XCTAssertTrue(try VisitReview.parse(proposal(quote: source, names: [name], instructions: [partial]), transcript: source, medicines: []).medicines.isEmpty, partial)
            }
        }
        for (source, names, instructions) in [
            ("Start aspirin 81.5 µg daily and ibuprofen 200 mg twice daily.", ["aspirin", "ibuprofen"], ["81.5 µg daily", "200 mg twice daily"]),
            ("Commencez aspirine 81,5 μg par jour et ibuprofène 200 mg deux fois par jour.", ["aspirine", "ibuprofène"], ["81,5 μg par jour", "200 mg deux fois par jour"])
        ] {
            let summary = try VisitReview.parse(proposal(quote: source, names: names, instructions: instructions), transcript: source, medicines: [])
            XCTAssertEqual(summary.medicines.map(\.medicine.id), ["aspirin", "ibuprofen"], source)
            XCTAssertEqual(summary.medicines.map(\.medicine.instructions), instructions, source)
            let borrowed = try VisitReview.parse(proposal(quote: source, names: names, instructions: [instructions[1], instructions[0]]), transcript: source, medicines: [])
            XCTAssertTrue(borrowed.medicines.isEmpty, source)
        }
        for (source, names) in [
            ("Start aspirin and ibuprofen 200 mg daily.", ["aspirin", "ibuprofen"]),
            ("Commencez aspirine et ibuprofène 200 mg par jour.", ["aspirine", "ibuprofène"])
        ] {
            let directions = source.contains("par jour") ? "200 mg par jour" : "200 mg daily"
            XCTAssertTrue(try VisitReview.parse(proposal(quote: source, names: names, instructions: [directions, directions]), transcript: source, medicines: []).medicines.isEmpty, source)
        }
        let threeMedicines = "Start aspirin 81 mg daily, ibuprofen 200 mg twice daily, and metformin 500 mg twice daily."
        let threeDirections = ["81 mg daily", "200 mg twice daily", "500 mg twice daily"]
        let three = try VisitReview.parse(proposal(quote: threeMedicines, names: ["aspirin", "ibuprofen", "metformin"], instructions: threeDirections), transcript: threeMedicines, medicines: [])
        XCTAssertEqual(three.medicines.map(\.medicine.instructions), threeDirections)
        for (source, quote, name, full, borrowed) in [
            ("Start aspirin 81 mg daily and book blood work at 2 pm.", "Start aspirin 81 mg daily and book blood work at 2 pm.", "aspirin", "81 mg daily", "81 mg daily and book blood work at 2 pm"),
            ("Book blood work at 2 pm and start aspirin 81 mg daily.", "Book blood work at 2 pm and start aspirin 81 mg daily.", "aspirin", "81 mg daily", "blood work at 2 pm and start aspirin 81 mg daily"),
            ("Commencez aspirine 81 mg par jour et prenez rendez-vous à 14 h.", "Commencez aspirine 81 mg par jour", "aspirine", "81 mg par jour", "81 mg par jour et prenez rendez-vous à 14 h"),
            ("Prenez rendez-vous à 14 h et commencez aspirine 81 mg par jour.", "commencez aspirine 81 mg par jour.", "aspirine", "81 mg par jour", "rendez-vous à 14 h et commencez aspirine 81 mg par jour"),
            ("Commencez aspirine 81 mg par jour et planifiez une prise de sang à 14 h.", "Commencez aspirine 81 mg par jour et planifiez une prise de sang à 14 h.", "aspirine", "81 mg par jour", "81 mg par jour et planifiez une prise de sang à 14 h"),
            ("Start aspirin 81 mg daily; book blood work at 2 pm.", "Start aspirin 81 mg daily; book blood work at 2 pm.", "aspirin", "81 mg daily", "81 mg daily; book blood work at 2 pm"),
            ("Start aspirin 81 mg daily; please book blood work at 2 pm.", "Start aspirin 81 mg daily; please book blood work at 2 pm.", "aspirin", "81 mg daily", "81 mg daily; please book blood work at 2 pm"),
            ("Start aspirin 81 mg daily, schedule an appointment at 2 pm.", "Start aspirin 81 mg daily, schedule an appointment at 2 pm.", "aspirin", "81 mg daily", "81 mg daily, schedule an appointment at 2 pm"),
            ("Commencez aspirine 81 mg par jour; veuillez planifier une prise de sang à 14 h.", "Commencez aspirine 81 mg par jour; veuillez planifier une prise de sang à 14 h.", "aspirine", "81 mg par jour", "81 mg par jour; veuillez planifier une prise de sang à 14 h"),
            ("Commencez aspirine 81 mg par jour, planifiez un rendez-vous à 14 h.", "Commencez aspirine 81 mg par jour, planifiez un rendez-vous à 14 h.", "aspirine", "81 mg par jour", "81 mg par jour, planifiez un rendez-vous à 14 h")
        ] {
            let summary = try VisitReview.parse(proposal(quote: quote, names: [name], instructions: [full]), transcript: source, medicines: [])
            let medicine = try XCTUnwrap(summary.medicines.first, source)
            XCTAssertEqual(medicine.medicine.instructions, full, source)
            XCTAssertTrue(medicine.times.isEmpty, source)
            XCTAssertEqual(medicine.frequency, MedicationFrequency(count: 1, period: .day), source)
            XCTAssertTrue(try VisitReview.parse(proposal(quote: source, names: [name], instructions: [borrowed]), transcript: source, medicines: []).medicines.isEmpty, source)
        }
        for (source, name, full) in [
            ("Start aspirin 81 mg daily and arrange a laboratory test at 2 pm.", "aspirin", "81 mg daily"),
            ("Start aspirin 81 mg daily and call the clinic at 2 pm.", "aspirin", "81 mg daily"),
            ("Start aspirin 81 mg daily and return to the clinic at 2 pm.", "aspirin", "81 mg daily"),
            ("Start aspirin 81 mg daily and repeat the blood test at 2 pm.", "aspirin", "81 mg daily"),
            ("Commencez aspirine 81 mg par jour et appelez la clinique à 14 h.", "aspirine", "81 mg par jour"),
            ("Commencez aspirine 81 mg par jour et revenez à la clinique à 14 h.", "aspirine", "81 mg par jour"),
            ("Commencez aspirine 81 mg par jour et répétez les analyses sanguines à 14 h.", "aspirine", "81 mg par jour")
        ] {
            let summary = try VisitReview.parse(proposal(quote: source, names: [name], instructions: [full]), transcript: source, medicines: [])
            XCTAssertEqual(summary.medicines.first?.medicine.instructions, full, source)
            XCTAssertEqual(summary.medicines.first?.times, [], source)
        }
        for (source, names, shared) in [
            ("Start aspirin and book blood work at 2 pm and ibuprofen 200 mg daily.", ["aspirin", "ibuprofen"], "200 mg daily"),
            ("Commencez aspirine et planifiez une prise de sang à 14 h et ibuprofène 200 mg par jour.", ["aspirine", "ibuprofène"], "200 mg par jour")
        ] {
            XCTAssertTrue(try VisitReview.parse(proposal(quote: source, names: names, instructions: [shared, shared]), transcript: source, medicines: []).medicines.isEmpty, source)
        }
        let source = "Commencez l’aspirine à 81,5\u{00a0}µg une fois par jour."
        let summary = try VisitReview.parse(proposal(quote: source, names: ["aspirine"], instructions: ["81,5 µg une fois par jour"]), transcript: source, medicines: [])
        XCTAssertEqual(summary.medicines.first?.medicine.instructions, "81,5 µg une fois par jour")
        let ordinary = "Start metformin 500 mg at 8 am and 8 pm."
        let withEmptySavedName = try VisitReview.parse(proposal(quote: ordinary, names: ["metformin"], instructions: ["500 mg at 8 am and 8 pm"]), transcript: ordinary, medicines: [Medicine(id: "empty", name: "")])
        XCTAssertEqual(withEmptySavedName.medicines.first?.medicine.id, "metformin")
    }

    func testStoredMedicineDraftTamperingCannotDiscardDoseOrClockDirectionsAndStopsStayEmpty() throws {
        for (source, name, full, shortened) in [
            ("Start metformin 500 mg at 8 am and 8 pm.", "metformin", "500 mg at 8 am and 8 pm", "8 am and 8 pm."),
            ("Commencez aspirine 81,5 mg à 8 h et 20 h.", "aspirine", "81,5 mg à 8 h et 20 h", "81,5 mg à 8 h"),
            ("Start aspirin 81 mg daily and book blood work at 2 pm.", "aspirin", "81 mg daily", "81 mg daily and book blood work at 2 pm"),
            ("Commencez aspirine 81 mg par jour et planifiez une prise de sang à 14 h.", "aspirine", "81 mg par jour", "81 mg par jour et planifiez une prise de sang à 14 h")
        ] {
            let summary = try VisitReview.parse(proposal(quote: source, names: [name], instructions: [full]), transcript: source, medicines: [])
            let original = try XCTUnwrap(summary.medicines.first, source)
            var visit = DoctorVisit(transcript: source)
            visit.summary = summary
            visit.medicineBaseline = []
            XCTAssertEqual(try VisitReview.applying([original.id], from: visit, to: []).first?.instructions, full)
            var tampered = summary
            tampered.medicines[0].medicine.instructions = shortened
            visit.summary = tampered
            XCTAssertThrowsError(try VisitReview.applying([original.id], from: visit, to: []), source)
        }
        let aspirin = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        for (source, name) in [("Stop aspirin today.", "aspirin"), ("Cessez de prendre l'aspirine aujourd'hui.", "aspirine")] {
            let summary = try VisitReview.parse(proposal(quote: source, names: [name], instructions: [""], actions: ["stop"]), transcript: source, medicines: [aspirin])
            let change = try XCTUnwrap(summary.medicines.first, source)
            XCTAssertEqual(change.medicine.instructions, "")
            var visit = DoctorVisit(transcript: source)
            visit.summary = summary
            visit.medicineBaseline = [aspirin]
            XCTAssertTrue(try VisitReview.applying([change.id], from: visit, to: [aspirin]).isEmpty)
            XCTAssertTrue(try VisitReview.parse(proposal(quote: source, names: [name], instructions: [name], actions: ["stop"]), transcript: source, medicines: [aspirin]).medicines.isEmpty)
        }
    }

    func testDisplayedQuotesPreserveNegationHistoryConditionsExceptionsAndCourseContext() throws {
        let cases = [
            ("Do not book an appointment tomorrow.", ["book", "an appointment", "tomorrow."]),
            ("Ne prenez pas un rendez-vous demain.", ["prenez", "un rendez-vous", "demain."]),
            ("Do not start metformin 500 mg twice daily.", ["Do not start", "metformin", "500 mg", "twice daily"]),
            ("Ne commencez pas aspirine 81 mg par jour.", ["Ne commencez pas", "aspirine", "81 mg", "par jour"]),
            ("Last year the doctor told me to start aspirin 81 mg daily.", ["start aspirin 81 mg daily.", "81 mg daily"]),
            ("L’an dernier, le médecin m’avait dit de commencer aspirine 81 mg par jour.", ["commencer aspirine 81 mg par jour.", "81 mg par jour"]),
            ("If symptoms return, start aspirin 81 mg daily.", ["start aspirin 81 mg daily.", "aspirin"]),
            ("Si les symptômes reviennent, commencez aspirine 81 mg par jour.", ["commencez aspirine 81 mg par jour.", "aspirine"]),
            ("Take aspirin 81 mg daily except Mondays.", ["Take aspirin 81 mg daily", "81 mg daily"]),
            ("Prenez aspirine 81 mg par jour sauf le lundi.", ["Prenez aspirine 81 mg par jour", "81 mg par jour"]),
            ("Take aspirin 81 mg daily for five days.", ["Take aspirin 81 mg daily", "81 mg daily"]),
            ("Prenez aspirine 81 mg par jour pendant cinq jours.", ["Prenez aspirine 81 mg par jour", "81 mg par jour"]),
            ("Last year the doctor said, “Start aspirin 81 mg daily. Book blood work.”", ["Book blood work.", "blood work"])
        ]
        for (source, fragments) in cases {
            let quotes = ([source] + fragments).map { ["quote": $0] }
            let output = String(decoding: try JSONSerialization.data(withJSONObject: ["highlights": quotes, "followUps": quotes, "appointments": [], "medicines": []]), as: UTF8.self)
            let summary = try VisitReview.parse(output, transcript: source, medicines: [])
            XCTAssertEqual(summary.highlights, [VisitQuote(quote: source)], source)
            XCTAssertFalse(summary.followUps.contains { fragments.contains($0.quote) }, source)
            XCTAssertTrue(summary.followUps.contains(VisitQuote(quote: source)), source)
            XCTAssertTrue(summary.medicines.isEmpty)
        }
        for (source, fullWithoutPeriod, fragments) in [
            ("Yesterday, my knee hurt.", "Yesterday, my knee hurt", ["my knee hurt", "knee hurt"]),
            ("Hier, mon genou était douloureux.", "Hier, mon genou était douloureux", ["mon genou était douloureux", "genou était douloureux"]),
            ("The patient reported dizziness.", "The patient reported dizziness", ["dizziness"]),
            ("Le patient a rapporté des étourdissements.", "Le patient a rapporté des étourdissements", ["des étourdissements"]),
            ("Yesterday, my temperature was 36.7.", "Yesterday, my temperature was 36.7", ["Yesterday, my temperature was 36", "temperature was 36.7"])
        ] {
            let quotes = ([fullWithoutPeriod] + fragments).map { ["quote": $0] }
            let output = String(decoding: try JSONSerialization.data(withJSONObject: ["highlights": quotes, "followUps": quotes, "appointments": [], "medicines": []]), as: UTF8.self)
            let summary = try VisitReview.parse(output, transcript: source, medicines: [])
            XCTAssertEqual(summary.highlights, [VisitQuote(quote: fullWithoutPeriod)], source)
            XCTAssertEqual(summary.followUps, [VisitQuote(quote: fullWithoutPeriod)], source)
        }
        for source in ["If symptoms return, book blood work?", "Si les symptômes reviennent, prenez rendez-vous!", "If symptoms return, book blood work..."] {
            let shortened = String(source.dropLast())
            let output = String(decoding: try JSONSerialization.data(withJSONObject: ["highlights": [["quote": shortened]], "followUps": [], "appointments": [], "medicines": []]), as: UTF8.self)
            XCTAssertTrue(try VisitReview.parse(output, transcript: source, medicines: []).highlights.isEmpty, source)
        }
        let source = "We discussed laboratory preparation. Book blood work in two weeks."
        let output = #"{"highlights":[{"quote":"laboratory preparation"}],"followUps":[{"quote":"blood work"}],"appointments":[],"medicines":[]}"#
        let summary = try VisitReview.parse(output, transcript: source, medicines: [])
        XCTAssertEqual(summary.highlights, [VisitQuote(quote: "laboratory preparation")])
        XCTAssertTrue(summary.followUps.contains(VisitQuote(quote: "blood work")))
    }

    func testCandidatesKeepDecimalDosesAndExcludeUnchangedOrFollowUpFacts() {
        let source = "Start aspirin 81.5 mg daily. Continue the current treatment unchanged. Book laboratory tests next month. Cessez l'ibuprofène aujourd'hui. Gardez le traitement inchangé. Prenez un rendez-vous à la clinique."
        let candidates = VisitSourceGrounding.candidates(source)
        XCTAssertEqual(candidates.map(\.quote), ["Start aspirin 81.5 mg daily.", "Cessez l'ibuprofène aujourd'hui."])
        XCTAssertEqual(candidates.map(\.actions), [[.start], [.stop]])
        XCTAssertEqual(VisitSourceGrounding.candidates("Continue aspirin 81.5 mg daily.").first?.actions, [.update])
        XCTAssertEqual(VisitSourceGrounding.candidates("Continuez aspirine 81,5 mg par jour.").first?.actions, [.update])
    }

    func testDynamicCandidatesAndParserShareSourceIntentRejections() throws {
        let medicine = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        let sources = [
            "Do not start aspirin 81.5 mg daily.", "Could we start aspirin 81.5 mg daily?",
            "My father should start aspirin 81.5 mg daily.", "Ne commencez pas aspirine 81,5 mg par jour.",
            "Ma sœur commence aspirine 81,5 mg par jour.", "Continue aspirin 81.5 mg daily unchanged.",
            "Continuez aspirine 81,5 mg par jour au même traitement.",
            "Continue aspirin 81.5 mg daily without changes.",
            "Continue aspirin 81.5 mg daily without any modification."
        ]
        for source in sources {
            XCTAssertTrue(VisitSourceGrounding.candidates(source).isEmpty, source)
            for action in MedicineChangeAction.allCases {
                let output: [String: Any] = ["highlights": [], "followUps": [], "medicines": [["quote": source, "action": action.rawValue, "name": source.contains("aspirine") ? "aspirine" : "aspirin", "instructions": action == .stop ? "" : source]]]
                let json = String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self)
                XCTAssertTrue(try VisitReview.parse(json, transcript: source, medicines: [medicine]).medicines.isEmpty, source)
            }
            XCTAssertTrue(VisitReview.outputGrammar(transcript: source).contains(#"medicines ::= "[" ws "]""#), source)
        }
    }

    func testCompleteDecimalSentencePreventsTruncatedNegationBypass() throws {
        let source = "If necessary, start aspirin 81.5 mg daily."
        let output = #"{"highlights":[],"medicines":[{"quote":"start aspirin 81.5 mg daily.","action":"start","name":"aspirin","instructions":"81.5 mg daily"}],"followUps":[]}"#
        XCTAssertTrue(try VisitReview.parse(output, transcript: source, medicines: []).medicines.isEmpty)
        XCTAssertEqual(VisitSourceGrounding.sentences(source), [source])
    }

    func testCandidatesBoundSourceLengthQuoteLengthAndCountWithoutInventingData() {
        let many = (0..<20).map { "Start Medicine\($0) 5 mg daily." }.joined(separator: " ")
        let candidates = VisitSourceGrounding.candidates(many)
        XCTAssertEqual(candidates.count, 12)
        XCTAssertTrue(candidates.allSatisfy { many.contains($0.quote) })
        let tooLong = "Start medicine " + String(repeating: "longword ", count: 90) + "."
        XCTAssertTrue(VisitSourceGrounding.candidates(tooLong).isEmpty)
        let beyondChunk = String(repeating: "word ", count: 370) + ". Start aspirin 81 mg daily."
        XCTAssertTrue(VisitSourceGrounding.candidates(beyondChunk).isEmpty)
    }

    func testActionsBindToTheirMedicineWithinCompoundSourceSentences() throws {
        let source = "Stop aspirin and start ibuprofen 200 mg daily."
        let medicine = try XCTUnwrap(Catalog.medicines.first { $0.id == "ibuprofen" })
        let wrong = #"{"highlights":[],"medicines":[{"quote":"Stop aspirin and start ibuprofen 200 mg daily.","action":"stop","name":"ibuprofen","instructions":""}],"followUps":[]}"#
        XCTAssertTrue(try VisitReview.parse(wrong, transcript: source, medicines: [medicine]).medicines.isEmpty)
        let correct = wrong.replacingOccurrences(of: #""action":"stop""#, with: #""action":"start""#).replacingOccurrences(of: #""instructions":"""#, with: #""instructions":"200 mg daily""#)
        XCTAssertEqual(try VisitReview.parse(correct, transcript: source, medicines: [medicine]).medicines.first?.action, .start)
    }

    func testLegacyMultiSentenceMedicineQuotesRemainValidThroughApplying() throws {
        let source = "Start aspirin 81.5 mg daily. Book blood work next month."
        let output = #"{"highlights":[],"medicines":[{"quote":"Start aspirin 81.5 mg daily. Book blood work next month.","action":"start","name":"aspirin","instructions":"81.5 mg daily"}],"followUps":[]}"#
        let summary = try VisitReview.parse(output, transcript: source, medicines: [])
        XCTAssertEqual(summary.medicines.count, 1)
        XCTAssertEqual(VisitSourceGrounding.containingContext(quote: source, source: source), source)
        var visit = DoctorVisit(transcript: source)
        visit.summary = summary
        visit.medicineBaseline = []
        let change = try XCTUnwrap(summary.medicines.first)
        XCTAssertEqual(try VisitReview.applying([change.id], from: visit, to: []).first?.instructions, "81.5 mg daily")
    }

    func testMultiSentenceQuotedSpanRetainsCompleteFirstAndLastSourceSentences() throws {
        let source = "Do not start aspirin 81.5 mg daily. Book blood work next month if symptoms persist."
        let quote = "start aspirin 81.5 mg daily. Book blood work next month"
        XCTAssertEqual(VisitSourceGrounding.containingContext(quote: quote, source: source), source)
        let output: [String: Any] = ["highlights": [], "followUps": [], "medicines": [["quote": quote, "action": "start", "name": "aspirin", "instructions": "81.5 mg daily"]]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self)
        XCTAssertTrue(try VisitReview.parse(json, transcript: source, medicines: []).medicines.isEmpty)
    }

    func testCompoundSourceCanSupplyDistinctStopAndStartProposals() throws {
        let source = "Stop aspirin and start ibuprofen 200 mg daily."
        let medicine = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        let output = #"{"highlights":[],"medicines":[{"quote":"Stop aspirin and start ibuprofen 200 mg daily.","action":"stop","name":"aspirin","instructions":""},{"quote":"Stop aspirin and start ibuprofen 200 mg daily.","action":"start","name":"ibuprofen","instructions":"200 mg daily"}],"followUps":[]}"#
        let summary = try VisitReview.parse(output, transcript: source, medicines: [medicine])
        XCTAssertEqual(summary.medicines.map(\.action), [.stop, .start])
        XCTAssertEqual(VisitSourceGrounding.candidates(source).first?.actions.count, 2)
        let grammar = VisitReview.outputGrammar(transcript: source)
        XCTAssertTrue(grammar.contains(#"medicines ::= "[" ws (medicine (ws "," ws medicine){0,1})? ws "]""#))
        var visit = DoctorVisit(transcript: source)
        visit.summary = summary
        visit.medicineBaseline = [medicine]
        XCTAssertEqual(try VisitReview.applying(Set(summary.medicines.map(\.id)), from: visit, to: [medicine]).map(\.id), ["ibuprofen"])
    }

    func testReportedEnglishRegimenDoesNotBecomeAClinicianInstruction() throws {
        let medicine = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        for source in ["I take aspirin 81 mg daily.", "I am taking aspirin 81 mg daily.", "We currently take aspirin 81 mg daily."] {
            XCTAssertTrue(VisitSourceGrounding.candidates(source).isEmpty, source)
            let output: [String: Any] = ["highlights": [], "followUps": [], "medicines": [["quote": source, "action": "update", "name": "aspirin", "instructions": "81 mg daily"]]]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self)
            XCTAssertTrue(try VisitReview.parse(json, transcript: source, medicines: [medicine]).medicines.isEmpty, source)
        }
        let instruction = "Take aspirin 81 mg daily."
        XCTAssertEqual(VisitSourceGrounding.candidates(instruction).first?.actions, [.update])
        let output = #"{"highlights":[],"medicines":[{"quote":"Take aspirin 81 mg daily.","action":"update","name":"aspirin","instructions":"81 mg daily"}],"followUps":[]}"#
        XCTAssertEqual(try VisitReview.parse(output, transcript: instruction, medicines: [medicine]).medicines.first?.action, .update)
    }

    func testConjoinedSameVerbMedicinesStayWithinTheInstructionClause() throws {
        let aspirin = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        let ibuprofen = try XCTUnwrap(Catalog.medicines.first { $0.id == "ibuprofen" })
        for (source, names) in [("Stop aspirin and ibuprofen.", ["aspirin", "ibuprofen"]), ("Arrêtez aspirine et ibuprofène.", ["aspirine", "ibuprofène"])] {
            let changes = names.map { ["quote": source, "action": "stop", "name": $0, "instructions": ""] }
            let json = String(decoding: try JSONSerialization.data(withJSONObject: ["highlights": [], "followUps": [], "medicines": changes]), as: UTF8.self)
            let summary = try VisitReview.parse(json, transcript: source, medicines: [aspirin, ibuprofen])
            XCTAssertEqual(summary.medicines.map(\.medicine.id), ["aspirin", "ibuprofen"], source)
            XCTAssertEqual(VisitSourceGrounding.candidates(source).first?.maximumEntries, 2, source)
        }
        XCTAssertFalse(VisitSourceGrounding.permits(.stop, quote: "Stop aspirin and start ibuprofen 200 mg daily.", context: "Stop aspirin and start ibuprofen 200 mg daily.", name: "ibuprofen"))
        XCTAssertEqual(VisitSourceGrounding.candidates("Stop CustomMedicineA and CustomMedicineB.").first?.maximumEntries, 2)
    }

    func testDistinctSameActionInstructionsHaveCapacityForBothChanges() throws {
        let aspirin = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        let ibuprofen = try XCTUnwrap(Catalog.medicines.first { $0.id == "ibuprofen" })
        let cases = [
            ("Increase aspirin to 100 mg and reduce ibuprofen to 200 mg.", ["aspirin", "ibuprofen"], ["100 mg", "200 mg"]),
            ("Augmentez aspirine à 100 mg et réduisez ibuprofène à 200 mg.", ["aspirine", "ibuprofène"], ["100 mg", "200 mg"])
        ]
        for (source, names, instructions) in cases {
            let changes = names.indices.map { ["quote": source, "action": "update", "name": names[$0], "instructions": instructions[$0]] }
            let json = String(decoding: try JSONSerialization.data(withJSONObject: ["highlights": [], "followUps": [], "medicines": changes]), as: UTF8.self)
            XCTAssertEqual(try VisitReview.parse(json, transcript: source, medicines: [aspirin, ibuprofen]).medicines.map(\.medicine.instructions), instructions, source)
            let swapped = names.indices.map { ["quote": source, "action": "update", "name": names[$0], "instructions": instructions[1 - $0]] }
            let swappedJSON = String(decoding: try JSONSerialization.data(withJSONObject: ["highlights": [], "followUps": [], "medicines": swapped]), as: UTF8.self)
            XCTAssertTrue(try VisitReview.parse(swappedJSON, transcript: source, medicines: [aspirin, ibuprofen]).medicines.isEmpty, source)
            XCTAssertEqual(VisitSourceGrounding.candidates(source).first?.maximumEntries, 2, source)
            XCTAssertTrue(VisitReview.outputGrammar(transcript: source).contains(#"medicines ::= "[" ws (medicine (ws "," ws medicine){0,1})? ws "]""#), source)
        }
    }

    func testStopTakingChainsKeepTheOuterStopActionInBothLanguages() throws {
        let medicine = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        let cases = [
            ("Stop taking aspirin.", "aspirin"),
            ("Cessez de prendre l'aspirine.", "aspirine"),
            ("Arrêtez de prendre aspirine.", "aspirine")
        ]
        for (source, name) in cases {
            XCTAssertEqual(VisitSourceGrounding.candidates(source).first?.actions, [.stop], source)
            XCTAssertEqual(VisitSourceGrounding.candidates(source).first?.maximumEntries, 1, source)
            let output: [String: Any] = ["highlights": [], "followUps": [], "medicines": [["quote": source, "action": "stop", "name": name, "instructions": ""]]]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self)
            let summary = try VisitReview.parse(json, transcript: source, medicines: [medicine])
            XCTAssertEqual(summary.medicines.first?.action, .stop, source)
            var visit = DoctorVisit(transcript: source)
            visit.summary = summary
            visit.medicineBaseline = [medicine]
            XCTAssertTrue(try VisitReview.applying(Set(summary.medicines.map(\.id)), from: visit, to: [medicine]).isEmpty, source)
            let wrong: [String: Any] = ["highlights": [], "followUps": [], "medicines": [["quote": source, "action": "update", "name": name, "instructions": name]]]
            let wrongJSON = String(decoding: try JSONSerialization.data(withJSONObject: wrong), as: UTF8.self)
            XCTAssertTrue(try VisitReview.parse(wrongJSON, transcript: source, medicines: [medicine]).medicines.isEmpty, source)
        }
    }

    func testStartTakingChainsDoNotBecomeInnerDoseUpdates() throws {
        let medicine = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        let cases = [
            ("Begin taking aspirin 81 mg daily.", "aspirin", "81 mg daily"),
            ("Begin to take aspirin 81 mg daily.", "aspirin", "81 mg daily"),
            ("Commencez à prendre l'aspirine 81 mg par jour.", "aspirine", "81 mg par jour")
        ]
        for (source, name, instructions) in cases {
            XCTAssertEqual(VisitSourceGrounding.candidates(source).first?.actions, [.start], source)
            XCTAssertEqual(VisitSourceGrounding.candidates(source).first?.maximumEntries, 1, source)
            for action in [MedicineChangeAction.start, .update] {
                let output: [String: Any] = ["highlights": [], "followUps": [], "medicines": [["quote": source, "action": action.rawValue, "name": name, "instructions": instructions]]]
                let json = String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self)
                let summary = try VisitReview.parse(json, transcript: source, medicines: [medicine])
                XCTAssertEqual(summary.medicines.map(\.action), action == .start ? [.start] : [], source)
            }
        }
        let source = "Cessez de prendre l'aspirine."
        let shortened: [String: Any] = ["highlights": [], "followUps": [], "medicines": [["quote": "prendre l'aspirine.", "action": "update", "name": "aspirine", "instructions": "aspirine"]]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: shortened), as: UTF8.self)
        XCTAssertTrue(try VisitReview.parse(json, transcript: source, medicines: [medicine]).medicines.isEmpty)
    }

    func testTakingChainsPreserveIndependentActionsAndTheirDoseClauses() throws {
        let aspirin = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        let ibuprofen = try XCTUnwrap(Catalog.medicines.first { $0.id == "ibuprofen" })
        let cases = [
            ("Stop taking aspirin and increase ibuprofen to 200 mg daily.", ["aspirin", "ibuprofen"], "200 mg daily"),
            ("Cessez de prendre aspirine et augmentez ibuprofène à 200 mg par jour.", ["aspirine", "ibuprofène"], "200 mg par jour")
        ]
        for (source, names, instructions) in cases {
            let changes = [
                ["quote": source, "action": "stop", "name": names[0], "instructions": ""],
                ["quote": source, "action": "update", "name": names[1], "instructions": instructions]
            ]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: ["highlights": [], "followUps": [], "medicines": changes]), as: UTF8.self)
            let summary = try VisitReview.parse(json, transcript: source, medicines: [aspirin, ibuprofen])
            XCTAssertEqual(summary.medicines.map(\.action), [.stop, .update], source)
            XCTAssertEqual(summary.medicines.last?.medicine.instructions, instructions, source)
            XCTAssertEqual(VisitSourceGrounding.candidates(source).first?.maximumEntries, 2, source)
            XCTAssertEqual(Set(VisitSourceGrounding.candidates(source).first?.actions ?? []), Set([.stop, .update]), source)
            XCTAssertFalse(VisitSourceGrounding.permits(.update, quote: source, context: source, name: names[0], instructions: instructions), source)
            XCTAssertFalse(VisitSourceGrounding.permits(.stop, quote: source, context: source, name: names[1]), source)
        }
    }
}
