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
    public var medications: [Medicine] = []
    public var medicines: [Medicine] { get { medications } set { medications = newValue } }
    public var appointments: [Appointment] = []
    public var readings: [Reading] = []
    public var symptoms: [Symptom] = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case schemaVersion, medications, medicines, appointments, readings, symptoms }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        medications = try values.decodeIfPresent([Medicine].self, forKey: .medications) ?? values.decodeIfPresent([Medicine].self, forKey: .medicines) ?? []
        appointments = try values.decodeIfPresent([Appointment].self, forKey: .appointments) ?? []
        readings = try values.decode([Reading].self, forKey: .readings)
        symptoms = try values.decode([Symptom].self, forKey: .symptoms)
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(medications, forKey: .medications)
        try values.encode(appointments, forKey: .appointments)
        try values.encode(readings, forKey: .readings)
        try values.encode(symptoms, forKey: .symptoms)
    }
    public var appointmentNote: String {
        let concern = symptoms.sorted { $0.date > $1.date }.first
        return """
        Concern: \(concern?.text ?? "Not recorded")
        Started: \(concern?.onset.isEmpty == false ? concern!.onset : "Not recorded")
        Severity: \(concern?.severity ?? "Not recorded")
        Medications entered: \(medicines.isEmpty ? "None entered" : medicines.map(\.name).joined(separator: ", "))
        Recent readings: \(readings.sorted { $0.date > $1.date }.prefix(5).map { "\($0.kind.rawValue): \($0.value) \($0.kind.unit)" }.joined(separator: "; "))
        Questions: What should I watch for? Should a pharmacist review my medications?
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
    private static let aliases: [String: [String]] = [
        "warfarin": ["warfarine"], "ibuprofen": ["ibuprofène"],
        "aspirin": ["ASA", "aspirine", "AAS", "acide acétylsalicylique"],
        "naproxen": ["naproxène"], "acetaminophen": ["acétaminophène"],
        "metformin": ["metformine"]
    ]
    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    public static func names(for medicine: Medicine) -> [String] {
        let names = [medicine.name, medicine.name.components(separatedBy: " / ").first!]
        guard let canonical = medicines.first(where: { $0.id == medicine.id }),
              ([canonical.name, canonical.name.components(separatedBy: " / ").first!] + (aliases[canonical.id] ?? [])).contains(where: { folded($0) == folded(medicine.name) }) else { return names }
        return names + [canonical.name, canonical.name.components(separatedBy: " / ").first!] + (aliases[medicine.id] ?? [])
    }
    public static func ingredientNames(for ingredient: String) -> [String] {
        [ingredient] + (aliases[ingredient] ?? [])
    }
    public static func resolve(_ name: String, saved: [Medicine] = []) -> Medicine? {
        let query = folded(name.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return nil }
        return (saved + medicines).first { names(for: $0).contains { folded($0) == query } }
    }
    public static func search(_ query: String) -> [Medicine] {
        let query = folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return medicines.filter { medicine in
            query.isEmpty || (names(for: medicine) + medicine.ingredients.flatMap { ingredientNames(for: $0) }).contains { folded($0).contains(query) }
        }
    }
    public static func mentioned(in text: String, saved: [Medicine] = []) -> [Medicine] {
        var found = Set<String>()
        let text = folded(text)
        return (saved + medicines).filter { medicine in
            names(for: medicine).contains { text.range(of: "(?<![\\p{L}\\p{M}\\p{N}_])" + NSRegularExpression.escapedPattern(for: folded($0)) + "(?![\\p{L}\\p{M}\\p{N}_])", options: .regularExpression) != nil } && found.insert(medicine.id).inserted
        }
    }
}

public enum ReadingParser {
    public static func parse(_ input: String) -> Reading? {
        let input = input.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let labels: [(ReadingKind, String)] = [
            (.heartRate, "heart rate|pulse|pouls|frequence cardiaque|rythme cardiaque"),
            (.bloodPressure, "blood pressure|tension arterielle|pression arterielle|tension"),
            (.temperature, "temperature")
        ]
        let matches = labels.compactMap { (kind, label) -> (ReadingKind, Range<String.Index>)? in
            guard let range = input.range(of: "\\b(?:" + label + ")(?![\\p{L}\\p{M}])", options: .regularExpression) else { return nil }
            return (kind, range)
        }
        guard let match = matches.min(by: { $0.1.lowerBound < $1.1.lowerBound }) else { return nil }
        let kind = match.0
        let portion = String(input[match.1.upperBound...].prefix(36)).components(separatedBy: .newlines).first!
        guard portion.range(of: "[0-9]+(?:[.,][0-9]+)?[eE][+-]?[0-9]+", options: .regularExpression) == nil else { return nil }
        let number = kind == .bloodPressure ? "[0-9]{2,3}\\s*/\\s*[0-9]{2,3}" : "[0-9]{1,3}(?:[.,][0-9]+)?"
        let numeric = "(?<![0-9.,/+−-])" + number + "(?![0-9.,/]|[eE][+-]?[0-9])"
        guard let valueRange = portion.range(of: numeric, options: .regularExpression) else { return nil }
        let value = normalizedValue(String(portion[valueRange]))
        guard valid(value, kind: kind) else { return nil }
        return Reading(kind: kind, value: value)
    }
    public static func normalizedValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\s*/\\s*", with: "/", options: .regularExpression).replacingOccurrences(of: ",", with: ".")
    }
    public static func valid(_ value: String, kind: ReadingKind) -> Bool {
        let value = normalizedValue(value)
        if kind == .bloodPressure {
            guard value.range(of: "\\A[0-9]{2,3}/[0-9]{2,3}\\z", options: .regularExpression) != nil else { return false }
            let parts = value.split(separator: "/").compactMap { Double($0) }
            return parts.count == 2 && parts.allSatisfy { (10...350).contains($0) } && parts[0] > parts[1]
        }
        guard value.range(of: "\\A[0-9]{1,3}(?:\\.[0-9]+)?\\z", options: .regularExpression) != nil else { return false }
        guard let number = Double(value), number.isFinite else { return false }
        return kind == .heartRate ? (10...300).contains(number) : (25...45).contains(number)
    }
}
