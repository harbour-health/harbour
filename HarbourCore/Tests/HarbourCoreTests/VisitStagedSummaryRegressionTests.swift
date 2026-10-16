import Foundation
import XCTest
@testable import HarbourCore

final class VisitStagedSummaryRegressionTests: XCTestCase {
    private func json(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    private func output(highlights: [String] = [], medicines: [[String: String]] = [], appointments: [String] = []) throws -> String {
        try json(["medicines": medicines, "followUps": [], "appointments": appointments.map { ["quote": $0] },
                  "highlights": highlights.map { ["quote": $0] }] as [String: Any])
    }

    @MainActor private func extract(_ source: String, language: ModelLanguage = .english,
                                    selected: Set<Int>? = nil, outputs: [Int: String]) async throws -> VisitExtractionRun {
        let units = VisitExtraction.sourceUnits(source), selected = selected ?? Set(units.map(\.id))
        let classification = try json(["units": units.map { unit in
            ["id": unit.id, "kinds": [selected.contains(unit.id) ? "highlight" : "none"]] as [String: Any]
        }])
        return await VisitExtraction.run(transcript: source, medicines: [], language: language, modelID: "fixed") { request in
            let value: String
            if request.id == "classify" { value = classification }
            else {
                let id = try XCTUnwrap(request.unitIDs.first)
                value = try XCTUnwrap(outputs[id])
            }
            return .init(output: value, preparedPrompt: request.prompt, modelID: "fixed")
        }
    }

    @MainActor func testStagedHighlightsRetainTwelveThirteenAndTwentyFourItemsInBothLanguages() async throws {
        for language in [ModelLanguage.english, .french] {
            for count in [12, 13, VisitExtraction.maximumUnits] {
                let facts = (1...count).map { language == .english ? "Pain in area \($0) is mild." : "La douleur dans la zone \($0) est légère." }
                let source = facts.joined(separator: " "), units = VisitExtraction.sourceUnits(source)
                XCTAssertLessThan(source.count, VisitReview.chunkCharacters)
                XCTAssertEqual(units.map(\.text), facts)
                let outputs = try Dictionary(uniqueKeysWithValues: units.map { ($0.id, try output(highlights: [$0.text])) })
                let run = try await extract(source, language: language, outputs: outputs)
                XCTAssertTrue(run.completed, run.errors.description)
                XCTAssertTrue(run.errors.isEmpty)
                XCTAssertTrue(run.warnings.isEmpty, run.warnings.description)
                XCTAssertEqual(run.generationCalls, count + 1)
                XCTAssertEqual(run.acceptedSummary?.highlights.map(\.quote), facts)
                if count == 12 {
                    XCTAssertEqual(try VisitReview.parse(run.assembledOutput, transcript: source, medicines: []).highlights.map(\.quote), facts)
                } else {
                    // Combining stages does not widen the public single-call parser.
                    XCTAssertThrowsError(try VisitReview.parse(run.assembledOutput, transcript: source, medicines: []))
                }
            }
        }
    }

    func testStagedParserRejectsForgedBoundsAndKeepsAggregateCap() throws {
        let source = "The patient has a mild cough."
        for count in [0, -1, VisitExtraction.maximumUnits + 1, Int.max] {
            XCTAssertThrowsError(try VisitReview.parseStaged(output(), transcript: source, medicines: [], unitCount: count))
        }
        let thirteen = try output(highlights: Array(repeating: source, count: 13))
        XCTAssertThrowsError(try VisitReview.parse(thirteen, transcript: source, medicines: []))
        XCTAssertThrowsError(try VisitReview.parseStaged(thirteen, transcript: source, medicines: [], unitCount: 1))
        XCTAssertEqual(try VisitReview.parseStaged(thirteen, transcript: source, medicines: [], unitCount: 2).highlights, [VisitQuote(quote: source)])
        let maximum = VisitExtraction.maximumUnits * VisitReview.maximumModelItemsPerCategory
        let atBound = try output(highlights: Array(repeating: source, count: maximum))
        XCTAssertEqual(try VisitReview.parseStaged(atBound, transcript: source, medicines: [], unitCount: VisitExtraction.maximumUnits).highlights.count, 1)
        let overBound = try output(highlights: Array(repeating: source, count: maximum + 1))
        XCTAssertThrowsError(try VisitReview.parseStaged(overBound, transcript: source, medicines: [], unitCount: VisitExtraction.maximumUnits))
    }

    @MainActor func testEachExtractionStageStillRejectsThirteenItems() async throws {
        let source = "The patient has a mild cough."
        for count in [12, 13] {
            let raw = try output(highlights: Array(repeating: source, count: count))
            let run = try await extract(source, outputs: [0: raw])
            XCTAssertEqual(run.stages.last?.generation?.output, raw)
            if count == 12 {
                XCTAssertTrue(run.completed, run.errors.description)
                XCTAssertEqual(run.acceptedSummary?.highlights, [VisitQuote(quote: source)])
            } else {
                XCTAssertFalse(run.completed)
                XCTAssertNil(run.acceptedSummary)
                XCTAssertTrue(run.errors.contains { $0.hasPrefix("extraction_invalid.unit.0:") })
            }
        }
    }

    @MainActor func testCompleteHistoricalContextQuotesSurviveUnitExtractionInBothLanguages() async throws {
        for (language, source) in [
            (ModelLanguage.english, "Yesterday my brother said: \"I had a cough. It is worse at night.\""),
            (.french, "Hier, mon frère a dit : « J'avais une toux. Elle est pire la nuit. »")
        ] {
            let units = VisitExtraction.sourceUnits(source)
            let selected = Set(units.filter { $0.text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) }.map(\.id))
            XCTAssertEqual(selected.count, 2)
            for unit in units where selected.contains(unit.id) {
                XCTAssertTrue(unit.contexts.contains(source))
                XCTAssertFalse(unit.text.contains(source))
                XCTAssertTrue(try VisitReview.parse(output(highlights: [unit.text]), transcript: source, medicines: []).highlights.isEmpty)
            }
            let complete = try output(highlights: [source])
            let run = try await extract(source, language: language, selected: selected,
                                        outputs: Dictionary(uniqueKeysWithValues: selected.map { ($0, complete) }))
            XCTAssertTrue(run.completed, run.errors.description)
            XCTAssertTrue(run.warnings.isEmpty, run.warnings.description)
            XCTAssertEqual(run.acceptedSummary?.highlights, [VisitQuote(quote: source)])
            XCTAssertEqual(run.stages.dropFirst().compactMap { $0.generation?.output }, Array(repeating: complete, count: selected.count))

            // Context expansion cannot make the shortened, qualified statements valid.
            let shortened = try Dictionary(uniqueKeysWithValues: units.filter { selected.contains($0.id) }.map { ($0.id, try output(highlights: [$0.text])) })
            let incomplete = try await extract(source, language: language, selected: selected, outputs: shortened)
            XCTAssertTrue(incomplete.completed, incomplete.errors.description)
            XCTAssertTrue(try XCTUnwrap(incomplete.acceptedSummary).highlights.isEmpty)
            XCTAssertTrue(incomplete.warnings.contains("proposals_rejected.highlights"))
        }
    }

    @MainActor func testContextExpansionRejectsUnrelatedParagraphsAndDoesNotExpandMedicineOwnership() async throws {
        for (language, source, name, instructions) in [
            (ModelLanguage.english, "Last year the doctor said: \"Discuss exercise. Start aspirin 81 mg daily.\"", "aspirin", "81 mg daily"),
            (.french, "L'an dernier, le médecin a dit : « Discutez de l'exercice. Commencez aspirine 81 mg par jour. »", "aspirine", "81 mg par jour")
        ] {
            let unit = try XCTUnwrap(VisitExtraction.sourceUnits(source).first)
            XCTAssertTrue(unit.contexts.contains(source))
            let medicine = ["quote": source, "action": "start", "name": name, "instructions": instructions]
            let raw = try output(highlights: [source], medicines: [medicine])
            XCTAssertTrue(try VisitReview.parse(raw, transcript: source, medicines: []).medicines.isEmpty)
            let run = try await extract(source, language: language, selected: [unit.id], outputs: [unit.id: raw])
            XCTAssertTrue(run.completed, run.errors.description)
            XCTAssertEqual(run.acceptedSummary?.highlights, [VisitQuote(quote: source)])
            XCTAssertTrue(try XCTUnwrap(run.acceptedSummary).medicines.isEmpty)
            XCTAssertTrue(run.warnings.contains("unrelated_quote.unit.\(unit.id).medicines"))
            XCTAssertEqual(run.stages.last?.generation?.output, raw)

            let extended = source + (language == .english ? " Weight is 72 kg." : " Le poids est de 72 kg.")
            let wrongParagraph = try output(highlights: [extended])
            let unrelated = try await extract(extended, language: language, selected: [0], outputs: [0: wrongParagraph])
            XCTAssertTrue(unrelated.completed, unrelated.errors.description)
            XCTAssertTrue(try XCTUnwrap(unrelated.acceptedSummary).highlights.isEmpty)
            XCTAssertTrue(unrelated.warnings.contains("unrelated_quote.unit.0.highlights"))
        }
        let source = "Cough is mild. Nausea is mild."
        let unrelated = try await extract(source, selected: [0], outputs: [0: try output(highlights: [source])])
        XCTAssertTrue(unrelated.completed, unrelated.errors.description)
        XCTAssertTrue(try XCTUnwrap(unrelated.acceptedSummary).highlights.isEmpty)
        XCTAssertTrue(unrelated.warnings.contains("unrelated_quote.unit.0.highlights"))
    }

    @MainActor func testContextExpansionStillRejectsOversizedRetainedContextBeforeGeneration() async throws {
        let chunk = "Cough persists."
        let full = "Yesterday my brother said: \"" + String(repeating: chunk + " ", count: 250) + "\""
        XCTAssertGreaterThan(full.count, VisitExtraction.maximumRetainedContextCharacters)
        let run = await VisitExtraction.run(transcript: chunk, fullTranscript: full, medicines: []) { _ in
            XCTFail("Oversized retained context must fail before model generation")
            return .init(output: "", modelID: "fixed")
        }
        XCTAssertFalse(run.completed)
        XCTAssertTrue(run.stages.isEmpty)
        XCTAssertEqual(run.errors, ["source_context_out_of_bounds"])
    }

    func testSummaryIsEmptyIncludesParserProducedAppointmentsAndAllOtherCategories() throws {
        var empty = VisitSummary()
        XCTAssertTrue(empty.isEmpty)
        empty.appointments = []
        XCTAssertTrue(empty.isEmpty)
        for source in ["Appointment tomorrow at 3 pm.", "Rendez-vous demain à 15 h."] {
            for raw in [try output(), try output(appointments: [source])] {
                let summary = try VisitReview.parse(raw, transcript: source, medicines: [])
                XCTAssertEqual(summary.appointments, [VisitQuote(quote: source)])
                XCTAssertTrue(summary.highlights.isEmpty && summary.followUps.isEmpty && summary.medicines.isEmpty)
                XCTAssertFalse(summary.isEmpty)
                var merged = VisitSummary()
                merged.merge(summary)
                XCTAssertFalse(merged.isEmpty)
                XCTAssertFalse(try JSONDecoder().decode(VisitSummary.self, from: JSONEncoder().encode(summary)).isEmpty)
            }
        }
        let highlight = "The patient has a mild cough."
        XCTAssertFalse(try VisitReview.parse(output(highlights: [highlight]), transcript: highlight, medicines: []).isEmpty)
        XCTAssertFalse(try VisitReview.parse(output(), transcript: "Return in three weeks.", medicines: []).isEmpty)
        let source = "Start metformin 500 mg twice daily."
        let medicine = ["quote": source, "action": "start", "name": "metformin", "instructions": "500 mg twice daily"]
        XCTAssertFalse(try VisitReview.parse(output(medicines: [medicine]), transcript: source, medicines: []).isEmpty)
        XCTAssertTrue(try VisitReview.parse(output(), transcript: "General discussion.", medicines: []).isEmpty)
    }
}
