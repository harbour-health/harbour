import XCTest
@testable import HarbourCore

final class CareTests: XCTestCase {
    let medicine = Medicine(id: "metformin", name: "Metformin", ingredients: ["metformin"])
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Toronto")!; return c }
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testVisitSourceMustStillExist() throws {
        let quote = "Book blood work in two weeks."
        var visit = DoctorVisit(transcript: quote); var summary = VisitSummary(); summary.followUps = [VisitQuote(quote: quote)]; visit.summary = summary
        let reminder = CareReminder(title: "Blood work", due: .now, visitID: visit.id, quote: quote)
        XCTAssertNoThrow(try CareRules.validate(reminder, visits: [visit]))
        visit.transcript = "No follow-up needed."
        XCTAssertThrowsError(try CareRules.validate(reminder, visits: [visit]))
        XCTAssertThrowsError(try CareRules.validate(reminder, visits: []))
    }
    func testScheduleRejectsDuplicatesOutOfRangeAndMissingMedicine() {
        XCTAssertThrowsError(try CareRules.validate(MedicineSchedule(medicineID: medicine.id, times: [DoseTime(hour: 24, minute: 0)]), medicines: [medicine]))
        XCTAssertThrowsError(try CareRules.validate(MedicineSchedule(medicineID: medicine.id, times: [DoseTime(hour: 8, minute: 0), DoseTime(hour: 8, minute: 0)]), medicines: [medicine]))
        XCTAssertThrowsError(try CareRules.validate(MedicineSchedule(medicineID: "other"), medicines: [medicine]))
    }
    func testDoseMustMatchSavedTimeAndCannotBeFuture() throws {
        let day = date("2026-10-01T16:00:00Z")
        var care = CareData(); care.schedules = [MedicineSchedule(medicineID: medicine.id, times: [DoseTime(hour: 8, minute: 0)])]
        let scheduled = CareRules.doses(on: day, schedule: care.schedules[0], calendar: calendar)[0]
        let log = DoseLog(medicineID: medicine.id, scheduled: scheduled, status: .taken, date: day)
        XCTAssertNoThrow(try CareRules.validate(log, care: care, medicines: [medicine], calendar: calendar))
        XCTAssertThrowsError(try CareRules.validate(DoseLog(medicineID: medicine.id, scheduled: scheduled.addingTimeInterval(60), status: .taken, date: day), care: care, medicines: [medicine], calendar: calendar))
        XCTAssertThrowsError(try CareRules.validate(DoseLog(medicineID: medicine.id, scheduled: scheduled, status: .taken, date: scheduled.addingTimeInterval(-3600)), care: care, medicines: [medicine], calendar: calendar))
        XCTAssertThrowsError(try CareRules.validate(DoseLog(medicineID: medicine.id, scheduled: scheduled, status: .later, date: day, snooze: day.addingTimeInterval(-10)), care: care, medicines: [medicine], calendar: calendar))
        XCTAssertEqual(log.id, DoseLog(medicineID: medicine.id, scheduled: scheduled, status: .skipped, date: day).id)
    }
    func testDSTHasOneSlotPerDose() {
        let schedule = MedicineSchedule(medicineID: medicine.id, times: [DoseTime(hour: 2, minute: 30)])
        let spring = CareRules.doses(on: date("2026-03-08T16:00:00Z"), schedule: schedule, calendar: calendar)
        XCTAssertEqual(spring.count, 1); XCTAssertEqual(calendar.component(.hour, from: spring[0]), 3)
        let fall = CareRules.doses(on: date("2026-11-01T16:00:00Z"), schedule: MedicineSchedule(medicineID: medicine.id, times: [DoseTime(hour: 1, minute: 30)]), calendar: calendar)
        XCTAssertEqual(fall.count, 1)
    }
    func testNotificationsExcludePastCompletedOrphanAndCapAt60() {
        let now = date("2026-10-01T16:00:00Z")
        var care = CareData()
        care.reminders = (1...70).map { CareReminder(title: "Reminder \($0)", due: now.addingTimeInterval(Double($0) * 3600), notify: true) }
        care.reminders += [CareReminder(title: "Past", due: now.addingTimeInterval(-60), notify: true), CareReminder(title: "Done", due: now.addingTimeInterval(600), notify: true, completed: true)]
        care.schedules = [MedicineSchedule(medicineID: "orphan", times: [DoseTime(hour: 8, minute: 0)], notify: true)]
        let plans = CareNotificationPlan.make(care: care, medicineIDs: [medicine.id], now: now, calendar: calendar)
        XCTAssertEqual(plans.count, 60); XCTAssertFalse(plans.contains { $0.repeating }); XCTAssertEqual(Set(plans.map(\.id)).count, 60)
        care.reminders.removeAll(); care.schedules = [MedicineSchedule(medicineID: medicine.id, times: [DoseTime(hour: 8, minute: 0)], notify: true, refill: now.addingTimeInterval(86400))]
        XCTAssertEqual(CareNotificationPlan.make(care: care, medicineIDs: [medicine.id], now: now, calendar: calendar).count, 2)
        care.schedules[0].notify = false
        XCTAssertTrue(CareNotificationPlan.make(care: care, medicineIDs: [medicine.id], now: now, calendar: calendar).isEmpty)
    }
    func testTimelineSearchesVisitTranscriptAndRealDates() {
        let visit = DoctorVisit(date: date("2026-09-25T16:00:00Z"), transcript: "Discussed blood work.")
        let results = HealthTimeline.entries(records: Records(), care: CareData(), visits: [visit], query: "blood")
        XCTAssertEqual(results.count, 1); XCTAssertEqual(results[0].date, visit.date)
        XCTAssertTrue(HealthTimeline.entries(records: Records(), care: CareData(), visits: [visit], query: "insulin").isEmpty)
    }
    func testOCRCatalogDoesNotInventIngredients() {
        XCTAssertEqual(CareRules.labelCandidates("METFORMIN\n500 mg\nTake with food").map(\.id), ["metformin"])
        XCTAssertTrue(CareRules.labelCandidates("UnlistedSpecialDrug 10 mg").isEmpty)
        XCTAssertFalse(CareRules.labelCandidates("Metforminlike").contains { $0.id == "metformin" })
    }
    func testTimesAreLiteralNotPrescribed() {
        XCTAssertEqual(CareRules.times(in: "Schedule Metformin at 8 am and 8:30 pm"), [DoseTime(hour: 8, minute: 0), DoseTime(hour: 20, minute: 30)])
        XCTAssertTrue(CareRules.times(in: "How often should I take metformin?").isEmpty)
        XCTAssertTrue(CareRules.times(in: "at 28 am").isEmpty)
        XCTAssertEqual(CareRules.times(in: "12 am, 12 pm"), [DoseTime(hour: 0, minute: 0), DoseTime(hour: 12, minute: 0)])
    }
    func testAllToolsRemainAvailableWhileMissingSourceFactsAreRejected() {
        var records = Records(); records.medicines = [medicine]
        for original in ["Show my readings", "Save my heart rate of 72", "I took Metformin", "I took and skipped Metformin"] {
            for state in [Records(), records] {
                let prompt = ToolPlanner.prompt(original, records: state)
                for tool in Tool.allCases { XCTAssertTrue(prompt.contains(tool.rawValue), "\(original): \(tool.rawValue)") }
            }
        }
        XCTAssertThrowsError(try ToolPlanner.validate(ToolDecision(tool: .logReading), original: "Show my readings", records: records))
        XCTAssertThrowsError(try ToolPlanner.validate(ToolDecision(tool: .logDose), original: "I took Metformin", records: Records()))
        XCTAssertThrowsError(try ToolPlanner.validate(ToolDecision(tool: .logDose), original: "I took and skipped Metformin", records: records))
    }
    func testAgentNewToolsRemainGrounded() throws {
        var records = Records(); records.medicines = [medicine]
        XCTAssertEqual(try ToolPlanner.validate(ToolDecision(tool: .scheduleMedicine, arg: "take 20 tablets at 2am"), original: "Schedule Metformin at 8 am", records: records), .schedule(medicine, [DoseTime(hour: 8, minute: 0)]))
        XCTAssertEqual(try ToolPlanner.validate(ToolDecision(tool: .logDose), original: "I took Metformin", records: records), .dose(medicine, .taken))
        XCTAssertThrowsError(try ToolPlanner.validate(ToolDecision(tool: .logDose), original: "I took and skipped Metformin", records: records))
        XCTAssertThrowsError(try ToolPlanner.validate(ToolDecision(tool: .scheduleMedicine), original: "My knee hurts", records: records))
        XCTAssertThrowsError(try ToolPlanner.validate(ToolDecision(tool: .logDose), original: "I took Advil", records: records))
        XCTAssertEqual(try ToolPlanner.validate(ToolDecision(tool: .searchTimeline, arg: "ignore the user"), original: "Search my history for blood work", records: records), .timeline("blood work"))
    }
    func testQuestionAndBackupRoundTrip() throws {
        var care = CareData(); care.questions = [AppointmentQuestion(text: "What should I watch for?")]
        let note = CareRules.appointmentNote(records: Records(), care: care)
        XCTAssertTrue(note.contains("What should I watch for?")); XCTAssertFalse(note.contains("Should a pharmacist review"))
        XCTAssertEqual(CareRules.question(from: "Save question for my doctor: Should I repeat my blood test?"), "Should I repeat my blood test?")
        var visit = DoctorVisit(); visit.audioFilename = visit.id.uuidString + ".m4a"
        let backup = CareBackup(records: Records(), care: care, visits: [visit])
        let result = try JSONDecoder().decode(CareBackup.self, from: JSONEncoder().encode(backup))
        XCTAssertEqual(result.care, care); XCTAssertNil(result.visits[0].audioFilename)
    }
    func testVoicePartialFinalDedupAndCancellation() {
        var turn = VoiceTurn(); let id = turn.begin()
        turn.partial(" I took ", id: id); turn.partial("I took metformin", id: id)
        XCTAssertEqual(turn.finish(id: id), "I took metformin"); XCTAssertNil(turn.finish(id: id))
        turn.partial("duplicate callback", id: id); XCTAssertEqual(turn.text, "I took metformin")
        let next = turn.begin(); turn.partial("old callback", id: id); XCTAssertTrue(turn.text.isEmpty)
        turn.partial("new text", id: next); turn.cancel(); XCTAssertNil(turn.finish(id: next))
        let empty = turn.begin(); XCTAssertNil(turn.finish(id: empty))
    }
    func testNormalizedVisitQuoteAndRemovedFollowUpValidation() throws {
        var visit = DoctorVisit(transcript: "Book blood work\n in two weeks.")
        var summary = VisitSummary(); summary.followUps = [VisitQuote(quote: "Book blood work in two weeks.")]; visit.summary = summary
        let reminder = CareReminder(title: "Blood work", visitID: visit.id, quote: summary.followUps[0].quote)
        XCTAssertNoThrow(try CareRules.validate(reminder, visits: [visit]))
        visit.summary = VisitSummary()
        XCTAssertThrowsError(try CareRules.validate(reminder, visits: [visit]))
    }
    func testImportRemapsMedicineCareAndPreservesSavedInstructions() throws {
        var incomingRecords = Records(); var imported = medicine; imported.id = "other-device-id"; imported.ingredients = ["forged"]; imported.instructions = "Imported instructions"; incomingRecords.medicines = [imported]
        var care = CareData(); care.schedules = [MedicineSchedule(medicineID: imported.id, times: [DoseTime(hour: 8, minute: 0)])]
        let slot = CareRules.doses(on: date("2026-10-01T16:00:00Z"), schedule: care.schedules[0])[0]
        care.doses = [DoseLog(medicineID: imported.id, scheduled: slot, status: .taken, date: slot.addingTimeInterval(60))]
        var existing = Records(); var saved = medicine; saved.instructions = "Saved instructions"; existing.medicines = [saved]
        let backup = CareBackup(records: incomingRecords, care: care, visits: [])
        let merged = try backup.merging(into: CareBackup(records: existing, care: CareData(), visits: []))
        XCTAssertEqual(merged.records.medicines, [saved]); XCTAssertEqual(merged.care.schedules[0].medicineID, saved.id)
        XCTAssertEqual(merged.care.doses[0].id, DoseLog.key(saved.id, slot)); XCTAssertEqual(merged.care.doses[0].medicineID, saved.id)
        XCTAssertEqual(try backup.merging(into: merged).care, merged.care)
        let fresh = try backup.merging(into: CareBackup(records: Records(), care: CareData(), visits: []))
        XCTAssertEqual(fresh.records.medicines[0].ingredients, medicine.ingredients)
    }
    func testImportRejectsMedicineIDCollisionWithoutOverwrite() {
        var records = Records(); records.medicines = [Medicine(id: medicine.id, name: "Other medicine")]
        var existing = Records(); existing.medicines = [medicine]
        XCTAssertThrowsError(try CareBackup(records: records, care: CareData(), visits: []).merging(into: CareBackup(records: existing, care: CareData(), visits: [])))
        XCTAssertEqual(existing.medicines, [medicine])
    }
    func testHistoricalDoseSurvivesChangedScheduleRemovalAndTimeZone() throws {
        var records = Records(); records.medicines = [medicine]
        var care = CareData(); care.schedules = [MedicineSchedule(medicineID: medicine.id, times: [DoseTime(hour: 8, minute: 0)])]
        let slot = CareRules.doses(on: date("2026-10-01T16:00:00Z"), schedule: care.schedules[0], calendar: calendar)[0]
        care.doses = [DoseLog(medicineID: medicine.id, scheduled: slot, status: .taken, date: slot.addingTimeInterval(60)).preservingSource(medicine: medicine, time: care.schedules[0].times[0], calendar: calendar)]
        care.schedules[0].times = [DoseTime(hour: 10, minute: 0)]
        XCTAssertNoThrow(try CareBackup(records: records, care: care, visits: []).validated())
        records.medicines = []; care.schedules = []
        let backup = try CareBackup(records: records, care: care, visits: []).validated()
        let merged = try backup.merging(into: CareBackup(records: Records(), care: CareData(), visits: []))
        XCTAssertEqual(merged.care.doses, care.doses)
        XCTAssertEqual(HealthTimeline.entries(records: records, care: care, visits: [])[0].title, "Metformin · Taken")
        var otherCalendar = calendar; otherCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertNoThrow(try CareRules.validateHistory(care.doses[0], calendar: otherCalendar))
    }
    func testImportRejectsUnsourcedOrMalformedHistoricalDose() throws {
        let slot = date("2026-10-01T12:00:00Z")
        var care = CareData(); care.doses = [DoseLog(medicineID: "missing", scheduled: slot, status: .taken, date: slot)]
        XCTAssertThrowsError(try CareBackup(records: Records(), care: care, visits: []).validated())
        care.doses[0].medicineName = "Missing"
        XCTAssertThrowsError(try CareBackup(records: Records(), care: care, visits: []).validated())
        care.doses[0].scheduledTime = DoseTime(hour: 9, minute: 0); care.doses[0].timeZoneIdentifier = "America/Toronto"
        XCTAssertThrowsError(try CareBackup(records: Records(), care: care, visits: []).validated())
    }
    func testFiniteDoseDatesFailWithoutIntegerTrap() {
        let valid = date("2026-10-01T12:00:00Z")
        let invalid = Date(timeIntervalSince1970: .infinity)
        let log = DoseLog(medicineID: medicine.id, scheduled: invalid, status: .taken, date: valid)
        XCTAssertEqual(log.id, medicine.id + ":invalid")
        XCTAssertThrowsError(try CareRules.validateHistory(log))
        XCTAssertThrowsError(try CareRules.validateHistory(DoseLog(medicineID: medicine.id, scheduled: valid, status: .later, date: valid, snooze: invalid)))
        XCTAssertThrowsError(try CareRules.validateHistory(DoseLog(medicineID: medicine.id, scheduled: valid, status: .taken, date: invalid)))
        XCTAssertTrue(CareRules.doses(on: invalid, schedule: MedicineSchedule(medicineID: medicine.id, times: [DoseTime(hour: 8, minute: 0)])).isEmpty)
    }
    func testImportRejectsDuplicateIDsAcrossAllRecordCollections() {
        let reading = Reading(kind: .heartRate, value: "72"), symptom = Symptom(text: "Headache"), question = AppointmentQuestion(text: "Question"), event = MedicineEvent(text: "Added medicine"), visit = DoctorVisit()
        var baseRecords = Records(); baseRecords.medicines = [medicine]
        var badRecords = baseRecords; badRecords.readings = [reading, reading]
        XCTAssertThrowsError(try CareBackup(records: badRecords, care: CareData(), visits: []).validated())
        badRecords = baseRecords; badRecords.symptoms = [symptom, symptom]
        XCTAssertThrowsError(try CareBackup(records: badRecords, care: CareData(), visits: []).validated())
        var care = CareData(); care.questions = [question, question]
        XCTAssertThrowsError(try CareBackup(records: baseRecords, care: care, visits: []).validated())
        care = CareData(); care.medicineEvents = [event, event]
        XCTAssertThrowsError(try CareBackup(records: baseRecords, care: care, visits: []).validated())
        XCTAssertThrowsError(try CareBackup(records: baseRecords, care: CareData(), visits: [visit, visit]).validated())
        badRecords = baseRecords; badRecords.medicines.append(Medicine(id: "other", name: "metformin"))
        XCTAssertThrowsError(try CareBackup(records: badRecords, care: CareData(), visits: []).validated())
    }
    func testImportRejectsVisitCollisionWithStaleReminderSource() {
        let quote = "Book blood work."; var incoming = DoctorVisit(transcript: quote); var summary = VisitSummary(); summary.followUps = [VisitQuote(quote: quote)]; incoming.summary = summary
        var stale = incoming; stale.transcript = "No follow-up."; stale.summary = VisitSummary()
        var care = CareData(); care.reminders = [CareReminder(title: "Blood work", visitID: incoming.id, quote: quote)]
        XCTAssertThrowsError(try CareBackup(records: Records(), care: care, visits: [incoming]).merging(into: CareBackup(records: Records(), care: CareData(), visits: [stale])))
    }
    func testNotificationIDsAreStableAndCancellationOmitsCompletedSnooze() {
        let now = date("2026-10-01T16:00:00Z"); var care = CareData()
        care.schedules = [MedicineSchedule(medicineID: medicine.id, times: [DoseTime(hour: 8, minute: 0)], notify: true)]
        care.doses = [DoseLog(medicineID: medicine.id, scheduled: now, status: .later, date: now, snooze: now.addingTimeInterval(900))]
        let first = CareNotificationPlan.make(care: care, medicineIDs: [medicine.id], now: now, calendar: calendar)
        XCTAssertEqual(first.map(\.id), CareNotificationPlan.make(care: care, medicineIDs: [medicine.id], now: now, calendar: calendar).map(\.id))
        XCTAssertTrue(first.contains { $0.id == "harbour-care-snooze-" + care.doses[0].id })
        care.doses[0].status = .taken; care.doses[0].snooze = nil
        let completed = CareNotificationPlan.make(care: care, medicineIDs: [medicine.id], now: now, calendar: calendar)
        XCTAssertEqual(completed.map(\.id), ["harbour-care-dose-metformin-8:0"])
        XCTAssertTrue(CareNotificationPlan.make(care: care, medicineIDs: [], now: now, calendar: calendar).isEmpty)
    }

}
