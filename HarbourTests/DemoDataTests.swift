import XCTest
import HarbourCore
@testable import Harbour

@MainActor final class DemoDataTests: XCTestCase {
    func testReplacementRemovesOldRecordsAudioAndSurvivesRelaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(folder: folder)
        store.append(ChatMessage(isUser: true, text: "private old message"))
        store.add(Symptom(text: "old symptom"))
        try FileManager.default.createDirectory(at: store.visitAudioDirectory, withIntermediateDirectories: true)
        let audio = store.visitAudioDirectory.appendingPathComponent("old.m4a")
        try Data("old audio".utf8).write(to: audio)
        XCTAssertTrue(store.loadDemoData(french: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertFalse(store.records.symptoms.contains { $0.text == "old symptom" })
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.conversations.flatMap(\.messages).contains { $0.text == "private old message" })
        let reloaded = AppStore(folder: folder)
        XCTAssertEqual(reloaded.archive.demoData, true)
        XCTAssertEqual(reloaded.visits.count, 3)
        XCTAssertEqual(reloaded.records.readings.count, 126)
        XCTAssertFalse(reloaded.conversations.isEmpty)
        XCTAssertTrue(store.loadDemoData(french: true))
        XCTAssertEqual(store.visits.count, 3, "Reload must replace, not append")
        store.clear()
        XCTAssertNil(store.archive.demoData)
        XCTAssertTrue(store.visits.isEmpty)
    }
    func testEnglishAndFrenchDemoRecordsUseRealValidationAndReview() throws {
        for french in [false, true] {
            let archive = DemoData.make(french: french)
            let visits = try XCTUnwrap(archive.visits), care = try XCTUnwrap(archive.care)
            XCTAssertEqual(archive.demoData, true)
            XCTAssertTrue(visits.allSatisfy { $0.audioFilename == nil && $0.summary != nil && !$0.transcript.isEmpty })
            XCTAssertTrue(archive.records.readings.allSatisfy { ReadingParser.valid($0.value, kind: $0.kind) })
            for appointment in archive.records.appointments { try AppointmentRules.validate(appointment, visits: visits) }
            for reminder in care.reminders { try CareRules.validate(reminder, visits: visits); XCTAssertFalse(reminder.notify) }
            for schedule in care.schedules { try CareRules.validate(schedule, medicines: archive.records.medicines); XCTAssertFalse(schedule.notify) }
            for log in care.doses { try CareRules.validate(log, care: care, medicines: archive.records.medicines) }
            let visit = try XCTUnwrap(visits.first)
            let changes = try XCTUnwrap(visit.summary).medicines
            let applied = try VisitReview.applying(Set(changes.map(\.id)), from: visit, to: archive.records.medicines)
            XCTAssertTrue(applied.first { $0.id == "amlodipine" }!.instructions.contains("10 mg"))
            XCTAssertFalse(visits.flatMap { $0.summary?.unconfirmedMedicines ?? [] }.isEmpty)
        }
    }
    func testUnreadableArchiveIsNotOverwrittenByDemoReplacement() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("records.json"), original = Data("not a valid archive".utf8)
        try original.write(to: url)
        let store = AppStore(folder: folder)
        try FileManager.default.createDirectory(at: store.visitAudioDirectory, withIntermediateDirectories: true)
        let audio = store.visitAudioDirectory.appendingPathComponent("keep.m4a")
        try Data("keep".utf8).write(to: audio)
        XCTAssertFalse(store.loadDemoData())
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertNotNil(store.error)
    }
}
