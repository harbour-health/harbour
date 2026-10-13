import Foundation
import HarbourCore
import HarbourRuntime

private struct ProbeAction: Codable {
    var type: String
    var medicineID: String?
    var name: String?
    var instructions: String?
    var kind: String?
    var value: String?
    var unit: String?
    var times: [DoseTime]?
    var frequency: MedicationFrequency?
    var status: String?
    var text: String?
    var medicineIDs: [String]?
}
private extension ProbeAction {
    init(_ action: ValidatedAction) {
        switch action {
        case .appointment(let text): self.init(type: "create_appointment", text: text)
        case .appointments: self.init(type: "list_appointments")
        case .reply(let text): self.init(type: "reply", text: text)
        case .symptom(let text): self.init(type: "capture_symptom", text: text)
        case .add(let medicine, let times, let frequency): self.init(type: "add_medication", medicineID: medicine.id, name: medicine.name, instructions: medicine.instructions, times: times, frequency: frequency)
        case .remove(let medicine): self.init(type: "remove_medication", medicineID: medicine.id, name: medicine.name)
        case .medicines: self.init(type: "list_medications")
        case .interactions(let medicines): self.init(type: "check_interactions", medicineIDs: medicines.map(\.id))
        case .reading(let reading): self.init(type: "log_reading", kind: reading.kind.rawValue, value: reading.value, unit: reading.kind.unit)
        case .readings: self.init(type: "list_readings")
        case .importHealth: self.init(type: "import_readings")
        case .export: self.init(type: "export_data")
        case .note: self.init(type: "copy_note")
        case .clear: self.init(type: "clear_data")
        case .reminder(let text): self.init(type: "create_reminder", text: text)
        case .reminders: self.init(type: "list_reminders")
        case .schedule(let medicine, let times, let frequency): self.init(type: "schedule_medication", medicineID: medicine.id, name: medicine.name, instructions: medicine.instructions, times: times, frequency: frequency)
        case .dose(let medicine, let status): self.init(type: "log_dose", medicineID: medicine.id, name: medicine.name, status: status.rawValue)
        case .timeline(let text): self.init(type: "search_timeline", text: text)
        case .scan: self.init(type: "scan_medication")
        case .question(let text): self.init(type: "save_question", text: text)
        }
    }
}
private struct ProbeResult: Codable {
    let kind: String
    let caseID: String
    let input: String
    let records: Records
    var prompt: String
    var responseGrammar: String
    var budget: Int
    var seconds: Double = 0
    var rawOutput = ""
    var rawTool: String?
    var effectiveTool: String?
    var expectedTool: String?
    var replyPrompt: String?
    var replyOutput: String?
    var acceptedAction: ProbeAction?
    var acceptedSummary: VisitSummary?
    var validationSucceeded = false
    var fixtureMatched = false
    var semanticFixtureMatched = false
    var fallbackUsed = false
    var fallbackReason: String?
    // Routing/reply disposition only; visit summary fallbacks are recorded independently.
    var actionOrigin: String?
    var applicationDecision: ToolDecision?
    var actionValidationSucceeded: Bool?
    var validationError: String?
    var rejectedMedicineProposals: Int?
    var error: String?
}

@main struct Probe {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count > 1 else { print("Usage: model-probe /path/model.gguf [--cpu] [--transcripts-only] [--qwen35] [--report FILE.jsonl]"); return }
        let file = URL(fileURLWithPath: arguments[1]), runtime = LocalModel(useGPU: !arguments.contains("--cpu"))
        let format: ModelPromptFormat = arguments.contains("--qwen35") ? .qwen35 : .qwen25
        let transcriptsOnly = arguments.contains("--transcripts-only")
        var report: FileHandle?
        if let position = arguments.firstIndex(of: "--report") {
            guard position + 1 < arguments.count else { throw NSError(domain: "Probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing --report path."]) }
            let output = URL(fileURLWithPath: arguments[position + 1])
            guard !FileManager.default.fileExists(atPath: output.path) else { throw NSError(domain: "Probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Refusing to overwrite an existing report."]) }
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: output, options: .withoutOverwriting)
            report = try FileHandle(forWritingTo: output)
        }
        defer { try? report?.close() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; encoder.dateEncodingStrategy = .iso8601
        func emit(_ result: ProbeResult) throws {
            guard let report else { return }
            try report.write(contentsOf: encoder.encode(result)); try report.write(contentsOf: Data([10])); try report.synchronize()
        }
        let cases = transcriptsOnly ? [] : Evaluation.routingCases.map { ($0.input, $0.tool) }
        var passed = 0
        for (index, fixture) in cases.enumerated() {
            let (input, expected) = fixture, start = Date(), records = Evaluation.records
            let routingPrompt = ModelPrompts.localized(ToolPlanner.prompt(input, records: records), language: .english, purpose: .routing)
            let grammar = try ToolOutputGrammar.make(allowedTools: ToolPlanner.availableTools.map(\.rawValue))
            var result = ProbeResult(kind: "routing", caseID: "routing.\(index)", input: input, records: records, prompt: try format.prepare(routingPrompt), responseGrammar: grammar, budget: 160, expectedTool: expected.rawValue)
            var decision: ToolDecision?
            do {
                result.rawOutput = try await runtime.generate(file: file, prompt: routingPrompt, grammar: grammar, promptFormat: format)
                decision = try ToolPlanner.parse(result.rawOutput); result.rawTool = decision?.tool.rawValue
                var action: ValidatedAction?
                if let decision, decision.tool != .reply {
                    do { action = try ToolPlanner.validate(decision, original: input, records: records); result.actionValidationSucceeded = true }
                    catch { result.actionValidationSucceeded = false; result.validationError = error.localizedDescription; result.fallbackUsed = true; result.fallbackReason = "invalid_action" }
                }
                if action == nil, let fallback = ToolPlanner.replyFallback(original: input, records: records, language: .english) {
                    action = fallback.action; result.fallbackUsed = true; result.fallbackReason = fallback.reason
                    result.actionOrigin = "application"; result.applicationDecision = fallback.decision
                } else if action == nil {
                    let replyPrompt = ModelPrompts.localized(ToolPlanner.conversationPrompt(input, records: records, language: .english, compactProsePolicy: format.usesCompactProsePolicy), language: .english, purpose: .prose)
                    result.replyPrompt = try format.prepare(replyPrompt)
                    let reply = try await runtime.generate(file: file, prompt: replyPrompt, maxTokens: 512, stopAtJSON: false, promptFormat: format)
                    result.replyOutput = reply
                    action = try ToolPlanner.validate(.init(tool: .reply, arg: reply), original: input, records: records)
                }
                if let action {
                    result.acceptedAction = ProbeAction(action); result.effectiveTool = result.acceptedAction?.type; result.validationSucceeded = true
                    if result.actionOrigin == nil { result.actionOrigin = "model" }
                }
            } catch { result.error = error.localizedDescription }
            result.fixtureMatched = result.rawTool == expected.rawValue && result.validationSucceeded && result.actionValidationSucceeded != false
            result.semanticFixtureMatched = result.fixtureMatched
            if result.fixtureMatched { passed += 1 }
            result.seconds = Date().timeIntervalSince(start)
            print("\(result.fixtureMatched ? "PASS" : "FAIL") \(input) | \(String(format: "%.2f", result.seconds))s | \(result.rawOutput) | \(result.replyOutput ?? "")")
            fflush(stdout); try emit(result)
        }
        if transcriptsOnly { print("Routing cases skipped: transcript-only run") }
        else { print("\(passed)/\(cases.count) model routing cases passed") }
        var transcriptPassed = 0
        for fixture in Evaluation.visitSummaryCases {
            let start = Date(), records = Evaluation.records
            let language: ModelLanguage = fixture.name.contains("French") ? .french : .english
            let prompt = ModelPrompts.localized(try VisitReview.prompt(fixture.transcript, medicines: records.medicines), language: language, purpose: .visit)
            let grammar = VisitReview.outputGrammar(transcript: fixture.transcript, medicines: Evaluation.records.medicines)
            var result = ProbeResult(kind: "visit", caseID: fixture.name, input: fixture.transcript, records: records, prompt: try format.prepare(prompt), responseGrammar: grammar, budget: 650)
            do {
                result.rawOutput = try await runtime.generate(file: file, prompt: prompt, maxTokens: 650, grammar: grammar, promptFormat: format)
                let summary = try VisitReview.parse(result.rawOutput, transcript: fixture.transcript, medicines: records.medicines)
                result.acceptedSummary = summary; result.validationSucceeded = true
                result.fixtureMatched = fixture.matches(result.rawOutput)
                result.semanticFixtureMatched = fixture.matches(result.rawOutput, allowTerminalPeriodEquivalence: true)
                if let first = result.rawOutput.firstIndex(of: "{"), let last = result.rawOutput.lastIndex(of: "}"), first <= last,
                   let raw = try? JSONSerialization.jsonObject(with: Data(result.rawOutput[first...last].utf8)) as? [String: Any] {
                    let medicines = raw["medicines"] as? [[String: Any]] ?? []
                    result.rejectedMedicineProposals = max(0, medicines.count - summary.medicines.count)
                    func quotes(_ field: String) -> Set<String> { Set((raw[field] as? [[String: String]] ?? []).compactMap { $0["quote"] }.map(VisitReview.normalise)) }
                    result.fallbackUsed = !Set(summary.followUps.map(\.quote)).isSubset(of: quotes("followUps")) || !Set((summary.appointments ?? []).map(\.quote)).isSubset(of: quotes("appointments"))
                }
                if result.fixtureMatched { transcriptPassed += 1 }
                result.seconds = Date().timeIntervalSince(start)
                print("\(result.fixtureMatched ? "PASS" : "FAIL") transcript: \(fixture.name) | \(String(format: "%.2f", result.seconds))s | \(result.rawOutput)")
            } catch {
                result.error = error.localizedDescription; result.seconds = Date().timeIntervalSince(start)
                print("FAIL transcript: \(fixture.name) | \(error)")
            }
            fflush(stdout); try emit(result)
        }
        print("\(transcriptPassed)/\(Evaluation.visitSummaryCases.count) transcript cases passed")
        fflush(stdout)
        await runtime.unload()
        if passed != cases.count || transcriptPassed != Evaluation.visitSummaryCases.count { exit(1) }
    }
}
