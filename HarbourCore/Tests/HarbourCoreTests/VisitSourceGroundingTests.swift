import XCTest
@testable import HarbourCore

final class VisitSourceGroundingTests: XCTestCase {
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
}
