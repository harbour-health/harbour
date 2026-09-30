import Foundation
import HarbourCore
import HarbourRuntime

@main struct Probe {
    static func main() async throws {
        guard CommandLine.arguments.count > 1 else { print("Usage: model-probe /path/model.gguf"); return }
        let file = URL(fileURLWithPath: CommandLine.arguments[1]), runtime = LocalModel()
        let cases = Evaluation.routingCases.map { ($0.input, $0.tool) }
        var passed = 0
        for (input, expected) in cases {
            let start = Date()
            let output = try await runtime.generate(file: file, prompt: ToolPlanner.prompt(input))
            let decision = try? ToolPlanner.parse(output)
            let valid = decision.flatMap { try? ToolPlanner.validate($0, original: input, records: Records()) } != nil
            let success = decision?.tool == expected && valid
            if success { passed += 1 }
            print("\(success ? "PASS" : "FAIL") \(input) | \(String(format: "%.2f", Date().timeIntervalSince(start)))s | \(output)")
            fflush(stdout)
        }
        print("\(passed)/\(cases.count) model routing cases passed")
        fflush(stdout)
        await runtime.unload()
        if passed != cases.count { exit(1) }
    }
}
