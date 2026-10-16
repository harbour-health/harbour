import XCTest
@testable import HarbourCore

final class VisitScheduleScopeTests: XCTestCase {
    private func output(quote: String, name: String, instructions: String, action: MedicineChangeAction = .start) throws -> String {
        let object: [String: Any] = ["highlights": [], "followUps": [], "appointments": [], "medicines": [
            ["quote": quote, "name": name, "instructions": instructions, "action": action.rawValue]
        ]]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    func testCalendarAndCourseRestrictionsLeaveTheMedicineMinimumOptional() throws {
        let sources = [
            "Start aspirin 81 mg once daily at 08:00 except Mondays.",
            "Commencez aspirine 81 mg une fois par jour à 8 h sauf le lundi.",
            "Start aspirin 81 mg once daily at 08:00 for 5 days.",
            "Commencez aspirine 81 mg une fois par jour à 8 h pendant cinq jours.",
            "Start aspirin 81 mg once daily at 08:00 for eleven days.",
            "Commencez aspirine 81 mg une fois par jour à 8 h pendant quinze jours.",
            "Start aspirin 81 mg once daily at 08:00 for 1.5 weeks.",
            "Commencez aspirine 81 mg une fois par jour à 8 h pendant 1,5 semaine.",
            "Start aspirin 81 mg at 08:00 every other day.",
            "Start aspirin 81 mg at 08:00 every 2 days.",
            "Start aspirin 81 mg at 08:00 every six days.",
            "Start aspirin 81 mg at 08:00 every 1 week.",
            "Commencez aspirine 81 mg à 8 h tous les deux jours.",
            "Commencez aspirine 81 mg à 8 h tous les six jours.",
            "Commencez aspirine 81 mg à 8 h un jour sur deux.",
            "Start aspirin 81 mg at 08:00 every week.",
            "Commencez aspirine 81 mg à 8 h chaque semaine.",
            "Start aspirin 81 mg at 08:00 every two hours.",
            "Commencez aspirine 81 mg à 8 h toutes les deux heures.",
            "Start aspirin 81 mg at 08:00 every 30 minutes.",
            "Commencez aspirine 81 mg à 8 h toutes les 30 minutes.",
            "Start aspirin 81 mg at 08:00 every hour.",
            "Commencez aspirine 81 mg à 8 h chaque minute.",
            "Start aspirin 81 mg once daily at 08:00 on Tuesdays.",
            "Commencez aspirine 81 mg une fois par jour à 8 h les mardis.",
            "Start aspirin 81 mg once daily at 08:00 starting 2027-02-14."
        ]
        for source in sources {
            let candidates = VisitSourceGrounding.candidates(source)
            XCTAssertEqual(candidates.count, 1, source)
            XCTAssertNil(VisitSourceGrounding.requiredMedicineProposal(source, medicines: [], candidates: candidates), source)
            let rule = try XCTUnwrap(VisitReview.outputGrammar(transcript: source).components(separatedBy: "\n").first { $0.hasPrefix("medicines ::=") })
            XCTAssertTrue(rule.contains("})?"), source)
        }
    }

    func testRestrictedSourceDirectionsArePreservedWithoutAnUnconditionalMedicineProposal() throws {
        let cases = [
            ("Start aspirin 81 mg once daily at 08:00 except Mondays.", "aspirin", "81 mg once daily at 08:00 except Mondays"),
            ("Commencez aspirine 81 mg une fois par jour à 8 h sauf le lundi.", "aspirine", "81 mg une fois par jour à 8 h sauf le lundi"),
            ("Start aspirin 81 mg once daily at 08:00 for five days.", "aspirin", "81 mg once daily at 08:00 for five days"),
            ("Commencez aspirine 81 mg une fois par jour à 8 h pendant 5 jours.", "aspirine", "81 mg une fois par jour à 8 h pendant 5 jours"),
            ("Start aspirin 81 mg once daily at 08:00 for eleven days.", "aspirin", "81 mg once daily at 08:00 for eleven days"),
            ("Commencez aspirine 81 mg une fois par jour à 8 h pendant quinze jours.", "aspirine", "81 mg une fois par jour à 8 h pendant quinze jours"),
            ("Start aspirin 81 mg at 08:00 every other day.", "aspirin", "81 mg at 08:00 every other day"),
            ("Start aspirin 81 mg at 08:00 every 2 days.", "aspirin", "81 mg at 08:00 every 2 days"),
            ("Start aspirin 81 mg at 08:00 every six days.", "aspirin", "81 mg at 08:00 every six days"),
            ("Start aspirin 81 mg at 08:00 every 1 week.", "aspirin", "81 mg at 08:00 every 1 week"),
            ("Commencez aspirine 81 mg à 8 h tous les deux jours.", "aspirine", "81 mg à 8 h tous les deux jours"),
            ("Commencez aspirine 81 mg à 8 h tous les six jours.", "aspirine", "81 mg à 8 h tous les six jours"),
            ("Commencez aspirine 81 mg à 8 h un jour sur deux.", "aspirine", "81 mg à 8 h un jour sur deux"),
            ("Start aspirin 81 mg at 08:00 every week.", "aspirin", "81 mg at 08:00 every week"),
            ("Commencez aspirine 81 mg à 8 h chaque semaine.", "aspirine", "81 mg à 8 h chaque semaine"),
            ("Start aspirin 81 mg at 08:00 every two hours.", "aspirin", "81 mg at 08:00 every two hours"),
            ("Commencez aspirine 81 mg à 8 h toutes les deux heures.", "aspirine", "81 mg à 8 h toutes les deux heures"),
            ("Start aspirin 81 mg at 08:00 every 30 minutes.", "aspirin", "81 mg at 08:00 every 30 minutes"),
            ("Commencez aspirine 81 mg à 8 h toutes les 30 minutes.", "aspirine", "81 mg à 8 h toutes les 30 minutes"),
            ("Start aspirin 81 mg at 08:00 every hour.", "aspirin", "81 mg at 08:00 every hour"),
            ("Commencez aspirine 81 mg à 8 h chaque minute.", "aspirine", "81 mg à 8 h chaque minute"),
            ("Start aspirin 81 mg once daily at 08:00 on Thursdays.", "aspirin", "81 mg once daily at 08:00 on Thursdays"),
            ("Commencez aspirine 81 mg une fois par jour à 8 h les jeudis.", "aspirine", "81 mg une fois par jour à 8 h les jeudis")
        ]
        for (source, name, instructions) in cases {
            let summary = try VisitReview.parse(output(quote: source, name: name, instructions: instructions), transcript: source, medicines: [])
            XCTAssertTrue(summary.medicines.isEmpty, source)
            XCTAssertEqual(summary.highlights, [VisitQuote(quote: source)], source)
        }
    }

    func testShortenedQuoteCannotDiscardTheCompleteSourceRestriction() throws {
        for (prefix, restriction, name, instructions) in [
            ("Start aspirin 81 mg once daily at 08:00", " except Mondays.", "aspirin", "81 mg once daily at 08:00"),
            ("Commencez aspirine 81 mg une fois par jour à 8 h", " pendant cinq jours.", "aspirine", "81 mg une fois par jour à 8 h")
        ] {
            let source = prefix + restriction
            let summary = try VisitReview.parse(output(quote: prefix, name: name, instructions: instructions), transcript: source, medicines: [])
            XCTAssertTrue(summary.medicines.isEmpty, source)
            XCTAssertEqual(summary.highlights, [VisitQuote(quote: source)], source)
        }
    }

    func testTamperedStoredSummaryCannotApplyADailyScheduleWithADiscardedRestriction() throws {
        let aspirin = try XCTUnwrap(Catalog.medicines.first { $0.id == "aspirin" })
        for (source, quote, directions) in [
            ("Take aspirin 81 mg once daily at 08:00 except Mondays.", "Take aspirin 81 mg once daily at 08:00", "81 mg once daily at 08:00"),
            ("Prenez aspirine 81 mg une fois par jour à 8 h pendant cinq jours.", "Prenez aspirine 81 mg une fois par jour à 8 h", "81 mg une fois par jour à 8 h"),
            ("Take aspirin 81 mg at 08:00 every other day.", "Take aspirin 81 mg at 08:00", "81 mg at 08:00"),
            ("Take aspirin 81 mg at 08:00 every 2 days.", "Take aspirin 81 mg at 08:00", "81 mg at 08:00"),
            ("Take aspirin 81 mg at 08:00 every six days.", "Take aspirin 81 mg at 08:00", "81 mg at 08:00"),
            ("Take aspirin 81 mg at 08:00 every 1 week.", "Take aspirin 81 mg at 08:00", "81 mg at 08:00"),
            ("Prenez aspirine 81 mg à 8 h tous les deux jours.", "Prenez aspirine 81 mg à 8 h", "81 mg à 8 h"),
            ("Prenez aspirine 81 mg à 8 h tous les six jours.", "Prenez aspirine 81 mg à 8 h", "81 mg à 8 h"),
            ("Prenez aspirine 81 mg à 8 h un jour sur deux.", "Prenez aspirine 81 mg à 8 h", "81 mg à 8 h"),
            ("Take aspirin 81 mg at 08:00 every week.", "Take aspirin 81 mg at 08:00", "81 mg at 08:00"),
            ("Prenez aspirine 81 mg à 8 h chaque semaine.", "Prenez aspirine 81 mg à 8 h", "81 mg à 8 h"),
            ("Take aspirin 81 mg at 08:00 every two hours.", "Take aspirin 81 mg at 08:00", "81 mg at 08:00"),
            ("Prenez aspirine 81 mg à 8 h toutes les deux heures.", "Prenez aspirine 81 mg à 8 h", "81 mg à 8 h"),
            ("Take aspirin 81 mg at 08:00 every 30 minutes.", "Take aspirin 81 mg at 08:00", "81 mg at 08:00"),
            ("Prenez aspirine 81 mg à 8 h toutes les 30 minutes.", "Prenez aspirine 81 mg à 8 h", "81 mg à 8 h"),
            ("Take aspirin 81 mg at 08:00 every hour.", "Take aspirin 81 mg at 08:00", "81 mg at 08:00"),
            ("Prenez aspirine 81 mg à 8 h chaque minute.", "Prenez aspirine 81 mg à 8 h", "81 mg à 8 h")
        ] {
            var altered = aspirin; altered.instructions = directions
            let change = VisitMedicineChange(action: .update, medicine: altered, quote: quote, frequency: MedicationFrequency(count: 1, period: .day), times: [DoseTime(hour: 8, minute: 0)])
            var summary = VisitSummary(); summary.medicines = [change]
            var visit = DoctorVisit(transcript: source); visit.summary = summary; visit.medicineBaseline = [aspirin]
            XCTAssertThrowsError(try VisitReview.applying([change.id], from: visit, to: [aspirin])) { error in
                switch error {
                case VisitReviewError.unsupportedChange: break
                default: XCTFail("Unexpected rejection: \(error)")
                }
            }
        }
    }

    func testOrdinaryExplicitSchedulesKeepExactRequiredSourceFieldsAndCanApply() throws {
        for (source, name, directions) in [
            ("Start aspirin 81.5 mg once daily at 08:00.", "aspirin", "81.5 mg once daily at 08:00"),
            ("Commencez aspirine 81 mg une fois par jour à 8 h.", "aspirine", "81 mg une fois par jour à 8 h")
        ] {
            let required = try XCTUnwrap(VisitSourceGrounding.requiredMedicineProposal(source, medicines: [], candidates: VisitSourceGrounding.candidates(source)), source)
            XCTAssertEqual(required.name, name); XCTAssertEqual(required.instructions, directions)
            XCTAssertEqual(required.validatedChange.frequency, MedicationFrequency(count: 1, period: .day))
            XCTAssertEqual(required.validatedChange.times, [DoseTime(hour: 8, minute: 0)])
            let parsed = try VisitReview.parse(output(quote: source, name: name, instructions: directions), transcript: source, medicines: [])
            let change = try XCTUnwrap(parsed.medicines.first)
            var visit = DoctorVisit(transcript: source); visit.summary = parsed; visit.medicineBaseline = []
            XCTAssertEqual(try VisitReview.applying([change.id], from: visit, to: []).first?.instructions, directions)
        }
    }

    func testSeparateDatedFollowUpDoesNotDisableAnOrdinaryMedicineSchedule() throws {
        for (directive, followUp, name, directions) in [
            ("Start aspirin 81 mg once daily at 08:00.", "Book tests in five days on Monday.", "aspirin", "81 mg once daily at 08:00"),
            ("Commencez aspirine 81 mg une fois par jour à 8 h.", "Planifiez des analyses dans cinq jours le lundi.", "aspirine", "81 mg une fois par jour à 8 h")
        ] {
            let source = directive + " " + followUp
            XCTAssertNotNil(VisitSourceGrounding.requiredMedicineProposal(source, medicines: [], candidates: VisitSourceGrounding.candidates(source)), source)
            // A legacy multi-sentence quote still binds to the medicine sentence,
            // without treating a separate follow-up date as its schedule scope.
            let summary = try VisitReview.parse(output(quote: source, name: name, instructions: directions), transcript: source, medicines: [])
            XCTAssertEqual(summary.medicines.first?.medicine.instructions, directions, source)
        }
    }

    func testStandaloneMedicineActionsRejectUnsupportedSourceScheduleScopes() throws {
        let aspirin = try XCTUnwrap(Catalog.resolve("aspirin"))
        var records = Records(); records.medicines = [aspirin]
        // Each source spelling must bind even when the saved name is English.
        for name in Set(Catalog.names(for: aspirin)).sorted() {
            for (tool, source) in [
                (Tool.scheduleMedicine, "Schedule \(name) at 08:00 except Mondays."),
                (.scheduleMedicine, "Set \(name) at 08:00 for 1.5 weeks."),
                (.scheduleMedicine, "Programme \(name) à 8 h sauf le lundi."),
                (.scheduleMedicine, "Planifie \(name) à 8 h pendant cinq jours."),
                (.scheduleMedicine, "Schedule \(name) every other day at 08:00."),
                (.scheduleMedicine, "Schedule \(name) every 2 days at 08:00."),
                (.scheduleMedicine, "Schedule \(name) every six days at 08:00."),
                (.scheduleMedicine, "Schedule \(name) every 1 week at 08:00."),
                (.scheduleMedicine, "Programme \(name) tous les deux jours à 8 h."),
                (.scheduleMedicine, "Programme \(name) tous les six jours à 8 h."),
                (.scheduleMedicine, "Programme \(name) un jour sur deux à 8 h."),
                (.scheduleMedicine, "Schedule \(name) every week at 08:00."),
                (.scheduleMedicine, "Programme \(name) chaque semaine à 8 h."),
                (.scheduleMedicine, "Schedule \(name) every two hours at 08:00."),
                (.scheduleMedicine, "Programme \(name) toutes les deux heures à 8 h."),
                (.scheduleMedicine, "Schedule \(name) every 30 minutes at 08:00."),
                (.scheduleMedicine, "Programme \(name) toutes les 30 minutes à 8 h."),
                (.scheduleMedicine, "Schedule \(name) every hour at 08:00."),
                (.scheduleMedicine, "Programme \(name) chaque minute à 8 h."),
                (.addMedicine, "Add \(name) 81 mg daily at 08:00 for 5 days."),
                (.addMedicine, "Put \(name) 81 mg daily at 08:00 on Tuesdays."),
                (.addMedicine, "Ajoute \(name) 81 mg une fois par jour à 8 h pendant 1,5 semaine."),
                (.addMedicine, "Add \(name) 81 mg every other day at 08:00."),
                (.addMedicine, "Ajoute \(name) 81 mg tous les deux jours à 8 h."),
                (.addMedicine, "Add \(name) 81 mg every two hours at 08:00."),
                (.addMedicine, "Ajoute \(name) 81 mg toutes les 30 minutes à 8 h.")
            ] {
                XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: tool), original: source, records: records), source)
            }
        }
    }

    func testStandaloneOrdinaryMedicineSchedulesKeepExactTimesFrequencyAndSourceDirections() throws {
        let aspirin = try XCTUnwrap(Catalog.resolve("aspirin"))
        var records = Records(); records.medicines = [aspirin]
        let times = [DoseTime(hour: 8, minute: 0), DoseTime(hour: 20, minute: 30)]
        let frequency = MedicationFrequency(count: 2, period: .day)
        for source in [
            "Schedule aspirin twice daily at 08:00 and 20:30.",
            "Programme aspirine deux fois par jour à 8 h et 20 h 30.",
            "Schedule aspirin twice daily at 08:00 and 20:30. Book tests in five days on Monday.",
            "Programme aspirine deux fois par jour à 8 h et 20 h 30. Planifiez des analyses dans cinq jours le lundi."
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .scheduleMedicine), original: source, records: records), .schedule(aspirin, times, frequency), source)
        }
        for source in ["Schedule aspirin twice daily.", "Programme aspirine deux fois par jour."] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .scheduleMedicine), original: source, records: records), .schedule(aspirin, [], frequency), source)
        }
        for source in ["Schedule aspirin every day at 08:00.", "Schedule aspirin every 1 day at 08:00.", "Programme aspirine tous les jours à 8 h.", "Programme aspirine tous les 1 jour à 8 h."] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .scheduleMedicine), original: source, records: records), .schedule(aspirin, [DoseTime(hour: 8, minute: 0)], MedicationFrequency(count: 1, period: .day)), source)
        }
        for (source, expectedFrequency) in [
            ("Schedule aspirin once every week.", MedicationFrequency(count: 1, period: .week)),
            ("Programme aspirine deux fois par semaine.", MedicationFrequency(count: 2, period: .week)),
            ("Schedule aspirin twice monthly.", MedicationFrequency(count: 2, period: .month)),
            ("Programme aspirine une fois par mois.", MedicationFrequency(count: 1, period: .month))
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .scheduleMedicine), original: source, records: records), .schedule(aspirin, [], expectedFrequency), source)
        }
        for (source, instructions) in [
            ("Add aspirin 81.5 mg twice daily at 08:00 and 20:30.", "81.5 mg twice daily at 08:00 and 20:30."),
            ("Ajoute aspirine 81,5 mg deux fois par jour à 8 h et 20 h 30.", "81,5 mg deux fois par jour à 8 h et 20 h 30.")
        ] {
            var expected = aspirin; expected.instructions = instructions
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .addMedicine), original: source, records: records), .add(expected, times, frequency), source)
        }
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .listMedicines), original: "Show my medicines on Monday.", records: records), .medicines)
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .logDose), original: "Mark aspirin taken.", records: records), .dose(aspirin, .taken))
    }
}
