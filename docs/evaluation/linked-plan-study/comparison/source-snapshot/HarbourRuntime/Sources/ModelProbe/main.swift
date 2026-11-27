import Foundation
import HarbourCore
import HarbourRuntime

@main struct Probe {
    static func main() async throws {
        guard CommandLine.arguments.count > 1 else { print("Usage: model-probe /path/model.gguf [--cpu] [--transcripts-only]"); return }
        if CommandLine.arguments.contains("--rescore-suite") {
            func argument(_ flag: String) -> URL { URL(fileURLWithPath: CommandLine.arguments[CommandLine.arguments.firstIndex(of: flag)! + 1]) }
            try TextEvaluation.rescore(dataset: argument("--dataset"), source: argument("--report"), destination: argument("--output"))
            return
        }
        if CommandLine.arguments.contains("--correct-routing") {
            func argument(_ flag: String) -> URL { URL(fileURLWithPath: CommandLine.arguments[CommandLine.arguments.firstIndex(of: flag)! + 1]) }
            try TextEvaluation.correctRouting(source: argument("--report"), destination: argument("--output"))
            return
        }
        let file = URL(fileURLWithPath: CommandLine.arguments[1]), runtime = LocalModel(useGPU: !CommandLine.arguments.contains("--cpu"))
        if CommandLine.arguments.contains("--linked-suite") {
            func argument(_ flag: String) -> URL { URL(fileURLWithPath: CommandLine.arguments[CommandLine.arguments.firstIndex(of: flag)! + 1]) }
            try await LinkedInstructionEvaluation.run(file: file, dataset: argument("--dataset"), destination: argument("--output"), audit: CommandLine.arguments.contains("--audit"))
            return
        }
        if CommandLine.arguments.contains("--instructions-suite") {
            func argument(_ flag: String) -> String { CommandLine.arguments[CommandLine.arguments.firstIndex(of: flag)! + 1] }
            func optional(_ flag: String) -> String? { CommandLine.arguments.firstIndex(of: flag).map { CommandLine.arguments[$0 + 1] } }
            try await InstructionEvaluation.run(file: file, dataset: URL(fileURLWithPath: argument("--dataset")), destination: URL(fileURLWithPath: argument("--output")), sampling: ModelSampling(temperature: optional("--temperature").flatMap(Float.init) ?? 0, seed: optional("--seed").flatMap(UInt32.init) ?? 42))
            return
        }
        if CommandLine.arguments.contains("--titles-suite") {
            func argument(_ flag: String) -> URL { URL(fileURLWithPath: CommandLine.arguments[CommandLine.arguments.firstIndex(of: flag)! + 1]) }
            try await TextEvaluation.runTitles(file: file, dataset: argument("--dataset"), destination: argument("--output"))
            return
        }
        if CommandLine.arguments.contains("--narration-suite") {
            func argument(_ flag: String) -> String { CommandLine.arguments[CommandLine.arguments.firstIndex(of: flag)! + 1] }
            func optional(_ flag: String) -> String? { CommandLine.arguments.firstIndex(of: flag).map { CommandLine.arguments[$0 + 1] } }
            let sampling = ModelSampling(temperature: optional("--temperature").flatMap(Float.init) ?? 0, seed: optional("--seed").flatMap(UInt32.init) ?? 42)
            try await TextEvaluation.runNarration(file: file, dataset: URL(fileURLWithPath: argument("--dataset")), destination: URL(fileURLWithPath: argument("--output")), sampling: sampling)
            return
        }
        if CommandLine.arguments.contains("--focused-suite") {
            func argument(_ flag: String) -> String { CommandLine.arguments[CommandLine.arguments.firstIndex(of: flag)! + 1] }
            func optional(_ flag: String) -> String? { CommandLine.arguments.firstIndex(of: flag).map { CommandLine.arguments[$0 + 1] } }
            let sampling = ModelSampling(temperature: optional("--temperature").flatMap(Float.init) ?? 0, seed: optional("--seed").flatMap(UInt32.init) ?? 42)
            try await TextEvaluation.runFocused(file: file, dataset: URL(fileURLWithPath: argument("--dataset")), destination: URL(fileURLWithPath: argument("--output")), sampling: sampling, audit: CommandLine.arguments.contains("--audit"))
            return
        }
        if CommandLine.arguments.contains("--text-suite") {
            func argument(_ flag: String) -> String { CommandLine.arguments[CommandLine.arguments.firstIndex(of: flag)! + 1] }
            try await TextEvaluation.run(file: file, dataset: URL(fileURLWithPath: argument("--dataset")), destination: URL(fileURLWithPath: argument("--output")))
            return
        }
        let transcriptsOnly = CommandLine.arguments.contains("--transcripts-only")
        let cases = transcriptsOnly ? [] : Evaluation.routingCases.map { ($0.input, $0.tool) }
        var passed = 0
        for (input, expected) in cases {
            let start = Date()
            let output = try await runtime.generate(file: file, prompt: ToolPlanner.prompt(input, records: Evaluation.records), grammar: ToolOutputGrammar.make(allowedTools: ToolPlanner.availableTools.map(\.rawValue)))
            var decision = try? ToolPlanner.parse(output)
            if decision?.tool == .reply { decision?.arg = try await runtime.generate(file: file, prompt: ToolPlanner.conversationPrompt(input, records: Evaluation.records), maxTokens: 512, stopAtJSON: false) }
            let valid = decision.flatMap { try? ToolPlanner.validate($0, original: input, records: Evaluation.records) } != nil
            let success = decision?.tool == expected && valid
            if success { passed += 1 }
            print("\(success ? "PASS" : "FAIL") \(input) | \(String(format: "%.2f", Date().timeIntervalSince(start)))s | \(output) | \(decision?.arg ?? "")")
            fflush(stdout)
        }
        if transcriptsOnly { print("Routing cases skipped: transcript-only run") }
        else { print("\(passed)/\(cases.count) model routing cases passed") }
        var transcriptPassed = 0
        for fixture in Evaluation.visitSummaryCases {
            let start = Date()
            do {
                let output = try await runtime.generate(file: file, prompt: VisitReview.prompt(fixture.transcript, medicines: Evaluation.records.medicines), maxTokens: 1536, grammar: VisitSummaryOutputGrammar.make())
                let success = fixture.matches(output)
                if success { transcriptPassed += 1 }
                print("\(success ? "PASS" : "FAIL") transcript: \(fixture.name) | \(String(format: "%.2f", Date().timeIntervalSince(start)))s | \(output)")
            } catch { print("FAIL transcript: \(fixture.name) | \(error)") }
            fflush(stdout)
        }
        print("\(transcriptPassed)/\(Evaluation.visitSummaryCases.count) transcript cases passed")
        fflush(stdout)
        await runtime.unload()
        if passed != cases.count || transcriptPassed != Evaluation.visitSummaryCases.count { exit(1) }
    }
}
