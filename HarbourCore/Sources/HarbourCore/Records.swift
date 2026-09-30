import Foundation

public struct Medicine: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var ingredients: [String]
    public var instructions: String
    public init(id: String = UUID().uuidString, name: String, ingredients: [String] = [], instructions: String = "") {
        self.id = id; self.name = name; self.ingredients = ingredients; self.instructions = instructions
    }
}

public enum ReadingKind: String, Codable, CaseIterable, Sendable {
    case heartRate = "Heart rate", bloodPressure = "Blood pressure", temperature = "Temperature"
    public var unit: String { switch self { case .heartRate: "bpm"; case .bloodPressure: "mmHg"; case .temperature: "°C" } }
    public var symbol: String { switch self { case .heartRate: "heart.fill"; case .bloodPressure: "waveform.path.ecg"; case .temperature: "thermometer.medium" } }
}

public struct Reading: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: ReadingKind
    public var value: String
    public var date: Date
    public var source: String
    public init(id: String = UUID().uuidString, kind: ReadingKind, value: String, date: Date = .now, source: String = "Manual") {
        self.id = id; self.kind = kind; self.value = value; self.date = date; self.source = source
    }
}

public enum EmergencySign: String, Codable, CaseIterable, Identifiable, Sendable {
    case consciousness = "Loss of consciousness", confusion = "New confusion", chest = "Persistent, severe chest pain", breathing = "Difficulty breathing", pain = "Severe pain not relieved by pain medicine"
    public var id: String { rawValue }
}

public struct Symptom: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var onset: String
    public var severity: String
    public var signs: [EmergencySign]
    public var date: Date
    public init(id: UUID = UUID(), text: String, onset: String = "", severity: String = "Not specified", signs: [EmergencySign] = [], date: Date = .now) {
        self.id = id; self.text = text; self.onset = onset; self.severity = severity; self.signs = signs; self.date = date
    }
}

public struct Records: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var medicines: [Medicine] = []
    public var readings: [Reading] = []
    public var symptoms: [Symptom] = []
    public init() {}
    public var appointmentNote: String {
        let concern = symptoms.sorted { $0.date > $1.date }.first
        return """
        Concern: \(concern?.text ?? "Not recorded")
        Started: \(concern?.onset.isEmpty == false ? concern!.onset : "Not recorded")
        Severity: \(concern?.severity ?? "Not recorded")
        Medicines entered: \(medicines.isEmpty ? "None entered" : medicines.map(\.name).joined(separator: ", "))
        Recent readings: \(readings.sorted { $0.date > $1.date }.prefix(5).map { "\($0.kind.rawValue): \($0.value) \($0.kind.unit)" }.joined(separator: "; "))
        Questions: What should I watch for? Should a pharmacist review my medicines?
        """
    }
}

public enum Catalog {
    public static let medicines: [Medicine] = [
        Medicine(id: "warfarin", name: "Warfarin", ingredients: ["warfarin"]),
        Medicine(id: "advil", name: "Advil", ingredients: ["ibuprofen"]),
        Medicine(id: "ibuprofen", name: "Ibuprofen", ingredients: ["ibuprofen"]),
        Medicine(id: "aspirin", name: "Aspirin / ASA", ingredients: ["aspirin"]),
        Medicine(id: "aleve", name: "Aleve", ingredients: ["naproxen"]),
        Medicine(id: "naproxen", name: "Naproxen", ingredients: ["naproxen"]),
        Medicine(id: "tylenol", name: "Tylenol", ingredients: ["acetaminophen"]),
        Medicine(id: "acetaminophen", name: "Acetaminophen", ingredients: ["acetaminophen"]),
        Medicine(id: "metformin", name: "Metformin", ingredients: ["metformin"]),
        Medicine(id: "amlodipine", name: "Amlodipine", ingredients: ["amlodipine"]),
        Medicine(id: "apixaban", name: "Apixaban", ingredients: ["apixaban"])
    ]
    public static func mentioned(in text: String, saved: [Medicine] = []) -> [Medicine] {
        var found = Set<String>()
        return (saved + medicines).filter { medicine in
            let names = [medicine.name.components(separatedBy: " / ").first!] + (medicine.id == "aspirin" ? ["ASA"] : [])
            return names.contains { text.range(of: "\\b" + NSRegularExpression.escapedPattern(for: $0) + "\\b", options: [.regularExpression, .caseInsensitive]) != nil } && found.insert(medicine.id).inserted
        }
    }
}

public enum ReadingParser {
    public static func parse(_ input: String) -> Reading? {
        let pattern = "(?i)\\b(heart rate|pulse|blood pressure|temperature)\\b([^\\n]{0,36})"
        guard let match = input.range(of: pattern, options: .regularExpression) else { return nil }
        let portion = String(input[match]).lowercased()
        let kind: ReadingKind = portion.hasPrefix("blood pressure") ? .bloodPressure : portion.hasPrefix("temperature") ? .temperature : .heartRate
        let numeric = kind == .bloodPressure ? "\\b[0-9]{2,3}\\s*/\\s*[0-9]{2,3}\\b" : "\\b[0-9]{1,3}(?:\\.[0-9]+)?\\b"
        guard let valueRange = portion.range(of: numeric, options: .regularExpression) else { return nil }
        let value = String(portion[valueRange]).replacingOccurrences(of: " ", with: "")
        guard valid(value, kind: kind) else { return nil }
        return Reading(kind: kind, value: value)
    }
    public static func valid(_ value: String, kind: ReadingKind) -> Bool {
        if kind == .bloodPressure {
            let parts = value.split(separator: "/").compactMap { Double($0) }
            return parts.count == 2 && parts.allSatisfy { (10...350).contains($0) } && parts[0] > parts[1]
        }
        guard let number = Double(value), number.isFinite else { return false }
        return kind == .heartRate ? (10...300).contains(number) : (25...45).contains(number)
    }
}
