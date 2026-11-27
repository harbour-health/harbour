import XCTest
import HarbourCore
import HarbourRuntime
@testable import Harbour

@MainActor final class NativeVisitSummaryTests: XCTestCase {
    func testNativeModelManagerRetainsInhalerDirections() async throws {
        let models = ModelManager()
        try XCTSkipUnless(
            models.installed(.balanced),
            "Requires the existing verified Balanced cache; this test does not download a model."
        )
        let source = "Start salbutamol 2 puffs every 4 to 6 hours if needed for wheezing, maximum 8 puffs in 24 hours."
        var combined = VisitSummary()
        for pass in VisitExtractionPass.allCases {
            let output = try await models.generate(
                VisitReview.focusedPrompt(pass, transcript: source, medicines: Evaluation.records.medicines),
                maxTokens: pass.tokenBudget,
                responseGrammar: VisitSummaryOutputGrammar.make(section: pass.rawValue),
                model: .balanced
            )
            let attachment = XCTAttachment(string: output)
            attachment.name = "synthetic-inhaler-" + pass.rawValue
            attachment.lifetime = .keepAlways
            add(attachment)
            combined.merge(try VisitReview.parsePass(
                output,
                pass: pass,
                transcript: source,
                medicines: Evaluation.records.medicines
            ))
        }
        let item = try XCTUnwrap(combined.unconfirmedMedicines?.first)
        let text = item.text ?? ""
        for detail in [
            "salbutamol",
            "2 puffs",
            "4 to 6 hours",
            "if needed for wheezing",
            "maximum 8 puffs in 24 hours"
        ] {
            XCTAssertTrue(text.contains(detail), "Missing \(detail): \(text)")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("native-visit-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(folder: folder), visit = DoctorVisit(transcript: source)
        XCTAssertTrue(store.saveVisit(visit))
        store.saveVisitSummary(combined, id: visit.id, transcript: source, baseline: [])
        XCTAssertEqual(store.visits.first?.summary?.unconfirmedMedicines?.first?.text, text)
    }
}
