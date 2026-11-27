import Foundation
import HarbourCore
import HarbourRuntime

/// Experimental only: preserves raw generations and validation failures separately.
enum InstructionEvaluation {
    struct Expected: Codable { var subject: String; var kind: String; var scope: String; var steps: Int; var required: [String]; var action: String?; var conditions: [String]?; var timings: [String]?; var repetitions: [String]?; var durations: [String]? }
    struct Fixture: Codable { var id: String; var language: String; var group: String; var input: String; var expected: [Expected] }
    struct Dataset: Codable { var cases: [Fixture] }
    struct Run: Codable {
        var id: String; var language: String; var group: String; var seconds: Double
        var input: String; var output: String; var valid: Bool; var passed: Bool
        var plans: [InstructionPlan]; var failures: [String]; var error: String?
    }
    struct Report: Codable { var model: String; var protocolDescription: String; var runs: [Run] }
    static func score(_ plans: [InstructionPlan], expected: [Expected]) -> [String] {
            var failures: [String] = []
            if plans.count != expected.count { failures.append("plan count \(plans.count), expected \(expected.count)") }
            var remaining = plans
            for expected in expected {
                let eligible = remaining.indices.filter { remaining[$0].subject.lowercased() == expected.subject.lowercased() && remaining[$0].kind.rawValue == expected.kind }
                let best = eligible.first { index in
                    let text = remaining[index].steps.map(\.text).joined(separator: " ")
                    return expected.required.allSatisfy { text.range(of: $0, options: .caseInsensitive) != nil }
                } ?? eligible.first
                guard let index = best else {
                    failures.append("missing \(expected.kind):\(expected.subject)"); continue
                }
                let plan = remaining.remove(at: index)
                if let action = expected.action, plan.action != action { failures.append("\(expected.subject): action \(plan.action), expected \(action)") }
                for (label, required, actual) in [
                    ("condition", expected.conditions ?? [], plan.steps.map(\.condition)),
                    ("timing", expected.timings ?? [], plan.steps.map(\.timing)),
                    ("repetition", expected.repetitions ?? [], plan.steps.map(\.repetition)),
                    ("duration", expected.durations ?? [], plan.steps.map(\.duration))
                ] {
                    for value in required where !actual.contains(where: { $0.range(of: value, options: .caseInsensitive) != nil }) {
                        failures.append("\(expected.subject): missing structured \(label) \(value)")
                    }
                }
                if plan.scope.rawValue != expected.scope { failures.append("\(expected.subject): scope \(plan.scope.rawValue), expected \(expected.scope)") }
                if plan.steps.count != expected.steps { failures.append("\(expected.subject): \(plan.steps.count) phases, expected \(expected.steps)") }
                let details = plan.steps.map { [$0.text, $0.condition, $0.timing, $0.repetition, $0.duration].joined(separator: " ") }.joined(separator: " ")
                for required in expected.required where details.range(of: required, options: .caseInsensitive) == nil { failures.append("\(expected.subject): missing \(required)") }
                if plan.steps.count > 1 && plan.steps.dropFirst().enumerated().contains(where: { $0.element.after != $0.offset }) { failures.append("\(expected.subject): unlinked phases") }
            }
            return failures
    }
    static func run(file: URL, dataset: URL, destination: URL, sampling: ModelSampling) async throws {
        let fixtures = try JSONDecoder().decode(Dataset.self, from: Data(contentsOf: dataset))
        let model = LocalModel(useGPU: true)
        var report = Report(model: file.lastPathComponent,
            protocolDescription: "Experimental typed plans; 4096 context; 2048 output tokens; source references are selected by the model. No deterministic fact additions. Exact scope, count, ordered phase and required-detail checks; not clinical validation or directly comparable to the legacy summary representation.", runs: [])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        for fixture in fixtures.cases {
            let started = Date(); var output = ""; var plans: [InstructionPlan] = []; var failure: String?
            do {
                output = try await model.generate(file: file, prompt: InstructionPlans.prompt(fixture.input), maxTokens: 2048, grammar: InstructionPlans.grammar, sampling: sampling)
                plans = try InstructionPlans.parse(output, source: fixture.input)
            } catch { failure = String(describing: error) }
            let failures = score(plans, expected: fixture.expected)
            let result = Run(id: fixture.id, language: fixture.language, group: fixture.group, seconds: Date().timeIntervalSince(started), input: fixture.input, output: output, valid: failure == nil, passed: failure == nil && failures.isEmpty, plans: plans, failures: failures, error: failure)
            report.runs.append(result)
            try encoder.encode(report).write(to: destination, options: .atomic)
            print("\(fixture.id) \(result.passed ? "PASS" : "FAIL") \(String(format: "%.1f", result.seconds))s \(failure ?? failures.joined(separator: "; "))"); fflush(stdout)
        }
        await model.unload()
    }
}
