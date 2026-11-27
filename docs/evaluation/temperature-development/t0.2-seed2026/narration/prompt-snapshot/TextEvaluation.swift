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
                    success = decision.tool == fixture.tool && (decision.tool == .reply || (try? ToolPlanner.validate(decision, original: fixture.input, records: Evaluation.records)) != nil)
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
                        summary.merge(try LegacySourceRecovery.parse(output, transcript: chunk, medicines: savedMedicines))
                    }
                } catch let failure { error = String(describing: failure) }
                let validated = facts(summary)
                let finalSummary = baseline ? summary : LegacySourceRecovery.complete(summary, transcript: fixture.input, medicines: savedMedicines)
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

extension TextEvaluation {
    /// Revalidates preserved generations without claiming a second model run or new latency measurement.
    static func rescore(dataset: URL, source: URL, destination: URL) throws {
        let fixtures = try JSONDecoder().decode(Dataset.self, from: Data(contentsOf: dataset))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var report = try decoder.decode(Report.self, from: Data(contentsOf: source))
        for index in report.runs.indices where report.runs[index].category == "medical" {
            guard let fixture = fixtures.medical.first(where: { $0.name == report.runs[index].name }) else { continue }
            var summary = VisitSummary(); var error: String?
            let saved = (fixture.savedMedicineIDs ?? []).compactMap { Catalog.resolve($0) }
            let chunks = VisitReview.chunks(fixture.input)
            let outputs = report.runs[index].output
            if chunks.count != outputs.count { error = "Incomplete original generation" }
            do { for (chunk, output) in zip(chunks, outputs) { summary.merge(try LegacySourceRecovery.parse(output, transcript: chunk, medicines: saved)) } }
            catch let failure { error = String(describing: failure) }
            let validated = facts(summary)
            let final = report.runs[index].effort == "baseline" ? summary : LegacySourceRecovery.complete(summary, transcript: fixture.input, medicines: saved)
            let completed = facts(final)
            let expected = Set(report.runs[index].expectedCompletedFacts ?? [])
            let unknownReviewPassed = fixture.expected.medicines.filter { Catalog.resolve($0.name) == nil }.allSatisfy { medicine in
                (final.unconfirmedMedicines ?? []).contains { normal($0.text ?? "").contains(normal(medicine.name)) && normal($0.quote).contains(normal(medicine.instructions)) }
            }
            report.runs[index].validatedFacts = validated.sorted(); report.runs[index].completedFacts = completed.sorted()
            report.runs[index].passed = error == nil && completed == expected && unknownReviewPassed
            report.runs[index].error = error
        }
        report.protocolDescription += " VALIDATION-ONLY REPLAY: original generations and latencies retained; current validation/source-completeness code reapplied. Not a fresh inference run. Original report remains alongside this file."
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: destination, options: .atomic)
    }
}

extension TextEvaluation {
    static func runFocused(file: URL, dataset: URL, destination: URL, sampling: ModelSampling = .greedy) async throws {
        let fixtures = try JSONDecoder().decode(Dataset.self, from: Data(contentsOf: dataset))
        let runtime = LocalModel(useGPU: true)
        var report = Report(model: file.lastPathComponent, started: .now, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, processors: ProcessInfo.processInfo.processorCount, memoryBytes: ProcessInfo.processInfo.physicalMemory,
                            protocolDescription: "Focused model-only extraction: medicines, followUps/appointments, highlights, per source chunk. Local Metal,4096 context,1536/1024/768 token limits. No source recovery; validators only reject candidates. Raw facts and accepted facts are separate. Exact-field scoring is not clinical validation. Development results are not held-out results. Dataset role and description: " + fixtures.description + " Temperature=" + String(sampling.temperature) + ",seed=" + String(sampling.seed) + ",topP=" + String(sampling.topP) + ",topK=" + String(sampling.topK), runs: [])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        for fixture in fixtures.medical {
            let started = Date(); let saved = (fixture.savedMedicineIDs ?? []).compactMap { Catalog.resolve($0) }
            var summary = VisitSummary(); var raw = Set<String>(); var outputs: [String] = []; var errors: [String] = []
            for chunk in VisitReview.chunks(fixture.input) {
                for pass in VisitExtractionPass.allCases {
                    do {
                        let output = try await runtime.generate(file: file, prompt: VisitReview.focusedPrompt(pass, transcript: chunk, medicines: saved), maxTokens: pass.tokenBudget, grammar: VisitSummaryOutputGrammar.make(section: pass.rawValue), sampling: sampling)
                        outputs.append(output); raw.formUnion(rawFacts(output))
                        summary.merge(try VisitReview.parsePass(output, pass: pass, transcript: chunk, medicines: saved))
                    } catch { errors.append(pass.rawValue + ": " + String(describing: error)) }
                }
            }
            let expected = Set(fixture.expected.medicines.map { fact($0.action, $0.name, $0.instructions) } + fixture.expected.followUps.map { "followUp|\(normal($0))" } + fixture.expected.appointments.map { "appointment|\(normal($0))" })
            let expectedCompleted = Set(expected.filter { value in !fixture.expected.medicines.contains { Catalog.resolve($0.name) == nil && fact($0.action, $0.name, $0.instructions) == value } })
            let unknownPassed = fixture.expected.medicines.filter { Catalog.resolve($0.name) == nil }.allSatisfy { medicine in
                (summary.unconfirmedMedicines ?? []).contains { normal($0.text ?? "").contains(normal(medicine.name)) && normal($0.text ?? "").contains(normal(medicine.instructions)) }
            }
            let accepted = facts(summary)
            report.runs.append(Run(category: "medical", name: fixture.name, effort: "focused", seconds: Date().timeIntervalSince(started), output: outputs, passed: errors.isEmpty && accepted == expectedCompleted && unknownPassed, error: errors.isEmpty ? nil : errors.joined(separator: "; "), expectedFacts: expected.sorted(), expectedCompletedFacts: expectedCompleted.sorted(), rawFacts: raw.sorted(), validatedFacts: accepted.sorted(), completedFacts: accepted.sorted()))
            try encoder.encode(report).write(to: destination, options: .atomic)
            print("\(report.runs.count) \(report.runs.last!.passed ? "PASS" : "FAIL") \(fixture.name) \(String(format: "%.2f", Date().timeIntervalSince(started)))s"); fflush(stdout)
        }
        await runtime.unload()
    }
}

extension TextEvaluation {
    static func runNarration(file: URL, dataset: URL, destination: URL, sampling: ModelSampling = .greedy) async throws {
        let fixtures = try JSONDecoder().decode(Dataset.self, from: Data(contentsOf: dataset))
        let runtime = LocalModel(useGPU: true)
        var report = Report(model: file.lastPathComponent, started: .now, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, processors: ProcessInfo.processInfo.processorCount, memoryBytes: ProcessInfo.processInfo.physicalMemory,
                            protocolDescription: "Focused tool-result narration; actual result after request/history; local Metal. Pattern checks are not semantic or clinical validation. Temperature=" + String(sampling.temperature) + ",seed=" + String(sampling.seed) + ". " + fixtures.description, runs: [])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        for (effort, limit) in [("Quick",256),("Standard",512),("Extended",768)] {
            for fixture in fixtures.toolResults {
                let start = Date(); var output = ""; var error: String?
                do { output = try await runtime.generate(file: file, prompt: ToolPlanner.toolResultPrompt(fixture.payload, history: [ConversationTurn(isUser: true, text: fixture.input)]), maxTokens: limit, stopAtJSON: false, sampling: sampling) }
                catch let failure { error = String(describing: failure) }
                report.runs.append(Run(category: "tool-result", name: fixture.name, effort: effort, seconds: Date().timeIntervalSince(start), output: [output], passed: error == nil && matches(output, required: fixture.requiredPatterns, forbidden: fixture.forbiddenPatterns), error: error))
                try encoder.encode(report).write(to: destination, options: .atomic)
                print("\(report.runs.count) \(report.runs.last!.passed ? "PASS" : "FAIL") \(fixture.name)/\(effort)"); fflush(stdout)
            }
        }
        await runtime.unload()
    }
}

extension TextEvaluation {
    static func correctRouting(source: URL, destination: URL) throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var report = try decoder.decode(Report.self, from: Data(contentsOf: source))
        for index in report.runs.indices where report.runs[index].category == "routing" {
            guard let fixture = Evaluation.routingCases.first(where: { $0.input == report.runs[index].name }) else { continue }
            do {
                let decision = try ToolPlanner.parse(report.runs[index].output.first ?? "")
                report.runs[index].passed = decision.tool == fixture.tool && (decision.tool == .reply || (try? ToolPlanner.validate(decision, original: fixture.input, records: Evaluation.records)) != nil)
            } catch { report.runs[index].passed = false; report.runs[index].error = String(describing: error) }
        }
        report.protocolDescription += " ROUTING GRADING CORRECTION: a correct reply choice needs no reply text at the routing-only stage; conversation is evaluated separately. Original generations/latencies and medical scores retained. Non-reply calls use current source validation."
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: destination, options: .atomic)
    }
}
