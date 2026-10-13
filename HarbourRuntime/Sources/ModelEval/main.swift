import Foundation
import HarbourCore
import HarbourRuntime
import llama

private struct EvalTurn: Decodable {
    let isUser: Bool
    let text: String
}
private struct EvalCase: Decodable {
    let id: String
    let split: String
    let kind: String
    let language: ModelLanguage
    let input: String
    let recordsProfile: String?
    let records: Records?
    let history: [EvalTurn]?
    let hint: String?
    let effortSubset: Bool?
    let timingSubset: Bool?
    var resolvedRecords: Records { records ?? (recordsProfile == "empty" ? Records() : Evaluation.records) }
    var turns: [ConversationTurn] { (history ?? []).map { .init(isUser: $0.isUser, text: $0.text) } }
}
private struct EvalSuite: Decodable { let id: String; let version: Int; let cases: [EvalCase] }
private struct FrequencySummary: Codable { let count: Int; let period: String }
private struct MedicineProposal: Codable {
    let action: String
    let medicineID: String
    let name: String
    let instructions: String
    let quote: String
    var frequency: FrequencySummary?
    var times: [String]?
}
private struct ActionSummary: Codable {
    var type: String
    var medicineID: String?
    var name: String?
    var instructions: String?
    var kind: String?
    var value: String?
    var unit: String?
    var times: [String]?
    var frequency: FrequencySummary?
    var status: String?
    var text: String?
    var medicineIDs: [String]?
    var highlightQuotes: [String]?
    var followUpQuotes: [String]?
    var appointmentQuotes: [String]?
    var medicines: [MedicineProposal]?
}
private struct EvalResult: Codable {
    let caseID: String
    let split: String
    let kind: String
    let language: String
    let model: String
    let effort: String
    let repeatIndex: Int
    let coldLoad: Bool
    var seconds: Double = 0
    var routeSeconds: Double?
    var replySeconds: Double?
    var budget: Int = 0
    var replyBudget: Int?
    var promptUTF8Bytes: Int = 0
    var prompt: String?
    var replyPrompt: String?
    var responseGrammar: String?
    var promptTokens: Int?
    var replyPromptTokens: Int?
    var context = 4096
    var batch = 512
    var threads = max(1, min(4, ProcessInfo.processInfo.processorCount - 2))
    var sampler = "greedy; grammar constraint when enabled"
    var routeOutput: String?
    var output = ""
    var observedTool: String?
    var finalTool: String?
    var actionValidationSucceeded: Bool?
    var validationSucceeded = false
    var validationError: String?
    var fallbackUsed = false
    var actionSummary: ActionSummary?
    var records: Records?
    var baselinePrompts: Bool
    var expectedAcceptance: Bool?
    var grammarAccepted: Bool?
    var residentBytes: Int?
    var peakResidentBytes: Int?
}
private struct Options {
    var model: URL?
    var modelID = "qwen35"
    var suite: URL?
    var output: URL?
    var efforts = ["standard"]
    var repeats = 1
    var split = "all"
    var ids: Set<String>?
    var baseline = false
    var contextChecks = false
    var grammarChecks = false
    var diagnosticsOnly = false
    static func parse() throws -> Self {
        var result = Self(), arguments = Array(CommandLine.arguments.dropFirst())
        while !arguments.isEmpty {
            let key = arguments.removeFirst()
            if key == "--baseline-prompts" { result.baseline = true; continue }
            if key == "--context-checks" { result.contextChecks = true; continue }
            if key == "--grammar-checks" { result.grammarChecks = true; continue }
            if key == "--diagnostics-only" { result.diagnosticsOnly = true; continue }
            guard !arguments.isEmpty else { throw NSError(domain: "Options", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing value for \(key)"]) }
            let value = arguments.removeFirst()
            switch key {
            case "--model": result.model = URL(fileURLWithPath: value)
            case "--model-id": result.modelID = value
            case "--suite": result.suite = URL(fileURLWithPath: value)
            case "--output": result.output = URL(fileURLWithPath: value)
            case "--efforts": result.efforts = value.split(separator: ",").map(String.init)
            case "--repeats": result.repeats = Int(value) ?? 0
            case "--split": result.split = value
            case "--ids": result.ids = Set(value.split(separator: ",").map(String.init))
            default: throw NSError(domain: "Options", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown option \(key)"])
            }
        }
        guard result.model != nil, result.suite != nil, result.output != nil,
              ["small", "balanced", "qwen35"].contains(result.modelID),
              (1...5).contains(result.repeats), ["all", "dev", "heldout"].contains(result.split),
              (!result.diagnosticsOnly || result.grammarChecks || result.contextChecks),
              !result.efforts.isEmpty, result.efforts.allSatisfy({ ["quick", "standard", "extended"].contains($0) }) else {
            throw NSError(domain: "Options", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: model-eval --model FILE --model-id small|balanced|qwen35 --suite JSON --output JSONL [--efforts quick,standard,extended] [--repeats 1...5] [--split all|dev|heldout] [--ids comma-separated IDs] [--baseline-prompts] [--context-checks] [--grammar-checks]"])
        }
        return result
    }
}

private func actionSummary(_ action: ValidatedAction) -> ActionSummary {
    func frequency(_ value: MedicationFrequency?) -> FrequencySummary? { value.map { .init(count: $0.count, period: $0.period.rawValue) } }
    func times(_ values: [DoseTime]) -> [String] { values.map { String(format: "%02d:%02d", $0.hour, $0.minute) } }
    switch action {
    case .appointment(let text): return .init(type: "create_appointment", text: text)
    case .appointments: return .init(type: "list_appointments")
    case .reply(let text): return .init(type: "reply", text: text)
    case .symptom(let text): return .init(type: "capture_symptom", text: text)
    case .add(let medicine, let values, let schedule): return .init(type: "add_medication", medicineID: medicine.id, name: medicine.name, instructions: medicine.instructions, times: times(values), frequency: frequency(schedule))
    case .remove(let medicine): return .init(type: "remove_medication", medicineID: medicine.id, name: medicine.name)
    case .medicines: return .init(type: "list_medications")
    case .interactions(let medicines): return .init(type: "check_interactions", medicineIDs: medicines.map(\.id))
    case .reading(let reading): return .init(type: "log_reading", kind: reading.kind.rawValue, value: reading.value, unit: reading.kind.unit)
    case .readings: return .init(type: "list_readings")
    case .importHealth: return .init(type: "import_readings")
    case .export: return .init(type: "export_data")
    case .note: return .init(type: "copy_note")
    case .clear: return .init(type: "clear_data")
    case .reminder(let text): return .init(type: "create_reminder", text: text)
    case .reminders: return .init(type: "list_reminders")
    case .schedule(let medicine, let values, let schedule): return .init(type: "schedule_medication", medicineID: medicine.id, name: medicine.name, instructions: medicine.instructions, times: times(values), frequency: frequency(schedule))
    case .dose(let medicine, let status): return .init(type: "log_dose", medicineID: medicine.id, name: medicine.name, status: status.rawValue)
    case .timeline(let text): return .init(type: "search_timeline", text: text)
    case .scan: return .init(type: "scan_medication")
    case .question(let text): return .init(type: "save_question", text: text)
    }
}

private func log(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }

@main private struct ModelEvaluator {
    static func main() async throws {
        let options = try Options.parse()
        let model = options.model!, output = options.output!, runtime = LocalModel(useGPU: false)
        let format: ModelPromptFormat = options.modelID == "qwen35" ? .qwen35 : .qwen25
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: options.suite!)
        guard data.count <= 20_000_000 else { throw NSError(domain: "Suite", code: 1) }
        let suite = try decoder.decode(EvalSuite.self, from: data)
        guard suite.cases.count <= 1_000, Set(suite.cases.map(\.id)).count == suite.cases.count,
              suite.cases.allSatisfy({ $0.input.count <= 60_000 && ["routing", "prose", "title", "visit"].contains($0.kind) }) else { throw NSError(domain: "Suite", code: 1) }
        if let ids = options.ids, !ids.isSubset(of: Set(suite.cases.map(\.id))) { throw NSError(domain: "Suite", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown case IDs requested."]) }
        let selectedCases = options.diagnosticsOnly ? [] : suite.cases.filter { (options.split == "all" || $0.split == options.split) && (options.ids == nil || options.ids!.contains($0.id)) }
        guard options.diagnosticsOnly || !selectedCases.isEmpty else { throw NSError(domain: "Suite", code: 1, userInfo: [NSLocalizedDescriptionKey: "No matching evaluation cases."]) }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: output.path) else { throw NSError(domain: "Output", code: 1, userInfo: [NSLocalizedDescriptionKey: "Refusing to overwrite an existing result file: \(output.path)"]) }
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw NSError(domain: "Output", code: 1) }
        let stream = try FileHandle(forWritingTo: output)
        defer { try? stream.close() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; encoder.dateEncodingStrategy = .iso8601
        func emit(_ row: EvalResult) throws {
            try stream.write(contentsOf: encoder.encode(row)); try stream.write(contentsOf: Data([10])); try stream.synchronize()
        }
        var rows = 0, firstLoad = true
        for effort in options.efforts {
            let routingBudget = effort == "quick" ? 96 : effort == "extended" ? 256 : 160
            let replyBudget = effort == "quick" ? 256 : effort == "extended" ? 768 : 512
            for fixture in selectedCases {
                if effort != "standard" && fixture.effortSubset != true { continue }
                let repetitions = effort == "standard" && fixture.timingSubset == true ? options.repeats : 1
                for repeatIndex in 0..<repetitions {
                    var result = EvalResult(caseID: fixture.id, split: fixture.split, kind: fixture.kind, language: fixture.language.rawValue,
                        model: options.modelID, effort: effort, repeatIndex: repeatIndex, coldLoad: firstLoad, baselinePrompts: options.baseline)
                    let records = fixture.resolvedRecords
                    result.records = records
                    var prompt = "", replyPrompt: String?
                    let started = Date()
                    do {
                        switch fixture.kind {
                        case "routing":
                            prompt = ModelPrompts.localized(ToolPlanner.prompt(fixture.input, hint: fixture.hint, records: records, history: fixture.turns), language: fixture.language, purpose: .routing)
                            result.budget = routingBudget
                            result.responseGrammar = try ToolOutputGrammar.make(allowedTools: ToolPlanner.availableTools.map(\.rawValue))
                            let routeStart = Date()
                            let raw = try await runtime.generate(file: model, prompt: prompt, maxTokens: routingBudget,
                                grammar: result.responseGrammar, promptFormat: format)
                            result.routeSeconds = Date().timeIntervalSince(routeStart); result.routeOutput = raw
                            let decision = try ToolPlanner.parse(raw); result.observedTool = decision.tool.rawValue
                            var action: ValidatedAction?
                            if decision.tool != .reply {
                                do { action = try ToolPlanner.validate(decision, original: fixture.input, records: records); result.actionValidationSucceeded = true }
                                catch { result.actionValidationSucceeded = false; result.fallbackUsed = true; result.validationError = error.localizedDescription }
                            }
                            if let action {
                                result.finalTool = decision.tool.rawValue; result.output = raw; result.actionSummary = actionSummary(action)
                            } else {
                                replyPrompt = ModelPrompts.localized(ToolPlanner.conversationPrompt(fixture.input, records: records, history: fixture.turns, language: fixture.language), language: fixture.language, purpose: .prose)
                                result.replyBudget = replyBudget
                                let replyStart = Date()
                                result.output = try await runtime.generate(file: model, prompt: replyPrompt!, maxTokens: replyBudget, stopAtJSON: false, promptFormat: format)
                                result.replySeconds = Date().timeIntervalSince(replyStart); result.finalTool = Tool.reply.rawValue
                                result.actionSummary = actionSummary(try ToolPlanner.validate(.init(tool: .reply, arg: result.output), original: fixture.input, records: records))
                            }
                            result.validationSucceeded = true
                        case "prose":
                            prompt = ModelPrompts.localized(ToolPlanner.conversationPrompt(fixture.input, records: records, history: fixture.turns, language: fixture.language), language: fixture.language, purpose: .prose)
                            result.budget = replyBudget
                            result.output = try await runtime.generate(file: model, prompt: prompt, maxTokens: replyBudget, stopAtJSON: false, promptFormat: format)
                            result.finalTool = Tool.reply.rawValue
                            result.actionSummary = actionSummary(try ToolPlanner.validate(.init(tool: .reply, arg: result.output), original: fixture.input, records: records)); result.validationSucceeded = true
                        case "title":
                            prompt = ModelPrompts.localized(try ModelPrompts.title(fixture.input, language: fixture.language), language: fixture.language, purpose: .title)
                            result.budget = ModelPrompts.titleTokenBudget(language: fixture.language)
                            let grammar = !options.baseline || fixture.language == .french ? TitleOutputGrammar.make() : nil
                            result.responseGrammar = grammar
                            result.output = try await runtime.generate(file: model, prompt: prompt, maxTokens: result.budget, grammar: grammar, promptFormat: format)
                            if let title = ModelPrompts.parseTitle(result.output) { result.actionSummary = .init(type: "title", text: title); result.validationSucceeded = true }
                        case "visit":
                            prompt = ModelPrompts.localized(try VisitReview.prompt(fixture.input, medicines: records.medicines), language: fixture.language, purpose: .visit)
                            result.budget = 650
                            result.responseGrammar = options.baseline ? nil : VisitReview.outputGrammar(transcript: fixture.input, medicines: records.medicines)
                            result.output = try await runtime.generate(file: model, prompt: prompt, maxTokens: 650, grammar: result.responseGrammar, promptFormat: format)
                            let summary = try VisitReview.parse(result.output, transcript: fixture.input, medicines: records.medicines)
                            result.actionSummary = .init(type: "visit", highlightQuotes: summary.highlights.map(\.quote), followUpQuotes: summary.followUps.map(\.quote), appointmentQuotes: (summary.appointments ?? []).map(\.quote), medicines: summary.medicines.map { .init(action: $0.action.rawValue, medicineID: $0.medicine.id, name: $0.medicine.name, instructions: $0.medicine.instructions, quote: $0.quote, frequency: $0.frequency.map { .init(count: $0.count, period: $0.period.rawValue) }, times: $0.times.map { String(format: "%02d:%02d", $0.hour, $0.minute) }) })
                            result.validationSucceeded = true
                        default: break
                        }
                    } catch { result.validationError = error.localizedDescription }
                    result.seconds = Date().timeIntervalSince(started)
                    result.prompt = try? format.prepare(prompt)
                    result.promptUTF8Bytes = result.prompt?.utf8.count ?? prompt.utf8.count
                    result.replyPrompt = try? replyPrompt.map { try format.prepare($0) }
                    result.promptTokens = try? await runtime.tokenCount(file: model, prompt: prompt, promptFormat: format)
                    if let replyPrompt { result.replyPromptTokens = try? await runtime.tokenCount(file: model, prompt: replyPrompt, promptFormat: format) }
                    if let status = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) {
                        for line in status.split(separator: "\n") {
                            let parts = line.split(whereSeparator: \.isWhitespace)
                            guard parts.count >= 2, let kibibytes = Int(parts[1]) else { continue }
                            if parts[0] == "VmRSS:" { result.residentBytes = kibibytes * 1024 }
                            if parts[0] == "VmHWM:" { result.peakResidentBytes = kibibytes * 1024 }
                        }
                    }
                    firstLoad = false; rows += 1; try emit(result)
                    let status = fixture.split == "heldout" ? "result=sealed" : "valid=\(result.validationSucceeded)"
                    log("\(options.modelID) \(effort) \(fixture.id) repeat=\(repeatIndex) \(status) seconds=\(String(format: "%.2f", result.seconds))")
                }
            }
        }
        if options.contextChecks {
            let budget = 16, threshold = 4096 - budget - 1
            func boundaryPrompt(_ count: Int) -> String { "<|im_start|>system\nOutput OK only.\n<|im_end|>\n<|im_start|>user\n" + String(repeating: " test", count: count) + "\n<|im_end|>\n<|im_start|>assistant" }
            var lower = 0, upper = 6_000
            while lower < upper {
                let middle = (lower + upper + 1) / 2
                let count = try await runtime.tokenCount(file: model, prompt: boundaryPrompt(middle), promptFormat: format)
                if count <= threshold { lower = middle } else { upper = middle - 1 }
            }
            for (offset, shouldReject) in [(0, false), (1, true)] {
                let prompt = boundaryPrompt(lower + offset)
                let count = try await runtime.tokenCount(file: model, prompt: prompt, promptFormat: format)
                let prepared = try format.prepare(prompt)
                var result = EvalResult(caseID: shouldReject ? "context.rejected" : "context.allowed", split: "invariant", kind: "context_boundary", language: "en", model: options.modelID, effort: "standard", repeatIndex: 0, coldLoad: false, budget: budget, promptUTF8Bytes: prepared.utf8.count, prompt: prepared, promptTokens: count, baselinePrompts: options.baseline)
                let started = Date()
                result.responseGrammar = "root ::= \"OK\""
                do {
                    result.output = try await runtime.generate(file: model, prompt: prompt, maxTokens: budget, grammar: result.responseGrammar, stopAtJSON: false, promptFormat: format)
                    result.validationSucceeded = !shouldReject && count + budget < 4096
                } catch ModelError.promptTooLong {
                    result.validationSucceeded = shouldReject && count + budget >= 4096
                    result.validationError = ModelError.promptTooLong.localizedDescription
                } catch { result.validationError = error.localizedDescription }
                result.seconds = Date().timeIntervalSince(started); rows += 1; try emit(result)
            }
        }
        await runtime.unload()
        if options.grammarChecks {
            llama_backend_init()
            var parameters = llama_model_default_params(); parameters.n_gpu_layers = 0
            guard let loaded = llama_model_load_from_file(model.path, parameters) else { throw ModelError.load }
            defer { llama_model_free(loaded) }
            let vocab = llama_model_get_vocab(loaded)
            func accepts(_ text: String, grammar: String) throws -> Bool {
                guard let sampler = llama_sampler_init_grammar(vocab, grammar, "root") else { throw ModelError.grammar }
                defer { llama_sampler_free(sampler) }
                var tokens = [llama_token](repeating: 0, count: text.utf8.count + 16)
                let count = tokens.withUnsafeMutableBufferPointer { llama_tokenize(vocab, text, Int32(text.utf8.count), $0.baseAddress, Int32($0.count), false, true) }
                guard count > 0 else { throw ModelError.tokenize }
                for token in Array(tokens.prefix(Int(count))) + [llama_vocab_eos(vocab)] {
                    var candidate = llama_token_data(id: token, logit: 0, p: 1)
                    let permitted = withUnsafeMutablePointer(to: &candidate) { pointer -> Bool in
                        var array = llama_token_data_array(data: pointer, size: 1, selected: -1, sorted: false)
                        llama_sampler_apply(sampler, &array)
                        return pointer.pointee.logit.isFinite
                    }
                    if !permitted { return false }
                    llama_sampler_accept(sampler, token)
                }
                return true
            }
            let visitObjects = options.baseline
                ? #"{"highlights":[{"quote":"Source fact."}],"medicines":[{"action":"start","name":"metformin","instructions":"500 mg daily","quote":"Start metformin 500 mg daily."}],"followUps":[{"quote":"Book blood work."}]}"#
                : #"{"highlights":[{"quote":"Source fact."}],"medicines":[{"quote":"Start metformin 500 mg daily.","action":"start","name":"metformin","instructions":"500 mg daily"}],"followUps":[{"quote":"Book blood work."}]}"#
            let unknownAction = options.baseline
                ? #"{"highlights":[],"medicines":[{"action":"prescribe","name":"metformin","instructions":"500 mg daily","quote":"Start metformin 500 mg daily."}],"followUps":[]}"#
                : #"{"highlights":[],"medicines":[{"quote":"Start metformin 500 mg daily.","action":"prescribe","name":"metformin","instructions":"500 mg daily"}],"followUps":[]}"#
            func visitLiteral(_ value: String) -> String {
                options.baseline ? value : String(value.dropLast()) + ",\"appointments\":[]}"
            }
            var tests: [(String, String, String, Bool)] = [
                ("visit.empty", VisitReview.outputGrammar(), visitLiteral(#"{"highlights":[],"medicines":[],"followUps":[]}"#), true),
                ("visit.source-objects", VisitReview.outputGrammar(), visitLiteral(visitObjects), true),
                ("visit.bare-highlights", VisitReview.outputGrammar(), visitLiteral(#"{"highlights":["Source fact."],"medicines":[],"followUps":[]}"#), false),
                ("visit.unknown-action", VisitReview.outputGrammar(), visitLiteral(unknownAction), false),
                ("visit.extra-key", VisitReview.outputGrammar(), visitLiteral(#"{"highlights":[],"medicines":[],"followUps":[],"extra":true}"#), false),
                ("title.valid", TitleOutputGrammar.make(), #"{"title":"A short neutral title"}"#, true),
                ("title.empty", TitleOutputGrammar.make(), #"{"title":""}"#, false),
                ("title.extra-key", TitleOutputGrammar.make(), #"{"title":"A short title","extra":true}"#, false)
            ]
            if !options.baseline {
                tests += [
                    ("visit.appointment-objects", VisitReview.outputGrammar(), #"{"highlights":[],"medicines":[],"followUps":[],"appointments":[{"quote":"Votre rendez-vous est mardi à 14 h."}]}"#, true),
                    ("visit.bare-appointments", VisitReview.outputGrammar(), #"{"highlights":[],"medicines":[],"followUps":[],"appointments":["Your appointment is Tuesday."]}"#, false),
                    ("visit.missing-appointments", VisitReview.outputGrammar(), #"{"highlights":[],"medicines":[],"followUps":[]}"#, false)
                ]
                func encoded(_ value: String) -> String { String(decoding: try! JSONEncoder().encode(value), as: UTF8.self) }
                func medicine(_ quote: String, _ action: String, _ name: String, _ instructions: String) -> String {
                    "{\"quote\":" + encoded(quote) + ",\"action\":" + encoded(action) + ",\"name\":" + encoded(name) + ",\"instructions\":" + encoded(instructions) + "}"
                }
                func summary(_ changes: [String]) -> String { "{\"highlights\":[],\"medicines\":[" + changes.joined(separator: ",") + "],\"followUps\":[],\"appointments\":[]}" }
                let start = "Start metformin 500 mg daily.", stop = "Stop warfarin today.", frenchStop = "Arrêtez la warfarine aujourd'hui."
                let continuation = "Continue loratadine 10 mg daily.", unchanged = "Continue loratadine without changes."
                let sourceTests: [(String, String, String, Bool)] = [
                    ("source.start", start, summary([medicine(start, "start", "metformin", "500 mg daily")]), true),
                    ("source.stop", stop, summary([medicine(stop, "stop", "warfarin", "")]), true),
                    ("source.french-stop", frenchStop, summary([medicine(frenchStop, "stop", "warfarine", "")]), true),
                    ("source.explicit-dose-continuation", continuation, summary([medicine(continuation, "update", "loratadine", "10 mg daily")]), true),
                    ("source.unchanged-empty", unchanged, summary([]), true),
                    ("source.unchanged-proposal", unchanged, summary([medicine(unchanged, "update", "loratadine", "without changes")]), false),
                    ("source.unknown-quote", start, summary([medicine("Start aspirin 500 mg daily.", "start", "aspirin", "500 mg daily")]), false),
                    ("source.translated-quote", frenchStop, summary([medicine("Stop warfarin today.", "stop", "warfarin", "")]), false),
                    ("source.mismatched-action", stop, summary([medicine(stop, "start", "warfarin", "today")]), false),
                    ("source.stop-instructions", stop, summary([medicine(stop, "stop", "warfarin", "today")]), false),
                    ("source.count-overflow", start, summary([medicine(start, "start", "metformin", "500 mg daily"), medicine(start, "start", "metformin", "500 mg daily")]), false),
                    ("source.negated", "Do not start metformin 500 mg daily.", summary([medicine("Do not start metformin 500 mg daily.", "start", "metformin", "500 mg daily")]), false),
                    ("source.third-person", "My mother should start metformin 500 mg daily.", summary([medicine("My mother should start metformin 500 mg daily.", "start", "metformin", "500 mg daily")]), false),
                    ("source.reported-current-regimen", "I take metformin 500 mg daily.", summary([medicine("I take metformin 500 mg daily.", "update", "metformin", "500 mg daily")]), false),
                    ("source.imperative-regimen", "Take metformin 500 mg daily.", summary([medicine("Take metformin 500 mg daily.", "update", "metformin", "500 mg daily")]), true),
                    ("source.compound-actions", "Stop warfarin and start metformin 500 mg daily.", summary([medicine("Stop warfarin and start metformin 500 mg daily.", "stop", "warfarin", ""), medicine("Stop warfarin and start metformin 500 mg daily.", "start", "metformin", "500 mg daily")]), true),
                    ("source.compound-same-action", "Increase metformin to 1000 mg daily and reduce warfarin to 1 mg daily.", summary([medicine("Increase metformin to 1000 mg daily and reduce warfarin to 1 mg daily.", "update", "metformin", "1000 mg daily"), medicine("Increase metformin to 1000 mg daily and reduce warfarin to 1 mg daily.", "update", "warfarin", "1 mg daily")]), true),
                    ("source.conjoined-stop", "Stop warfarin and metformin.", summary([medicine("Stop warfarin and metformin.", "stop", "warfarin", ""), medicine("Stop warfarin and metformin.", "stop", "metformin", "")]), true),
                    ("source.french-stop-chain", "Cessez de prendre la metformine.", summary([medicine("Cessez de prendre la metformine.", "stop", "metformine", "")]), true),
                    ("source.french-stop-chain-update", "Cessez de prendre la metformine.", summary([medicine("Cessez de prendre la metformine.", "update", "metformine", "")]), false),
                    ("source.french-stop-chain-count-overflow", "Cessez de prendre la metformine.", summary([medicine("Cessez de prendre la metformine.", "stop", "metformine", ""), medicine("Cessez de prendre la metformine.", "stop", "metformine", "")]), false),
                    ("source.english-stop-chain", "Stop taking metformin.", summary([medicine("Stop taking metformin.", "stop", "metformin", "")]), true),
                    ("source.english-begin-chain", "Begin taking metformin 500 mg daily.", summary([medicine("Begin taking metformin 500 mg daily.", "start", "metformin", "500 mg daily")]), true),
                    ("source.english-begin-chain-update", "Begin taking metformin 500 mg daily.", summary([medicine("Begin taking metformin 500 mg daily.", "update", "metformin", "500 mg daily")]), false),
                    ("source.french-start-chain", "Commencez à prendre la metformine 500 mg par jour.", summary([medicine("Commencez à prendre la metformine 500 mg par jour.", "start", "metformine", "500 mg par jour")]), true),
                    ("source.chain-independent-update", "Stop taking warfarin and increase metformin to 1000 mg daily.", summary([medicine("Stop taking warfarin and increase metformin to 1000 mg daily.", "stop", "warfarin", ""), medicine("Stop taking warfarin and increase metformin to 1000 mg daily.", "update", "metformin", "1000 mg daily")]), true),
                    ("source.follow-up", "Book blood work in two weeks.", summary([medicine("Book blood work in two weeks.", "start", "blood work", "two weeks")]), false),
                    ("source.decimal-dose", "Start amlodipine 2.5 mg daily.", summary([medicine("Start amlodipine 2.5 mg daily.", "start", "amlodipine", "2.5 mg daily")]), true),
                    ("source.escaped-quote", "Start aspirin 81 mg daily, labelled \"morning\".", summary([medicine("Start aspirin 81 mg daily, labelled \"morning\".", "start", "aspirin", "81 mg daily")]), true),
                    ("source.beyond-prompt-bound", String(repeating: "Background note without medication changes. ", count: 60) + start, summary([medicine(start, "start", "metformin", "500 mg daily")]), false)
                ]
                tests += sourceTests.map { ($0.0, VisitReview.outputGrammar(transcript: $0.1), $0.2, $0.3) }
                // Exercise minimum cardinality in llama.cpp itself, including
                // the saved-identity branch that an empty baseline cannot use.
                let requiredStartSource = "Start metformin 500 mg twice daily."
                let requiredStart = VisitReview.outputGrammar(transcript: requiredStartSource)
                let requiredStopSource = "Stop metformin today."
                let requiredStop = VisitReview.outputGrammar(transcript: requiredStopSource, medicines: Evaluation.records.medicines)
                tests += [
                    ("source.required-start-empty", requiredStart, summary([]), false),
                    ("source.required-start-grounded", requiredStart, summary([medicine(requiredStartSource, "start", "metformin", "500 mg twice daily")]), true),
                    ("source.required-saved-stop-empty", requiredStop, summary([]), false),
                    ("source.required-saved-stop-grounded", requiredStop, summary([medicine(requiredStopSource, "stop", "metformin", "")]), true),
                    ("source.required-start-changed-name", requiredStart, summary([medicine(requiredStartSource, "start", "aspirin", "500 mg twice daily")]), false),
                    ("source.required-start-changed-dose", requiredStart, summary([medicine(requiredStartSource, "start", "metformin", "850 mg twice daily")]), false),
                    ("source.required-start-inserted-comma", requiredStart, summary([medicine(requiredStartSource, "start", "metformin", "500 mg, twice daily")]), false),
                    ("source.required-saved-stop-changed-name", requiredStop, summary([medicine(requiredStopSource, "stop", "warfarin", "")]), false),
                ]
                let requiredFrenchSource = "Commencez la metformine 850 mg trois fois par jour."
                let requiredFrench = VisitReview.outputGrammar(transcript: requiredFrenchSource)
                tests += [
                    ("source.required-french-source-spelling", requiredFrench, summary([medicine(requiredFrenchSource, "start", "metformine", "850 mg trois fois par jour")]), true),
                    ("source.required-french-canonicalized-name", requiredFrench, summary([medicine(requiredFrenchSource, "start", "Metformin", "850 mg trois fois par jour")]), false),
                ]
            }
            for (id, grammar, text, expected) in tests {
                var result = EvalResult(caseID: "grammar." + id, split: "invariant", kind: "grammar", language: "en", model: options.modelID, effort: "standard", repeatIndex: 0, coldLoad: false, output: text, baselinePrompts: options.baseline, expectedAcceptance: expected)
                result.sampler = "native grammar token acceptance; no inference"
                result.responseGrammar = grammar
                let started = Date()
                do { let actual = try accepts(text, grammar: grammar); result.grammarAccepted = actual; result.validationSucceeded = actual == expected }
                catch { result.validationError = error.localizedDescription }
                result.seconds = Date().timeIntervalSince(started); rows += 1; try emit(result)
            }
        }
        let summary: [String: Any] = ["suite": suite.id, "suiteVersion": suite.version, "model": options.modelID, "rows": rows, "complete": true, "baselinePrompts": options.baseline, "contextChecks": options.contextChecks, "diagnosticsOnly": options.diagnosticsOnly, "availableTools": ToolPlanner.availableTools.map(\.rawValue)]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])); FileHandle.standardOutput.write(Data([10]))
    }
}
