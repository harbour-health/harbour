import Foundation

extension ToolPlanner {
    /// Closed, read-only retrieval requests can be answered directly from their
    /// source. This is application output, never a corrected model prediction.
    public static func groundedReply(original: String, records: Records, history: [ConversationTurn] = [], language: ModelLanguage = .english) -> ReplyFallback? {
        guard original.count <= 500, !original.contains("<|"),
              !original.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        let input = InputLanguage.folded(original).trimmingCharacters(in: .whitespaces)
        func matches(_ pattern: String) -> Bool { input.range(of: pattern, options: .regularExpression) != nil }
        func reply(_ text: String, _ reason: String) -> ReplyFallback {
            ReplyFallback(decision: .init(tool: .reply, arg: text), action: .reply(text), reason: reason)
        }
        let courtesy = #"(?:(?:please|svp|s'il vous plait),?\s+)?"#
        // Retrieve one owned field from one unambiguous saved medicine. A
        // catalog identity alone cannot supply personal directions, and the
        // instructions of another product must never fill an empty field.
        let directionQuestion = #"(?:what\s+(?:directions|instructions)\s+(?:are|have been)\s+(?:saved|stored|recorded)\s+for\s+|(?:show|repeat|read)\s+(?:me\s+)?(?:the\s+)?(?:saved|stored|recorded)\s+(?:directions|instructions)\s+for\s+|quelles\s+(?:consignes|instructions)\s+sont\s+(?:enregistrees|sauvegardees)\s+pour\s+|(?:montre|montrez|repete|repetez|lis|lisez)(?:-moi)?\s+les\s+(?:consignes|instructions)\s+(?:enregistrees|sauvegardees)\s+pour\s+)"#
        let sourceOnly = #"(?:\s+(?:please\s+)?repeat\s+(?:the\s+)?(?:stored|saved|recorded)\s+(?:directions|instructions),?\s+not\s+a\s+recommendation[.!]?|\s+(?:repete|repetez)\s+(?:seulement\s+)?les\s+(?:consignes|instructions)\s+(?:enregistrees|sauvegardees),?\s+pas\s+(?:un\s+conseil|une\s+recommandation)[.!]?)?"#
        let candidates = records.medicines.filter { medicine in
            Catalog.names(for: medicine).contains { name in
                let target = NSRegularExpression.escapedPattern(for: InputLanguage.folded(name))
                return !target.isEmpty && matches(#"\A"# + courtesy + directionQuestion + #"(?:(?:the|le|la)\s+|l')?"# + target + #"\s*[?.!]?"# + sourceOnly + #"\s*\z"#)
            }
        }
        if !candidates.isEmpty {
            guard candidates.count == 1 else {
                return reply(language == .french ? "Plusieurs médicaments enregistrés correspondent à ce nom. Précisez lequel." : "More than one saved medicine matches that name. Please specify which one.", "source_medicine_instructions")
            }
            let medicine = candidates[0]
            guard medicine.name.count <= 300, [medicine.name, medicine.instructions].allSatisfy({ value in
                !value.contains("<|") && !value.unicodeScalars.contains(where: {
                    CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
                })
            }) else { return nil }
            let name = medicine.name
            let directions = medicine.instructions
            guard !directions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return reply(language == .french ? "Aucune consigne n’est enregistrée pour \(name)." : "No directions are recorded for \(name).", "source_medicine_instructions")
            }
            let excerpt = directions.count > 1800
            let quoted = String(directions.prefix(1800))
            let text = language == .french
                ? "Consignes enregistrées pour \(name) : « \(quoted) »" + (excerpt ? " [extrait]" : "")
                : "Recorded directions for \(name): “\(quoted)”" + (excerpt ? " [excerpt]" : "")
            guard text.count <= maximumReplyCharacters else { return nil }
            return reply(text, "source_medicine_instructions")
        }
        let count = #"(?:how many\s+(?:(?:of\s+)?my\s+)?(medicines|medications|symptoms|readings|appointments)\s+(?:(?:do i have|have i|are)\s+)?(?:saved|stored|recorded)|combien\s+(?:de\s+)?(medicaments|symptomes|mesures|rendez-vous)\s+(?:(?:ai-je|sont)\s+)?(?:enregistres|enregistrees|sauvegardes|sauvegardees))"#
        if matches(#"\A"# + courtesy + count + #"\s*[?.!]?\s*\z"#) {
            let total: Int
            let label: String
            if matches(#"\b(?:medicines|medications|medicaments)\b"#) {
                total = records.medicines.count; label = language == .french ? "Médicaments enregistrés" : "Saved medicines"
            } else if matches(#"\b(?:symptoms|symptomes)\b"#) {
                total = records.symptoms.count; label = language == .french ? "Symptômes enregistrés" : "Saved symptoms"
            } else if matches(#"\b(?:readings|mesures)\b"#) {
                total = records.readings.count; label = language == .french ? "Mesures enregistrées" : "Saved readings"
            } else {
                total = records.appointments.count; label = language == .french ? "Rendez-vous enregistrés" : "Saved appointments"
            }
            return reply(label + (language == .french ? " : " : ": ") + "\(total).", "source_record_count")
        }

        // A broad recall request receives source quotations, with explicit
        // speaker attribution and excerpt boundaries. It cannot invent an
        // assistant question or promote an assistant assertion to a user fact.
        let recall = #"(?:what\s+(?:did i say|have i said|did i mention|have i mentioned|did i tell you)\s+(?:earlier|before|previously|in this conversation)|(?:remind me|tell me)\s+what i\s+(?:said|mentioned|told you)\s+(?:earlier|before|previously)|qu'ai-je\s+(?:dit|mentionne)\s+(?:plus tot|avant|dans cette conversation)|(?:rappelle|rappelez)-moi\s+ce que\s+j'ai\s+(?:dit|mentionne)\s+(?:plus tot|avant))"#
        if matches(#"\A"# + courtesy + recall + #"\s*[?.!]?\s*\z"#) {
            let turns = history.suffix(6).filter { $0.isUser && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard turns.allSatisfy({ turn in
                !turn.text.contains("<|") && !turn.text.unicodeScalars.contains(where: {
                    CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
                })
            }) else { return nil }
            guard !turns.isEmpty else {
                return reply(language == .french ? "Aucun message antérieur de votre part n’est disponible dans le contexte fourni." : "No earlier messages from you are available in the supplied conversation context.", "source_history_quote")
            }
            let heading = language == .french ? "Vos messages dans le contexte disponible :" : "Your messages in the available conversation context:"
            let quotes = turns.map { turn in
                let excerpt = turn.text.count > 400
                let text = String(turn.text.prefix(400))
                let suffix = excerpt ? (language == .french ? " [extrait]" : " [excerpt]") : ""
                return "“\(text)”\(suffix)"
            }.joined(separator: "\n")
            return reply(heading + "\n" + quotes, "source_history_quote")
        }
        return nil
    }
}
