import Foundation
import HarbourCore
import HarbourRuntime

/// Reproducible text-only probe. Raw generations and each validation stage stay separate.
enum TextEvaluation {
    struct Fact: Codable { var action: String; var name: String; var instructions: String }
    struct Expected: Codable { var medicines: [Fact]; var followUps: [String]; var appointments: [String] }
    struct Medical: Codable { var name: String; var input: String; var expected: Expected; var savedMedicineIDs: [String]? }
    struct Turn: Codable { var isUser: Bool; var text: String }
    struct Conversation: Codable { var name: String; var input: String; var history: [Turn]; var requiredPatterns: [String]; var forbiddenPatterns: [String] }
    struct ResultCase: Codable { var name: String; var input: String; var payload: String; var requiredPatterns: [String]; var forbiddenPatterns: [String] }
    struct Dataset: Codable { var version: Int; var description: String; var medical: [Medical]; var conversations: [Conversation]; var toolResults: [ResultCase] }
    struct Run: Codable {
        var category: String; var name: String; var effort: String; var seconds: Double
        var output: [String]; var passed: Bool; var error: String?
        var expectedFacts: [String]?; var expectedCompletedFacts: [String]?; var rawFacts: [String]?; var validatedFacts: [String]?; var completedFacts: [String]?
    }
    struct Report: Codable {
        var model: String; var started: Date; var operatingSystem: String; var processors: Int; var memoryBytes: UInt64
        var protocolDescription: String; var runs: [Run]
    }
    static func normal(_ text: String) -> String { text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
    static func fact(_ action: String, _ name: String, _ instructions: String) -> String { "medicine|\(normal(action))|\(Catalog.resolve(name)?.id ?? normal(name))|\(normal(instructions))" }
    static func facts(_ summary: VisitSummary) -> Set<String> {
        Set(summary.medicines.map { fact($0.action.rawValue, $0.medicine.name, $0.medicine.instructions) }
            + summary.followUps.map { "followUp|\(normal($0.quote))" }
            + (summary.appointments ?? []).map { "appointment|\(normal($0.quote))" })
    }
    static func rawFacts(_ output: String) -> Set<String> {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start <= end,
              let object = try? JSONSerialization.jsonObject(with: Data(output[start...end].utf8)) as? [String: Any] else { return [] }
        var result = Set<String>()
        for item in object["medicines"] as? [[String: String]] ?? [] { result.insert(fact(item["action"] ?? "", item["name"] ?? "", item["instructions"] ?? "")) }
        for (key, prefix) in [("followUps", "followUp"), ("appointments", "appointment")] {
            for item in object[key] as? [[String: String]] ?? [] { result.insert("\(prefix)|\(normal(item["quote"] ?? ""))") }
        }
        return result
    }
    static func matches(_ output: String, required: [String], forbidden: [String]) -> Bool {
        !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && required.allSatisfy { output.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
        && forbidden.allSatisfy { output.range(of: $0, options: [.regularExpression, .caseInsensitive]) == nil }
    }
    static func run(file: URL, dataset: URL, destination: URL) async throws {
        let fixtures = try JSONDecoder().decode(Dataset.self, from: Data(contentsOf: dataset))
        let runtime = LocalModel(useGPU: true)
        var report = Report(model: file.lastPathComponent, started: .now, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                            processors: ProcessInfo.processInfo.processorCount, memoryBytes: ProcessInfo.processInfo.physicalMemory,
                            protocolDescription: "Greedy local Metal inference; 4096 context. Routing/conversation/tool results: Quick 96/256, Standard 160/512, Extended 256/768 tokens. Medical baseline: commit 7b3a2e0 generation prompt/grammar, 650 tokens. Revised: current prompt/grammar,1536 tokens. Both use CURRENT validators; revised additionally uses source completeness. Exact source-fact and regex checks are not clinical validation. Medical generation has a fixed budget, independent of chat effort.", runs: [])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        func save(_ run: Run) throws {
            report.runs.append(run); try encoder.encode(report).write(to: destination, options: .atomic)
            print("\(report.runs.count) \(run.passed ? "PASS" : "FAIL") \(run.category)/\(run.name)/\(run.effort) \(String(format: "%.2f", run.seconds))s"); fflush(stdout)
        }
        for (effort, routerTokens, replyTokens) in [("Quick", 96, 256), ("Standard", 160, 512), ("Extended", 256, 768)] {
            for fixture in Evaluation.routingCases {
                let start = Date(); var output = ""; var success = false; var error: String?
                do {
                    output = try await runtime.generate(file: file, prompt: ToolPlanner.prompt(fixture.input, records: Evaluation.records), maxTokens: routerTokens, grammar: ToolOutputGrammar.make(allowedTools: ToolPlanner.availableTools.map(\.rawValue)))
                    let decision = try ToolPlanner.parse(output)
                    success = decision.tool == fixture.tool && (try? ToolPlanner.validate(decision, original: fixture.input, records: Evaluation.records)) != nil
                } catch let failure { error = String(describing: failure) }
                try save(Run(category: "routing", name: fixture.input, effort: effort, seconds: Date().timeIntervalSince(start), output: [output], passed: success, error: error))
            }
            for fixture in fixtures.conversations {
                let start = Date(); var output = ""; var error: String?
                do { output = try await runtime.generate(file: file, prompt: ToolPlanner.conversationPrompt(fixture.input, records: Evaluation.records, history: fixture.history.map { ConversationTurn(isUser: $0.isUser, text: $0.text) }), maxTokens: replyTokens, stopAtJSON: false) }
                catch let failure { error = String(describing: failure) }
                try save(Run(category: "conversation", name: fixture.name, effort: effort, seconds: Date().timeIntervalSince(start), output: [output], passed: error == nil && matches(output, required: fixture.requiredPatterns, forbidden: fixture.forbiddenPatterns), error: error))
            }
            for fixture in fixtures.toolResults {
                let start = Date(); var output = ""; var error: String?
                do { output = try await runtime.generate(file: file, prompt: ToolPlanner.toolResultPrompt(fixture.payload, history: [ConversationTurn(isUser: true, text: fixture.input)]), maxTokens: replyTokens, stopAtJSON: false) }
                catch let failure { error = String(describing: failure) }
                try save(Run(category: "tool-result", name: fixture.name, effort: effort, seconds: Date().timeIntervalSince(start), output: [output], passed: error == nil && matches(output, required: fixture.requiredPatterns, forbidden: fixture.forbiddenPatterns), error: error))
            }
        }
        for baseline in [true, false] {
            for fixture in fixtures.medical {
                let savedMedicines = (fixture.savedMedicineIDs ?? []).compactMap { Catalog.resolve($0) }
                let start = Date(); var outputs: [String] = []; var raw = Set<String>(); var summary = VisitSummary(); var error: String?
                let expected = Set(fixture.expected.medicines.map { fact($0.action, $0.name, $0.instructions) } + fixture.expected.followUps.map { "followUp|\(normal($0))" } + fixture.expected.appointments.map { "appointment|\(normal($0))" })
                do {
                    for chunk in VisitReview.chunks(fixture.input) {
                        let prompt = try baseline ? BaselineVisitPrompt.prompt(chunk, medicines: savedMedicines) : VisitReview.prompt(chunk, medicines: savedMedicines)
                        let output = try await runtime.generate(file: file, prompt: prompt, maxTokens: baseline ? 650 : 1536, grammar: baseline ? BaselineVisitGrammar.make() : VisitSummaryOutputGrammar.make())
                        outputs.append(output); raw.formUnion(rawFacts(output))
                        summary.merge(try VisitReview.parse(output, transcript: chunk, medicines: savedMedicines))
                    }
                } catch let failure { error = String(describing: failure) }
                let validated = facts(summary)
                let finalSummary = baseline ? summary : VisitReview.complete(summary, transcript: fixture.input, medicines: savedMedicines)
                let completed = facts(finalSummary)
                // Unknown products must remain review items, never automatically mapped to ingredients.
                let expectedCompleted = Set(expected.filter { value in !fixture.expected.medicines.contains { Catalog.resolve($0.name) == nil && fact($0.action, $0.name, $0.instructions) == value } })
                let unknownReviewPassed = fixture.expected.medicines.filter { Catalog.resolve($0.name) == nil }.allSatisfy { medicine in (finalSummary.unconfirmedMedicines ?? []).contains { normal($0.text ?? "").contains(normal(medicine.name)) && normal($0.quote).contains(normal(medicine.instructions)) } }
                try save(Run(category: "medical", name: fixture.name, effort: baseline ? "baseline" : "revised", seconds: Date().timeIntervalSince(start), output: outputs, passed: error == nil && completed == expectedCompleted && unknownReviewPassed, error: error, expectedFacts: expected.sorted(), expectedCompletedFacts: expectedCompleted.sorted(), rawFacts: raw.sorted(), validatedFacts: validated.sorted(), completedFacts: completed.sorted()))
            }
        }
        await runtime.unload()
    }
}
