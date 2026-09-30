import Foundation
import HarbourCore

struct ChatMessage: Codable, Identifiable {
    var id = UUID()
    var isUser = false
    var text: String
    var report: InteractionReport?
    var readings: [Reading]?
    var medicines: [Medicine]?
    var date = Date()
}
struct Archive: Codable {
    var version = 1
    var records = Records()
    var messages: [ChatMessage] = []
}
struct ShareFile: Identifiable { let id = UUID(); let url: URL }

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var archive = Archive()
    @Published var error: String?
    @Published var shareFile: ShareFile?
    let file: URL
    private var loadFailed = false
    var records: Records { archive.records }
    var messages: [ChatMessage] { archive.messages }
    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Harbour")
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
    private func update(_ change: (inout Archive) -> Void) {
        guard !loadFailed else { error = "The saved file could not be read. Changes are blocked to preserve it. Export or recover the file before resetting records in Settings."; return }
        var next = archive; change(&next)
        do {
            let data = try JSONEncoder().encode(next)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            archive = next
        } catch { self.error = "Couldn’t save this change. \(error.localizedDescription)" }
    }
    func add(_ medicine: Medicine) { update { value in
        if let i = value.records.medicines.firstIndex(where: { $0.id == medicine.id }) { value.records.medicines[i] = medicine }
        else { value.records.medicines.append(medicine) }
    } }
    func removeMedicine(_ id: String) { update { $0.records.medicines.removeAll { $0.id == id } } }
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
    func newChat() { update { $0.messages.removeAll() } }
    func clear() {
        if loadFailed {
            do { try FileManager.default.copyItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent("unreadable-\(UUID().uuidString).json")); loadFailed = false }
            catch { self.error = "Couldn’t preserve the unreadable file. \(error.localizedDescription)"; return }
        }
        update { $0 = Archive() }
    }
    func export() {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Harbour-records.json")
            try encoder.encode(records).write(to: destination, options: [.atomic, .completeFileProtection])
            shareFile = ShareFile(url: destination)
        } catch { self.error = error.localizedDescription }
    }
    func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size < 5_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let incoming = try decoder.decode(Records.self, from: Data(contentsOf: url))
            guard incoming.schemaVersion == 1,
                  incoming.readings.allSatisfy({ ReadingParser.valid($0.value, kind: $0.kind) }),
                  incoming.medicines.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }) else { throw CocoaError(.coderReadCorrupt) }
            // Ingredient mapping is rebuilt from our catalog; file-supplied ingredients aren't trusted.
            update { value in
                for imported in incoming.medicines {
                    var medicine = Catalog.medicines.first { $0.name.caseInsensitiveCompare(imported.name) == .orderedSame } ?? Medicine(name: imported.name)
                    medicine.instructions = imported.instructions
                    if !value.records.medicines.contains(where: { $0.name.caseInsensitiveCompare(medicine.name) == .orderedSame }) { value.records.medicines.append(medicine) }
                }
                let readingIDs = Set(value.records.readings.map(\.id)), symptomIDs = Set(value.records.symptoms.map(\.id))
                value.records.readings.append(contentsOf: incoming.readings.filter { !readingIDs.contains($0.id) })
                value.records.symptoms.append(contentsOf: incoming.symptoms.filter { !symptomIDs.contains($0.id) })
                value.records.readings.sort { $0.date > $1.date }; value.records.symptoms.sort { $0.date > $1.date }
            }
        } catch { self.error = "Couldn’t import these records. \(error.localizedDescription)" }
    }
}
