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
        XCTAssertEqual(visit.summary?.medicines[0].frequency, MedicationFrequency(count: 2, period: .day))
        XCTAssertEqual(visit.summary?.medicines[0].times, [])
        XCTAssertThrowsError(try VisitReview.applying([], from: visit, to: []))
    }
    func testVisitFrequencyAndExplicitTimesStayStructured() throws {
        let weekly = "Start metformin 500 mg 2 times per week."
        let weeklyOutput = #"{"highlights":[],"medicines":[{"action":"start","name":"metformin","instructions":"500 mg 2 times per week","quote":"Start metformin 500 mg 2 times per week."}],"followUps":[]}"#
        let weeklyChange = try XCTUnwrap(VisitReview.parse(weeklyOutput, transcript: weekly, medicines: []).medicines.first)
        XCTAssertEqual(weeklyChange.frequency, MedicationFrequency(count: 2, period: .week))
        XCTAssertTrue(weeklyChange.times.isEmpty)

        let timed = "Start metformin 500 mg at 8 am and 8 pm."
        let timedOutput = #"{"highlights":[],"medicines":[{"action":"start","name":"metformin","instructions":"500 mg at 8 am and 8 pm","quote":"Start metformin 500 mg at 8 am and 8 pm."}],"followUps":[]}"#
        let timedChange = try XCTUnwrap(VisitReview.parse(timedOutput, transcript: timed, medicines: []).medicines.first)
        XCTAssertEqual(timedChange.frequency, MedicationFrequency(count: 2, period: .day))
        XCTAssertEqual(timedChange.times, [DoseTime(hour: 8, minute: 0), DoseTime(hour: 20, minute: 0)])

        let conflict = "Start metformin 500 mg twice weekly at 8 am and 8 pm."
        let conflictOutput = #"{"highlights":[],"medicines":[{"action":"start","name":"metformin","instructions":"500 mg twice weekly at 8 am and 8 pm","quote":"Start metformin 500 mg twice weekly at 8 am and 8 pm."}],"followUps":[]}"#
        XCTAssertTrue(try VisitReview.parse(conflictOutput, transcript: conflict, medicines: []).medicines.isEmpty)
    }
    func testSharedQuoteDoesNotLendFrequencyOrTimesAcrossMedicines() throws {
        let frequencyQuote = "Start amlodipine as prescribed and continue metformin 500 mg twice daily."
        let frequencyOutput = #"{"highlights":[],"medicines":[{"action":"start","name":"amlodipine","instructions":"as prescribed","quote":"Start amlodipine as prescribed and continue metformin 500 mg twice daily."},{"action":"update","name":"metformin","instructions":"500 mg twice daily","quote":"Start amlodipine as prescribed and continue metformin 500 mg twice daily."}],"followUps":[],"appointments":[]}"#
        let savedMetformin = Catalog.medicines.first { $0.id == "metformin" }!
        let frequencyChanges = try VisitReview.parse(frequencyOutput, transcript: frequencyQuote, medicines: [savedMetformin]).medicines
        XCTAssertEqual(frequencyChanges.count, 2)
        let amlodipineChange = try XCTUnwrap(frequencyChanges.first { $0.medicine.id == "amlodipine" })
        let metforminChange = try XCTUnwrap(frequencyChanges.first { $0.medicine.id == "metformin" })
        XCTAssertNil(amlodipineChange.frequency)
        XCTAssertEqual(metforminChange.frequency, MedicationFrequency(count: 2, period: .day))

        let timeQuote = "Start metformin 500 mg at 8 am and start amlodipine 5 mg at 9 am."
        let timeOutput = #"{"highlights":[],"medicines":[{"action":"start","name":"metformin","instructions":"500 mg at 8 am","quote":"Start metformin 500 mg at 8 am and start amlodipine 5 mg at 9 am."},{"action":"start","name":"amlodipine","instructions":"5 mg at 9 am","quote":"Start metformin 500 mg at 8 am and start amlodipine 5 mg at 9 am."}],"followUps":[],"appointments":[]}"#
        let timeChanges = try VisitReview.parse(timeOutput, transcript: timeQuote, medicines: []).medicines
        XCTAssertEqual(timeChanges.first { $0.medicine.id == "metformin" }?.times, [DoseTime(hour: 8, minute: 0)])
        XCTAssertEqual(timeChanges.first { $0.medicine.id == "amlodipine" }?.times, [DoseTime(hour: 9, minute: 0)])
    }
    func testVisitSummaryEvaluationFixturesMatchExpectedOutputs() {
        for fixture in Evaluation.visitSummaryCases {
            XCTAssertTrue(fixture.matches(fixture.expectedJSON), fixture.name)
        }
    }
    func testLegacyVisitMedicineChangeDecodesWithoutScheduleFields() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","action":"start","medicine":{"id":"metformin","name":"Metformin","ingredients":["metformin"],"instructions":"500 mg twice daily"},"quote":"Start metformin 500 mg twice daily."}"#
        let change = try JSONDecoder().decode(VisitMedicineChange.self, from: Data(json.utf8))
        XCTAssertNil(change.frequency)
        XCTAssertTrue(change.times.isEmpty)
    }
    func testLegacyVisitChangeWithFrequencyTextStillAppliesWithoutStoredSchedule() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","action":"start","medicine":{"id":"metformin","name":"Metformin","ingredients":["metformin"],"instructions":"500 mg twice daily"},"quote":"Start metformin 500 mg twice daily."}"#
        let change = try JSONDecoder().decode(VisitMedicineChange.self, from: Data(json.utf8))
        var visit = DoctorVisit(transcript: "Start metformin 500 mg twice daily.")
        var summary = VisitSummary(); summary.medicines = [change]
        visit.summary = summary; visit.medicineBaseline = []

        let medicines = try VisitReview.applying([change.id], from: visit, to: [])
        XCTAssertEqual(medicines.first?.id, "metformin")
        XCTAssertNil(change.frequency)
        XCTAssertTrue(change.times.isEmpty)
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
        visit.transcript = "Do not change medications."
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

    func testFrenchQuoteObjectsRemainVerbatimAndBareStringsFail() throws {
        let source = "Commencez metformine 500 mg deux fois par jour. Prenez rendez-vous pour une prise de sang."
        let structured = #"{"highlights":[{"quote":"Commencez metformine 500 mg deux fois par jour."}],"medicines":[{"action":"start","name":"metformine","instructions":"500 mg deux fois par jour","quote":"Commencez metformine 500 mg deux fois par jour."}],"followUps":[{"quote":"Prenez rendez-vous pour une prise de sang."}]}"#
        let summary = try VisitReview.parse(structured, transcript: source, medicines: [])
        XCTAssertEqual(summary.highlights.map(\.quote), ["Commencez metformine 500 mg deux fois par jour."])
        XCTAssertEqual(summary.medicines.first?.medicine.id, "metformin")
        XCTAssertEqual(summary.medicines.first?.medicine.instructions, "500 mg deux fois par jour")
        XCTAssertEqual(summary.followUps.map(\.quote), ["Prenez rendez-vous pour une prise de sang."])
        let bareHighlights = structured.replacingOccurrences(of: #"[{"quote":"Commencez metformine 500 mg deux fois par jour."}]"#, with: #"["Commencez metformine 500 mg deux fois par jour."]"#)
        let bareFollowUps = structured.replacingOccurrences(of: #"[{"quote":"Prenez rendez-vous pour une prise de sang."}]"#, with: #"["Prenez rendez-vous pour une prise de sang."]"#)
        XCTAssertThrowsError(try VisitReview.parse(bareHighlights, transcript: source, medicines: []))
        XCTAssertThrowsError(try VisitReview.parse(bareFollowUps, transcript: source, medicines: []))
    }

    func testWellFormedVisitObjectsStillRequireSourceGrounding() throws {
        let ungrounded = #"{"highlights":[{"quote":"Your results are normal."}],"medicines":[{"action":"start","name":"metformin","instructions":"900 mg daily","quote":"Start metformin 900 mg daily."}],"followUps":[]}"#
        let summary = try VisitReview.parse(ungrounded, transcript: "Discussed exercise and sleep.", medicines: [])
        XCTAssertTrue(summary.highlights.isEmpty)
        XCTAssertTrue(summary.medicines.isEmpty)
        XCTAssertTrue(summary.followUps.isEmpty)
    }
}
