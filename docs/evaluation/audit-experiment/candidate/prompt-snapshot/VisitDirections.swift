import Foundation

/// Source-only slots; complex regimens stay intact instead of becoming invented clock reminders.
public struct VisitDirections: Equatable, Sendable {
    public var dose: String?
    public var frequency: String?
    public var timing: String?
    public var duration: String?
    public var needsIndividualSchedule: Bool
    public init(_ instructions: String) {
        func matches(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            let values = regex.matches(in: instructions, range: NSRange(instructions.startIndex..., in: instructions)).compactMap { Range($0.range, in: instructions).map { String(instructions[$0]) } }
            return values.isEmpty ? nil : values.joined(separator: " · ")
        }
        dose = matches(#"\b\d+(?:[.,]\d+)?\s*(?:mg|mcg|g|ml|units?|tablets?|capsules?|comprimés?|gélules?)\b"#)
        frequency = matches(#"\b(?:(?:once|twice|three times|four times|\d+ times?|une fois|deux fois|trois fois|\d+ fois)\s*(?:a |per |par )?(?:day|daily|week|weekly|month|monthly|jour|semaine|mois)|every (?:other day|\d+ hours?|\d+ days?)|tous les \d+ (?:jours|heures)|as needed|au besoin|daily|nightly|weekly)\b"#)
        timing = matches(#"\b(?:(?:before|after|with) (?:breakfast|lunch|dinner|food|meals?)|(?:avant|après|avec) (?:le repas|les repas|le déjeuner|le souper)|at bedtime|au coucher|(?:every |each )?(?:morning|evening)|le matin|le soir|\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.|p\.m\.|h(?:\s*\d{2})?))\b"#)
        duration = matches(#"\b(?:for|pendant|pour)\s+(?:\d+|one|two|three|four|five|six|seven|ten|un|une|deux|trois|quatre|cinq|sept|dix)\s+(?:days?|weeks?|months?|jours?|semaines?|mois)\b"#)
        needsIndividualSchedule = instructions.range(of: #"\b(?:then|taper|alternate|alternating|every other|as needed|if|maximum|up to|puis|ensuite|alterner|au besoin|un jour sur deux|si nécessaire)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

public enum VisitFollowUp {
    public static func dueDate(in text: String, relativeTo reference: Date, calendar: Calendar = .current) -> Date? {
        let folded = InputLanguage.folded(text)
        let numbers = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "ten": 10, "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "sept": 7, "dix": 10]
        let pattern = #"\b(?:in|dans)\s+(\d+|one|two|three|four|five|six|seven|ten|un|une|deux|trois|quatre|cinq|six|sept|dix)\s+(days?|weeks?|months?|jours?|semaines?|mois)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)), let n = Range(match.range(at: 1), in: folded), let unit = Range(match.range(at: 2), in: folded), let count = Int(folded[n]) ?? numbers[String(folded[n])], (1...365).contains(count) {
            let word = String(folded[unit])
            let component: Calendar.Component = word.hasPrefix("week") || word.hasPrefix("semaine") ? .weekOfYear : word.hasPrefix("month") || word == "mois" ? .month : .day
            return calendar.date(byAdding: component, value: count, to: calendar.startOfDay(for: reference))
        }
        if folded.range(of: #"\b(?:\d{4}-\d{2}-\d{2}|tomorrow|demain|monday|tuesday|wednesday|thursday|friday|saturday|sunday|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\b"#, options: .regularExpression) != nil { return AppointmentRules.draft(from: text, now: reference, calendar: calendar).date }
        return nil
    }
    public static func title(for text: String, french: Bool) -> String {
        let folded = InputLanguage.folded(text)
        if folded.range(of: #"\b(blood work|bloodwork|blood test|prise de sang|analyses sanguines)\b"#, options: .regularExpression) != nil { return french ? "Analyses sanguines" : "Blood work" }
        if folded.range(of: #"\b(call|appelez|appeler)\b"#, options: .regularExpression) != nil { return french ? "Appeler la clinique" : "Call the clinic" }
        return french ? "Suivi" : "Follow-up"
    }
}

