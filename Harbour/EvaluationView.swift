import SwiftUI
import HarbourCore
import HarbourRuntime

struct ModelRun: Codable, Identifiable {
    var id = UUID()
    var model: String
    var effort: String
    var input: String
    var expected: String
    var observed: String
    var rawOutput: String
    var elapsedSeconds: Double
    var passed: Bool
}
struct EvaluationReport: Codable {
    var date = Date()
    var device = ProcessInfo.processInfo.operatingSystemVersionString
    var memoryBytes = ProcessInfo.processInfo.physicalMemory
    var thermalState = ProcessInfo.processInfo.thermalState.rawValue
    var checks = Evaluation.checks()
    var runs: [ModelRun] = []
    var complete = false
}
@MainActor enum SimulatorEvaluation {
    static func evaluateVisit(_ fixture: VisitSummaryEvaluationCase, models: ModelManager) async -> ModelRun {
        let start = Date(); var output = ""
        do {
            output = try await models.generate(VisitReview.prompt(fixture.transcript, medicines: Evaluation.records.medicines), maxTokens: 650, responseGrammar: VisitSummaryOutputGrammar.make())
            let passed = fixture.matches(output)
            return ModelRun(model: models.resolved.rawValue, effort: models.effort.rawValue, input: fixture.transcript, expected: fixture.expectedJSON, observed: passed ? "Matched transcript facts" : "Transcript mismatch", rawOutput: output, elapsedSeconds: Date().timeIntervalSince(start), passed: passed)
        } catch {
            return ModelRun(model: models.resolved.rawValue, effort: models.effort.rawValue, input: fixture.transcript, expected: fixture.expectedJSON, observed: error.localizedDescription, rawOutput: output, elapsedSeconds: Date().timeIntervalSince(start), passed: false)
        }
    }
    static func run(models: ModelManager, store: AppStore) async {
        let previousModel = models.selection
        models.selection = ProcessInfo.processInfo.arguments.contains("--evaluate-balanced") ? .balanced : .small
        var report = EvaluationReport()
        let previous = models.effort
        defer { models.effort = previous; models.selection = previousModel }
        let efforts = ProcessInfo.processInfo.arguments.contains("--evaluate-all-efforts") ? Effort.allCases : [previous]
        let destination = store.file.deletingLastPathComponent().appendingPathComponent("model-evaluation-\(models.resolved.rawValue).json")
        func checkpoint() {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do { try encoder.encode(report).write(to: destination, options: [.atomic, .completeFileProtection]) }
            catch { store.error = L10n.string(error.localizedDescription) }
        }
        checkpoint()
        for effort in efforts {
        models.effort = effort
        for fixture in Evaluation.routingCases {
            let start = Date()
            var output = ""
            do {
                output = try await models.generate(ToolPlanner.prompt(fixture.input, records: Evaluation.records), allowedTools: ToolPlanner.availableTools.map(\.rawValue))
                var decision = try ToolPlanner.parse(output)
                if decision.tool == .reply { decision.arg = try await models.generate(ToolPlanner.conversationPrompt(fixture.input, records: Evaluation.records), maxTokens: effort.chatTokens, stopAtJSON: false); output += "\nReply: " + decision.arg }
                _ = try ToolPlanner.validate(decision, original: fixture.input, records: Evaluation.records)
                report.runs.append(ModelRun(model: models.resolved.rawValue, effort: models.effort.rawValue, input: fixture.input, expected: fixture.tool.rawValue, observed: decision.tool.rawValue, rawOutput: output, elapsedSeconds: Date().timeIntervalSince(start), passed: decision.tool == fixture.tool))
            } catch { report.runs.append(ModelRun(model: models.resolved.rawValue, effort: models.effort.rawValue, input: fixture.input, expected: fixture.tool.rawValue, observed: error.localizedDescription, rawOutput: output, elapsedSeconds: Date().timeIntervalSince(start), passed: false)) }
            checkpoint()
        }
        for fixture in Evaluation.visitSummaryCases {
            if Task.isCancelled { return }
            report.runs.append(await evaluateVisit(fixture, models: models)); checkpoint()
        }
        }
        report.complete = true; checkpoint()
    }
}
struct EvaluationView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var models: ModelManager
    @State private var report = EvaluationReport()
    @State private var task: Task<Void, Never>?
    @State private var busy = false
    @State private var allEfforts = true
    var body: some View {
        List {
            Section("Checks") {
                LabeledContent("Passed", value: "\(report.checks.filter(\.passed).count)/\(report.checks.count)")
                ForEach(report.checks) { check in Label(checkTitle(check), systemImage: check.passed ? "checkmark.circle" : "xmark.circle").foregroundStyle(check.passed ? Color.primary : Color.red).font(.subheadline) }
            }
            Section {
                Toggle("Test all effort settings", isOn: $allEfforts).disabled(busy)
                Button(L10n.string(busy ? "Stop evaluation" : "Evaluate selected model")) { if busy { task?.cancel() } else { run() } }
                if busy { ProgressView(models.downloading == nil ? L10n.string("Running fictional cases") : models.status) }
                if !report.runs.isEmpty { LabeledContent("Passed", value: "\(report.runs.filter(\.passed).count)/\(report.runs.count)") }
            } header: { Text("Local model") } footer: { Text(L10n.format("%d fictional prompts per effort setting. Results include model routing and latency; they do not measure clinical validity.", Evaluation.routingCases.count + Evaluation.visitSummaryCases.count)) }
            ForEach(report.runs) { result in
                VStack(alignment: .leading, spacing: 8) { Label(L10n.string(result.input), systemImage: result.passed ? "checkmark.circle" : "xmark.circle"); Text(L10n.format("%@ · %.2f seconds · %@", L10n.string(result.effort), result.elapsedSeconds, L10n.string(result.observed))).font(.caption).foregroundStyle(.secondary) }
            }
            Section { Button("Export results") { export() }.disabled(busy) }
        }.drawerHeight(650).navigationTitle("Evaluation").navigationBarTitleDisplayMode(.inline)
        .onDisappear { task?.cancel() }
    }
    private func checkTitle(_ check: CheckResult) -> String {
        if check.name.hasPrefix("Transcript fixture: ") { return L10n.format("Transcript fixture: %@", L10n.string(String(check.name.dropFirst("Transcript fixture: ".count)))) }
        for sign in EmergencySign.allCases where check.name == "Emergency sign: " + sign.rawValue {
            return L10n.format("Emergency sign: %@", L10n.string(sign.rawValue))
        }
        return L10n.string(check.name)
    }
    private func run() {
        busy = true; report = EvaluationReport()
        let initial = models.effort, selectedModel = models.resolved
        task = Task {
            defer { models.effort = initial; busy = false; task = nil }
            for effort in allEfforts ? Effort.allCases : [initial] {
                models.effort = effort
                for fixture in Evaluation.routingCases {
                    if Task.isCancelled { return }
                    let start = Date()
                    var output = ""
                    do {
                        output = try await models.generate(ToolPlanner.prompt(fixture.input, records: Evaluation.records), allowedTools: ToolPlanner.availableTools.map(\.rawValue))
                        var decision = try ToolPlanner.parse(output)
                        if decision.tool == .reply { decision.arg = try await models.generate(ToolPlanner.conversationPrompt(fixture.input, records: Evaluation.records), maxTokens: effort.chatTokens, stopAtJSON: false); output += "\nReply: " + decision.arg }
                        _ = try ToolPlanner.validate(decision, original: fixture.input, records: Evaluation.records)
                        report.runs.append(ModelRun(model: selectedModel.rawValue, effort: effort.rawValue, input: fixture.input, expected: fixture.tool.rawValue, observed: decision.tool.rawValue, rawOutput: output, elapsedSeconds: Date().timeIntervalSince(start), passed: decision.tool == fixture.tool))
                    } catch { if Task.isCancelled { return }; report.runs.append(ModelRun(model: selectedModel.rawValue, effort: effort.rawValue, input: fixture.input, expected: fixture.tool.rawValue, observed: error.localizedDescription, rawOutput: output, elapsedSeconds: Date().timeIntervalSince(start), passed: false)) }
                }
                for fixture in Evaluation.visitSummaryCases {
                    if Task.isCancelled { return }
                    let result = await SimulatorEvaluation.evaluateVisit(fixture, models: models)
                    if Task.isCancelled { return }; report.runs.append(result)
                }
            }
            report.complete = true
        }
    }
    private func export() {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Harbour-evaluation.json")
            try encoder.encode(report).write(to: url, options: [.atomic, .completeFileProtection]); store.shareFile = ShareFile(url: url)
        } catch { store.error = L10n.string(error.localizedDescription) }
    }
}
