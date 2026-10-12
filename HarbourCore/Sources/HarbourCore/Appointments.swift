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
