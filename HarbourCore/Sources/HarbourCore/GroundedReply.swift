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
