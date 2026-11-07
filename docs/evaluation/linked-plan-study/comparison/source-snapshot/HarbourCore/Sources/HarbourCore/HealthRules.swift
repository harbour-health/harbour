import Foundation

public struct InteractionAlert: Codable, Equatable, Sendable {
    public var pair: [String]
    public var summary: String
    public var source: String
}
public struct InteractionReport: Codable, Equatable, Sendable {
    public var alerts: [InteractionAlert] = []
    public var unassessed: [[String]] = []
    public var duplicates: [String] = []
    public var unresolved: [String] = []
    public init() {}
}
public enum HealthRules {
    public static let emergencySource = "https://www.ontario.ca/page/emergency-rooms"
    public static let helpSource = "https://www.ontario.ca/page/your-health"
    public static let pairs: [InteractionAlert] = [
        InteractionAlert(pair: ["ibuprofen", "warfarin"], summary: "Ibuprofen is listed among medications that may not mix well with warfarin. Ask a pharmacist or prescriber to review the exact products and your situation.", source: "https://www.nhs.uk/medicines/warfarin/"),
        InteractionAlert(pair: ["aspirin", "warfarin"], summary: "Aspirin is listed among medications that may not mix well with warfarin. Ask a pharmacist or prescriber to review the exact products and your situation.", source: "https://www.nhs.uk/medicines/warfarin/"),
        InteractionAlert(pair: ["naproxen", "warfarin"], summary: "Warfarin is listed among medications that may not mix well with naproxen. Ask a pharmacist or prescriber to review the exact products and your situation.", source: "https://www.nhs.uk/medicines/naproxen/"),
        InteractionAlert(pair: ["ibuprofen", "naproxen"], summary: "Check with a pharmacist before taking ibuprofen with another NSAID such as naproxen.", source: "https://www.nhs.uk/medicines/ibuprofen-for-adults/")
    ]
    public static func check(_ medicines: [Medicine]) -> InteractionReport {
        var report = InteractionReport(), seen = Set<String>(), duplicates = Set<String>()
        report.unresolved = medicines.filter { $0.ingredients.isEmpty }.map(\.name)
        for i in medicines.indices {
            for j in medicines.indices where j > i {
                for a in medicines[i].ingredients { for b in medicines[j].ingredients {
                    if a == b { duplicates.insert(a); continue }
                    let pair = [a, b].sorted(), key = pair.joined(separator: "|")
                    guard seen.insert(key).inserted else { continue }
                    if let alert = pairs.first(where: { $0.pair == pair }) { report.alerts.append(alert) }
                    else { report.unassessed.append(pair) }
                } }
            }
        }
        report.duplicates = duplicates.sorted()
        return report
    }
    public static func emergencyCue(_ text: String) -> Bool {
        let text = InputLanguage.folded(text)
        let frenchChest = "douleur(?:s)? (?:thoracique(?:s)?|a la poitrine|dans la poitrine) (?:intense(?:s)?|severe(?:s)?)[ ,]+(?:et )?persistante(?:s)?|douleur(?:s)? persistante(?:s)?[ ,]+(?:et )?(?:intense(?:s)?|severe(?:s)?) (?:thoracique(?:s)?|a la poitrine|dans la poitrine)"
        let frenchChestReversed = "douleur(?:s)? (?:thoracique(?:s)?|a la poitrine|dans la poitrine) persistante(?:s)?[ ,]+(?:et )?(?:intense(?:s)?|severe(?:s)?)"
        let pattern = "persistent[ ,]+severe chest pain|difficulty breathing|loss of consciousness|new confusion|(?:severe )?pain not relieved by (?:pain )?medic(?:ine|ation)|" + frenchChest + "|" + frenchChestReversed + "|(?:ne peux|ne peut|ne pouvez) pas respirer|(?:n'arrive|n'arrivez) pas a respirer|mal a respirer|difficulte(?:s)? (?:a|de) respirer|difficulte(?:s)? respiratoire(?:s)?|perte de (?:connaissance|conscience)|(?:nouvelle confusion|confusion (?:nouvelle|soudaine))|douleur(?:s)? (?:intense(?:s)? |severe(?:s)? )?(?:non soulagee(?:s)?|pas soulagee(?:s)?|qui n'est pas soulagee|qui ne sont pas soulagees) par (?:les |des |un |le )?(?:medicament(?:s)?|antidouleur(?:s)?|analgesique(?:s)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).contains { match in
            let before = ns.substring(with: NSRange(location: max(0, match.range.location - 64), length: min(64, match.range.location)))
            // Only local explicit negation suppresses a cue. History and third-person mentions
            // stay conservative because this heuristic cannot establish who is affected now.
            let negation = "\\b(no|not|without|denies|denied)\\s*(?:any\\s*)?$|\\b(?:pas|plus|jamais)\\s+(?:de |d'|des |une? )?$|\\b(?:aucune?|sans|nie|nie avoir)\\s*(?:de |d'|des |une? )?$"
            return before.range(of: negation, options: .regularExpression) == nil
        }
    }
    public static func isEmergency(_ symptom: Symptom) -> Bool { !symptom.signs.isEmpty || emergencyCue(symptom.text) }
    public static func guidance(_ symptom: Symptom) -> String {
        isEmergency(symptom)
            ? "If this sign is happening now, call 911. Your description or selected signs match an Ontario emergency example."
            : "Contact Health811 or a health professional for help deciding where to get care. These checks cannot rule out an urgent problem. If you think this is an emergency, call 911."
    }
}
