import Foundation

/// The app builds ChatML messages itself; the runtime does not apply a GGUF chat template.
public enum ModelPromptFormat: Sendable {
    case qwen25, qwen35

    /// Qwen2.5 uses the compact conversational policy shared by Small and Balanced.
    public var usesCompactProsePolicy: Bool { self == .qwen25 }

    /// Small and Balanced retain their established routing prompt; weights never choose by source content.
    public var usesLegacyRoutingPrompt: Bool { self == .qwen25 }

    public func prepare(_ prompt: String) throws -> String {
        guard self == .qwen35 else { return prompt }
        let assistant = "<|im_start|>assistant"
        // Matches Qwen3.5's tokenizer template with enable_thinking=false.
        let nonThinking = "\n<think>\n\n</think>\n\n"
        if prompt.hasSuffix(assistant + nonThinking) { return prompt }
        var result = prompt
        while let last = result.last, last.isWhitespace { result.removeLast() }
        guard result.hasSuffix(assistant) else { throw ModelError.promptFormat }
        return result + nonThinking
    }
}
