import Foundation
import HarbourCore

struct ChatTimelineEntry: Codable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var date: Date
    init(_ entry: TimelineEntry) { id = entry.id; title = entry.title; detail = entry.detail; date = entry.date }
}
struct ChatMessage: Codable, Identifiable {
    var id = UUID()
    var isUser = false
    var text: String
    var report: InteractionReport?
    var readings: [Reading]?
    var medicines: [Medicine]?
    var reminders: [CareReminder]?
    var timeline: [ChatTimelineEntry]?
    var date = Date()
}
struct Archive: Codable {
    var version = 1
    var records = Records()
    var messages: [ChatMessage] = []
    var chatTitle: String?
    var visits: [DoctorVisit]?
    var care: CareData?
}
struct ShareFile: Identifiable { let id = UUID(); let url: URL }

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var archive = Archive()
    @Published var error: String?
    @Published var shareFile: ShareFile?
    let file: URL
    private var loadFailed = false
    var visits: [DoctorVisit] { archive.visits ?? [] }
    var care: CareData { archive.care ?? CareData() }
    var records: Records { archive.records }
    var messages: [ChatMessage] { archive.messages }
    var chatTitle: String {
        if let title = archive.chatTitle { return title }
        guard let first = messages.first(where: \.isUser) else { return "New chat" }
        return String(first.text.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ").prefix(60))
    }
    func nameChat(_ title: String, firstMessage: UUID) {
        guard messages.first(where: \.isUser)?.id == firstMessage else { return }
        update { $0.chatTitle = title }
    }
    init(folder customFolder: URL? = nil) {
        let folder = customFolder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Harbour")
        file = folder.appendingPathComponent("records.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let loaded = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
                guard loaded.version == 1, loaded.records.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
                archive = loaded
            }
        } catch { loadFailed = true; self.error = "Your saved records could not be opened. The original file has been kept. \(error.localizedDescription)" }
    }
    @discardableResult func update(_ change: (inout Archive) -> Void) -> Bool {
        guard !loadFailed else { error = "The saved file could not be read. Changes are blocked to preserve it. Export or recover the file before resetting records in Settings."; return false }
        var next = archive; change(&next)
        do {
            let data = try JSONEncoder().encode(next)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            archive = next
            return true
        } catch { self.error = "Couldn’t save this change. \(error.localizedDescription)"; return false }
    }
    func add(_ medicine: Medicine) { _ = saveMedicine(medicine, schedule: care.schedules.first { $0.medicineID == medicine.id }) }
    @discardableResult func saveMedicine(_ medicine: Medicine, schedule: MedicineSchedule?) -> Bool {
        let name = medicine.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !medicine.id.isEmpty, !name.isEmpty, medicine.name.count <= 500 else { error = "Enter a medicine name of up to 500 characters."; return false }
        guard !records.medicines.contains(where: { $0.id != medicine.id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name }) else { error = "This medicine is already saved. Open it in Medicines to make changes."; return false }
        do { if let schedule { try CareRules.validate(schedule, medicines: [medicine]) } }
        catch { self.error = error.localizedDescription; return false }
        return update { value in
            var care = CareRules.preservingDoseSources(value.care ?? CareData(), medicines: value.records.medicines)
            let existing = value.records.medicines.firstIndex { $0.id == medicine.id }
            if let existing { value.records.medicines[existing] = medicine }
            else { value.records.medicines.append(medicine) }
            care.medicineEvents.insert(MedicineEvent(text: "\(existing == nil ? "Added" : "Updated") \(medicine.name)"), at: 0)
            care.schedules.removeAll { $0.medicineID == medicine.id }
            if let schedule, !schedule.times.isEmpty || schedule.refill != nil { care.schedules.append(schedule) }
            value.care = care
        }
    }
    func removeMedicine(_ id: String) { update {
        $0.care = CareRules.preservingDoseSources($0.care ?? CareData(), medicines: $0.records.medicines)
        if let name = $0.records.medicines.first(where: { $0.id == id })?.name {
            if $0.care == nil { $0.care = CareData() }
            $0.care!.medicineEvents.insert(MedicineEvent(text: "Removed " + name), at: 0)
        }
        $0.records.medicines.removeAll { $0.id == id }; $0.care?.schedules.removeAll { $0.medicineID == id }
    } }
    @discardableResult func saveReminder(_ reminder: CareReminder) -> Bool {
        do { try CareRules.validate(reminder, visits: visits) } catch { self.error = error.localizedDescription; return false }
        return update { if $0.care == nil { $0.care = CareData() }; $0.care!.reminders.removeAll { $0.id == reminder.id }; $0.care!.reminders.append(reminder) }
    }
    func removeReminder(_ id: UUID) { update { $0.care?.reminders.removeAll { $0.id == id } } }
    @discardableResult func logDose(_ log: DoseLog) -> Bool {
        do { try CareRules.validate(log, care: care, medicines: records.medicines) } catch { self.error = error.localizedDescription; return false }
        guard let medicine = records.medicines.first(where: { $0.id == log.medicineID }),
              let schedule = care.schedules.first(where: { $0.medicineID == log.medicineID }),
              let time = schedule.times.first(where: { CareRules.doses(on: log.scheduled, schedule: MedicineSchedule(medicineID: medicine.id, times: [$0])).contains(log.scheduled) }) else { error = CareError.missingMedicine.localizedDescription; return false }
        let saved = log.preservingSource(medicine: medicine, time: time)
        return update { if $0.care == nil { $0.care = CareData() }; $0.care!.doses.removeAll { $0.id == saved.id }; $0.care!.doses.append(saved) }
    }
    @discardableResult func saveQuestion(_ question: AppointmentQuestion) -> Bool {
        guard !question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, question.text.count <= 1000, question.date.timeIntervalSince1970.isFinite else { error = "Enter a question of up to 1,000 characters."; return false }
        return update { if $0.care == nil { $0.care = CareData() }; $0.care!.questions.removeAll { $0.id == question.id }; $0.care!.questions.append(question) }
    }
    func removeQuestion(_ id: UUID) { update { $0.care?.questions.removeAll { $0.id == id } } }
    func add(_ reading: Reading) { update { if !$0.records.readings.contains(where: { $0.id == reading.id }) { $0.records.readings.append(reading); $0.records.readings.sort { $0.date > $1.date } } } }
    func importReadings(_ readings: [Reading]) { update { value in
        let existing = Set(value.records.readings.map(\.id))
        value.records.readings.append(contentsOf: readings.filter { !existing.contains($0.id) })
        value.records.readings.sort { $0.date > $1.date }
    } }
    func removeReading(_ id: String) { update { $0.records.readings.removeAll { $0.id == id } } }
    func add(_ symptom: Symptom) { update { $0.records.symptoms.insert(symptom, at: 0) } }
    func removeSymptom(_ id: UUID) { update { $0.records.symptoms.removeAll { $0.id == id } } }
    func append(_ message: ChatMessage) { update { $0.messages.append(message) } }
    func newChat() { update { $0.messages.removeAll(); $0.chatTitle = nil } }
    func clear() {
        if loadFailed {
            do { try FileManager.default.copyItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent("unreadable-\(UUID().uuidString).json")); loadFailed = false }
            catch { self.error = "Couldn’t preserve the unreadable file. \(error.localizedDescription)"; return }
        }
        if update({ $0 = Archive() }), FileManager.default.fileExists(atPath: visitAudioDirectory.path) {
            do { try FileManager.default.removeItem(at: visitAudioDirectory) }
            catch { self.error = "Records were cleared, but the saved recordings couldn’t be deleted. Unlock the phone and try Delete all again. \(error.localizedDescription)" }
        }
    }
    var visitAudioDirectory: URL { file.deletingLastPathComponent().appendingPathComponent("VisitAudio") }
    func audioURL(for visit: DoctorVisit) -> URL? {
        guard let name = visit.audioFilename, name == visit.id.uuidString + ".m4a" else { return nil }
        return visitAudioDirectory.appendingPathComponent(name)
    }
    @discardableResult func saveVisit(_ visit: DoctorVisit) -> Bool {
        update { value in
            var visits = value.visits ?? []
            if let index = visits.firstIndex(where: { $0.id == visit.id }) { visits[index] = visit }
            else { visits.insert(visit, at: 0) }
            value.visits = visits
            if value.care != nil {
                for index in value.care!.reminders.indices where value.care!.reminders[index].visitID == visit.id {
                    if (try? CareRules.validate(value.care!.reminders[index], visits: visits)) == nil {
                        value.care!.reminders[index].visitID = nil; value.care!.reminders[index].quote = nil
                    }
                }
            }
        }
    }
    func deleteVisit(_ visit: DoctorVisit) {
        if update({ $0.visits?.removeAll { $0.id == visit.id }; if $0.care != nil { for i in $0.care!.reminders.indices where $0.care!.reminders[i].visitID == visit.id { $0.care!.reminders[i].visitID = nil; $0.care!.reminders[i].quote = nil } } }), let audio = audioURL(for: visit) {
            do { if FileManager.default.fileExists(atPath: audio.path) { try FileManager.default.removeItem(at: audio) } }
            catch { self.error = "The visit was removed, but its audio couldn’t be deleted. \(error.localizedDescription)" }
        }
    }
    func saveVisitSummary(_ summary: VisitSummary, id: UUID, transcript: String, baseline: [Medicine]) {
        guard var visit = visits.first(where: { $0.id == id }), visit.transcript == transcript else { return }
        visit.summary = summary; visit.medicineBaseline = baseline
        saveVisit(visit)
    }
    func applyVisitChanges(id: UUID, selected: Set<UUID>) -> Bool {
        guard let visit = visits.first(where: { $0.id == id }) else { return false }
        do {
            let medicines = try VisitReview.applying(selected, from: visit, to: records.medicines)
            return update { value in
                guard let index = value.visits?.firstIndex(where: { $0.id == id }) else { return }
                if value.care == nil { value.care = CareData() }
                value.care = CareRules.preservingDoseSources(value.care!, medicines: value.records.medicines)
                for change in visit.summary!.medicines where selected.contains(change.id) { value.care!.medicineEvents.insert(MedicineEvent(text: change.action.rawValue + " " + change.medicine.name), at: 0) }
                value.care!.schedules.removeAll { schedule in !medicines.contains { $0.id == schedule.medicineID } }
                value.records.medicines = medicines
                value.visits![index].appliedChanges = visit.summary!.medicines.filter { selected.contains($0.id) }
            }
        } catch { self.error = error.localizedDescription; return false }
    }
    func shareVisit(_ visit: DoctorVisit) {
        do {
            let text = "\(visit.title)\n\(visit.date.formatted())\n\n" + (visit.summary.map { "Notes\n" + $0.highlights.map(\.quote).joined(separator: "\n") + "\n\nFollow-up\n" + $0.followUps.map(\.quote).joined(separator: "\n") + "\n\n" } ?? "") + "Transcript\n" + visit.transcript
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Harbour-visit.txt")
            try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
            shareFile = ShareFile(url: url)
        } catch { self.error = error.localizedDescription }
    }
    func export() {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Harbour-records.json")
            try encoder.encode(CareBackup(records: records, care: care, visits: visits)).write(to: destination, options: [.atomic, .completeFileProtection])
            shareFile = ShareFile(url: destination)
        } catch { self.error = error.localizedDescription }
    }
    func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size < 5_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let data = try Data(contentsOf: url)
            guard data.count < 5_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let backup = try? decoder.decode(CareBackup.self, from: data)
            if let backup { guard backup.version == 2 else { throw CareError.invalid } }
            let incoming = try backup?.records ?? decoder.decode(Records.self, from: data)
            let incomingBackup = backup ?? CareBackup(records: incoming, care: CareData(), visits: [])
            let merged = try incomingBackup.merging(into: CareBackup(records: records, care: care, visits: visits))
            // The validated merge is prepared before the atomic write, so conflicts cannot partially import.
            if update({ value in
                value.records = merged.records; value.care = merged.care
                // Preserve local audio references; imported visits never bring file paths.
                let localIDs = Set((value.visits ?? []).map(\.id))
                if value.visits == nil { value.visits = [] }
                value.visits!.append(contentsOf: merged.visits.filter { !localIDs.contains($0.id) })
            }) { error = nil }

        } catch { self.error = "Couldn’t import these records. \(error.localizedDescription)" }
    }
}
