import Foundation
import HarbourCore

/// Human review of a source item; resolves known catalog identities without guessing ingredients.
struct VisitMedicineReviewSource: Identifiable {
    let visitID: UUID
    let transcript: String
    let quote: String
    let name: String
    let instructions: String
    var id: String {
        visitID.uuidString + quote
    }

    init(visit: DoctorVisit, item: VisitQuote) {
        visitID = visit.id
        transcript = visit.transcript
        quote = item.quote
        let text = item.text ?? item.quote
        // Older generated items use "name: directions". Only copy grounded parts.
        if let colon = text.firstIndex(of: ":") {
            let candidate = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
            let directions = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if
                !candidate.isEmpty, item.quote.localizedCaseInsensitiveContains(candidate),
                item.quote.contains(directions) {
                name = candidate
                instructions = directions

                return
            }
        }
        // Legacy free-form items remain editable; never guess a product from prose.
        name = ""
        instructions = text
    }

    func medicine(saved: [Medicine]) -> Medicine? {
        guard !name.isEmpty else {
            return nil
        }

        var medicine = Catalog.resolve(name, saved: saved) ?? Medicine(name: name)
        medicine.instructions = instructions

        return medicine
    }
}
