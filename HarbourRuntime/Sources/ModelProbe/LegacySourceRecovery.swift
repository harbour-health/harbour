import Foundation
import HarbourCore

/// Historical source-scanning comparator. Never linked into the iOS app target.
enum LegacySourceRecovery {
    private static func folded(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ) }

    private static func normalise(_ text: String) -> String {
        VisitReview.normalise(text)
    }

    static func parse(
        _ output: String,
        transcript: String,
        medicines: [Medicine],
        recoverOmissions: Bool = true
    ) throws -> VisitSummary {
        var summary = try VisitReview.parse(output, transcript: transcript, medicines: medicines)

        guard recoverOmissions else {
            return summary
        }

        let source = normalise(transcript)
        let followUpPattern = #"\b(book|schedule|arrange|follow[- ]?up|blood work|bloodwork|return|call the|repeat the|prendre rendez-vous|prenez rendez-vous|prendre un rendez-vous|prenez un rendez-vous|planifier|planifiez|suivi|prise de sang|analyses sanguines|revenez|retournez|appelez|repeter|repetez)\b"#
        if let regex = try? NSRegularExpression(pattern: "[^.!?]+[.!?]?") {
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range, in: source) else {
                    continue
                }

                let sentence = String(source[range]).trimmingCharacters(in: .whitespaces)
                let folded = folded(sentence)
                if
                    (4 ... 600).contains(sentence.count),
                    folded.range(of: followUpPattern, options: .regularExpression) != nil,
                    folded.range(
                        of: #"\b(not|don't|never|maybe|might|could|should i|can i|pas|jamais|peut-etre|pourrait)\b|\?"#,
                        options: .regularExpression
                    ) == nil,
                    !summary.followUps
                        .contains(where: { $0.quote == sentence }) {
                    summary.followUps.append(VisitQuote(quote: sentence))
                }
            }
        }
        for item in AppointmentRules.quotes(in: transcript)
            where !(summary.appointments ?? []).contains(where: { $0.quote == item.quote }) {
            if summary.appointments == nil {
                summary.appointments = []
            }
            summary.appointments!.append(item)
        }

        return summary
    }

    static func complete(_ summary: VisitSummary, transcript: String, medicines: [Medicine]) -> VisitSummary {
        var result = summary
        let recovered = recoverInstructions(transcript, medicines: medicines)
        for change in recovered.medicines {
            if
                let index = result.medicines
                    .firstIndex(where: { $0.medicine.id == change.medicine.id && $0.action == change.action }) {
                let old = result.medicines[index]
                if
                    change.medicine.instructions.contains(old.medicine.instructions),
                    change.medicine.instructions.count > old.medicine.instructions.count {
                    var complete = change
                    complete.id = old.id
                    result.medicines[index] = complete
                }
            } else {
                result.medicines.append(change)
            }
        }
        var other = recovered
        other.medicines = []
        result.merge(other)

        return result
    }

    /// Completeness pass for explicit named-drug directions omitted by small models.
    /// All recovered candidates still go through the original mutation validator.
    static func recoverInstructions(_ transcript: String, medicines: [Medicine]) -> VisitSummary {
        let source = normalise(transcript)
        let regex = try? NSRegularExpression(
            pattern: #"(?:\d[.,]\d|[ap]\.m\.|Dr\.|Dre\.|[^.!?])+[.!?]?"#,
            options: .caseInsensitive
        )
        var summary = (try? parse(
            #"{"highlights":[],"medicines":[],"followUps":[],"appointments":[]}"#,
            transcript: source,
            medicines: medicines,
            recoverOmissions: true
        )) ?? VisitSummary()
        let catalog = Dictionary(
            (Catalog.medicines + medicines).map { ($0.id, $0) },
            uniquingKeysWith: { _, saved in saved }
        ).values
        for match in regex?.matches(in: source, range: NSRange(source.startIndex..., in: source)) ?? [] {
            guard let range = Range(match.range, in: source) else {
                continue
            }

            let sentence = String(source[range]).trimmingCharacters(in: .whitespaces)

            guard sentence.count <= 600 else {
                continue
            }

            var hits: [(medicine: Medicine, name: String, range: Range<String.Index>)] = []
            for medicine in catalog {
                for name in Catalog.names(for: medicine).sorted(by: { $0.count > $1.count }) {
                    if let range = sentence.range(
                        of: #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#,
                        options: [.caseInsensitive, .regularExpression]
                    ) {
                        hits.append((medicine, String(sentence[range]), range))

                        break }
                }
            }
            hits.sort { $0.range.lowerBound < $1.range.lowerBound }
            for (index, hit) in hits.enumerated() {
                let prefix = folded(String(sentence[..<hit.range.lowerBound]))
                let action: MedicineChangeAction
                let verbs =
                    try? NSRegularExpression(
                        pattern: #"\b(start|begin|add|prescribe|stop|discontinue|take|continue|increase|decrease|change|reduce|commencez|commencer|ajoutez|arretez|cessez|prenez|continuez|augmentez|diminuez)\b"#
                    )
                let verb = verbs?.matches(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)).last
                    .flatMap { Range(
                        $0.range,
                        in: prefix
                    ).map { String(prefix[$0]) } }
                if let verb, ["stop", "discontinue", "arretez", "cessez"].contains(verb) {
                    action = .stop
                }
                else if
                    let verb,
                    ["start", "begin", "add", "prescribe", "commencez", "commencer", "ajoutez"]
                        .contains(verb) {
                    action = .start
                }
                else if
                    verb == "take" || verb ==
                    "prenez" {
                    action = medicines.contains(where: { $0.id == hit.medicine.id }) ? .update : .start
                }
                else {
                    action = .update
                }
                let end = index + 1 < hits.count ? hits[index + 1].range.lowerBound : sentence.endIndex
                var instructions = String(sentence[hit.range.upperBound ..< end])
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
                        .union(CharacterSet(charactersIn: ".,;:")))
                instructions = instructions.replacingOccurrences(
                    of: #"\s+(?:and|et)(?:\s+(?:start|begin|continue|take|commencez|prenez))?\s*$"#,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
                if action == .stop {
                    instructions = ""
                }
                let object: [String: Any] = [
                    "highlights": [],
                    "followUps": [],
                    "medicines": [[
                        "action": action.rawValue,
                        "name": hit.name,
                        "instructions": instructions,
                        "quote": sentence
                    ]]
                ]

                guard let data = try? JSONSerialization.data(withJSONObject: object), let extracted = try? parse(
                    String(decoding: data, as: UTF8.self),
                    transcript: source,
                    medicines: medicines
                ) else {
                    continue
                }

                summary.merge(extracted)
            }
        }

        return summary
    }
}
