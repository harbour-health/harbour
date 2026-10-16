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
    var appointments: [Appointment]?
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
        guard let first = messages.first(where: \.isUser) else { return L10n.string("New chat") }
        return String(first.text.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ").prefix(60))
    }
    func nameChat(_ title: String, firstMessage: UUID) {
        guard messages.first(where: \.isUser)?.id == firstMessage else { return }
        update { $0.chatTitle = title }
    }
    init(folder customFolder: URL? = nil) {
        #if DEBUG
        let screenshots = ProcessInfo.processInfo.arguments.contains("--app-store-screenshots")
        if screenshots { UserDefaults.standard.set(AppearanceChoice.light.rawValue, forKey: "appearance") }
        #endif
        var folder = customFolder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Harbour")
        #if DEBUG
        if screenshots && customFolder == nil { folder = folder.appendingPathComponent("AppStoreScreenshots") }
        #endif
        file = folder.appendingPathComponent("records.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let loaded = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
                guard loaded.version == 1, loaded.records.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
                archive = loaded
            }
        } catch { loadFailed = true; self.error = L10n.format("Your saved records could not be opened. The original file has been kept. %@", L10n.string(error.localizedDescription)) }
        #if DEBUG
        if screenshots { prepareAppStoreScreenshots() }
        #endif
    }
    @discardableResult func update(_ change: (inout Archive) -> Void) -> Bool {
        guard !loadFailed else { error = L10n.string("The saved file could not be read. Changes are blocked to preserve it. Export or recover the file before resetting records in Settings."); return false }
        var next = archive; change(&next)
        do {
            let data = try JSONEncoder().encode(next)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            archive = next
            return true
        } catch { self.error = L10n.format("Couldn’t save this change. %@", L10n.string(error.localizedDescription)); return false }
    }
    func add(_ medicine: Medicine) { _ = saveMedicine(medicine, schedule: care.schedules.first { $0.medicineID == medicine.id }) }
    @discardableResult func saveMedicine(_ medicine: Medicine, schedule: MedicineSchedule?) -> Bool {
        let name = medicine.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !medicine.id.isEmpty, !name.isEmpty, medicine.name.count <= 500 else { error = L10n.string("Enter a medicine name of up to 500 characters."); return false }
        guard !records.medicines.contains(where: { $0.id != medicine.id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name }) else { error = L10n.string("This medicine is already saved. Open it in Medications to make changes."); return false }
        do { if let schedule { try CareRules.validate(schedule, medicines: [medicine]) } }
        catch { self.error = L10n.string(error.localizedDescription); return false }
        return update { value in
            var care = CareRules.preservingDoseSources(value.care ?? CareData(), medicines: value.records.medicines)
            let existing = value.records.medicines.firstIndex { $0.id == medicine.id }
            if let existing { value.records.medicines[existing] = medicine }
            else { value.records.medicines.append(medicine) }
            care.medicineEvents.insert(MedicineEvent(text: L10n.format(existing == nil ? "Added %@" : "Updated %@", L10n.medicineName(medicine))), at: 0)
            care.schedules.removeAll { $0.medicineID == medicine.id }
            if let schedule, !schedule.times.isEmpty || schedule.frequency != nil || schedule.refill != nil { care.schedules.append(schedule) }
            value.care = care
        }
    }
    func removeMedicine(_ id: String) { update {
        $0.care = CareRules.preservingDoseSources($0.care ?? CareData(), medicines: $0.records.medicines)
        if let medicine = $0.records.medicines.first(where: { $0.id == id }) {
            if $0.care == nil { $0.care = CareData() }
            $0.care!.medicineEvents.insert(MedicineEvent(text: L10n.format("Removed %@", L10n.medicineName(medicine))), at: 0)
        }
        $0.records.medicines.removeAll { $0.id == id }; $0.care?.schedules.removeAll { $0.medicineID == id }
    } }
    @discardableResult func saveReminder(_ reminder: CareReminder) -> Bool {
        do { try CareRules.validate(reminder, visits: visits) } catch { self.error = L10n.string(error.localizedDescription); return false }
        return update { if $0.care == nil { $0.care = CareData() }; $0.care!.reminders.removeAll { $0.id == reminder.id }; $0.care!.reminders.append(reminder) }
    }
    func removeReminder(_ id: UUID) { update { $0.care?.reminders.removeAll { $0.id == id } } }
    @discardableResult func logDose(_ log: DoseLog) -> Bool {
        do { try CareRules.validate(log, care: care, medicines: records.medicines) } catch { self.error = L10n.string(error.localizedDescription); return false }
        guard let medicine = records.medicines.first(where: { $0.id == log.medicineID }),
              let schedule = care.schedules.first(where: { $0.medicineID == log.medicineID }),
              let time = schedule.times.first(where: { CareRules.doses(on: log.scheduled, schedule: MedicineSchedule(medicineID: medicine.id, times: [$0])).contains(log.scheduled) }) else { error = L10n.string(CareError.missingMedicine.localizedDescription); return false }
        let saved = log.preservingSource(medicine: medicine, time: time)
        return update { if $0.care == nil { $0.care = CareData() }; $0.care!.doses.removeAll { $0.id == saved.id }; $0.care!.doses.append(saved) }
    }
    @discardableResult func saveQuestion(_ question: AppointmentQuestion) -> Bool {
        guard !question.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, question.text.count <= 1000, question.date.timeIntervalSince1970.isFinite else { error = L10n.string("Enter a question of up to 1,000 characters."); return false }
        return update { if $0.care == nil { $0.care = CareData() }; $0.care!.questions.removeAll { $0.id == question.id }; $0.care!.questions.append(question) }
    }
    func removeQuestion(_ id: UUID) { update { $0.care?.questions.removeAll { $0.id == id } } }
    @discardableResult func saveAppointment(_ appointment: Appointment) -> Bool {
        do { try AppointmentRules.validate(appointment, visits: visits) }
        catch { self.error = L10n.string(error.localizedDescription); return false }
        return update { value in
            value.records.appointments.removeAll { $0.id == appointment.id }
            value.records.appointments.append(appointment)
            value.records.appointments.sort { $0.date < $1.date }
        }
    }
    func removeAppointment(_ id: UUID) { update { $0.records.appointments.removeAll { $0.id == id } } }
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
            catch { self.error = L10n.format("Couldn’t preserve the unreadable file. %@", L10n.string(error.localizedDescription)); return }
        }
        if update({ $0 = Archive() }), FileManager.default.fileExists(atPath: visitAudioDirectory.path) {
            do { try FileManager.default.removeItem(at: visitAudioDirectory) }
            catch { self.error = L10n.format("Records were cleared, but the saved recordings couldn’t be deleted. Unlock the phone and try Delete all again. %@", L10n.string(error.localizedDescription)) }
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
            for index in value.records.appointments.indices where value.records.appointments[index].visitID == visit.id {
                if (try? AppointmentRules.validate(value.records.appointments[index], visits: visits)) == nil {
                    value.records.appointments[index].visitID = nil; value.records.appointments[index].quote = nil
                }
            }
            if value.care != nil {
                for index in value.care!.reminders.indices where value.care!.reminders[index].visitID == visit.id {
                    if (try? CareRules.validate(value.care!.reminders[index], visits: visits)) == nil {
                        value.care!.reminders[index].visitID = nil; value.care!.reminders[index].quote = nil
                    }
                }
            }
        }
    }
    #if DEBUG
    func prepareMedicineReviewScreenshot() {
        let title = "Medication drawer review"
        for visit in visits where visit.title == title { deleteVisit(visit) }
        let transcript = "Start metformin 500 mg twice daily."
        let output = #"{"highlights":[],"medicines":[{"action":"start","name":"metformin","instructions":"500 mg twice daily","quote":"Start metformin 500 mg twice daily."}],"followUps":[]}"#
        guard let summary = try? VisitReview.parse(output, transcript: transcript, medicines: records.medicines), summary.medicines.count == 1 else { return }
        let visit = DoctorVisit(title: title, transcript: transcript)
        if saveVisit(visit) { saveVisitSummary(summary, id: visit.id, transcript: transcript, baseline: records.medicines) }
    }
    func prepareAppointmentSummaryFixture() {
        let title = "Appointment summary regression"
        for visit in visits where visit.title == title { deleteVisit(visit) }
        let transcript = L10n.isFrench ? "Rendez-vous demain à 15 h." : "Appointment tomorrow at 3 pm."
        let output = #"{"highlights":[],"medicines":[],"followUps":[]}"#
        guard let summary = try? VisitReview.parse(output, transcript: transcript, medicines: records.medicines),
              summary.appointments?.count == 1, summary.highlights.isEmpty,
              summary.medicines.isEmpty, summary.followUps.isEmpty else { return }
        let visit = DoctorVisit(title: title, transcript: transcript)
        if saveVisit(visit) { saveVisitSummary(summary, id: visit.id, transcript: transcript, baseline: records.medicines) }
    }
    #endif
    func deleteVisit(_ visit: DoctorVisit) {
        if update({ value in
            value.visits?.removeAll { $0.id == visit.id }
            for i in value.records.appointments.indices where value.records.appointments[i].visitID == visit.id {
                value.records.appointments[i].visitID = nil; value.records.appointments[i].quote = nil
            }
            if value.care != nil { for i in value.care!.reminders.indices where value.care!.reminders[i].visitID == visit.id { value.care!.reminders[i].visitID = nil; value.care!.reminders[i].quote = nil } }
        }), let audio = audioURL(for: visit) {
            do { if FileManager.default.fileExists(atPath: audio.path) { try FileManager.default.removeItem(at: audio) } }
            catch { self.error = L10n.format("The visit was removed, but its audio couldn’t be deleted. %@", L10n.string(error.localizedDescription)) }
        }
    }
    func saveVisitSummary(_ summary: VisitSummary, id: UUID, transcript: String, baseline: [Medicine], extractionRuns: [VisitExtractionRun]? = nil) {
        guard var visit = visits.first(where: { $0.id == id }), visit.transcript == transcript else { return }
        visit.summary = summary; visit.medicineBaseline = baseline
        visit.extractionRuns = extractionRuns
        saveVisit(visit)
    }
    func saveVisitExtractionRuns(_ runs: [VisitExtractionRun], id: UUID, transcript: String) {
        guard var visit = visits.first(where: { $0.id == id }), visit.transcript == transcript else { return }
        // Failed/cancelled attempts retain evidence without replacing a prior summary.
        visit.extractionRuns = runs; saveVisit(visit)
    }
    func applyVisitChanges(id: UUID, selected: Set<UUID>) -> Bool {
        guard let visit = visits.first(where: { $0.id == id }) else { return false }
        do {
            let medicines = try VisitReview.applying(selected, from: visit, to: records.medicines)
            return update { value in
                guard let index = value.visits?.firstIndex(where: { $0.id == id }) else { return }
                if value.care == nil { value.care = CareData() }
                value.care = CareRules.preservingDoseSources(value.care!, medicines: value.records.medicines)
                for change in visit.summary!.medicines where selected.contains(change.id) {
                    let event: String
                    switch change.action {
                    case .start: event = L10n.format("Started %@", L10n.medicineName(change.medicine))
                    case .update: event = L10n.format("Updated %@", L10n.medicineName(change.medicine))
                    case .stop: event = L10n.format("Stopped %@", L10n.medicineName(change.medicine))
                    }
                    value.care!.medicineEvents.insert(MedicineEvent(text: event), at: 0)
                    if change.action == .stop { value.care!.schedules.removeAll { $0.medicineID == change.medicine.id } }
                    else if change.frequency != nil || !change.times.isEmpty {
                        value.care!.schedules.removeAll { $0.medicineID == change.medicine.id }
                        value.care!.schedules.append(MedicineSchedule(medicineID: change.medicine.id, times: change.times, frequency: change.frequency))
                    }
                }
                value.care!.schedules.removeAll { schedule in !medicines.contains { $0.id == schedule.medicineID } }
                value.records.medicines = medicines
                value.visits![index].appliedChanges = visit.summary!.medicines.filter { selected.contains($0.id) }
            }
        } catch { self.error = L10n.string(error.localizedDescription); return false }
    }
    func shareVisit(_ visit: DoctorVisit) {
        do {
            var text = "\(visit.title)\n\(L10n.date(visit.date, time: true))\n\n"
            if let summary = visit.summary {
                text += L10n.string("Notes") + "\n" + summary.highlights.map(\.quote).joined(separator: "\n") + "\n\n"
                text += L10n.string("Follow-up") + "\n" + summary.followUps.map(\.quote).joined(separator: "\n") + "\n\n"
            }
            text += L10n.string("Transcript") + "\n" + visit.transcript
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Harbour-visit.txt")
            try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
            shareFile = ShareFile(url: url)
        } catch { self.error = L10n.string(error.localizedDescription) }
    }
    func export() {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Harbour-records.json")
            try encoder.encode(CareBackup(records: records, care: care, visits: visits)).write(to: destination, options: [.atomic, .completeFileProtection])
            shareFile = ShareFile(url: destination)
        } catch { self.error = L10n.string(error.localizedDescription) }
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

        } catch { self.error = L10n.format("Couldn’t import these records. %@", L10n.string(error.localizedDescription)) }
    }
}

#if DEBUG
extension AppStore {
    /// Fictional saved inputs only: this fixture never runs or simulates model inference.
    private func prepareAppStoreScreenshots() {
        let date = Date(timeIntervalSince1970: 1790859600) // 2026-10-01 09:00 America/Toronto
        let french = L10n.isFrench
        var records = Records()
        var metformin = Catalog.medicines.first { $0.id == "metformin" }!
        metformin.instructions = french ? "500 mg, deux fois par jour" : "500 mg, twice daily"
        var amlodipine = Catalog.medicines.first { $0.id == "amlodipine" }!
        amlodipine.instructions = french ? "5 mg, une fois par jour" : "5 mg, once daily"
        records.medicines = [metformin, amlodipine]
        records.readings = [
            Reading(id: "store-heart", kind: .heartRate, value: "72", date: date),
            Reading(id: "store-pressure", kind: .bloodPressure, value: "120/80", date: date.addingTimeInterval(-1800)),
            Reading(id: "store-temperature", kind: .temperature, value: "36.8", date: date.addingTimeInterval(-3600))
        ]
        records.symptoms = [Symptom(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, text: french ? "Genou douloureux après une promenade" : "Sore knee after a walk", onset: french ? "Depuis mardi" : "Since Tuesday", severity: "Mild", date: date.addingTimeInterval(-86400))]
        var care = CareData()
        care.questions = [AppointmentQuestion(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, text: french ? "Quels changements devrais-je surveiller?" : "What changes should I watch for?", date: date)]
        let visit = DoctorVisit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, title: french ? "Consultation de suivi" : "Follow-up visit", date: date.addingTimeInterval(-172800), transcript: french ? "Nous avons discuté du sommeil et des promenades quotidiennes. Apporter la liste des médicaments à la prochaine consultation." : "We discussed sleep habits and daily walks. Bring a medicine list to the next visit.")
        _ = update { $0 = Archive(); $0.records = records; $0.care = care; $0.visits = [visit] }
    }
}
#endif
