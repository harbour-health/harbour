import Foundation
import HarbourCore
import HarbourRuntime

@main struct Probe {
    static func main() async throws {
        guard CommandLine.arguments.count > 1 else { print("Usage: model-probe /path/model.gguf [--qwen35]"); return }
        let file = URL(fileURLWithPath: CommandLine.arguments[1]), runtime = LocalModel()
        let format: ModelPromptFormat = CommandLine.arguments.contains("--qwen35") ? .qwen35 : .qwen25
        let cases = Evaluation.routingCases.map { ($0.input, $0.tool) }
        var passed = 0
        for (input, expected) in cases {
            let start = Date()
            let output = try await runtime.generate(file: file, prompt: ToolPlanner.prompt(input, records: Evaluation.records), grammar: ToolOutputGrammar.make(allowedTools: ToolPlanner.availableTools.map(\.rawValue)), promptFormat: format)
            var decision = try? ToolPlanner.parse(output)
            if decision?.tool == .reply { decision?.arg = try await runtime.generate(file: file, prompt: ToolPlanner.conversationPrompt(input, records: Evaluation.records), maxTokens: 512, stopAtJSON: false, promptFormat: format) }
            let valid = decision.flatMap { try? ToolPlanner.validate($0, original: input, records: Evaluation.records) } != nil
            let success = decision?.tool == expected && valid
            if success { passed += 1 }
            print("\(success ? "PASS" : "FAIL") \(input) | \(String(format: "%.2f", Date().timeIntervalSince(start)))s | \(output) | \(decision?.arg ?? "")")
            fflush(stdout)
        }
        print("\(passed)/\(cases.count) model routing cases passed")
        fflush(stdout)
        await runtime.unload()
        if passed != cases.count { exit(1) }
    }
}
