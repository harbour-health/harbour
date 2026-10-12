import Foundation

struct VisitMedicineSourceCandidate: Equatable {
    let quote: String
    let actions: [MedicineChangeAction]
    let maximumEntries: Int
}

/// Shared source checks for generation constraints and final proposal validation.
enum VisitSourceGrounding {
    private static func verbs(_ action: MedicineChangeAction) -> (english: String, french: String) {
        switch action {
        case .start:
            ("start|begin|add|prescribe", "commencer|commencez|commence|debuter|debutez|debute|ajouter|ajoutez|ajoute|prescrire|prescrivez")
        case .update:
            ("increase|decrease|change|take|continue|reduce|switch|update", "augmenter|augmentez|augmente|diminuer|diminuez|diminue|modifier|modifiez|modifie|prendre|prenez|prends|continuer|continuez|continue|reduire|reduisez|reduit|changer|changez|change")
        case .stop:
            ("stop|discontinue", "arreter|arretez|arrete|cesser|cessez|cesse|suspendre|suspendez")
        }
    }

    private static func instructionRanges(_ foldedSource: String) -> [Range<String.Index>] {
        let allVerbs = MedicineChangeAction.allCases.map { verbs($0).english + "|" + verbs($0).french }.joined(separator: "|")
        guard let expression = try? NSRegularExpression(pattern: "\\b(?:" + allVerbs + ")\\b") else { return [] }
        return expression.matches(in: foldedSource, range: NSRange(foldedSource.startIndex..., in: foldedSource)).compactMap { Range($0.range, in: foldedSource) }
    }

    private static func entryCapacity(_ sentence: String) -> Int {
        let folded = InputLanguage.folded(sentence)
        let instructions = instructionRanges(folded).count
        // Count list slots independently of the catalog so custom source names
        // remain eligible; an Oxford comma plus conjunction is one separator.
        let separator = ",\\s*(?:(?:and|et)\\b)?|\\b(?:and|et|as well as|ainsi que)\\b"
        let separators = (try? NSRegularExpression(pattern: separator))?.numberOfMatches(in: folded, range: NSRange(folded.startIndex..., in: folded)) ?? 0
        let mentioned = Catalog.mentioned(in: sentence).count
        return min(12, max(1, instructions, separators + 1, mentioned))
    }
    private static func sentenceRanges(_ source: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = [], start = source.startIndex, index = start
        while index < source.endIndex {
            let next = source.index(after: index)
            let character = source[index]
            let decimal = character == "." && index > source.startIndex && next < source.endIndex
                && source[source.index(before: index)].isNumber && source[next].isNumber
            if ".!?".contains(character) && !decimal {
                let sentence = source[start..<next].trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { result.append(start..<next) }
                start = next
            }
            index = next
        }
        let remainder = source[start...].trimmingCharacters(in: .whitespaces)
        if !remainder.isEmpty { result.append(start..<source.endIndex) }
        return result
    }

    static func sentences(_ source: String) -> [String] {
        sentenceRanges(source).map { source[$0].trimmingCharacters(in: .whitespaces) }
    }

    static func containingContext(quote: String, source: String) -> String? {
        guard let quotedRange = source.range(of: quote) else { return nil }
        let containing = sentenceRanges(source).filter { $0.overlaps(quotedRange) }
        guard let first = containing.first, let last = containing.last else { return nil }
        return source[first.lowerBound..<last.upperBound].trimmingCharacters(in: .whitespaces)
    }

    static func permits(_ action: MedicineChangeAction, quote: String, context: String, name: String? = nil, instructions: String? = nil) -> Bool {
        let foldedContext = InputLanguage.folded(context), foldedQuote = InputLanguage.folded(quote)
        let blocked = "\\b(not|don't|do not|never|might|may|could|consider|if|maybe|should we|can i|pas|jamais|aucun|aucune|sans|si|peut-etre|pourrais|pourrait|pourrions|devrais|devrait|envisager|envisagez|eventuellement|est-ce que|puis-je|dois-je|faudrait-il|hier|autrefois|auparavant|prenait|prenaient|commencait|commencaient|avait|avaient|ma mere|mon pere|ma soeur|ma sœur|mon frere|mon mari|ma femme|my mother|my father|my sister|my brother|my wife|my husband|he|she|they|elle|elles|il|ils)\\b|\\?"
        let unchanged = "\\b(?:unchanged|no changes?|without (?:any )?(?:changes?|modifications?)|same dose|same regimen|same treatment|inchang[a-z]*|sans modification|meme dose|meme posologie|meme traitement)\\b"
        guard foldedContext.range(of: blocked, options: .regularExpression) == nil,
              foldedContext.range(of: unchanged, options: .regularExpression) == nil,
              foldedQuote.range(of: "\\bje\\s+(?:prends|commence|continue|change|augmente|diminue)\\b", options: .regularExpression) == nil,
              foldedQuote.range(of: "\\b(?:i|we)\\s+(?:(?:currently|usually|normally|regularly)\\s+)?(?:take|continue|am taking|are taking|use|am using|are using)\\b|\\bi'm taking\\b", options: .regularExpression) == nil else { return false }

        let selectedVerbs = verbs(action)
        let verbs = selectedVerbs.english, frenchVerbs = selectedVerbs.french
        let prefixes = "(?:(?:la|le|de|du|votre|dose de|traitement par|traitement avec)\\s+|l')*"
        let sourceName = name.map { NSRegularExpression.escapedPattern(for: InputLanguage.folded($0)) + "\\b" } ?? "[\\p{L}\\p{M}]"
        let frenchInstruction = "\\b(?:" + frenchVerbs + ")\\s+" + prefixes + sourceName
        let englishPrefixes = "(?:(?:the|your|my|our|dose of|dosage of|treatment with|treatment of|use of|taking|using|from|to)\\s+)*"
        let englishInstruction = "\\b(?:" + verbs + ")\\s+" + englishPrefixes + sourceName
        let english = foldedQuote.range(of: englishInstruction, options: .regularExpression) != nil
        let french = foldedQuote.range(of: frenchInstruction, options: .regularExpression) != nil
        var conjoined = false
        if let name {
            let selected = Set((verbs + "|" + frenchVerbs).split(separator: "|").map(String.init))
            let occurrences = instructionRanges(foldedQuote)
            let escapedName = NSRegularExpression.escapedPattern(for: InputLanguage.folded(name)) + "\\b"
            let targetPrefixes = "(?:(?:the|your|my|our|dose of|dosage of|treatment with|treatment of|use of|taking|using|from|to|la|le|de|du|votre|dose de|traitement par|traitement avec)\\s+|l')*"
            for (index, range) in occurrences.enumerated() where selected.contains(String(foldedQuote[range])) {
                let end = index + 1 < occurrences.count ? occurrences[index + 1].lowerBound : foldedQuote.endIndex
                let clause = String(foldedQuote[range.upperBound..<end])
                let listTarget = "(?:^\\s*|,\\s*(?:(?:and|et)\\s+)?|\\b(?:and|et|as well as|ainsi que)\\s+)" + targetPrefixes + escapedName
                if clause.range(of: listTarget, options: .regularExpression) != nil,
                   instructions.map({ $0.isEmpty || clause.contains(InputLanguage.folded($0)) }) ?? true { conjoined = true; break }
            }
        }
        guard name == nil ? english || french : conjoined else { return false }
        // A visit or test instruction is not a medicine instruction merely because
        // it uses a verb such as take/prenez. These checks also apply in parse().
        let followUpOnly = "\\b(?:take|continue|prendre|prenez|continuer|continuez)\\s+(?:(?:a|the|your|un|une|le|la|les|votre)\\s+)*(?:appointment|follow[- ]?up|blood work|blood test|rendez-vous|suivi|prise de sang|analyse)\\b"
        return foldedQuote.range(of: followUpOnly, options: .regularExpression) == nil
    }

    static func candidates(_ transcript: String) -> [VisitMedicineSourceCandidate] {
        let source = VisitReview.normalise(transcript)
        var result: [VisitMedicineSourceCandidate] = [], consumed = 0, seen = Set<String>()
        for sentence in sentences(source) {
            consumed += sentence.count + (consumed == 0 ? 0 : 1)
            guard consumed <= VisitReview.chunkCharacters else { break }
            guard (4...600).contains(sentence.count), !sentence.contains("<|"), seen.insert(sentence).inserted else { continue }
            let actions = MedicineChangeAction.allCases.filter { permits($0, quote: sentence, context: sentence) }
            if !actions.isEmpty { result.append(.init(quote: sentence, actions: actions, maximumEntries: entryCapacity(sentence))) }
            if result.count == 12 { break }
        }
        return result
    }
}
