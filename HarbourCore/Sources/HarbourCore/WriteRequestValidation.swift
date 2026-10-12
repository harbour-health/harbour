import Foundation

/// Reject explicit non-action intent after model selection; this does not choose a tool.
enum WriteRequestValidation {
    private static func match(_ text: String, _ pattern: String) -> Range<String.Index>? {
        text.range(of: pattern, options: .regularExpression)
    }

    static func permits(_ original: String, tool: Tool) -> Bool {
        let action: String
        switch tool {
        case .captureSymptom, .logReading:
            action = "save|record|log|note|track|add|enregistr[a-z]*|sauvegard[a-z]*|noter|notez|note|ajout[a-z]*|consign[a-z]*"
        case .addMedicine:
            action = "add|put|start|begin|ajout[a-z]*|commenc[a-z]*|debut[a-z]*|enregistr[a-z]*"
        case .removeMedicine:
            action = "remove|delete|stop|retir[a-z]*|supprim[a-z]*|effac[a-z]*|arret[a-z]*"
        case .clearData:
            action = "clear|delete|erase|reset|wipe|effac[a-z]*|supprim[a-z]*|vid[a-z]*|reinitialis[a-z]*"
        case .createReminder:
            action = "remind|reminder|create|set|add|save|rappel[a-z]*|cre[eazr]*|ajout[a-z]*|enregistr[a-z]*|programm[a-z]*"
        case .scheduleMedicine:
            action = "schedule|set|plan|program|programm[a-z]*|planifi[a-z]*|horaire"
        case .logDose:
            action = "log|record|mark|take|taken|took|skip|skipped|enregistr[a-z]*|consign[a-z]*|pris|prise|prends|prendre|saute|sautee|omis|omise"
        case .saveQuestion:
            action = "save|add|remember|keep|store|enregistr[a-z]*|sauv[a-z]*|ajout[a-z]*|gard[a-z]*|noter|note"
        case .importReadings:
            action = "import|sync|synchronize|import[a-z]*|synchronis[a-z]*"
        default:
            return true
        }
        let input = InputLanguage.folded(original)
        // Apostrophes inside words (j'ai, don't) are not quotation delimiters.
        let quotes = #""[^"]*"|“[^”]*”|«[^»]*»|‘[^’]*’|(?<![\p{L}\p{N}])'(?:[^']|(?<=[\p{L}])'(?=[\p{L}]))*'(?![\p{L}\p{N}])"#
        let outer = original.replacingOccurrences(of: quotes, with: " ", options: .regularExpression)
        let unquoted = InputLanguage.folded(outer)
        let quoted = outer != original
        let polite = "(?:(?:please|svp|s'il vous plait|s'il te plait),?\\s+)?"
        let request = "(?:(?:(?:can|could|would|will)\\s+you|(?:peux|pourrais|pouvez|pourriez)[ -](?:tu|vous)|est-ce que (?:tu (?:peux|pourrais)|vous (?:pouvez|pourriez)))\\s+|(?:i want to|i would like to|i'd like to|je veux|je souhaite|je voudrais)\\s+)?"
        let requestPrefix = "\\s*" + polite + request + polite + "(?:(?:me|nous)\\s+|m')?"
        let imperative = "(?:^|[.;:]\\s*)" + requestPrefix + "(?:" + action + ")\\b"
        let command = match(unquoted, imperative)
        if quoted && command == nil { return false }

        // A reminder or saved question requires an affirmative outer request.
        // Its payload may itself contain a medical question, negation, or condition.
        var scope = unquoted
        if tool == .saveQuestion {
            guard let command, let question = match(unquoted, "\\bquestion\\b"), question.lowerBound >= command.lowerBound else { return false }
            scope = String(unquoted[..<question.upperBound])
        } else if tool == .createReminder {
            guard let command else { return false }
            if match(String(unquoted[command]), "\\b(?:remind|rappel[a-z]*)\\b") != nil {
                scope = String(unquoted[..<command.upperBound])
            } else {
                guard let reminder = match(unquoted, "\\b(?:reminder|rappel|alerte)\\b") else { return false }
                scope = String(unquoted[..<reminder.upperBound])
            }
        } else if [.clearData, .importReadings].contains(tool) && command == nil {
            return false
        }
        if tool == .clearData {
            guard let command, !quoted else { return false }
            let object = String(scope[command.upperBound...])
            let app = "(?:(?:the|this|my|our|entire|whole|le|la|cette|mon|ma|notre|toute|tout)\\s+|l')*(?:harbour|app|application)\\b"
            let reset = match(String(scope[command]), "\\b(?:reset|wipe|reinitialis[a-z]*)\\b") != nil
            let wholeApp = reset ? match(object, "^\\s*" + app) : nil
            let qualifier = "(?:(?:of|the|my|our|your|all|saved|stored|health|medical|single|les|mes|nos|vos|ces)\\s+)*"
            let allRecords = match(object, "^\\s*(?:(?:all|every|tous|toutes|tout)\\s+" + qualifier + "(?:records?|data|donnees|enregistrements?|dossiers?)\\b|everything\\b|tout\\b)")
            guard let target = wholeApp ?? allRecords else { return false }
            // A whole-archive target may identify this app or health-data domain,
            // but date/topic/exclusion qualifiers describe an unsupported subset.
            let remainder = String(object[target.upperBound...])
            let healthDomain = "(?:\\s+de sante)?"
            let appLocation = "(?:\\s+(?:from|in|on|of|within|inside|de|dans)\\s+(?:" + app + "))?"
            let courtesy = "(?:\\s*[,.;!?]?\\s*(?:please|thanks|thank you|svp|s'il vous plait|merci))?"
            guard match(remainder, "^" + healthDomain + appLocation + courtesy + "\\s*[.!?]*\\s*$") != nil else { return false }
            if wholeApp == nil {
                guard Catalog.mentioned(in: original).isEmpty,
                      match(scope, "\\b(?:reading|measurement|symptom|reminder|question|releve|mesure|symptome|rappel)\\b") == nil else { return false }
            }
        }

        if command == nil, [.addMedicine, .removeMedicine, .scheduleMedicine, .logDose].contains(tool),
           match(scope, "\\b(?:pas|jamais|sans|si|puis-je|dois-je|devrais-je|faudrait-il|pourrais-je|peut-etre|not|don't|didn't|haven't|never|without)\\b") != nil {
            return false
        }

        let negation = "(?:\\b(?:do not|don't|didn't|haven't|hasn't|never|avoid|without|not asking|not asked|not to|not)\\b|\\b(?:pas|jamais|sans|aucun|aucune)\\b)\\s*.{0,60}\\b(?:" + action + ")[a-z]*\\b"
        let frenchNegation = "(?:\\bne\\s+|\\bn')\\s*.{0,60}\\b(?:" + action + ")\\b.{0,60}\\b(?:pas|jamais|plus|aucun|aucune)\\b"
        if match(scope, negation) != nil || match(scope, frenchNegation) != nil { return false }
        let hypothetical = "^" + requestPrefix + "(?:what if|if|suppose|imagine|hypothetically|maybe|si|et si|suppos[a-z]*|imagin[a-z]*|peut-etre)\\b|\\b(?:only quoting|just quoting|hypothetical|hypothetique|je cite|simple citation)\\b"
        if match(scope, hypothetical) != nil { return false }
        if command == nil {
            let question = "^\\s*(?:why|what|how|when|where|which|should|could|can|would|do|does|did|is|are|was|were|may|might|will|pourquoi|comment|quand|quel|quelle|quels|quelles|puis-je|dois-je|devrais-je|pourrais-je|est-ce que)\\b"
            if match(scope, question) != nil { return false }
        }
        let reported = "^\\s*(?:(?:my|his|her|their)\\s+(?:mother|father|brother|sister|partner|wife|husband|friend|doctor|patient)|he|she|they|(?:ma|mon|sa|son|leur)\\s+(?:mere|pere|frere|soeur|sœur|conjoint|conjointe|ami|amie|medecin|patient)|il|elle|ils|elles)\\b"
        if match(scope, reported) != nil { return false }
        if tool == .logReading {
            // A negated numeric observation is not a measurement of that number.
            if match(input, "\\b(?:not|pas|jamais)\\s+(?:at|de|a|of)?\\s*[0-9]") != nil { return false }
        }
        return true
    }
}
