import Foundation
import HarbourCore
import HarbourRuntime

/// Routing generations and source validation remain separate; no generated dose is trusted.
enum MedicationNameEvaluation {
    struct Fixture: Codable {
        let name: String
        let input: String
        let tool: Tool
        let medicine: String?
        let mustReject: Bool
    }

    struct Result: Codable {
        let fixture: Fixture
        let rawOutput: String
        let chosenTool: Tool?
        let validatedMedicine: String?
        let validationError: String?
        let passed: Bool
        let seconds: Double
    }

    struct Report: Codable {
        let modelFile: String
        let created: Date
        let protocolDescription: String
        let results: [Result]
    }

    static func run(file: URL, dataset: URL, destination: URL) async throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: dataset))
        let runtime = LocalModel(useGPU: true)
        var results: [Result] = []
        for fixture in fixtures {
            let start = Date()
            let raw = try await runtime.generate(
                file: file,
                prompt: ToolPlanner.prompt(fixture.input, records: Records()),
                grammar: ToolOutputGrammar.make(allowedTools: ToolPlanner.availableTools.map(\.rawValue))
            )
            let decision = try? ToolPlanner.parse(raw)
            var name: String?, error: String?
            if let decision, decision.tool != .reply {
                do {
                    if case let .add(medicine, _, _) = try ToolPlanner.validate(
                        decision,
                        original: fixture.input,
                        records: Records()
                    ) {
                        name = medicine.name
                    }
                } catch let problem { error = String(describing: problem) }
            }
            let identity = fixture.medicine
                .map { MedicationVocabulary.key(name ?? "") == MedicationVocabulary.key($0) } ?? (name == nil)
            let passed = decision?.tool == fixture.tool && identity && (!fixture.mustReject || error != nil)
            results.append(Result(
                fixture: fixture,
                rawOutput: raw,
                chosenTool: decision?.tool,
                validatedMedicine: name,
                validationError: error,
                passed: passed,
                seconds: Date().timeIntervalSince(start)
            ))
            print("\(passed ? "PASS" : "FAIL") \(fixture.name): \(raw) | \(name ?? error ?? "no medicine write")")
            fflush(stdout)
        }
        let report = Report(
            modelFile: file.lastPathComponent,
            created: Date(),
            protocolDescription: "Actual local greedy grammar-constrained routing, followed by the app's source validator and exact DPD lookup. Empty records. No reply narration, audio, acoustic accuracy, visit summary or dose correctness is evaluated. Phonetic names must be rejected, never automatically substituted.",
            results: results
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: destination)
        print("\(results.filter(\.passed).count)/\(results.count) passed")
    }
}
