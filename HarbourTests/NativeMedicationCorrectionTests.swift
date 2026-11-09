import XCTest
import HarbourCore
@testable import Harbour

@MainActor final class NativeMedicationCorrectionTests: XCTestCase {
    func testLocalAgentChoosesDoseCorrection() async throws {
        let models = ModelManager(); try XCTSkipUnless(models.installed(.balanced), "Requires the verified Balanced cache; no model is downloaded.")
        let previous = models.selection; models.selection = .balanced; defer { models.selection = previous }
        let records = DemoData.make(french: false).records, request = "Update my metformin to 400mg"
        let decision = try await models.chatDecision(request, records: records)
        let attachment = XCTAttachment(string: String(describing: decision)); attachment.name = "fictional-dose-correction"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(decision.tool, .updateMedicine)
        guard case let .add(medicine, _, _) = try ToolPlanner.validate(decision, original: request, records: records) else { return XCTFail("Expected medicine review") }
        XCTAssertTrue(medicine.instructions.contains("400mg")); XCTAssertTrue(medicine.instructions.contains("breakfast and dinner"))
    }
    func testUncertainNameRequestsClarification() async throws {
        let models = ModelManager(); try XCTSkipUnless(models.installed(.balanced), "Requires the verified Balanced cache; no model is downloaded.")
        let previous = models.selection; models.selection = .balanced; defer { models.selection = previous }
        let decision = try await models.chatDecision("Update my metfulsin to 400mg", records: DemoData.make(french: false).records)
        let answer = decision.arg
        let attachment = XCTAttachment(string: String(describing: decision)); attachment.name = "fictional-uncertain-medicine-name"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(decision.tool, .reply)
        XCTAssertTrue(answer.contains("?"), "Expected a clarification question: \(answer)")
        XCTAssertTrue(answer.localizedCaseInsensitiveContains("medicine") || answer.localizedCaseInsensitiveContains("metformin"), answer)
        XCTAssertFalse(answer.contains("400")); XCTAssertFalse(answer.localizedCaseInsensitiveContains("hypoglycemia"))
    }
}
