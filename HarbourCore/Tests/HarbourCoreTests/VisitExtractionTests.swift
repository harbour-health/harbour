import XCTest
@testable import HarbourCore

final class VisitExtractionTests: XCTestCase {
    private let empty = #"{"medicines":[],"followUps":[],"appointments":[],"highlights":[]}"#
    private func output(medicines: [[String: String]] = [], followUps: [String] = [], highlights: [String] = []) throws -> String {
        let value: [String: Any] = ["medicines": medicines, "followUps": followUps.map { ["quote": $0] }, "appointments": [], "highlights": highlights.map { ["quote": $0] }]
        return String(decoding: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), as: UTF8.self)
    }
    private func classification(_ units: [VisitSourceUnit], kind: String = "medicine") throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["units": units.map { ["id": $0.id, "kinds": [kind]] as [String: Any] }]), as: UTF8.self)
    }

    func testExtractionReadsSourceIndependentlyOfClassifierCategoryGuesses() throws {
        for language in [ModelLanguage.english, .french] {
            let source = language == .english ? "Return for a check in four months." : "Revenez pour un contrôle dans quatre mois."
            let unit = try XCTUnwrap(VisitExtraction.sourceUnits(source).first)
            let first = try VisitExtraction.extractionRequest(unit: unit, transcript: source, kinds: [.medicine], language: language)
            let second = try VisitExtraction.extractionRequest(unit: unit, transcript: source, kinds: [.appointment, .uncertain], language: language)
            XCTAssertEqual(first, second)
            XCTAssertFalse(first.prompt.contains("modelClassifications"))
            XCTAssertTrue(first.prompt.contains(source))
            XCTAssertEqual(first.grammar, VisitReview.outputGrammar())
        }
    }

    func testClassificationAccountsForEveryUnitWithoutChoosingClinicalValues() throws {
        let source = "Increase amlodipine to 7.5 mg once daily. Return in three weeks."
        let units = VisitExtraction.sourceUnits(source)
        XCTAssertEqual(units.count, 2)
        let request = try VisitExtraction.classificationRequest(units: units, language: .english)
        XCTAssertEqual(request.unitIDs, [0, 1]); XCTAssertEqual(request.maximumTokens, 650)
        XCTAssertFalse(request.prompt.contains(#""kinds":["none"]"#))
        XCTAssertFalse(request.grammar.contains("amlodipine"))
        XCTAssertEqual(try VisitExtraction.parseClassification(classification(units, kind: "none"), units: units).map(\.kinds), [[.none], [.none]])
        for invalid in [
            #"{"units":[{"id":0,"kinds":["medicine"]}]}"#,
            #"{"units":[{"id":0,"kinds":["medicine"]},{"id":0,"kinds":["medicine"]}]}"#,
            #"{"units":[{"id":1,"kinds":["medicine"]},{"id":0,"kinds":["medicine"]}]}"#,
            #"{"units":[{"id":0,"kinds":["none","medicine"]},{"id":1,"kinds":["none"]}]}"#,
            #"{"units":[{"id":0,"kinds":["medicine","medicine"]},{"id":1,"kinds":["none"]}]}"#,
            #"{"units":[{"id":0,"kinds":[]},{"id":1,"kinds":["none"]}]}"#,
            #"{"units":[{"id":0,"kinds":["medicine"],"dose":"7.5"},{"id":1,"kinds":["none"]}]}"#
        ] { XCTAssertThrowsError(try VisitExtraction.parseClassification(invalid, units: units), invalid) }
        let many = (1...60).map { "Source sentence \($0)." }.joined(separator: " ")
        let grouped = VisitExtraction.sourceUnits(many)
        XCTAssertLessThanOrEqual(grouped.count, 24)
        XCTAssertEqual(grouped.map(\.text).joined(separator: " "), many)
    }

    @MainActor func testStagesRetainModelDecisionsPromptsAndFullValidatedChangesInBothLanguages() async throws {
        let saved = [try XCTUnwrap(Catalog.resolve("amlodipine")), try XCTUnwrap(Catalog.resolve("naproxen"))]
        for (language, update, name, directions, stop, stoppedName, followUp) in [
            (ModelLanguage.english, "Increase amlodipine to 7.5 mg once daily at 09:15.", "amlodipine", "7.5 mg once daily at 09:15", "Discontinue naproxen.", "naproxen", "Return to the clinic in three weeks."),
            (ModelLanguage.french, "Augmentez amlodipine à 7,5 mg une fois par jour à 9 h 15.", "amlodipine", "7,5 mg une fois par jour à 9 h 15", "Cessez naproxène.", "naproxène", "Revenez à la clinique dans trois semaines.")
        ] {
            let source = [update, stop, followUp].joined(separator: " ")
            let units = VisitExtraction.sourceUnits(source)
            XCTAssertEqual(units.count, 3)
            var requests: [VisitStageRequest] = []
            let run = await VisitExtraction.run(transcript: source, medicines: saved, language: language, modelID: "fixed") { request in
                requests.append(request)
                let value: String
                switch request.id {
                case "classify": value = try self.classification(units)
                case "extract.0": value = try self.output(medicines: [["quote": update, "action": "update", "name": name, "instructions": directions]])
                case "extract.1": value = try self.output(medicines: [["quote": stop, "action": "stop", "name": stoppedName, "instructions": ""]])
                default: value = try self.output(followUps: [followUp])
                }
                return .init(output: value, preparedPrompt: "prepared:" + request.prompt, modelID: "fixed", configuration: ["context": "4096"])
            }
            XCTAssertTrue(run.completed, run.errors.description); XCTAssertTrue(run.classificationCoverageComplete)
            XCTAssertEqual(requests.map(\.id), ["classify", "extract.0", "extract.1", "extract.2"])
            XCTAssertEqual(run.maximumRequestedTokens, 2600); XCTAssertEqual(run.generationCalls, 4)
            XCTAssertEqual(run.outputOrigin, "application_assembled_model_stages")
            XCTAssertTrue(run.stages.allSatisfy { $0.generation?.preparedPrompt == "prepared:" + $0.request.prompt && $0.generation?.modelID == "fixed" })
            XCTAssertTrue(requests.dropFirst().allSatisfy { $0.grammar == VisitReview.outputGrammar() && $0.maximumTokens == 650 })
            let summary = try XCTUnwrap(run.acceptedSummary)
            XCTAssertEqual(summary.medicines.map(\.action), [.update, .stop]); XCTAssertEqual(summary.followUps.map(\.quote), [followUp])
            XCTAssertEqual(summary.medicines.first?.medicine.instructions, directions)
            XCTAssertEqual(summary.medicines.first?.times, [DoseTime(hour: 9, minute: 15)])
            var visit = DoctorVisit(transcript: source); visit.summary = summary; visit.medicineBaseline = saved; visit.extractionRuns = [run]
            let applied = try VisitReview.applying(Set(summary.medicines.map(\.id)), from: visit, to: saved)
            XCTAssertEqual(applied.map(\.id), ["amlodipine"])
            XCTAssertEqual(try JSONDecoder().decode(DoctorVisit.self, from: JSONEncoder().encode(visit)), visit)
        }
    }

    @MainActor func testModelNoneAndDeclinedUnitNeverForceAClinicalProposal() async throws {
        let source = "Start amlodipine 5 mg twice daily."
        let units = VisitExtraction.sourceUnits(source)
        for kind in ["none", "medicine"] {
            let run = await VisitExtraction.run(transcript: source, medicines: [], modelID: "fixed") { request in
                .init(output: request.id == "classify" ? try self.classification(units, kind: kind) : self.empty, modelID: "fixed")
            }
            XCTAssertTrue(run.completed); XCTAssertTrue(try XCTUnwrap(run.acceptedSummary).medicines.isEmpty)
            XCTAssertEqual(run.stages.count, kind == "none" ? 1 : 2)
            XCTAssertTrue(run.warnings.contains("possible_medicine_omission"))
            if kind == "medicine" { XCTAssertTrue(run.warnings.contains("selected_unit_declined.0")) }
        }
    }

    @MainActor func testFullHistoricalAndNegativeContextSurvivesChunkExtraction() async throws {
        let medicine = try XCTUnwrap(Catalog.resolve("amlodipine"))
        for (full, chunk) in [
            ("Previous treatment. Increase amlodipine to 7.5 mg once daily.", "Increase amlodipine to 7.5 mg once daily."),
            ("Do not increase amlodipine to 7.5 mg once daily.", "Do not increase amlodipine to 7.5 mg once daily.")
        ] {
            let units = VisitExtraction.sourceUnits(chunk, fullTranscript: full)
            XCTAssertTrue(units.first?.contexts.contains(where: { $0 == full }) == true, full)
            let proposed = try output(medicines: [["quote": chunk, "action": "update", "name": "amlodipine", "instructions": "7.5 mg once daily"]])
            let run = await VisitExtraction.run(transcript: chunk, fullTranscript: full, medicines: [medicine], modelID: "fixed") { request in
                .init(output: request.id == "classify" ? try self.classification(units) : proposed, modelID: "fixed")
            }
            XCTAssertTrue(run.completed, run.errors.description)
            XCTAssertEqual(run.validationTranscript, full)
            XCTAssertTrue(try XCTUnwrap(run.acceptedSummary).medicines.isEmpty)
            XCTAssertEqual(run.stages.last?.generation?.output, proposed)
            XCTAssertTrue(run.warnings.contains("medicine_proposals_rejected"))
        }
    }

    @MainActor func testFailuresAndChangedModelRetainEvidenceAndAbortAcceptance() async throws {
        let source = "Start amlodipine 5 mg twice daily.", units = VisitExtraction.sourceUnits("Start amlodipine 5 mg twice daily.")
        let invalid = await VisitExtraction.run(transcript: source, medicines: [], modelID: "fixed") { _ in .init(output: #"{"units":[]}"#, modelID: "fixed") }
        XCTAssertFalse(invalid.completed); XCTAssertEqual(invalid.stages.count, 1); XCTAssertNil(invalid.acceptedSummary)
        let changed = await VisitExtraction.run(transcript: source, medicines: [], modelID: "fixed") { request in
            .init(output: request.id == "classify" ? try self.classification(units) : self.empty, modelID: request.id == "classify" ? "fixed" : "different")
        }
        XCTAssertFalse(changed.completed); XCTAssertTrue(changed.errors.contains("model_identity_changed"))
        let failure = await VisitExtraction.run(transcript: source, medicines: [], modelID: "fixed") { request in
            .init(output: request.id == "classify" ? try self.classification(units) : "", preparedPrompt: "exact prepared", modelID: "fixed", configuration: ["context": "4096"], error: request.id == "classify" ? nil : "runtime failure")
        }
        XCTAssertFalse(failure.completed); XCTAssertEqual(failure.stages.last?.error, "runtime failure")
        XCTAssertEqual(failure.stages.last?.generation?.preparedPrompt, "exact prepared")
        XCTAssertEqual(failure.stages.last?.generation?.configuration["context"], "4096")
        let legacy = DoctorVisit(transcript: source)
        let data = try JSONEncoder().encode(legacy)
        XCTAssertNil(try JSONDecoder().decode(DoctorVisit.self, from: data).extractionRuns)
    }

    @MainActor func testUnrelatedUnitOutputIsNotMergedAndContextBoundsFailClosed() async throws {
        let source = "Start amlodipine 5 mg twice daily. Discontinue naproxen."
        let units = VisitExtraction.sourceUnits(source)
        let wrongUnit = try output(medicines: [["quote": "Discontinue naproxen.", "action": "stop", "name": "naproxen", "instructions": ""]])
        let run = await VisitExtraction.run(transcript: source, medicines: [try XCTUnwrap(Catalog.resolve("naproxen"))], modelID: "fixed") { request in
            let classified = #"{"units":[{"id":0,"kinds":["medicine"]},{"id":1,"kinds":["none"]}]}"#
            return .init(output: request.id == "classify" ? classified : wrongUnit, modelID: "fixed")
        }
        XCTAssertEqual(units.count, 2); XCTAssertTrue(run.completed)
        XCTAssertTrue(try XCTUnwrap(run.acceptedSummary).medicines.isEmpty)
        XCTAssertTrue(run.warnings.contains("unrelated_quote.unit.0.medicines"))
        XCTAssertEqual(run.stages.last?.generation?.output, wrongUnit)
        let wholeParagraph = try output(medicines: [["quote": source, "action": "stop", "name": "naproxen", "instructions": ""]])
        let paragraphRun = await VisitExtraction.run(transcript: source, medicines: [try XCTUnwrap(Catalog.resolve("naproxen"))], modelID: "fixed") { request in
            .init(output: request.id == "classify" ? #"{"units":[{"id":0,"kinds":["medicine"]},{"id":1,"kinds":["none"]}]}"# : wholeParagraph, modelID: "fixed")
        }
        XCTAssertTrue(paragraphRun.warnings.contains("unrelated_quote.unit.0.medicines"))
        XCTAssertFalse(paragraphRun.assembledOutput.contains(source))
        XCTAssertEqual(paragraphRun.stages.last?.generation?.output, wholeParagraph)
        let tooLong = await VisitExtraction.run(transcript: String(repeating: "x", count: VisitReview.chunkCharacters + 1), medicines: []) { _ in XCTFail("No generation for an out-of-bounds chunk"); return .init(output: "", modelID: "fixed") }
        XCTAssertFalse(tooLong.completed); XCTAssertTrue(tooLong.stages.isEmpty)
        XCTAssertEqual(tooLong.errors, ["source_context_out_of_bounds"])
    }
}
