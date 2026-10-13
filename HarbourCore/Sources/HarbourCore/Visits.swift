import Foundation

public struct VisitQuote: Codable, Equatable, Sendable, Identifiable {
    public var quote: String
    public var id: String { quote }
    public init(quote: String) { self.quote = quote }
}
public enum MedicineChangeAction: String, Codable, CaseIterable, Sendable { case start, update, stop }
public struct VisitMedicineChange: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var action: MedicineChangeAction
    public var medicine: Medicine
    public var quote: String
    public var frequency: MedicationFrequency?
    public var times: [DoseTime]
    public init(id: UUID = UUID(), action: MedicineChangeAction, medicine: Medicine, quote: String, frequency: MedicationFrequency? = nil, times: [DoseTime] = []) {
        self.id = id; self.action = action; self.medicine = medicine; self.quote = quote; self.frequency = frequency; self.times = times
    }
    private enum CodingKeys: String, CodingKey { case id, action, medicine, quote, frequency, times }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id); action = try values.decode(MedicineChangeAction.self, forKey: .action)
        medicine = try values.decode(Medicine.self, forKey: .medicine); quote = try values.decode(String.self, forKey: .quote)
        frequency = try values.decodeIfPresent(MedicationFrequency.self, forKey: .frequency)
        times = try values.decodeIfPresent([DoseTime].self, forKey: .times) ?? []
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(action, forKey: .action); try values.encode(medicine, forKey: .medicine)
        try values.encode(quote, forKey: .quote); try values.encodeIfPresent(frequency, forKey: .frequency); try values.encode(times, forKey: .times)
    }
}
public struct VisitSummary: Codable, Equatable, Sendable {
    public var highlights: [VisitQuote] = []
    public var medicines: [VisitMedicineChange] = []
    public var followUps: [VisitQuote] = []
    public var appointments: [VisitQuote]?
    public init() {}
    public mutating func merge(_ other: VisitSummary) {
        for quote in other.appointments ?? [] where !(appointments ?? []).contains(quote) { if appointments == nil { appointments = [] }; appointments!.append(quote) }
        for quote in other.highlights where !highlights.contains(quote) { highlights.append(quote) }
        for quote in other.followUps where !followUps.contains(quote) { followUps.append(quote) }
        for change in other.medicines where !medicines.contains(where: { $0.action == change.action && $0.medicine == change.medicine && $0.quote == change.quote && $0.frequency == change.frequency && $0.times == change.times }) { medicines.append(change) }
    }
}
public struct DoctorVisit: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var duration: TimeInterval
    public var transcript: String
    public var audioFilename: String?
    public var interrupted: Bool
    public var transcriptionWarning: String?
    public var summary: VisitSummary?
    public var medicineBaseline: [Medicine]?
    public var appliedChanges: [VisitMedicineChange]
    public init(id: UUID = UUID(), title: String = "Doctor visit", date: Date = .now, duration: TimeInterval = 0, transcript: String = "", audioFilename: String? = nil, interrupted: Bool = false) {
        self.id = id; self.title = title; self.date = date; self.duration = duration
        self.transcript = transcript; self.audioFilename = audioFilename; self.interrupted = interrupted
        self.appliedChanges = []
    }
}
public enum VisitReviewError: LocalizedError {
    case invalidOutput, unsupportedChange, changedMedicines, alreadyApplied, conflictingChanges
    public var errorDescription: String? {
        switch self {
        case .invalidOutput: "The model couldn’t extract a visit summary. Your transcript is still saved."
        case .unsupportedChange: "This medicine change doesn’t match the transcript. Review the transcript and edit Medications directly."
        case .changedMedicines: "Your medications changed after this summary was prepared. Review a new summary before saving."
        case .alreadyApplied: "Medication changes from this visit have already been saved."
        case .conflictingChanges: "Choose only one change for each medicine."
        }
    }
}

/// Model output is a suggestion. Every displayed fact must include a verbatim source quote.
public enum VisitReview {
    public static let chunkCharacters = 1800
    public static func chunks(_ transcript: String) -> [String] {
        let words = transcript.split(whereSeparator: \.isWhitespace)
        var result: [String] = [], current = ""
        for word in words {
            if word.count > chunkCharacters {
                if !current.isEmpty { result.append(current); current = "" }
                var remaining = word[...]
                while !remaining.isEmpty { result.append(String(remaining.prefix(chunkCharacters))); remaining = remaining.dropFirst(min(chunkCharacters, remaining.count)) }
                continue
            }
            if !current.isEmpty && current.count + word.count + 1 > chunkCharacters { result.append(current); current = "" }
            current += (current.isEmpty ? "" : " ") + String(word)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
    public static func normalise(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    public static func prompt(_ transcript: String, medicines _: [Medicine]) throws -> String {
        // Identity resolution uses saved medicines in parse(), after exact source extraction.
        // Canonical names here can prime translation of a differently spelled source name.
        struct Input: Encodable { let transcript: String }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let encoded = try encoder.encode(Input(transcript: normalise(transcript).replacingOccurrences(of: "<|", with: "< |")))
        return """
        <|im_start|>system
        \(ModelPrompts.visitInstruction(language: .english))
        <|im_end|>
        <|im_start|>user
        \(String(decoding: encoded, as: UTF8.self))
        <|im_end|>
        <|im_start|>assistant
        """
    }

    /// Constrains structure only. Source grounding and medicine validation remain mandatory.
    public static func outputGrammar() -> String {
        #"""
        root ::= ws "{" ws "\"highlights\"" ws ":" ws quotes ws "," ws "\"medicines\"" ws ":" ws medicines ws "," ws "\"followUps\"" ws ":" ws quotes ws "," ws "\"appointments\"" ws ":" ws quotes ws "}" ws
        quotes ::= "[" ws (quote (ws "," ws quote){0,11})? ws "]"
        quote ::= "{" ws "\"quote\"" ws ":" ws quoted ws "}"
        medicines ::= "[" ws (medicine (ws "," ws medicine){0,11})? ws "]"
        medicine ::= "{" ws "\"quote\"" ws ":" ws quoted ws "," ws "\"action\"" ws ":" ws action ws "," ws "\"name\"" ws ":" ws name ws "," ws "\"instructions\"" ws ":" ws instructions ws "}"
        action ::= "\"" ("start" | "update" | "stop") "\""
        name ::= "\"" character{1,100} "\""
        instructions ::= "\"" character{0,180} "\""
        quoted ::= "\"" character{4,600} "\""
        character ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
        ws ::= [ \t\n\r]{0,4}
        """#
    }

    /// Medicine quotes and actions come only from source sentences that pass
    /// the same intent checks as parse(). For one independently prevalidated
    /// direct instruction, exact source name/directions also constrain decoding.
    /// This is app pipeline behaviour, not unconstrained model extraction;
    /// final source and saved-identity validation remains mandatory in parse().
    public static func outputGrammar(transcript: String, medicines: [Medicine] = []) -> String {
        let candidates = VisitSourceGrounding.candidates(transcript)
        func literal(_ value: String) -> String {
            let encoder = JSONEncoder(); encoder.outputFormatting = .withoutEscapingSlashes
            return String(decoding: try! encoder.encode(value), as: UTF8.self)
        }
        var lines = outputGrammar().components(separatedBy: "\n")
        lines.removeAll { $0.hasPrefix("medicines ::=") || $0.hasPrefix("medicine ::=") }
        guard !candidates.isEmpty else {
            lines.append(#"medicines ::= "[" ws "]""#)
            return lines.joined(separator: "\n")
        }
        let alternatives = candidates.indices.map { "source-medicine-\($0)" }.joined(separator: " | ")
        lines.append("medicine ::= " + alternatives)
        // A compound sentence can supply distinct stop/start proposals.
        let maximumEntries = min(12, candidates.reduce(0) { $0 + $1.maximumEntries })
        let required = VisitSourceGrounding.requiredMedicineProposal(transcript, medicines: medicines, candidates: candidates)
        let optional = required == nil ? "?" : ""
        lines.append(#"medicines ::= "[" ws (medicine (ws "," ws medicine){0,"# + String(maximumEntries - 1) + "})" + optional + #" ws "]""#)
        for (index, candidate) in candidates.enumerated() {
            let actionRules = candidate.actions.map { "source-medicine-\(index)-\($0.rawValue)" }.joined(separator: " | ")
            lines.append("source-medicine-\(index) ::= " + actionRules)
            for action in candidate.actions {
                let bound = required.flatMap { $0.quote == candidate.quote && $0.action == action ? $0 : nil }
                let name = bound.map { literal(literal($0.name)) } ?? "name"
                let instructions = bound.map { literal(literal($0.instructions)) } ?? (action == .stop ? literal(literal("")) : "instructions")
                let fields = #" ws "," ws "\"name\"" ws ":" ws "# + name + #" ws "," ws "\"instructions\"" ws ":" ws "#
                lines.append("source-medicine-\(index)-\(action.rawValue) ::= " + #""{" ws "\"quote\"" ws ":" ws "# + literal(literal(candidate.quote)) + #" ws "," ws "\"action\"" ws ":" ws "# + literal(literal(action.rawValue)) + fields + instructions + #" ws "}""#)
            }
        }
        return lines.joined(separator: "\n")
    }
    public static func parse(_ output: String, transcript: String, medicines: [Medicine]) throws -> VisitSummary {
        struct RawChange: Decodable { let action: MedicineChangeAction; let name: String; let instructions: String; let quote: String }
        struct RawSummary: Decodable { let highlights: [VisitQuote]; let medicines: [RawChange]; let followUps: [VisitQuote]; let appointments: [VisitQuote]? }
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start <= end,
              let raw = try? JSONDecoder().decode(RawSummary.self, from: Data(output[start...end].utf8)),
              raw.highlights.count <= 12, raw.followUps.count <= 12, raw.medicines.count <= 12, (raw.appointments?.count ?? 0) <= 12 else { throw VisitReviewError.invalidOutput }
        let source = normalise(transcript)
        func quoteIsValid(_ quote: String) -> Bool {
            let text = normalise(quote)
            return (4...600).contains(text.count) && source.contains(text) && !text.contains("<|")
        }
        var summary = VisitSummary()
        func grounded(_ quotes: [VisitQuote]) -> [VisitQuote] {
            var seen = Set<String>()
            return quotes.filter { quoteIsValid($0.quote) }.map { VisitQuote(quote: normalise($0.quote)) }.filter { seen.insert($0.quote).inserted }
        }
        summary.highlights = grounded(raw.highlights)
        summary.followUps = grounded(raw.followUps)
        // Preserve obvious source follow-up lines even when a small model omits that JSON category.
        let followUpPattern = "\\b(book|schedule|arrange|follow[- ]?up|blood work|bloodwork|return|call the|repeat the|prendre rendez-vous|prenez rendez-vous|prendre un rendez-vous|prenez un rendez-vous|planifier|planifiez|suivi|prise de sang|analyses sanguines|revenez|retournez|appelez|repeter|repetez)\\b"
        let sourceSentences = VisitSourceGrounding.sentences(source)
        for sentence in sourceSentences {
            if quoteIsValid(sentence), InputLanguage.folded(sentence).range(of: followUpPattern, options: .regularExpression) != nil {
                let item = VisitQuote(quote: sentence)
                if !summary.followUps.contains(item) { summary.followUps.append(item) }
            }
        }
        let appointmentSentences = AppointmentRules.quotes(in: transcript)
        summary.appointments = grounded((raw.appointments ?? []) + summary.followUps + appointmentSentences).filter { item in
            AppointmentRules.isAppointment(item.quote) && appointmentSentences.contains { $0.quote.contains(item.quote) }
        }
        for change in raw.medicines {
            let quote = normalise(change.quote), name = normalise(change.name), instructions = normalise(change.instructions)
            guard quoteIsValid(quote), !name.isEmpty, name.count <= 100,
                  quote.range(of: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b", options: [.regularExpression, .caseInsensitive]) != nil,
                  instructions.count <= 180, instructions.isEmpty || quote.contains(instructions),
                  change.action == .stop || !instructions.isEmpty else { continue }
            // Validate the complete containing sentence, preserving decimal doses
            // and preventing truncated quotations from dropping negation.
            guard VisitSourceGrounding.containingContexts(quote: quote, source: source).contains(where: {
                VisitSourceGrounding.permits(change.action, quote: quote, context: $0, name: name, instructions: instructions)
            }) else { continue }
            let known = Catalog.resolve(name, saved: medicines)
            // Unknown names remain a transcript item; no model-created ingredient mapping is trusted.
            guard var medicine = known else {
                let item = VisitQuote(quote: quote)
                if !summary.highlights.contains(item) { summary.highlights.append(item) }
                continue
            }
            if change.action != .start && !medicines.contains(where: { $0.id == medicine.id }) { continue }
            medicine.instructions = change.action == .stop ? "" : instructions
            let times = change.action == .stop ? [] : CareRules.times(in: instructions)
            var frequency = change.action == .stop ? nil : CareRules.frequency(in: instructions)
            if frequency == nil, !times.isEmpty { frequency = MedicationFrequency(count: times.count, period: .day) }
            guard times.isEmpty || (frequency?.period == .day && frequency?.count == times.count) else { continue }
            summary.medicines.append(.init(action: change.action, medicine: medicine, quote: quote, frequency: frequency, times: times))
        }
        return summary
    }
    public static func applying(_ selected: Set<UUID>, from visit: DoctorVisit, to medicines: [Medicine]) throws -> [Medicine] {
        guard visit.appliedChanges.isEmpty else { throw VisitReviewError.alreadyApplied }
        guard let summary = visit.summary, let baseline = visit.medicineBaseline, baseline == medicines else { throw VisitReviewError.changedMedicines }
        let changes = summary.medicines.filter { selected.contains($0.id) }
        guard !selected.isEmpty, changes.count == selected.count else { throw VisitReviewError.unsupportedChange }
        guard Set(changes.map { $0.medicine.id }).count == changes.count else { throw VisitReviewError.conflictingChanges }
        var next = medicines
        for change in changes {
            // Revalidate against the saved transcript at the mutation boundary.
            guard let sourceName = Catalog.names(for: change.medicine).first(where: {
                change.quote.range(of: "\\b" + NSRegularExpression.escapedPattern(for: $0) + "\\b", options: [.regularExpression, .caseInsensitive]) != nil
            }) else { throw VisitReviewError.unsupportedChange }
            let proposal: [String: Any] = ["highlights": [], "followUps": [], "medicines": [["action": change.action.rawValue, "name": sourceName, "instructions": change.medicine.instructions, "quote": change.quote]]]
            let validated = try parse(String(decoding: JSONSerialization.data(withJSONObject: proposal), as: UTF8.self), transcript: visit.transcript, medicines: baseline)
            let hasStoredSchedule = change.frequency != nil || !change.times.isEmpty
            guard validated.medicines.count == 1, validated.medicines[0].medicine == change.medicine,
                  !hasStoredSchedule || (validated.medicines[0].frequency == change.frequency && validated.medicines[0].times == change.times) else { throw VisitReviewError.unsupportedChange }
            let index = next.firstIndex { $0.id == change.medicine.id }
            switch change.action {
            case .stop: if let index { next.remove(at: index) }
            case .start, .update: if let index { next[index] = change.medicine } else { next.append(change.medicine) }
            }
        }
        return next
    }
}
