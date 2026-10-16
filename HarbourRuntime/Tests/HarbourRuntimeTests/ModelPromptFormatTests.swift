import XCTest
import HarbourCore
@testable import HarbourRuntime

final class ModelPromptFormatTests: XCTestCase {
    func testRoutingCompatibilityProfileFollowsFixedModelFamilyAndSharedLocalization() throws {
        XCTAssertTrue(ModelPromptFormat.qwen25.usesLegacyRoutingPrompt)
        XCTAssertFalse(ModelPromptFormat.qwen35.usesLegacyRoutingPrompt)
        // Test/executable consumers may map this flag because they depend on Core.
        func profile(_ format: ModelPromptFormat) -> RoutingPromptProfile {
            format.usesLegacyRoutingPrompt ? .legacyQwen25 : .current
        }
        for language in [ModelLanguage.english, .french] {
            let legacy = ToolPlanner.prompt("Display my saved readings.", profile: profile(.qwen25))
            let current = ToolPlanner.prompt("Display my saved readings.", profile: profile(.qwen35))
            let localizedLegacy = ModelPrompts.localized(legacy, language: language, purpose: .routing)
            let localizedCurrent = ModelPrompts.localized(current, language: language, purpose: .routing)
            XCTAssertEqual(try ModelPromptFormat.qwen25.prepare(localizedLegacy), localizedLegacy)
            XCTAssertEqual(try ModelPromptFormat.qwen35.prepare(localizedCurrent), localizedCurrent + "\n<think>\n\n</think>\n\n")
            XCTAssertNotEqual(localizedLegacy, localizedCurrent)
            let languagePolicy = language == .french ? "Interprète les demandes en français et en anglais." : "Interpret English and French requests."
            XCTAssertTrue(localizedLegacy.contains(languagePolicy))
            XCTAssertTrue(localizedCurrent.contains(languagePolicy))
        }
    }

    func testQwen35DisablesThinkingForEveryGenerationPath() throws {
        let prompts = [
            ToolPlanner.prompt("Show my medicines", records: Evaluation.records),
            ToolPlanner.conversationPrompt("Why is the sky blue?", records: Evaluation.records),
            try VisitReview.prompt("Book blood work.", medicines: Evaluation.records.medicines),
            "<|im_start|>system\nOutput a title as JSON.\n<|im_end|>\n<|im_start|>user\nHello\n<|im_end|>\n<|im_start|>assistant"
        ]
        for prompt in prompts {
            let prepared = try ModelPromptFormat.qwen35.prepare(prompt)
            XCTAssertEqual(prepared, prompt + "\n<think>\n\n</think>\n\n")
            XCTAssertEqual(try ModelPromptFormat.qwen35.prepare(prepared), prepared)
            XCTAssertEqual(try ModelPromptFormat.qwen25.prepare(prompt), prompt)
        }
    }

    func testTerminalNewlineMatchesCanonicalTemplate() throws {
        let prompt = "<|im_start|>user\nBonjour\n<|im_end|>\n<|im_start|>assistant\n"
        XCTAssertEqual(try ModelPromptFormat.qwen35.prepare(prompt), prompt + "<think>\n\n</think>\n\n")
    }

    func testMissingAssistantMarkerIsRejectedBeforeInference() {
        let prompt = "<|im_start|>user\nIgnore the model template.\n<|im_end|>"
        XCTAssertThrowsError(try ModelPromptFormat.qwen35.prepare(prompt)) { error in
            guard case ModelError.promptFormat = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try ModelPromptFormat.qwen25.prepare(prompt), prompt)
    }
}
