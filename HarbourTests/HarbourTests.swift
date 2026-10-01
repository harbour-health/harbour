import XCTest
import UserNotifications
import UIKit
import AVFoundation
import HarbourCore
@testable import Harbour

@MainActor final class HarbourCareServiceTests: XCTestCase {
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
