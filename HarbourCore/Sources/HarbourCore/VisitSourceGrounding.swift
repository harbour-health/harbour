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
        let matches = expression.matches(in: foldedSource, range: NSRange(foldedSource.startIndex..., in: foldedSource)).compactMap { Range($0.range, in: foldedSource) }
        var instructions: [Range<String.Index>] = []
        for range in matches {
            // An infinitive in "cessez de prendre" or "begin to take" belongs
            // to the outer instruction, rather than a separate dose update.
            if ["prendre", "take"].contains(String(foldedSource[range])), let outer = instructions.last {
                let link = foldedSource[outer.upperBound..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                if ["de", "a", "to"].contains(link) { continue }
            }
            instructions.append(range)
        }
        return instructions
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

    private static func isHistoricalInstructionHeader(_ text: String) -> Bool {
        // Only an explicit section label carries history into another sentence.
        // "My old treatment caused nausea" is a report, not such a label.
        let ending = "(?:\\s*:\\s*|\\s*\\.?\\s*$)"
        let headers = [
            "^(?:(?:these|those|this|the following|here are|here is)\\s+(?:(?:were|are|was|is)\\s+)?)?(?:(?:my|the|our)\\s+)?(?:past|previous|old|historical|former)\\s+(?:medications?|medicines?|treatments?|prescriptions?|regimens?|instructions?|directions?|plans?)(?:\\s+(?:history|instructions?|directions?|plan|list))?",
            "^(?:these|those|this|the following)\\s+(?:were|are|was|is)\\s+(?:(?:my|the|our)\\s+)?(?:instructions?|directions?|prescriptions?|treatment|plan)\\s+from\\s+(?:(?:my|the|our)\\s+)?(?:(?:past|previous|old)(?:\\s+(?:treatment|plan|prescription))?|last year|yesterday)",
            "^(?:medication|medicine|treatment|prescription|instruction)\\s+history",
            "^(?:(?:voici|ce sont|c'etaient|c'etait|ces|les|mes|nos)\\s+)*(?:anciennes?|anciens?|precedents?|precedentes?|passes?|passees?)\\s+(?:consignes|instructions|prescriptions|traitements?|medicaments?|ordonnances?|posologies?|plans?)",
            "^(?:(?:voici|ces|les|mes|nos)\\s+)*(?:consignes|instructions|prescriptions|traitements?|ordonnances?|posologies?)\\s+(?:anciennes?|anciens?|precedents?|precedentes?|du passe|d'autrefois|de l'an dernier|de l'annee derniere|d'hier|de (?:mon|notre) ancien traitement)"
        ]
        let pattern = headers.map { $0 + ending }.joined(separator: "|")
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static let currentInstructionHeader = "^\\s*(?:(?:for|the|our|your|my|here is|this is)\\s+)*(?:current|new|today's|present)\\s+(?:plan|treatment|instructions?|prescription|regimen|directions?|medication)\\b|^\\s*(?:(?:pour|le|la|notre|votre|mon|mes|voici)\\s+)*(?:plan|traitement|consignes|instructions|prescription|ordonnance|posologie)\\s+(?:actuels?|actuelles?|nouveaux?|nouvelles?|d'aujourd'hui)\\b"

    private static func quotationRanges(_ source: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = [], opening: String.Index?, closing: Character?
        for index in source.indices {
            let character = source[index], next = source.index(after: index)
            let apostrophe = character == "'" || character == "’"
            let withinWord = apostrophe && index > source.startIndex && next < source.endIndex
                && source[source.index(before: index)].isLetter && source[next].isLetter
            if withinWord { continue }
            if let end = closing, character == end || (end == "’" && character == "'"), let start = opening {
                result.append(start..<next); opening = nil; closing = nil
            } else if closing == nil {
                switch character {
                case "\"": opening = index; closing = "\""
                case "“": opening = index; closing = "”"
                case "«": opening = index; closing = "»"
                case "'", "‘":
                    // Possessives and French contractions are not quote delimiters.
                    if next < source.endIndex, source[next].isLetter,
                       index == source.startIndex || !source[source.index(before: index)].isLetter {
                        opening = index; closing = character == "‘" ? "’" : "'"
                    }
                default: break
                }
            }
        }
        return result
    }

    private static func sourceContext(first: Range<String.Index>, last: Range<String.Index>, source: String) -> String {
        let ranges = sentenceRanges(source)
        var first = first, last = last
        // A later sentence inside a quotation keeps the clinician/reporting
        // introduction outside the opening quote, rather than losing its tense.
        for quoted in quotationRanges(source) where quoted.overlaps(first) {
            let overlap = max(first.lowerBound, quoted.lowerBound)..<min(first.upperBound, quoted.upperBound)
            guard !instructionRanges(InputLanguage.folded(String(source[overlap]))).isEmpty else { continue }
            if let start = ranges.first(where: { $0.contains(quoted.lowerBound) }), start.lowerBound < first.lowerBound { first = start }
            let closing = source.index(before: quoted.upperBound)
            if let end = ranges.first(where: { $0.contains(closing) }), end.upperBound > last.upperBound { last = end }
        }
        var historicalStart: String.Index?
        for range in ranges where range.lowerBound < first.lowerBound {
            let sentence = InputLanguage.folded(source[range].trimmingCharacters(in: .whitespaces))
            if sentence.range(of: currentInstructionHeader, options: .regularExpression) != nil { historicalStart = nil }
            else if isHistoricalInstructionHeader(sentence) { historicalStart = range.lowerBound }
        }
        let firstSentence = InputLanguage.folded(source[first].trimmingCharacters(in: .whitespaces))
        if firstSentence.range(of: currentInstructionHeader, options: .regularExpression) != nil { historicalStart = nil }
        return source[(historicalStart ?? first.lowerBound)..<last.upperBound].trimmingCharacters(in: .whitespaces)
    }

    static func containingContext(quote: String, source: String) -> String? {
        containingContexts(quote: quote, source: source).first
    }

    static func containingContexts(quote: String, source: String) -> [String] {
        guard !quote.isEmpty else { return [] }
        var contexts: [String] = [], seen = Set<String>(), start = source.startIndex
        let ranges = sentenceRanges(source)
        while start < source.endIndex, let quoted = source.range(of: quote, range: start..<source.endIndex) {
            let containing = ranges.filter { $0.overlaps(quoted) }
            if let first = containing.first, let last = containing.last {
                let context = sourceContext(first: first, last: last, source: source)
                if seen.insert(context).inserted { contexts.append(context) }
            }
            start = quoted.upperBound
        }
        return contexts
    }

    private static func isHistoricalInstruction(_ instruction: Range<String.Index>, in context: String) -> Bool {
        let ranges = sentenceRanges(context)
        for quoted in quotationRanges(context) where quoted.contains(instruction.lowerBound) {
            if let introduction = ranges.first(where: { $0.contains(quoted.lowerBound) }),
               isHistoricalPrefix(String(context[introduction.lowerBound..<quoted.lowerBound]).trimmingCharacters(in: .whitespaces)) { return true }
        }
        let prefix = String(context[..<instruction.lowerBound])
        var historicalSection = false
        for sentence in sentences(prefix) {
            if sentence.range(of: currentInstructionHeader, options: .regularExpression) != nil { historicalSection = false }
            else if isHistoricalInstructionHeader(sentence.trimmingCharacters(in: .whitespaces)) { historicalSection = true }
        }
        if historicalSection { return true }
        guard let sentence = ranges.first(where: { $0.contains(instruction.lowerBound) }) else { return true }
        var localPrefix = String(context[sentence.lowerBound..<instruction.lowerBound]).trimmingCharacters(in: .whitespaces)
        if let expression = try? NSRegularExpression(pattern: currentInstructionHeader),
           let last = expression.matches(in: localPrefix, range: NSRange(localPrefix.startIndex..., in: localPrefix)).last,
           let range = Range(last.range, in: localPrefix) { localPrefix = String(localPrefix[range.upperBound...]) }
        if isHistoricalPrefix(localPrefix.trimmingCharacters(in: .whitespaces)) { return true }
        let next = instructionRanges(context).first { $0.lowerBound > instruction.lowerBound }?.lowerBound ?? sentence.upperBound
        let suffix = String(context[instruction.upperBound..<min(next, sentence.upperBound)])
        let historicalDescription = "\\b(?:was|were|etait|etaient)\\s+(?:(?:my|our|the|mon|notre|le|la)\\s+)?(?:old|past|previous|ancien|ancienne|precedent|precedente)\\s+(?:treatment|instructions?|prescription|plan|traitement|consigne|ordonnance)\\b"
        return suffix.range(of: historicalDescription, options: .regularExpression) != nil
    }

    private static func isHistoricalPrefix(_ prefix: String) -> Bool {
        if isHistoricalInstructionHeader(prefix) { return true }
        let temporal = "\\b(?:yesterday|last year|last month|last week|years? ago|months? ago|in the past|previously|formerly|used to|once|hier|autrefois|auparavant|jadis|l'an dernier|l'annee derniere|la semaine derniere|le mois dernier|dans le passe)\\b"
        let reported = "\\b(?:said|told|advised|prescribed|asked|instructed|recommended|dit|disait|demande|prescrit|conseille|recommande)\\b"
        let pastUse = "\\b(?:i|we)\\s+(?:used to(?:\\s*$|\\s+(?:take|use|continue|start|stop)\\b)|(?:previously|formerly|once)\\s*$)|\\bje\\s+(?:devais|avais l'habitude de)\\s*$|\\b(?:prenais|prenions|prenait|prenaient|commencais|commencions|commencait|commencaient|continuais|continuions|utilisais|utilisions)\\b"
        let pastReport = "\\b(?:had|had been)\\s+(?:told|instructed|prescribed|advised|recommended)\\b|\\b(?:m'avait|m'avaient|avait|avaient)\\s+(?:dit|prescrit|conseille|demande|recommande)\\b|\\b(?:j'avais|nous avions|avait|avaient)\\b.{0,30}\\b(?:consigne|instruction|ordonnance|prescription)\\b|\\b(?:demandait|demandaient|conseillait|conseillaient|prescrivait|prescrivaient|recommandait|recommandaient|disait|disaient)\\b"
        let datedInstruction = "^(?:yesterday|last year|last month|last week|previously|formerly|hier|autrefois|auparavant|jadis|l'an dernier|l'annee derniere)[,:\\s]*$"
        return prefix.range(of: pastUse, options: .regularExpression) != nil
            || prefix.range(of: pastReport, options: .regularExpression) != nil
            || prefix.range(of: datedInstruction, options: .regularExpression) != nil
            || (prefix.range(of: temporal, options: .regularExpression) != nil && prefix.range(of: reported, options: .regularExpression) != nil)
    }

    static func permits(_ action: MedicineChangeAction, quote: String, context: String, name: String? = nil, instructions: String? = nil) -> Bool {
        let foldedContext = InputLanguage.folded(context), foldedQuote = InputLanguage.folded(quote)
        let blocked = "\\b(not|don't|do not|never|might|may|could|consider|if|maybe|should we|can i|pas|jamais|aucun|aucune|sans|si|peut-etre|pourrais|pourrait|pourrions|devrais|devrait|envisager|envisagez|eventuellement|est-ce que|puis-je|dois-je|faudrait-il|ma mere|mon pere|ma soeur|ma sœur|mon frere|mon mari|ma femme|my mother|my father|my sister|my brother|my wife|my husband|he|she|they|elle|elles|il|ils)\\b|\\?"
        let unchanged = "\\b(?:unchanged|no changes?|without (?:any )?(?:changes?|modifications?)|same dose|same regimen|same treatment|inchang[a-z]*|sans modification|meme dose|meme posologie|meme traitement)\\b"
        guard foldedContext.range(of: blocked, options: .regularExpression) == nil,
              foldedContext.range(of: unchanged, options: .regularExpression) == nil,
              foldedQuote.range(of: "\\bje\\s+(?:prends|commence|continue|change|augmente|diminue)\\b", options: .regularExpression) == nil,
              foldedQuote.range(of: "\\b(?:i|we)\\s+(?:(?:currently|usually|normally|regularly)\\s+)?(?:take|continue|am taking|are taking|use|am using|are using)\\b|\\bi'm taking\\b", options: .regularExpression) == nil else { return false }

        let selectedVerbs = verbs(action)
        let verbs = selectedVerbs.english, frenchVerbs = selectedVerbs.french
        let prefixes = "(?:(?:la|le|de|du|a|prendre|votre|dose de|traitement par|traitement avec)\\s+|l')*"
        let sourceName = name.map { NSRegularExpression.escapedPattern(for: InputLanguage.folded($0)) + "\\b" } ?? "[\\p{L}\\p{M}]"
        let frenchInstruction = "\\b(?:" + frenchVerbs + ")\\s+" + prefixes + sourceName
        let englishPrefixes = "(?:(?:the|your|my|our|dose of|dosage of|treatment with|treatment of|use of|take|taking|using|from|to)\\s+)*"
        let englishInstruction = "\\b(?:" + verbs + ")\\s+" + englishPrefixes + sourceName
        let english = foldedQuote.range(of: englishInstruction, options: .regularExpression) != nil
        let french = foldedQuote.range(of: frenchInstruction, options: .regularExpression) != nil
        let selected = Set((verbs + "|" + frenchVerbs).split(separator: "|").map(String.init))
        // Bind to complete source context so a quote shortened to the inner
        // infinitive cannot discard the outer stop/start instruction.
        let occurrences = instructionRanges(foldedContext)
        let eligibleOccurrences = occurrences.filter { !isHistoricalInstruction($0, in: foldedContext) }
        guard instructionRanges(foldedQuote).contains(where: { selected.contains(String(foldedQuote[$0])) }),
              eligibleOccurrences.contains(where: { selected.contains(String(foldedContext[$0])) }) else { return false }
        var conjoined = false
        if let name {
            let escapedName = NSRegularExpression.escapedPattern(for: InputLanguage.folded(name)) + "\\b"
            let targetPrefixes = "(?:(?:the|your|my|our|dose of|dosage of|treatment with|treatment of|use of|take|taking|using|from|to|la|le|de|du|a|prendre|votre|dose de|traitement par|traitement avec)\\s+|l')*"
            for (index, range) in occurrences.enumerated() where selected.contains(String(foldedContext[range])) {
                guard eligibleOccurrences.contains(range) else { continue }
                let end = index + 1 < occurrences.count ? occurrences[index + 1].lowerBound : foldedContext.endIndex
                let clause = String(foldedContext[range.upperBound..<end])
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
        for range in sentenceRanges(source) {
            let sentence = source[range].trimmingCharacters(in: .whitespaces)
            consumed += sentence.count + (consumed == 0 ? 0 : 1)
            guard consumed <= VisitReview.chunkCharacters else { break }
            guard (4...600).contains(sentence.count), !sentence.contains("<|"), !seen.contains(sentence) else { continue }
            let context = sourceContext(first: range, last: range, source: source)
            let actions = MedicineChangeAction.allCases.filter { permits($0, quote: sentence, context: context) }
            if !actions.isEmpty {
                seen.insert(sentence)
                result.append(.init(quote: sentence, actions: actions, maximumEntries: entryCapacity(sentence)))
            }
            if result.count == 12 { break }
        }
        return result
    }

    /// A minimum is permitted only after constructing and validating one narrow,
    /// source-verbatim proposal. This does not populate model output or relax parse().
    static func requiredMedicineProposal(_ transcript: String, medicines: [Medicine], candidates: [VisitMedicineSourceCandidate]) -> VisitMedicineChange? {
        let source = VisitReview.normalise(transcript)
        guard source.count <= VisitReview.chunkCharacters, candidates.count == 1,
              let candidate = candidates.first, candidate.maximumEntries == 1, candidate.actions.count == 1,
              let action = candidate.actions.first,
              containingContexts(quote: candidate.quote, source: source).contains(candidate.quote),
              quotationRanges(source).isEmpty,
              InputLanguage.folded(source).range(of: "\\b(?:if|unless|might|may|could|consider|maybe|not|never|don't|do not|si|sauf|peut-etre|pourrais|pourrait|devrais|devrait|envisager|pas|jamais|yesterday|previously|formerly|used to|last year|last month|last week|hier|autrefois|auparavant|jadis|l'an dernier|l'annee derniere)\\b|\\?", options: .regularExpression) == nil else { return nil }
        // No catalog count without a copied, uniquely resolved source name.
        let mentioned = Catalog.mentioned(in: candidate.quote)
        guard mentioned.count == 1, let canonical = mentioned.first,
              sentences(source).filter({ Catalog.mentioned(in: $0, saved: medicines).contains { $0.id == canonical.id } }).count == 1 else { return nil }
        let selected = verbs(action)
        let prefixes = "(?:(?:the|your|my|our|dose of|dosage of|treatment with|treatment of|use of|take|taking|to take|la|le|de|du|a|prendre|a prendre|votre|dose de|traitement par|traitement avec)\\s+|l')*"
        let names = Array(Set(Catalog.names(for: canonical))).sorted { $0.count > $1.count }
        var extracted: (name: String, instructions: String)?
        for name in names {
            // Match the name in the original source so its native range retains
            // exact accents and spelling. Only the separate prefix is folded;
            // folded-string offsets are never applied to original source text.
            guard let nameRange = candidate.quote.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            if nameRange.upperBound < candidate.quote.endIndex {
                let next = candidate.quote[nameRange.upperBound]
                if next.isLetter || next.isNumber || next == "_" { continue }
            }
            let pattern = "^(?:(?:please|veuillez)\\s+)?(?:" + selected.english + "|" + selected.french + ")\\s+" + prefixes + "$"
            let prefix = InputLanguage.folded(String(candidate.quote[..<nameRange.lowerBound]))
            guard prefix.range(of: pattern, options: .regularExpression) != nil else { continue }
            let copiedName = String(candidate.quote[nameRange])
            let matchingIDs = Set((medicines + Catalog.medicines).filter { medicine in
                Catalog.names(for: medicine).contains { InputLanguage.folded($0) == InputLanguage.folded(copiedName) }
            }.map(\.id))
            guard matchingIDs == [canonical.id], medicines.filter({ $0.id == canonical.id }).count <= 1,
                  let resolved = Catalog.resolve(copiedName, saved: medicines), resolved.id == canonical.id,
                  resolved.ingredients == canonical.ingredients,
                  names.contains(where: { InputLanguage.folded($0) == InputLanguage.folded(resolved.name) }) else { return nil }
            var tail = String(candidate.quote[nameRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if tail.hasSuffix(".") { tail.removeLast() }
            tail = tail.trimmingCharacters(in: .whitespaces)
            if action == .stop {
                guard InputLanguage.folded(tail).range(of: "^(?:today|now|aujourd'hui|maintenant)?$", options: .regularExpression) != nil else { return nil }
                extracted = (copiedName, "")
            } else {
                if let connector = tail.range(of: "^(?:to|à|a)\\s+", options: [.regularExpression, .caseInsensitive]) { tail.removeSubrange(connector) }
                // Requiring a quantified dose and explicit interpretable schedule
                // leaves vague directions, free text and uncertain scopes optional.
                let folded = InputLanguage.folded(tail)
                let dose = "^[0-9]+(?:[.,][0-9]+)?\\s*(?:mg|mcg|μg|µg|g|ml|units?|unites?|ui)\\b"
                guard !tail.isEmpty, tail.count <= 180, candidate.quote.contains(tail),
                      folded.range(of: dose, options: .regularExpression) != nil,
                      folded.range(of: ";|\\b(?:or|ou|unless|sauf|as needed|au besoin|depending|selon|until|jusqu|when|after|before|apres|avant|lorsque|another|other|second|autre|deuxieme|then|puis|ensuite|followed by)\\b", options: .regularExpression) == nil else { return nil }
                let doseCount = (try? NSRegularExpression(pattern: "\\b[0-9]+(?:[.,][0-9]+)?\\s*(?:mg|mcg|μg|µg|g|ml|units?|unites?|ui)\\b"))?.numberOfMatches(in: folded, range: NSRange(folded.startIndex..., in: folded)) ?? 0
                guard doseCount == 1 else { return nil }
                let times = CareRules.times(in: tail), frequency = CareRules.frequency(in: tail)
                let frequencyMentioned = folded.range(of: "\\b(?:times?|fois|daily|weekly|monthly|per|par|jour|semaine|mois|quotidien|quotidienne|hebdomadaire|mensuel|mensuelle)\\b", options: .regularExpression) != nil
                let clockPattern = "\\b[0-9]{1,2}(?::[0-9]{2})?\\s*(?:am|pm)\\b|\\b[0-9]{1,2}\\s*h(?:\\s*[0-9]{2})?\\b|\\b[0-9]{1,2}:[0-9]{2}\\b(?!\\s*(?:am|pm)\\b)"
                let clockCount = (try? NSRegularExpression(pattern: clockPattern, options: [.caseInsensitive]))?.numberOfMatches(in: tail, range: NSRange(tail.startIndex..., in: tail)) ?? 0
                guard clockCount == times.count, !frequencyMentioned || frequency != nil,
                      frequency != nil || !times.isEmpty else { return nil }
                extracted = (copiedName, tail)
            }
            break
        }
        guard let extracted, action == .start || medicines.contains(where: { $0.id == canonical.id }) else { return nil }
        let raw: [String: Any] = ["highlights": [], "followUps": [], "appointments": [], "medicines": [
            ["quote": candidate.quote, "action": action.rawValue, "name": extracted.name, "instructions": extracted.instructions]
        ]]
        guard let data = try? JSONSerialization.data(withJSONObject: raw),
              let summary = try? VisitReview.parse(String(decoding: data, as: UTF8.self), transcript: source, medicines: medicines),
              summary.medicines.count == 1, let proposal = summary.medicines.first,
              proposal.action == action, proposal.medicine.id == canonical.id,
              proposal.medicine.instructions == extracted.instructions else { return nil }
        if action != .stop {
            let schedule = MedicineSchedule(medicineID: canonical.id, times: proposal.times, frequency: proposal.frequency)
            guard (try? CareRules.validate(schedule, medicines: [proposal.medicine])) != nil else { return nil }
        }
        return proposal
    }
}
