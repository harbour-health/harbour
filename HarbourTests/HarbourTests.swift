import XCTest
import UserNotifications
import UIKit
import AVFoundation
import HarbourCore
@testable import Harbour

@MainActor final class HarbourModelPreferenceTests: XCTestCase {
    private func withPreferences(_ body: (UserDefaults, URL) throws -> Void) throws {
        let suite = "model-preferences-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(defaults, directory)
    }

    func testFreshAndUnrecognizedPreferencesKeepAutomatic() throws {
        try withPreferences { defaults, directory in
            let fresh = ModelManager(defaults: defaults, directory: directory)
            XCTAssertEqual(fresh.selection, .automatic)
            #if targetEnvironment(simulator)
            XCTAssertEqual(fresh.resolved, .small)
            #endif
            XCTAssertEqual(fresh.effort, .standard)

            defaults.set("a-model-from-an-unknown-version", forKey: "model")
            defaults.set("an-unknown-effort", forKey: "effort")
            let restored = ModelManager(defaults: defaults, directory: directory)
            XCTAssertEqual(restored.selection, .automatic)
            XCTAssertEqual(restored.effort, .standard)
        }
    }

    func testExistingModelChoicesAndEffortSurviveUpgrade() throws {
        try withPreferences { defaults, directory in
            for choice in ModelChoice.allCases {
                defaults.set(choice.rawValue, forKey: "model")
                defaults.set(Effort.extended.rawValue, forKey: "effort")
                let restored = ModelManager(defaults: defaults, directory: directory)
                XCTAssertEqual(restored.selection, choice)
                XCTAssertEqual(restored.effort, .extended)
                XCTAssertEqual(defaults.string(forKey: "model"), choice.rawValue)
            }
        }
    }

    func testChangingModelAndEffortPersistsAcrossManagers() throws {
        try withPreferences { defaults, directory in
            let manager = ModelManager(defaults: defaults, directory: directory)
            manager.selection = .small
            manager.effort = .quick
            let small = ModelManager(defaults: defaults, directory: directory)
            XCTAssertEqual(small.selection, .small)
            XCTAssertEqual(small.effort, .quick)

            small.selection = .qwen35
            small.effort = .extended
            let qwen35 = ModelManager(defaults: defaults, directory: directory)
            XCTAssertEqual(qwen35.selection, .qwen35)
            XCTAssertEqual(qwen35.resolved, .qwen35)
            XCTAssertEqual(qwen35.effort, .extended)
        }
    }

    func testAutomaticSelectionRetainsMemoryPowerAndThermalSafeguards() {
        let choose = ModelChoice.automaticModel
        XCTAssertEqual(choose(7_999_999_999, false, .nominal), .small)
        XCTAssertEqual(choose(8_000_000_000, false, .nominal), .balanced)
        XCTAssertEqual(choose(16_000_000_000, true, .nominal), .small)
        for thermalState in [ProcessInfo.ThermalState.fair, .serious, .critical] {
            XCTAssertEqual(choose(16_000_000_000, false, thermalState), .small)
        }
    }

    func testQwen35PinsVerifiedWeightsAndUsesNonThinkingPrompt() throws {
        let model = ModelChoice.qwen35
        XCTAssertEqual(model.size, 1_280_835_840)
        XCTAssertEqual(model.hash, "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223")
        XCTAssertEqual(model.url.absoluteString, "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/f6d5376be1edb4d416d56da11e5397a961aca8ae/Qwen3.5-2B-Q4_K_M.gguf")
        XCTAssertEqual(model.url.lastPathComponent, model.filename)
        let prompt = "<|im_start|>assistant"
        XCTAssertEqual(try model.promptFormat.prepare(prompt), prompt + "\n<think>\n\n</think>\n\n")
        for legacy in [ModelChoice.small, .balanced] {
            XCTAssertEqual(try legacy.promptFormat.prepare(prompt), prompt)
        }
    }
}

@MainActor final class HarbourCareServiceTests: XCTestCase {
    func testVisitExtractionEvidencePersistsWithSummaryAndRejectsStaleTranscript() async throws {
        let store = temporaryStore(), source = "The patient reported a mild cough."
        defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        let visit = DoctorVisit(transcript: source)
        XCTAssertTrue(store.saveVisit(visit))
        let run = await VisitExtraction.run(transcript: source, medicines: [], modelID: "storage-test") { request in
            let output = request.id == "classify"
                ? #"{"units":[{"id":0,"kinds":["highlight"]}]}"#
                : #"{"highlights":[{"quote":"The patient reported a mild cough."}],"medicines":[],"followUps":[],"appointments":[]}"#
            return .init(output: output, preparedPrompt: request.prompt, modelID: "storage-test")
        }
        XCTAssertTrue(run.completed)
        let summary = try XCTUnwrap(run.acceptedSummary)
        XCTAssertEqual(summary.highlights.map(\.quote), [source])
        store.saveVisitSummary(summary, id: visit.id, transcript: source, baseline: [], extractionRuns: [run])
        let restored = AppStore(folder: store.file.deletingLastPathComponent())
        XCTAssertNil(restored.error)
        XCTAssertEqual(restored.visits.first?.summary, summary)
        XCTAssertEqual(restored.visits.first?.extractionRuns, [run])
        XCTAssertEqual(restored.visits.first?.medicineBaseline, [])

        let saved = restored.visits
        restored.saveVisitSummary(VisitSummary(), id: visit.id, transcript: "A stale transcript.", baseline: [], extractionRuns: [])
        restored.saveVisitExtractionRuns([], id: visit.id, transcript: "A stale transcript.")
        XCTAssertEqual(restored.visits, saved)
        XCTAssertEqual(AppStore(folder: store.file.deletingLastPathComponent()).visits, saved)
    }

    func testFailedAndCancelledVisitExtractionRetainPreviousSummaryAcrossRelaunch() throws {
        let store = temporaryStore(), source = "The patient reported a mild cough."
        defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        var visit = DoctorVisit(transcript: source)
        visit.summary = try VisitReview.parse(#"{"highlights":[{"quote":"The patient reported a mild cough."}],"medicines":[],"followUps":[],"appointments":[]}"#, transcript: source, medicines: [])
        visit.medicineBaseline = []
        XCTAssertTrue(store.saveVisit(visit))
        var failed = VisitExtractionRun(transcript: source, validationTranscript: source, language: .english, modelID: "storage-test")
        failed.errors = ["generation_failed"]
        var cancelled = failed
        cancelled.errors = ["cancelled"]; cancelled.cancelled = true
        store.saveVisitExtractionRuns([failed, cancelled], id: visit.id, transcript: source)
        let restored = AppStore(folder: store.file.deletingLastPathComponent())
        XCTAssertNil(restored.error)
        XCTAssertEqual(restored.visits.first?.summary, visit.summary)
        XCTAssertEqual(restored.visits.first?.medicineBaseline, visit.medicineBaseline)
        XCTAssertEqual(restored.visits.first?.extractionRuns, [failed, cancelled])
    }

    func testAppointmentPersistsExportsAndDetachesEditedSource() throws {
        let store = temporaryStore(), target = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()); try? FileManager.default.removeItem(at: target.file.deletingLastPathComponent()) }
        let quote = "Follow-up appointment Friday at 3 pm."
        var visit = DoctorVisit(transcript: quote)
        visit.summary = try VisitReview.parse(#"{"highlights":[],"medicines":[],"followUps":[]}"#, transcript: quote, medicines: [])
        XCTAssertTrue(store.saveVisit(visit))
        let draft = AppointmentRules.draft(from: quote, visitID: visit.id)
        XCTAssertTrue(store.saveAppointment(draft))
        XCTAssertEqual(AppStore(folder: store.file.deletingLastPathComponent()).records.appointments, [draft])
        store.export(); target.importFile(try XCTUnwrap(store.shareFile?.url))
        XCTAssertNil(target.error); XCTAssertEqual(target.records.appointments, [draft])
        visit.transcript = "Cancelled."; visit.summary = nil; XCTAssertTrue(store.saveVisit(visit))
        XCTAssertNil(store.records.appointments[0].visitID)
        XCTAssertFalse(store.saveAppointment(draft))
    }
    private func temporaryStore() -> AppStore { AppStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("care-test-" + UUID().uuidString)) }
    func testLegacyArchiveAndNewCareSurviveRelaunch() throws {
        let store = temporaryStore()
        let old = "{\"version\":1,\"records\":{\"schemaVersion\":1,\"medicines\":[],\"readings\":[],\"symptoms\":[]},\"messages\":[]}"
        try Data(old.utf8).write(to: store.file)
        let loaded = AppStore(folder: store.file.deletingLastPathComponent())
        XCTAssertNil(loaded.error); XCTAssertTrue(loaded.care.reminders.isEmpty)
        XCTAssertTrue(loaded.saveReminder(CareReminder(title: "Book blood work", due: .now.addingTimeInterval(86400))))
        XCTAssertTrue(loaded.saveQuestion(AppointmentQuestion(text: "What should I watch for?")))
        let restored = AppStore(folder: store.file.deletingLastPathComponent())
        XCTAssertEqual(restored.care, loaded.care)
        try FileManager.default.removeItem(at: store.file.deletingLastPathComponent())
    }
    func testDoseUpsertAndScheduleSaveAreAtomic() throws {
        let store = temporaryStore(), medicine = Catalog.medicines.first { $0.id == "metformin" }!
        let parts = Calendar.current.dateComponents([.hour, .minute], from: max(Calendar.current.startOfDay(for: .now), Date.now.addingTimeInterval(-600)))
        let schedule = MedicineSchedule(medicineID: medicine.id, times: [DoseTime(hour: parts.hour!, minute: parts.minute!)])
        XCTAssertTrue(store.saveMedicine(medicine, schedule: schedule))
        let slot = CareRules.doses(on: .now, schedule: schedule)[0]
        XCTAssertTrue(store.logDose(DoseLog(medicineID: medicine.id, scheduled: slot, status: .taken)))
        XCTAssertTrue(store.logDose(DoseLog(medicineID: medicine.id, scheduled: slot, status: .skipped)))
        XCTAssertEqual(store.care.doses.count, 1); XCTAssertEqual(store.care.doses[0].status, .skipped)
        XCTAssertFalse(store.saveMedicine(Medicine(id: "bad", name: "Bad"), schedule: MedicineSchedule(medicineID: "bad", times: [DoseTime(hour: 90, minute: 0)])))
        XCTAssertFalse(store.records.medicines.contains { $0.id == "bad" })
        store.removeMedicine(medicine.id); XCTAssertTrue(store.care.schedules.isEmpty)
        try FileManager.default.removeItem(at: store.file.deletingLastPathComponent())
    }
    func testApplyingVisitFrequencyAndExplicitTimesUpdatesSchedule() throws {
        let store = temporaryStore(), medicine = Catalog.medicines.first { $0.id == "metformin" }!
        defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }

        let weeklyQuote = "Start metformin 500 mg 2 times per week."
        let weeklyJSON = #"{"highlights":[],"medicines":[{"action":"start","name":"metformin","instructions":"500 mg 2 times per week","quote":"Start metformin 500 mg 2 times per week."}],"followUps":[]}"#
        var weeklyVisit = DoctorVisit(transcript: weeklyQuote)
        weeklyVisit.summary = try VisitReview.parse(weeklyJSON, transcript: weeklyQuote, medicines: [])
        weeklyVisit.medicineBaseline = []
        XCTAssertTrue(store.saveVisit(weeklyVisit))
        let weeklyChange = try XCTUnwrap(weeklyVisit.summary?.medicines.first)
        XCTAssertTrue(store.applyVisitChanges(id: weeklyVisit.id, selected: [weeklyChange.id]))
        XCTAssertEqual(store.care.schedules.first?.frequency, MedicationFrequency(count: 2, period: .week))
        XCTAssertTrue(store.care.schedules.first?.times.isEmpty == true)

        let timedQuote = "Update metformin to 500 mg at 8 am and 8 pm."
        let timedJSON = #"{"highlights":[],"medicines":[{"action":"update","name":"metformin","instructions":"500 mg at 8 am and 8 pm","quote":"Update metformin to 500 mg at 8 am and 8 pm."}],"followUps":[]}"#
        var timedVisit = DoctorVisit(transcript: timedQuote)
        timedVisit.summary = try VisitReview.parse(timedJSON, transcript: timedQuote, medicines: store.records.medicines)
        timedVisit.medicineBaseline = store.records.medicines
        XCTAssertTrue(store.saveVisit(timedVisit))
        let timedChange = try XCTUnwrap(timedVisit.summary?.medicines.first)
        XCTAssertTrue(store.applyVisitChanges(id: timedVisit.id, selected: [timedChange.id]))
        XCTAssertEqual(store.care.schedules.first?.frequency, MedicationFrequency(count: 2, period: .day))
        XCTAssertEqual(store.care.schedules.first?.times, [DoseTime(hour: 8, minute: 0), DoseTime(hour: 20, minute: 0)])
        XCTAssertTrue(store.records.medicines.contains { $0.id == medicine.id })
    }
    func testCorruptArchiveRemainsUntouched() throws {
        let store = temporaryStore(); let corrupt = Data("not json".utf8); try corrupt.write(to: store.file)
        let loaded = AppStore(folder: store.file.deletingLastPathComponent())
        XCTAssertNotNil(loaded.error); XCTAssertFalse(loaded.saveReminder(CareReminder(title: "Blocked")))
        XCTAssertEqual(try Data(contentsOf: store.file), corrupt)
        try FileManager.default.removeItem(at: store.file.deletingLastPathComponent())
    }
    func testMedicineSaveRejectsDuplicateNamesAndInvalidBoundsBeforeWriting() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        let original = Medicine(id: "imported-metformin", name: "Metformin", ingredients: ["metformin"])
        XCTAssertTrue(store.saveMedicine(original, schedule: MedicineSchedule(medicineID: original.id, times: [DoseTime(hour: 8, minute: 0)])))
        let before = try Data(contentsOf: store.file)
        XCTAssertFalse(store.saveMedicine(Medicine(id: "metformin", name: " metFORMIN "), schedule: nil))
        XCTAssertFalse(store.saveMedicine(Medicine(name: String(repeating: "x", count: 501)), schedule: nil))
        XCTAssertFalse(store.saveMedicine(Medicine(id: "", name: "Valid name"), schedule: nil))
        XCTAssertEqual(try Data(contentsOf: store.file), before)
        XCTAssertNoThrow(try CareBackup(records: store.records, care: store.care, visits: store.visits).validated())
        var updated = original; updated.instructions = "Take with food"
        XCTAssertTrue(store.saveMedicine(updated, schedule: store.care.schedules.first))
        XCTAssertEqual(store.records.medicines.count, 1); XCTAssertEqual(store.records.medicines[0].instructions, updated.instructions)
    }
    func testExportImportPreservesCareAndRejectsForgedSource() throws {
        let store = temporaryStore(); let medicine = Catalog.medicines.first { $0.id == "metformin" }!
        XCTAssertTrue(store.saveMedicine(medicine, schedule: MedicineSchedule(medicineID: medicine.id, times: [DoseTime(hour: 8, minute: 0)])))
        XCTAssertTrue(store.saveQuestion(AppointmentQuestion(text: "Discuss blood work")))
        XCTAssertTrue(store.saveReminder(CareReminder(title: "Book a visit", due: .now.addingTimeInterval(86400))))
        store.export(); let exported = try XCTUnwrap(store.shareFile?.url)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let serialized = try decoder.decode(CareBackup.self, from: Data(contentsOf: exported)).care
        let target = temporaryStore(); target.importFile(exported)
        XCTAssertNil(target.error); XCTAssertEqual(target.care, serialized)
        target.importFile(exported); XCTAssertEqual(target.care, serialized)
        var invalid = CareData(); invalid.reminders = [CareReminder(title: "Forged", visitID: UUID(), quote: "Made up")]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let bad = store.file.deletingLastPathComponent().appendingPathComponent("bad.json")
        try encoder.encode(CareBackup(records: store.records, care: invalid, visits: [])).write(to: bad)
        target.importFile(bad); XCTAssertNotNil(target.error); XCTAssertEqual(target.care, serialized)
        try FileManager.default.removeItem(at: store.file.deletingLastPathComponent()); try FileManager.default.removeItem(at: target.file.deletingLastPathComponent())
    }
    func testVisionReadsActualImageAndDoesNotSaveMedicine() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1100, height: 700)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1100, height: 700))
            ("METFORMIN\n500 mg\nTake one tablet with food" as NSString).draw(in: CGRect(x: 70, y: 90, width: 970, height: 520), withAttributes: [.font: UIFont.systemFont(ofSize: 58), .foregroundColor: UIColor.black])
        }
        let scanner = MedicineScanner(); await scanner.recognize(try XCTUnwrap(image.pngData()))
        XCTAssertNil(scanner.error); XCTAssertEqual(CareRules.labelCandidates(scanner.text).first?.id, "metformin")
        XCTAssertTrue(CareRules.labelInstructions(scanner.text).localizedCaseInsensitiveContains("Take one tablet"))
        await scanner.recognize(Data("invalid image".utf8)); XCTAssertNotNil(scanner.error)
    }
    func testSpokenResponseIncludesStructuredCareResults() {
        let reminder = CareReminder(title: "Book blood work")
        let reminderResponse = ChatMessage(text: "Reminders", reminders: [reminder])
        XCTAssertTrue(reminderResponse.spokenText.contains("Book blood work"))
        let entry = HealthTimeline.entries(records: Records(), care: CareData(), visits: [DoctorVisit(title: "Blood test visit", transcript: "Recheck glucose")])[0]
        let history = ChatMessage(text: "Health history", timeline: [ChatTimelineEntry(entry)])
        XCTAssertTrue(history.spokenText.contains("Blood test visit")); XCTAssertTrue(history.spokenText.contains("Recheck glucose"))
        XCTAssertEqual(ChatMessage(text: "Plain response").spokenText, "Plain response")
    }
    func testNativeVoiceStopCancelsSpeechAndLateCompletion() async {
        let voice = VoiceService(); var completed = false
        voice.speak("This is a voice playback lifecycle test. It does not test speech recognition.", finished: { completed = true })
        XCTAssertTrue(voice.speaking || voice.error != nil)
        voice.stop(); XCTAssertFalse(voice.speaking); XCTAssertFalse(voice.listening)
        try? await Task.sleep(for: .milliseconds(300)); XCTAssertFalse(completed)
    }
    func testChangedScheduleAndRemovedMedicineHistorySurviveExportImport() throws {
        let store = temporaryStore(), target = temporaryStore(); let medicine = Catalog.medicines.first { $0.id == "metformin" }!
        defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()); try? FileManager.default.removeItem(at: target.file.deletingLastPathComponent()) }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: max(Calendar.current.startOfDay(for: .now), Date.now.addingTimeInterval(-600)))
        let time = DoseTime(hour: parts.hour!, minute: parts.minute!); let schedule = MedicineSchedule(medicineID: medicine.id, times: [time])
        XCTAssertTrue(store.saveMedicine(medicine, schedule: schedule))
        let slot = CareRules.doses(on: .now, schedule: schedule)[0]
        XCTAssertTrue(store.logDose(DoseLog(medicineID: medicine.id, scheduled: slot, status: .taken)))
        XCTAssertTrue(store.saveMedicine(medicine, schedule: MedicineSchedule(medicineID: medicine.id, times: [DoseTime(hour: (time.hour + 1) % 24, minute: time.minute)])))
        store.export(); target.importFile(try XCTUnwrap(store.shareFile?.url)); XCTAssertNil(target.error); XCTAssertEqual(target.care.doses.count, 1)
        store.removeMedicine(medicine.id); store.export()
        let fresh = temporaryStore(); defer { try? FileManager.default.removeItem(at: fresh.file.deletingLastPathComponent()) }
        fresh.importFile(try XCTUnwrap(store.shareFile?.url)); XCTAssertNil(fresh.error); XCTAssertTrue(fresh.records.medicines.isEmpty)
        XCTAssertEqual(fresh.care.doses[0].medicineName, medicine.name)
        let restored = AppStore(folder: fresh.file.deletingLastPathComponent()); XCTAssertEqual(restored.care.doses, fresh.care.doses)
    }
    func testVisitEditDetachesStaleReminderAndStaleDraftCannotSave() throws {
        let store = temporaryStore(); defer { try? FileManager.default.removeItem(at: store.file.deletingLastPathComponent()) }
        let quote = "Book blood work."; var visit = DoctorVisit(transcript: quote); var summary = VisitSummary(); summary.followUps = [VisitQuote(quote: quote)]; visit.summary = summary
        XCTAssertTrue(store.saveVisit(visit)); let reminder = CareReminder(title: "Blood work", visitID: visit.id, quote: quote)
        XCTAssertTrue(store.saveReminder(reminder)); visit.transcript = "No follow-up."; visit.summary = nil
        XCTAssertTrue(store.saveVisit(visit)); XCTAssertNil(store.care.reminders[0].visitID); XCTAssertNil(store.care.reminders[0].quote)
        XCTAssertFalse(store.saveReminder(reminder)); XCTAssertEqual(store.care.reminders.count, 1)
    }
    func testNewestNotificationSnapshotCleansUpSupersededInFlightAdd() async throws {
        let delivery = SuspendedCareNotificationDelivery(); let notifications = CareNotifications(delivery: delivery)
        var care = CareData(); care.reminders = [CareReminder(title: "First", due: .now.addingTimeInterval(3600), notify: true)]
        let first = Task { await notifications.sync(care: care, medicines: []) }
        for _ in 0..<1000 where delivery.resumeAdd == nil { await Task.yield() }
        let resume = try XCTUnwrap(delivery.resumeAdd)
        await notifications.sync(care: CareData(), medicines: [])
        resume.resume(); await first.value
        XCTAssertEqual(delivery.ids, ["unrelated-request"])
    }
    func testNativeVoiceActuallyCompletesShortUtterance() async throws {
        guard UIApplication.shared.applicationState == .active else { throw XCTSkip("The host app is not active, so its playback lifecycle guard blocks speech.") }
        guard AVSpeechSynthesisVoice(language: "en-CA") != nil else { throw XCTSkip("No English Canadian speech voice is installed on this simulator or device.") }
        let voice = VoiceService(); defer { voice.stop() }
        let completed = expectation(description: "Native speech synthesis completes Hello")
        voice.speak("Hello", finished: { completed.fulfill() })
        if let error = voice.error { throw XCTSkip("Native audio session unavailable: " + error) }
        await fulfillment(of: [completed], timeout: 15)
        XCTAssertFalse(voice.speaking)
    }
    func testNativeNotificationPrivacyIDsAndCancellation() async throws {
        let center = UNUserNotificationCenter.current(); let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { throw XCTSkip("Native notification permission has not been granted; no permission prompt is triggered by this test.") }
        let prefix = "harbour-test-" + UUID().uuidString + "-"; let notifications = CareNotifications(prefix: prefix)
        var care = CareData(); let reminder = CareReminder(title: "Private diagnosis or medicine name", due: .now.addingTimeInterval(3600), notify: true); care.reminders = [reminder]
        defer { center.removePendingNotificationRequests(withIdentifiers: [prefix + "reminder-" + reminder.id.uuidString]) }
        await notifications.sync(care: care, medicines: [])
        let pending = await center.pendingNotificationRequests(); let request = try XCTUnwrap(pending.first { $0.identifier == prefix + "reminder-" + reminder.id.uuidString })
        XCTAssertEqual(request.content.title, "Harbour"); XCTAssertEqual(request.content.body, "You have a reminder. Open Harbour to view it.")
        XCTAssertFalse(request.content.body.contains(reminder.title)); XCTAssertFalse(try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger).repeats)
        care.reminders[0].completed = true; await notifications.sync(care: care, medicines: [])
        let remaining = await center.pendingNotificationRequests(); XCTAssertFalse(remaining.contains { $0.identifier.hasPrefix(prefix) })
        let unrelated = Set(pending.filter { !$0.identifier.hasPrefix(prefix) }.map(\.identifier))
        XCTAssertTrue(unrelated.isSubset(of: Set(remaining.map(\.identifier))))
    }

}


@MainActor private final class SuspendedCareNotificationDelivery: CareNotificationDelivery {
    var ids = ["unrelated-request"]
    var resumeAdd: CheckedContinuation<Void, Never>?
    func authorized() async -> Bool { true }
    func pending() async -> [String] { ids }
    func delivered() async -> [(id: String, date: Date)] { [] }
    func add(_ plan: CareNotificationPlan) async throws {
        await withCheckedContinuation { resumeAdd = $0 }
        ids.append(plan.id)
    }
    func removePending(_ removed: [String]) { ids.removeAll { removed.contains($0) } }
    func removeDelivered(_ ids: [String]) {}
}

@MainActor final class HarbourLocalizationTests: XCTestCase {
    private func table(_ name: String, language: String) throws -> [String: String] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "strings", subdirectory: nil, localization: language), "Missing packaged \(language)/\(name).strings")
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [], format: nil) as? [String: String])
    }

    func testActualAppBundlesContainCompleteEnglishAndFrenchTables() throws {
        XCTAssertTrue(Bundle.main.localizations.contains("en")); XCTAssertTrue(Bundle.main.localizations.contains("fr-CA"))
        let english = try table("Localizable", language: "en")
        let french = try table("Localizable", language: "fr-CA")
        XCTAssertFalse(english.isEmpty); XCTAssertEqual(Set(english.keys), Set(french.keys))
        let formatPattern = "%(?:[0-9]+\\$)?[-+ #0]*(?:[0-9]+)?(?:\\.[0-9]+)?(?:hh|h|ll|l|L|z|t|j)?[@diuoxXfFeEgGaAcCsSpn%]"
        let expression = try NSRegularExpression(pattern: formatPattern)
        func formats(_ value: String) -> [String] {
            expression.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { Range($0.range, in: value).map { String(value[$0]) } }.sorted()
        }
        for (key, source) in english {
            let translated = try XCTUnwrap(french[key], key)
            XCTAssertFalse(translated.isEmpty, key)
            XCTAssertEqual(formats(source), formats(translated), "Format mismatch: " + key)
        }
        XCTAssertEqual(french["Today"], "Aujourd’hui"); XCTAssertEqual(french["Settings"], "Réglages")
        XCTAssertEqual(french["Harbour"], "Harbour")
        XCTAssertEqual(L10n.string("Settings"), L10n.isFrench ? "Réglages" : "Settings")
        XCTAssertEqual(L10n.locale.language.languageCode?.identifier, L10n.isFrench ? "fr" : "en")
    }

    func testPackagedPermissionDescriptionsCoverAllNativeAccess() throws {
        let english = try table("InfoPlist", language: "en"), french = try table("InfoPlist", language: "fr-CA")
        let keys: Set<String> = ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription", "NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription", "NSFaceIDUsageDescription", "NSCameraUsageDescription"]
        XCTAssertEqual(Set(english.keys), keys); XCTAssertEqual(Set(french.keys), keys)
        for key in keys {
            let source = try XCTUnwrap(english[key]), translated = try XCTUnwrap(french[key])
            XCTAssertFalse(source.isEmpty); XCTAssertFalse(translated.isEmpty); XCTAssertNotEqual(source, translated)
            XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: key) as? String, L10n.isFrench ? translated : source, key)
        }
    }

    func testCountAndPercentageFormatsForZeroOneAndTwo() throws {
        let french = try table("Localizable", language: "fr-CA")
        for (count, expected) in [(0, "0 entrées"), (1, "1 entrée"), (2, "2 entrées")] {
            let suffix = count == 1 ? "record" : "records"
            let format = try XCTUnwrap(french["%d " + suffix])
            XCTAssertEqual(String(format: format, locale: Locale(identifier: "fr_CA"), arguments: [count]), expected)
            let swiftFormat = try XCTUnwrap(french["%lld " + suffix])
            XCTAssertEqual(String(format: swiftFormat, locale: Locale(identifier: "fr_CA"), arguments: [Int64(count)]), expected)
            XCTAssertEqual(L10n.format("%d " + suffix, count), L10n.isFrench ? expected : "\(count) \(suffix)")
        }
        XCTAssertEqual(String(format: try XCTUnwrap(french["%d%% downloaded"]), locale: Locale(identifier: "fr_CA"), arguments: [50]), "50 % téléchargé")
    }

    func testCanonicalPersistedValuesRemainIndependentOfPresentation() throws {
        XCTAssertEqual(ReadingKind.allCases.map(\.rawValue), ["Heart rate", "Blood pressure", "Temperature"])
        XCTAssertEqual(DoseStatus.allCases.map(\.rawValue), ["Taken", "Skipped", "Remind later"])
        XCTAssertEqual(Effort.allCases.map(\.rawValue), ["Quick", "Standard", "Extended"])
        XCTAssertEqual(AppearanceChoice.allCases.map(\.rawValue), ["System", "Light", "Dark"])
        XCTAssertEqual(MedicineChangeAction.allCases.map(\.rawValue), ["start", "update", "stop"])
        XCTAssertEqual(Tool.captureSymptom.rawValue, "capture_symptom"); XCTAssertEqual(Tool.addMedicine.rawValue, "add_medication")
        let reading = try XCTUnwrap(ReadingParser.parse("Ma température est de 36,8"))
        XCTAssertEqual(reading.value, "36.8"); XCTAssertEqual(reading.source, "Manual")
        XCTAssertEqual(L10n.readingValue(reading), L10n.isFrench ? "36,8" : "36.8")
        let encoded = try JSONEncoder().encode(reading)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("Temperature"))
        XCTAssertEqual(try JSONDecoder().decode(Reading.self, from: encoded), reading)
        let medicine = try XCTUnwrap(Catalog.resolve("acétaminophène"))
        XCTAssertEqual(medicine.id, "acetaminophen"); XCTAssertEqual(medicine.ingredients, ["acetaminophen"])
        XCTAssertEqual(L10n.medicineName(medicine), L10n.isFrench ? "Acétaminophène" : "Acetaminophen")
        XCTAssertEqual(L10n.ingredientNames(medicine.ingredients), L10n.isFrench ? "acétaminophène" : "acetaminophen")
        XCTAssertEqual(L10n.medicineName(Medicine(id: "user-product", name: "Acetaminophen")), "Acetaminophen")
    }

    func testGeneratedNoteAndHistoryKeepMixedUserTextVerbatim() throws {
        var records = Records(), care = CareData()
        let symptom = Symptom(text: "Sore knee — douleur au genou", onset: "Tuesday et mercredi", severity: "Mild")
        let reading = try XCTUnwrap(ReadingParser.parse("Température 36,8"))
        records.symptoms = [symptom]; records.readings = [reading]
        records.medicines = [Medicine(id: "user-product", name: "Mon produit / My product", instructions: "Suivre mon étiquette / follow my label")]
        care.questions = [AppointmentQuestion(text: "Should I bring mes relevés? Questions: keep this exact text.")]
        let note = LocalizedHealthContent.appointmentNote(records: records, care: care)
        for source in [symptom.text, symptom.onset, records.medicines[0].name, care.questions[0].text] { XCTAssertTrue(note.contains(source), source) }
        if L10n.isFrench {
            XCTAssertTrue(note.hasPrefix("Préoccupation")); XCTAssertTrue(note.contains("Intensité")); XCTAssertTrue(note.contains("Légère")); XCTAssertTrue(note.contains("36,8"))
            XCTAssertFalse(note.contains("Medications entered:")); XCTAssertFalse(note.contains("Recent readings:"))
        } else { XCTAssertTrue(note.hasPrefix("Concern:")); XCTAssertTrue(note.contains("36.8")) }
        let visit = DoctorVisit(title: "My consultation / ma consultation", transcript: "Keep my English and French transcript.")
        let timeline = LocalizedHealthContent.timelineEntries(records: records, care: care, visits: [visit])
        let visitEntry = try XCTUnwrap(timeline.first { $0.id == "visit-" + visit.id.uuidString })
        XCTAssertEqual(visitEntry.title, visit.title); XCTAssertEqual(visitEntry.detail, visit.transcript)
        let readingEntry = try XCTUnwrap(timeline.first { $0.id == "reading-" + reading.id })
        XCTAssertEqual(readingEntry.detail, L10n.isFrench ? "Manuel" : "Manual")
        XCTAssertTrue(readingEntry.title.contains(L10n.isFrench ? "Température 36,8" : "Temperature 36.8"))
        let spoken = ChatMessage(text: "My source / mon texte", readings: [reading]).spokenText
        XCTAssertTrue(spoken.hasPrefix("My source / mon texte")); XCTAssertTrue(spoken.contains(L10n.isFrench ? "36,8" : "36.8"))
    }
}
