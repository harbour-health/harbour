import Foundation

public struct Appointment: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var includesTime: Bool
    public var location: String
    public var notes: String
    public var visitID: UUID?
    public var quote: String?
    public init(id: UUID = UUID(), title: String = "", date: Date = .now, includesTime: Bool = true, location: String = "", notes: String = "", visitID: UUID? = nil, quote: String? = nil) {
        self.id = id; self.title = title; self.date = date; self.includesTime = includesTime
        self.location = location; self.notes = notes; self.visitID = visitID; self.quote = quote
    }
}

public enum AppointmentRules {
    public static func quotes(in transcript: String) -> [VisitQuote] {
        let source = VisitReview.normalise(transcript)
        guard let expression = try? NSRegularExpression(pattern: "(?:\\b(?:[ap]\\.m\\.|Dr\\.|Dre\\.|Mr\\.|Mrs\\.|Ms\\.|Mme\\.|M\\.)|[^.!?])+[.!?]?", options: .caseInsensitive) else { return [] }
        return expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { match in
            guard let range = Range(match.range, in: source) else { return nil }
            let sentence = source[range].trimmingCharacters(in: .whitespaces)
            return (4...600).contains(sentence.count) && isAppointment(sentence) ? VisitQuote(quote: sentence) : nil
        }
    }
    public static func validate(_ appointment: Appointment, visits: [DoctorVisit]) throws {
        guard !appointment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              appointment.title.count <= 500, appointment.location.count <= 500, appointment.notes.count <= 4000,
              appointment.date.timeIntervalSince1970.isFinite else { throw CareError.invalid }
        if let id = appointment.visitID {
            guard let visit = visits.first(where: { $0.id == id }), let quote = appointment.quote,
                  !VisitReview.normalise(quote).isEmpty,
                  VisitReview.normalise(visit.transcript).contains(VisitReview.normalise(quote)),
                  visit.summary?.appointments?.contains(where: { $0.quote == quote }) == true else { throw CareError.sourceChanged }
        } else if appointment.quote != nil { throw CareError.sourceChanged }
    }
    public static func isAppointment(_ text: String) -> Bool {
        let input = InputLanguage.folded(text)
        guard input.range(of: "\\b(?:appointment|rendez-vous|consultation|follow[- ]?up|see (?:dr|doctor)|visit with)\\b", options: .regularExpression) != nil else { return false }
        return input.range(of: "\\b(?:not|don't|do not|never|maybe|might|may|could|if|should i|can i|pas|jamais|peut-etre|si|pourrais|pourrait|pourrions|devrais|devrait|envisager|envisagez|eventuellement|puis-je|dois-je)\\b|\\?", options: .regularExpression) == nil
    }
    static func hasCreationCommandTarget(_ command: String) -> Bool {
        let verb = #"(?:create|add|save|record|book|schedule|set|make|cree|creez|creer|ajoute|ajoutez|ajouter|enregistre|enregistrez|enregistrer|reserve|reservez|reserver|planifie|planifiez|planifier|programme|programmez|programmer|prends|prenez|prendre)"#
        let qualifiers = #"(?:(?:my|the|an|a|our|new|next|upcoming|dentist|dentist's|dental|doctor|doctor's|medical|optometrist|mon|ma|le|la|un|une|notre|nouveau|nouvelle|prochain|prochaine)\s+){0,5}"#
        let target = #"\A"# + verb + #"\s+(?:(?:me|us|nous|moi)\s+)?"# + qualifiers + #"(?:appointment|rendez-vous|consultation)\b"#
        return command.range(of: target, options: .regularExpression) != nil
    }
    /// A polite current write request is distinct from an appointment fact in a
    /// transcript. Strip only the outer request modal and terminal question mark;
    /// the existing fact/negation checks still apply to the complete command.
    static func isPoliteCreationRequest(_ text: String) -> Bool {
        guard text.count <= 1000, !text.contains("<|"),
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        let quotes = #""[^"]*"|“[^”]*”|«[^»]*»|‘[^’]*’|(?<![\p{L}\p{N}])'(?:[^']|(?<=[\p{L}])'(?=[\p{L}]))*'(?![\p{L}\p{N}])"#
        guard text.range(of: quotes, options: .regularExpression) == nil else { return false }
        let input = InputLanguage.folded(text).trimmingCharacters(in: .whitespaces)
        let courtesy = #"(?:(?:please|svp|veuillez|s'il vous plait|s'il te plait),?\s+)?"#
        let modal = #"(?:(?:can|could|would|will)\s+you|(?:peux|pourrais|pouvez|pourriez)[ -](?:tu|vous)|est-ce que (?:tu (?:peux|pourrais)|vous (?:pouvez|pourriez)))\s+"#
        guard let prefix = input.range(of: #"\A"# + courtesy + modal + courtesy + #"(?:(?:me|nous)\s+|m')?"#, options: .regularExpression) else { return false }
        var command = String(input[prefix.upperBound...]).trimmingCharacters(in: .whitespaces)
        if command.hasSuffix("?") { command.removeLast(); command = command.trimmingCharacters(in: .whitespaces) }
        guard hasCreationCommandTarget(command), isAppointment(command) else { return false }
        // A polite wrapper cannot authorize a conditional booking or an
        // additional action concealed in a later clause.
        let condition = #"\b(?:unless|until|when|once|after|before|provided|assuming|pending|as\s+long\s+as|on\s+condition|subject\s+to|s'il(?:s)?(?!\s+(?:vous|te)\s+plait)|sauf|quand|lorsque|apres|avant|des\s+que|une\s+fois|a\s+condition|a\s+moins|pourvu|sous\s+reserve|en\s+attendant)\b"#
        let otherAction = #"(?:[,.;:]\s*|\b(?:and|then|also|et|puis|ensuite)\s+)"# + courtesy + "(?:" + modal + ")?" + courtesy
            + #"(?:add|create|save|record|book|schedule|remove|delete|clear|import|export|scan|log|stop|remind|reminder|reset|wipe|erase|set|make|open|use|read|take|skip|mark|remember|keep|store|start|begin|put|register|include|track|note|sync|ajout[a-z]*|cre[eazr]*|enregistr[a-z]*|retir[a-z]*|supprim[a-z]*|effac[a-z]*|import[a-z]*|export[a-z]*|scann[a-z]*|planifi[a-z]*|programm[a-z]*|arret[a-z]*|rappel[a-z]*|reinitialis[a-z]*|vid[a-z]*|consign[a-z]*|marqu[a-z]*|sauv[a-z]*|gard[a-z]*|inscris|inscrivez|inscrire)\b"#
        return command.range(of: condition, options: .regularExpression) == nil
            && command.range(of: otherAction, options: .regularExpression) == nil
            && command.range(of: #"\b(?:or|ou)\b"#, options: .regularExpression) == nil
    }
    public static func draft(from text: String, visitID: UUID? = nil, now: Date = .now, calendar: Calendar = .current) -> Appointment {
        let input = InputLanguage.folded(text)
        var date = calendar.startOfDay(for: now)
        if let range = input.range(of: "\\b[0-9]{4}-[0-9]{2}-[0-9]{2}\\b", options: .regularExpression) {
            let parts = input[range].split(separator: "-").compactMap { Int($0) }
            if parts.count == 3, let parsed = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
               calendar.component(.year, from: parsed) == parts[0], calendar.component(.month, from: parsed) == parts[1], calendar.component(.day, from: parsed) == parts[2] { date = parsed }
        } else if input.range(of: "\\b(tomorrow|demain)\\b", options: .regularExpression) != nil {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        } else {
            let weekdays = ["sunday|dimanche", "monday|lundi", "tuesday|mardi", "wednesday|mercredi", "thursday|jeudi", "friday|vendredi", "saturday|samedi"]
            let matches = weekdays.enumerated().filter { input.range(of: "\\b(?:" + $0.element + ")\\b", options: .regularExpression) != nil }
            if matches.count == 1 {
                date = calendar.nextDate(after: date, matching: DateComponents(weekday: matches[0].offset + 1), matchingPolicy: .nextTime) ?? date
            }
        }
        let times = CareRules.times(in: text.replacingOccurrences(of: "(?i)\\b([ap])\\.m\\.", with: "$1m", options: .regularExpression))
        if times.count == 1 { date = calendar.date(bySettingHour: times[0].hour, minute: times[0].minute, second: 0, of: date) ?? date }
        return Appointment(title: String(text.prefix(500)), date: date, includesTime: times.count == 1, notes: text.count > 500 ? text : "", visitID: visitID, quote: visitID == nil ? nil : text)
    }
}
