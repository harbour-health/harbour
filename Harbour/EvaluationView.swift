import SwiftUI
import HarbourCore

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
            catch { store.error = error.localizedDescription }
        }
        checkpoint()
        for effort in efforts {
        models.effort = effort
        for fixture in Evaluation.routingCases {
            let start = Date()
            var output = ""
            do {
                output = try await models.generate(ToolPlanner.prompt(fixture.input))
                let decision = try ToolPlanner.parse(output)
                _ = try ToolPlanner.validate(decision, original: fixture.input, records: Records())
                report.runs.append(ModelRun(model: models.resolved.rawValue, effort: models.effort.rawValue, input: fixture.input, expected: fixture.tool.rawValue, observed: decision.tool.rawValue, rawOutput: output, elapsedSeconds: Date().timeIntervalSince(start), passed: decision.tool == fixture.tool))
            } catch { report.runs.append(ModelRun(model: models.resolved.rawValue, effort: models.effort.rawValue, input: fixture.input, expected: fixture.tool.rawValue, observed: error.localizedDescription, rawOutput: output, elapsedSeconds: Date().timeIntervalSince(start), passed: false)) }
            checkpoint()
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
                ForEach(report.checks) { check in Label(check.name, systemImage: check.passed ? "checkmark.circle" : "xmark.circle").foregroundStyle(check.passed ? Color.primary : Color.red).font(.subheadline) }
            }
            Section {
                Toggle("Test all effort settings", isOn: $allEfforts).disabled(busy)
                Button(busy ? "Stop evaluation" : "Evaluate selected model") { if busy { task?.cancel() } else { run() } }
                if busy { ProgressView(models.downloading == nil ? "Running fictional cases" : models.status) }
                if !report.runs.isEmpty { LabeledContent("Passed", value: "\(report.runs.filter(\.passed).count)/\(report.runs.count)") }
            } header: { Text("Local model") } footer: { Text("Twelve fictional prompts per effort setting. Results include model routing and latency; they do not measure clinical validity.") }
            ForEach(report.runs) { result in
                VStack(alignment: .leading, spacing: 8) { Label(result.input, systemImage: result.passed ? "checkmark.circle" : "xmark.circle"); Text("\(result.effort) · \(String(format: "%.2f", result.elapsedSeconds)) seconds · \(result.observed)").font(.caption).foregroundStyle(.secondary) }
            }
            Section { Button("Export results") { export() }.disabled(busy) }
        }.navigationTitle("Evaluation").navigationBarTitleDisplayMode(.inline)
        .onDisappear { task?.cancel() }
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
                        output = try await models.generate(ToolPlanner.prompt(fixture.input))
                        let decision = try ToolPlanner.parse(output)
                        _ = try ToolPlanner.validate(decision, original: fixture.input, records: Records())
                        report.runs.append(ModelRun(model: selectedModel.rawValue, effort: effort.rawValue, input: fixture.input, expected: fixture.tool.rawValue, observed: decision.tool.rawValue, rawOutput: output, elapsedSeconds: Date().timeIntervalSince(start), passed: decision.tool == fixture.tool))
                    } catch { if Task.isCancelled { return }; report.runs.append(ModelRun(model: selectedModel.rawValue, effort: effort.rawValue, input: fixture.input, expected: fixture.tool.rawValue, observed: error.localizedDescription, rawOutput: output, elapsedSeconds: Date().timeIntervalSince(start), passed: false)) }
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
        } catch { store.error = error.localizedDescription }
    }
}
