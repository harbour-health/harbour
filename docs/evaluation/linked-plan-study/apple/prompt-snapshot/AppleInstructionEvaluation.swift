#if canImport(FoundationModels)
import Foundation
import FoundationModels
import HarbourCore

@available(macOS 26, iOS 26, *)
@Generable private struct AppleInstructionEnvelope: Codable {
    @Generable enum Kind: String, Codable { case medication, followUp, appointment, reminder }
    @Generable enum Scope: String, Codable { case affirmed, negated, conditional, historical, uncertain }
    @Generable struct Step: Codable {
        var source: Int
        var text: String
        var condition: String
        var timing: String
        var repetition: String
        var duration: String
        var after: Int?
    }
    @Generable struct Plan: Codable {
        var kind: Kind
        var subject: String
        var action: String
        var scope: Scope
        var sources: [Int]
        var steps: [Step]
    }
    var plans: [Plan]
}

@available(macOS 26, iOS 26, *)
enum AppleInstructionEvaluation {
    static func run(dataset: URL, destination: URL) async throws {
        let fixtures = try JSONDecoder().decode(InstructionEvaluation.Dataset.self, from: Data(contentsOf: dataset))
        var report = InstructionEvaluation.Report(model: "Apple SystemLanguageModel.default", protocolDescription: "Apple on-device Foundation Models; default guardrails; greedy; 2048 response tokens; native @Generable schema. Same typed-plan task instructions and shared evidence/scoring checks as Qwen. Framework adds system instructions and schema; not a byte-identical prompt/runtime comparison. No guardrail circumvention or cloud model. OS: \(ProcessInfo.processInfo.operatingSystemVersionString). Availability: \(SystemLanguageModel.default.availability)", runs: [])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        for fixture in fixtures.cases {
            let start = Date(); var output = ""; var plans: [InstructionPlan] = []; var failure: String?
            do {
                // Translate the same single system/user turn into the native API, not ChatML text.
                let prompt = try InstructionPlans.prompt(fixture.input)
                let systemPrefix = "<|im_start|>system\n", userMarker = "\n<|im_end|>\n<|im_start|>user\n"
                guard let userStart = prompt.range(of: userMarker), let userEnd = prompt.range(of: "\n<|im_end|>\n<|im_start|>assistant") else { throw InstructionPlans.Failure.invalidOutput }
                let instructions = String(prompt[prompt.index(prompt.startIndex, offsetBy: systemPrefix.count)..<userStart.lowerBound])
                let user = String(prompt[userStart.upperBound..<userEnd.lowerBound])
                let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
                let response = try await session.respond(to: user, generating: AppleInstructionEnvelope.self,
                    options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 2048))
                output = String(decoding: try encoder.encode(response.content), as: UTF8.self)
                plans = try InstructionPlans.parse(output, source: fixture.input)
            } catch { failure = String(describing: error) }
            let failures = InstructionEvaluation.score(plans, expected: fixture.expected)
            let run = InstructionEvaluation.Run(id: fixture.id, language: fixture.language, group: fixture.group,
                seconds: Date().timeIntervalSince(start), input: fixture.input, output: output, valid: failure == nil,
                passed: failure == nil && failures.isEmpty, plans: plans, failures: failures, error: failure)
            report.runs.append(run)
            try encoder.encode(report).write(to: destination, options: .atomic)
            print("\(fixture.id) \(run.passed ? "PASS" : "FAIL") \(String(format: "%.1f", run.seconds))s \(failure ?? failures.joined(separator: "; "))"); fflush(stdout)
        }
    }
}
#endif
