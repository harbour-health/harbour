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
    private let nameKeys: [[String]]
    private let ingredientKeys: [[String]]
    public init() {
        let doc = Bundle.module.url(forResource: "medication-vocabulary", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Document.self, from: $0) }
        self.init(entries: doc?.entries ?? [], publicationDate: doc?.publicationDate ?? "")
    }

    init(entries: [Entry], publicationDate: String) {
        self.entries = entries
        self.publicationDate = publicationDate
        var exact: [String: Int] = [:], ambiguous = Set<String>()
        var search: [(Int, String, String)] = []
        var names: [[String]] = [], ingredients: [[String]] = []
        for (index, entry) in entries.enumerated() {
            let aliases = Set(entry.aliases + [entry.name, entry.fr]).sorted()
            names.append(aliases.map(Self.key).filter { !$0.isEmpty })
            ingredients.append(entry.ingredients.map(Self.key).filter { !$0.isEmpty })
            for name in aliases {
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
        nameKeys = names
        ingredientKeys = ingredients
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

        guard key.count >= 3, key.count <= 80, limit > 0 else {
            return []
        }

        return entries.indices.compactMap { index -> (Medicine, Int)? in

            guard let rank = Self.matchRank(query: key, names: nameKeys[index], ingredients: ingredientKeys[index])
            else {
                return nil
            }

            return (entries[index].medicine, rank)
        }.sorted { Self.precedes($0, $1) }.prefix(limit).map(\.0)
    }

    /// Rank exact names, exact ingredients, prefixes and substrings consistently across both catalogs.
    static func matchRank(query: String, names: [String], ingredients: [String]) -> Int? {
        if names.contains(query) {
            return 0
        }
        if ingredients.contains(query) {
            return 1
        }
        if names.contains(where: { $0.hasPrefix(query) }) {
            return 2
        }
        if ingredients.contains(where: { $0.hasPrefix(query) }) {
            return 3
        }
        if names.contains(where: { $0.contains(query) }) {
            return 4
        }
        if ingredients.contains(where: { $0.contains(query) }) {
            return 5
        }

        return nil
    }

    func matchRank(for medicine: Medicine, query: String) -> Int? {
        guard let index = identities[medicine.id] else {
            return nil
        }

        return Self.matchRank(query: query, names: nameKeys[index], ingredients: ingredientKeys[index])
    }

    static func precedes(_ lhs: (Medicine, Int), _ rhs: (Medicine, Int)) -> Bool {
        if lhs.1 != rhs.1 {
            return lhs.1 < rhs.1
        }
        let a = key(lhs.0.name), b = key(rhs.0.name)
        if a != b {
            return a < b
        }
        let officialA = lhs.0.id.hasPrefix("dpd-"), officialB = rhs.0.id.hasPrefix("dpd-")
        if officialA != officialB {
            return !officialA
        }

        return lhs.0.id < rhs.0.id
    }

    /// Suggestions are never used by resolve(), validators or automatic transcript replacement.
    public func suggestions(_ input: String, limit: Int = 4) -> [Medicine] {
        let query = Self.sound(input)

        guard
            query.count >= 5, query.count <= 40, limit > 0,
            input.split(whereSeparator: \.isWhitespace).count <= 4 else {
            return []
        }

        var best: [String: (Medicine, Double)] = [:]
        func consider(_ sound: String, medicine makeMedicine: () -> Medicine) {
            guard abs(sound.count - query.count) <= 3, sound.first == query.first else {
                return
            }

            let distance = Self.distance(query, sound)
            let score = 1 - Double(distance) / Double(max(query.count, sound.count))

            guard score >= 0.78 else {
                return
            }

            let medicine = makeMedicine()
            let identity = Self.key(medicine.name) + "|" + medicine.ingredients.sorted().joined(separator: "|")
            let prior = best[identity]
            let preferIdentity = prior.map { previous in
                let generic = medicine.id.hasPrefix("dpd-ingredient:")
                let priorGeneric = previous.0.id.hasPrefix("dpd-ingredient:")

                return generic != priorGeneric ? generic : medicine.id < previous.0.id
            } ?? true
            if score > (prior?.1 ?? 0) || (score == (prior?.1 ?? -1) && preferIdentity) {
                best[identity] = (medicine, score)
            }
        }
        for item in searchable {
            consider(item.sound) { entries[item.index].medicine }
        }
        for medicine in Catalog.medicines {
            for name in Catalog.names(for: medicine) {
                consider(Self.sound(name)) { medicine }
            }
        }

        return best.values.sorted { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 > rhs.1
            }

            return Self.precedes((lhs.0, 0), (rhs.0, 0))
        }.prefix(limit).map(\.0)
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0 ... b.count)
        var beforePrevious = previous
        for i in a.indices {
            var next = [i + 1]
            for j in b
                .indices {
                next.append(min(next[j] + 1, previous[j + 1] + 1, previous[j] + (a[i] == b[j] ? 0 : 1)))
                if i > 0, j > 0, a[i] == b[j - 1], a[i - 1] == b[j] {
                    next[j + 1] = min(next[j + 1], beforePrevious[j - 1] + 1)
                }
            }
            beforePrevious = previous
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
