import Foundation

/// Exact database identity and phonetic suggestions are deliberately separate operations.
public struct MedicationVocabulary: Sendable {
    public struct Entry: Codable, Sendable {
        public let id: String
        public let name: String
        public let fr: String
        public let aliases: [String]
        public let ingredients: [String]
        public var medicine: Medicine {
            Medicine(
                id: id,
                name: name.capitalized,
                ingredients: ingredients.map { $0.lowercased() }
            ) }
    }

    private struct Document: Decodable { let publicationDate: String
        let entries: [Entry] }

    public static let shared = MedicationVocabulary()
    public let entries: [Entry]
    public let publicationDate: String
    private let identities: [String: Int]
    private let exact: [String: Int]
    private let searchable: [(index: Int, key: String, sound: String)]
    public init() {
        let doc = Bundle.module.url(forResource: "medication-vocabulary", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Document.self, from: $0) }
        entries = doc?.entries ?? []
        publicationDate = doc?.publicationDate ?? ""
        var exact: [String: Int] = [:], ambiguous = Set<String>()
        var search: [(Int, String, String)] = []
        for (index, entry) in entries.enumerated() {
            for name in Set(entry.aliases + [entry.name, entry.fr]) {
                let key = Self.key(name)

                guard key.count >= 4 else {
                    continue
                }

                if
                    let prior = exact[key],
                    Set(entries[prior].ingredients) != Set(entry.ingredients) {
                    ambiguous.insert(key)
                }
                else if
                    exact[key] == nil ||
                    (entry.id.hasPrefix("dpd-ingredient:") && !(entries[exact[key]!].id.hasPrefix("dpd-ingredient:"))) {
                    exact[key] = index
                }
                search.append((index, key, Self.sound(name)))
            }
        }
        for key in ambiguous {
            exact.removeValue(forKey: key)
        }
        self.exact = exact
        identities = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, $0.offset) })
        searchable = search
    }

    /// Translate only an unchanged database label; preserve custom user-entered names.
    public func localizedName(for medicine: Medicine, french: Bool) -> String? {
        guard let index = identities[medicine.id] else {
            return nil
        }

        let entry = entries[index]

        guard Self.key(medicine.name) == Self.key(entry.name) else {
            return nil
        }

        return (french && !entry.fr.isEmpty ? entry.fr : entry.name).capitalized
    }

    public static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_CA"))
            .lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func sound(_ text: String) -> String {
        var value = key(text)
        for (from, to) in [("ph", "f"), ("qu", "k"), ("th", "t"), ("y", "i"), ("ck", "k"), ("ch", "k"), ("c", "k")] {
            value = value.replacingOccurrences(of: from, with: to)
        }
        var previous: Character?, result = ""
        for letter in value {
            if letter != previous {
                result.append(letter)
            }
            previous = letter
        }

        return result
    }

    public func resolve(_ name: String) -> Medicine? {
        exact[Self.key(name)].map { entries[$0].medicine }
    }

    public func search(_ input: String, limit: Int = 12) -> [Medicine] {
        let key = Self.key(input)

        guard key.count >= 3, key.count <= 80 else {
            return []
        }

        var seen = Set<String>()

        return searchable.filter { $0.key.contains(key) }.sorted { lhs, rhs in
            let a = lhs.key == key ? 0 : lhs.key.hasPrefix(key) ? 1 : 2
            let b = rhs.key == key ? 0 : rhs.key.hasPrefix(key) ? 1 : 2

            return a == b ? lhs.key.count < rhs.key.count : a < b
        }.compactMap { value in
            let entry = entries[value.index]

            return seen.insert(entry.id).inserted ? entry.medicine : nil
        }.prefix(limit).map { $0 }
    }

    /// Suggestions are never used by resolve(), validators or automatic transcript replacement.
    public func suggestions(_ input: String, limit: Int = 4) -> [Medicine] {
        let query = Self.sound(input)

        guard
            query.count >= 5, query.count <= 40,
            input.split(whereSeparator: \.isWhitespace).count <= 4 else {
            return []
        }

        var best: [String: (Medicine, Double)] = [:]
        for item in searchable where abs(item.sound.count - query.count) <= 3 && item.sound.first == query.first {
            let distance = Self.distance(query, item.sound)
            let score = 1 - Double(distance) / Double(max(query.count, item.sound.count))

            guard score >= 0.78 else {
                continue
            }

            let medicine = entries[item.index].medicine
            let identity = Self.key(medicine.name) + "|" + medicine.ingredients.sorted().joined(separator: "|")
            if
                score > (best[identity]?.1 ?? 0) ||
                (score == best[identity]?.1 && medicine.id.hasPrefix("dpd-ingredient:")) {
                best[identity] = (medicine, score)
            }
        }

        return best.values.sorted { $0.1 == $1.1 ? $0.0.name < $1.0.name : $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0 ... b.count)
        for i in a.indices {
            var next = [i + 1]
            for j in b
                .indices {
                next.append(min(next[j] + 1, previous[j + 1] + 1, previous[j] + (a[i] == b[j] ? 0 : 1)))
            }
            previous = next
        }

        return previous[b.count]
    }

    public func mentioned(in text: String) -> [Medicine] {
        guard let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{M}\p{N}_]+(?:[-'][\p{L}\p{M}\p{N}_]+)*"#)
        else {
            return []
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let words = matches.compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        var found: [Medicine] = [], used = Set<String>(), index = 0
        while index < words.count {
            var match: (Medicine, Int)?
            for count in stride(from: min(5, words.count - index), through: 1, by: -1) {
                if let medicine = resolve(words[index ..< index + count].joined(separator: " ")) {
                    match = (
                        medicine,
                        count
                    )

                    break }
            }
            if let (medicine, count) = match {
                if used.insert(medicine.id).inserted {
                    found.append(medicine)
                }
                index += count }
            else {
                index += 1
            }
        }

        return found
    }

    /// Apple recommends no more than 100 brief phrases. Current medicines always win the budget.
    public func speechHints(saved: [Medicine], french: Bool, limit: Int = 100) -> [String] {
        let common = [
            "hydrochlorothiazide",
            "levothyroxine",
            "rosuvastatin",
            "atorvastatin",
            "empagliflozin",
            "rivaroxaban",
            "pantoprazole",
            "gliclazide",
            "candesartan",
            "salbutamol",
            "metformin",
            "amlodipine",
            "apixaban",
            "acetaminophen",
            "amoxicillin",
            "warfarin"
        ]
        let selected = common.compactMap { name -> String? in

            guard let index = exact[Self.key(name)] else {
                return nil
            }

            return french ? entries[index].fr : entries[index].name
        }
        var seen = Set<String>()

        return (saved.flatMap { medicine in
            Catalog.names(for: medicine) + (localizedName(for: medicine, french: french).map { [$0] } ?? [])
        } + selected).filter {
            !$0.isEmpty && $0.count <= 80 && seen.insert(Self.key($0)).inserted
        }.prefix(min(100, max(0, limit))).map { $0 }
    }
}
