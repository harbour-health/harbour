import Foundation
import XCTest
@testable import HarbourCore

/// Investigation-only tests. Passing assertions reproduce current defects;
/// these are not desired-behaviour regression tests and are outside the package.
final class VisitApplicationBugReproductionTests: XCTestCase {
    private let modelID = "visit-investigation-correct-stub"

    private func json(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    private func output(highlights: [String] = [], appointments: [String] = []) throws -> String {
        try json([
            "medicines": [], "followUps": [],
            "appointments": appointments.map { ["quote": $0] },
            "highlights": highlights.map { ["quote": $0] }
        ] as [String: Any])
    }

    @MainActor private func runHighlights(
        _ source: String,
        language: ModelLanguage = .english,
        selected: Set<Int>? = nil,
        quotes: [Int: [String]]
    ) async throws -> VisitExtractionRun {
        let units = VisitExtraction.sourceUnits(source)
        let selected = selected ?? Set(units.map(\.id))
        let classification = try json(["units": units.map { unit in
            ["id": unit.id, "kinds": [selected.contains(unit.id) ? "highlight" : "none"]] as [String: Any]
        }])
        let stageOutputs = try Dictionary(uniqueKeysWithValues: units.map { unit in
            (unit.id, try output(highlights: quotes[unit.id] ?? []))
        })
        return await VisitExtraction.run(transcript: source, medicines: [], language: language, modelID: modelID) { request in
            let value: String
            if request.id == "classify" {
                value = classification
            } else {
                let id = try XCTUnwrap(request.unitIDs.first)
                value = try XCTUnwrap(stageOutputs[id])
            }
            return .init(output: value, preparedPrompt: request.prompt, modelID: self.modelID,
                         configuration: ["origin": "controlled-correct-source-stub"])
        }
    }

    @MainActor func testIssue5TwelveValidHighlightsSucceedButThirteenRejectWholeRun() async throws {
        let facts = [
            "Left knee pain is mild.", "Right knee pain is mild.",
            "Left shoulder pain is mild.", "Right shoulder pain is mild.",
            "Left elbow pain is mild.", "Right elbow pain is mild.",
            "Left wrist pain is mild.", "Right wrist pain is mild.",
            "Left ankle pain is mild.", "Right ankle pain is mild.",
            "Neck pain is mild.", "Back pain is mild.", "Jaw pain is mild."
        ]
        for count in [12, 13] {
            let selectedFacts = Array(facts.prefix(count)), source = selectedFacts.joined(separator: " ")
            XCTAssertLessThan(source.count, VisitReview.chunkCharacters)
            let units = VisitExtraction.sourceUnits(source)
            XCTAssertEqual(units.map(\.text), selectedFacts)
            XCTAssertLessThanOrEqual(units.count, VisitExtraction.maximumUnits)
            for fact in selectedFacts {
                let individuallyValid = try VisitReview.parse(output(highlights: [fact]), transcript: source, medicines: [])
                XCTAssertEqual(individuallyValid.highlights, [VisitQuote(quote: fact)])
            }
            let run = try await runHighlights(source, quotes: Dictionary(uniqueKeysWithValues: units.map { ($0.id, [$0.text]) }))
            XCTAssertTrue(run.classificationCoverageComplete)
            XCTAssertEqual(run.generationCalls, count + 1)
            XCTAssertTrue(run.stages.allSatisfy { $0.error == nil && $0.generation?.preparedPrompt == $0.request.prompt })
            let assembled = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(run.assembledOutput.utf8)) as? [String: Any])
            let assembledHighlights = try XCTUnwrap(assembled["highlights"] as? [[String: String]])
            XCTAssertEqual(assembledHighlights.compactMap { $0["quote"] }, selectedFacts)
            if count == 12 {
                XCTAssertTrue(run.completed, run.errors.description)
                XCTAssertTrue(run.errors.isEmpty)
                XCTAssertEqual(run.acceptedSummary?.highlights.map(\.quote), selectedFacts)
                XCTAssertNoThrow(try VisitReview.parse(output(highlights: selectedFacts), transcript: source, medicines: []))
            } else {
                XCTAssertFalse(run.completed)
                XCTAssertNil(run.acceptedSummary)
                XCTAssertEqual(run.errors.count, 1)
                XCTAssertTrue(run.errors[0].hasPrefix("assembled_validation_failed:"), run.errors.description)
                XCTAssertThrowsError(try VisitReview.parse(output(highlights: selectedFacts), transcript: source, medicines: []))
            }
            print("VISIT_ISSUE_5 boundary=\(count) assembled=\(assembledHighlights.count) completed=\(run.completed) accepted=\(run.acceptedSummary?.highlights.count ?? -1)")
        }
    }

    @MainActor func testIssue6WholeQualifiedQuotePassesParserButCannotPassAnyUnitOwnership() async throws {
        let cases: [(ModelLanguage, String)] = [
            (.english, "Yesterday my brother said: \"I had a cough. It is worse at night.\""),
            (.french, "Hier, mon frère a dit : « J'avais une toux. Elle est pire la nuit. »")
        ]
        for (language, source) in cases {
            let direct = try VisitReview.parse(output(highlights: [source]), transcript: source, medicines: [])
            XCTAssertEqual(direct.highlights, [VisitQuote(quote: source)], source)
            let units = VisitExtraction.sourceUnits(source)
            XCTAssertGreaterThan(units.count, 1)
            XCTAssertFalse(units.contains { $0.text.contains(source) })
            let selected = Set(units.filter { $0.text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) }.map(\.id))
            XCTAssertEqual(selected.count, 2, units.description)
            for unit in units where selected.contains(unit.id) {
                XCTAssertTrue(unit.contexts.contains(source), "Full historical speaker context must actually be available: \(unit)")
                // The short quote is intentionally unsafe to display as an unqualified fact.
                let shortened = try VisitReview.parse(output(highlights: [unit.text]), transcript: source, medicines: [])
                XCTAssertTrue(shortened.highlights.isEmpty, unit.text)
            }
            let run = try await runHighlights(source, language: language, selected: selected,
                                             quotes: Dictionary(uniqueKeysWithValues: selected.map { ($0, [source]) }))
            XCTAssertTrue(run.completed, run.errors.description)
            XCTAssertTrue(run.errors.isEmpty)
            XCTAssertTrue(try XCTUnwrap(run.acceptedSummary).highlights.isEmpty)
            for id in selected {
                XCTAssertTrue(run.warnings.contains("unrelated_quote.unit.\(id).highlights"), run.warnings.description)
            }
            let generationOutputs = run.stages.dropFirst().compactMap { $0.generation?.output }
            XCTAssertEqual(generationOutputs.count, selected.count)
            for raw in generationOutputs {
                XCTAssertEqual(try VisitReview.parse(raw, transcript: source, medicines: []).highlights, [VisitQuote(quote: source)])
            }
            print("VISIT_ISSUE_6 language=\(language) units=\(units.count) fullQuoteValid=true retainedHighlights=\(run.acceptedSummary?.highlights.count ?? -1)")
        }
    }

    @MainActor func testIssue6ControlsAcceptSingleSentenceQualifiedAndSeparateOrdinaryFacts() async throws {
        for (language, source) in [
            (ModelLanguage.english, "Yesterday my brother reported a cough."),
            (.french, "Hier, mon frère a signalé une toux."),
            (.english, "The patient has a cough. Sleep quality is poor.")
        ] {
            let units = VisitExtraction.sourceUnits(source)
            let run = try await runHighlights(source, language: language,
                                             quotes: Dictionary(uniqueKeysWithValues: units.map { ($0.id, [$0.text]) }))
            XCTAssertTrue(run.completed, run.errors.description)
            XCTAssertEqual(run.acceptedSummary?.highlights.map(\.quote), units.map(\.text))
            XCTAssertTrue(run.warnings.isEmpty, run.warnings.description)
        }
    }

    func testIssue7ParserProducedAppointmentOnlyStateTriggersActualEmptyPredicate() throws {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["HARBOUR_INVESTIGATION_SOURCE_ROOT"],
                                 "Set HARBOUR_INVESTIGATION_SOURCE_ROOT to the current copied source root for exact UI predicate binding")
        let viewURL = URL(fileURLWithPath: root).appendingPathComponent("Harbour/VisitsView.swift")
        let viewSource = try String(contentsOf: viewURL, encoding: .utf8)
        let exactPredicate = "if summary.highlights.isEmpty && summary.followUps.isEmpty && summary.medicines.isEmpty { Text(\"No details extracted. Review the transcript.\")"
        XCTAssertTrue(viewSource.contains(exactPredicate), "UI predicate changed; do not assert the historical reproduction against different UI bytes")
        XCTAssertTrue(viewSource.contains("if let appointments = summary.appointments, !appointments.isEmpty"))
        func exactCurrentEmptyPredicate(_ summary: VisitSummary) -> Bool {
            summary.highlights.isEmpty && summary.followUps.isEmpty && summary.medicines.isEmpty
        }
        for source in ["Appointment tomorrow at 3 pm.", "Rendez-vous demain à 15 h."] {
            for raw in [try output(), try output(appointments: [source])] {
                let summary = try VisitReview.parse(raw, transcript: source, medicines: [])
                XCTAssertEqual(summary.appointments, [VisitQuote(quote: source)])
                XCTAssertTrue(summary.highlights.isEmpty)
                XCTAssertTrue(summary.followUps.isEmpty)
                XCTAssertTrue(summary.medicines.isEmpty)
                XCTAssertFalse(try XCTUnwrap(summary.appointments).isEmpty, "Appointment display branch is reachable")
                XCTAssertTrue(exactCurrentEmptyPredicate(summary), "The same state also reaches the false empty warning")
            }
        }
        let reallyEmpty = try VisitReview.parse(output(), transcript: "General discussion.", medicines: [])
        XCTAssertTrue((reallyEmpty.appointments ?? []).isEmpty)
        XCTAssertTrue(exactCurrentEmptyPredicate(reallyEmpty))
        let ordinaryFollowUp = try VisitReview.parse(output(), transcript: "Return in three weeks.", medicines: [])
        XCTAssertFalse(ordinaryFollowUp.followUps.isEmpty)
        XCTAssertFalse(exactCurrentEmptyPredicate(ordinaryFollowUp))
        print("VISIT_ISSUE_7 parserAppointmentOnlyReachable=true actualUIPredicateBound=true simultaneousAppointmentAndEmptyBranches=true")
    }
}
