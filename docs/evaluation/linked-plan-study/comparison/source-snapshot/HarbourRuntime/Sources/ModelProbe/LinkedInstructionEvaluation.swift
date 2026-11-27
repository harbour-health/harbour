import Foundation
import HarbourCore
import HarbourRuntime

/// Benchmark-only pipeline: narrow extraction, additive coverage review, then model-selected linking.
enum LinkedInstructionEvaluation {
    struct Call: Codable { var stage: String; var unit: Int?; var prompt: String; var output: String; var error: String? }
    struct Run: Codable {
        var id: String; var language: String; var group: String; var effort: String; var seconds: Double
        var passed: Bool; var valid: Bool; var needsReview: Bool
        var atoms: [LinkedInstructionPlans.Atom]; var plans: [InstructionPlan]
        var failures: [String]; var calls: [Call]
    }
    struct Report: Codable { var model: String; var protocolDescription: String; var runs: [Run] }
    static func run(file: URL, dataset: URL, destination: URL, audit: Bool) async throws {
        let fixtures = try JSONDecoder().decode(InstructionEvaluation.Dataset.self, from: Data(contentsOf: dataset))
        let runtime = LocalModel(useGPU: true)
        var report = Report(model: file.lastPathComponent, protocolDescription: "Experimental per-unit model extraction and model-selected grouping. Coverage review=\(audit). Greedy, 4096 context; 1536 extraction and 512 linking output tokens. No source-based fact recovery; only model-proposed atoms can be linked. Validation does not establish completeness or clinical safety. Fresh authored cases, no clinician review.", runs: [])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        for fixture in fixtures.cases {
            let started = Date(); var atoms: [LinkedInstructionPlans.Atom] = []; var plans: [InstructionPlan] = []
            var calls: [Call] = []; var errors: [String] = []; var concern = false
            for reviewing in audit ? [false, true] : [false] {
                for unit in InstructionPlans.sources(fixture.input) {
                    var prompt = "", output = "", error: String?
                    do {
                        prompt = try LinkedInstructionPlans.extractionPrompt(source: fixture.input, unit: unit.id,
                            existing: reviewing ? atoms.filter { $0.source == unit.id } : nil)
                        output = try await runtime.generate(file: file, prompt: prompt, maxTokens: 1536, grammar: LinkedInstructionPlans.extractionGrammar)
                        let result = try LinkedInstructionPlans.parseAtoms(output, source: fixture.input, unit: unit.id)
                        concern = concern || result.concern
                        for atom in result.atoms where !atoms.contains(atom) { atoms.append(atom) }
                    } catch let failure { error = String(describing: failure); errors.append("unit \(unit.id): \(failure)"); concern = true }
                    calls.append(Call(stage: reviewing ? "coverage" : "extraction", unit: unit.id, prompt: prompt, output: output, error: error))
                }
            var prompt = "", output = "", error: String?
            do {
                prompt = try LinkedInstructionPlans.linkingPrompt(atoms: atoms)
                output = try await runtime.generate(file: file, prompt: prompt, maxTokens: 512, grammar: LinkedInstructionPlans.linkingGrammar)
                plans = try LinkedInstructionPlans.link(output, atoms: atoms, source: fixture.input)
            } catch let failure { error = String(describing: failure); concern = true }
            calls.append(Call(stage: "linking", unit: nil, prompt: prompt, output: output, error: error))
            let failures = InstructionEvaluation.score(plans, expected: fixture.expected)
            // An abstention/review flag never earns a correctness pass.
            let run = Run(id: fixture.id, language: fixture.language, group: fixture.group, effort: reviewing ? "coverage" : "linked", seconds: Date().timeIntervalSince(started),
                passed: errors.isEmpty && error == nil && failures.isEmpty, valid: errors.isEmpty && error == nil, needsReview: concern,
                atoms: atoms, plans: plans, failures: errors + (error.map { ["link: " + $0] } ?? []) + failures, calls: calls)
            report.runs.append(run)
            try encoder.encode(report).write(to: destination, options: .atomic)
            print("\(fixture.id) \(run.effort) \(run.passed ? "PASS" : "FAIL") \(String(format: "%.1f", run.seconds))s review=\(concern) \(run.failures.joined(separator: "; "))"); fflush(stdout)
            }
        }
        await runtime.unload()
    }
}
