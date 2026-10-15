import Foundation
import CryptoKit
import HarbourRuntime
import HarbourCore

// Map the runtime's family flag in this consumer, which depends on HarbourCore.
extension ModelPromptFormat {
    var routingPromptProfile: RoutingPromptProfile { usesLegacyRoutingPrompt ? .legacyQwen25 : .current }
}

enum ModelChoice: String, CaseIterable, Identifiable, Codable {
    case automatic, small, balanced, qwen35
    static let defaultModel: ModelChoice = .automatic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: L10n.string("Automatic")
        case .small: L10n.string("Qwen Small")
        case .balanced: L10n.string("Qwen Balanced")
        case .qwen35: L10n.string("Qwen3.5 2B")
        }
    }
    var compactTitle: String { switch self { case .automatic: title; case .small: L10n.string("Small"); case .balanced: L10n.string("Balanced"); case .qwen35: L10n.string("Qwen3.5") } }
    var chatTitle: String { switch self { case .automatic: title; case .small: "Qwen 0.5B"; case .balanced: "Qwen 1.5B"; case .qwen35: L10n.string("Qwen3.5 2B") } }
    var size: Int64 {
        switch self { case .automatic, .small: 491_400_032; case .balanced: 1_117_320_736; case .qwen35: 1_280_835_840 }
    }
    var hash: String {
        switch self {
        case .automatic, .small: "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db"
        case .balanced: "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
        case .qwen35: "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223"
        }
    }
    var filename: String {
        switch self {
        case .automatic, .small: "qwen2.5-0.5b-instruct-q4_k_m.gguf"
        case .balanced: "qwen2.5-1.5b-instruct-q4_k_m.gguf"
        case .qwen35: "Qwen3.5-2B-Q4_K_M.gguf"
        }
    }
    var url: URL {
        let repo: String, revision: String
        switch self {
        case .automatic, .small:
            repo = "Qwen/Qwen2.5-0.5B-Instruct-GGUF"; revision = "9217f5db79a29953eb74d5343926648285ec7e67"
        case .balanced:
            repo = "Qwen/Qwen2.5-1.5B-Instruct-GGUF"; revision = "91cad51170dc346986eccefdc2dd33a9da36ead9"
        case .qwen35:
            repo = "unsloth/Qwen3.5-2B-GGUF"; revision = "f6d5376be1edb4d416d56da11e5397a961aca8ae"
        }
        return URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(filename)")!
    }
    var promptFormat: ModelPromptFormat { self == .qwen35 ? .qwen35 : .qwen25 }
    static func automaticModel(memoryBytes: UInt64, isLowPowerModeEnabled: Bool, thermalState: ProcessInfo.ThermalState) -> ModelChoice {
        memoryBytes >= 8_000_000_000 && !isLowPowerModeEnabled && thermalState == .nominal ? .balanced : .small
    }
}
enum Effort: String, CaseIterable, Identifiable {
    case quick = "Quick", standard = "Standard", extended = "Extended"
    var id: String { rawValue }
    var title: String { L10n.string(rawValue) }
    var tokens: Int { switch self { case .quick: 96; case .standard: 160; case .extended: 256 } }
    var chatTokens: Int { switch self { case .quick: 256; case .standard: 512; case .extended: 768 } }
}

private final class ModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private let destination: URL
    init(destination: URL, progress: @escaping @Sendable (Double) -> Void) { self.destination = destination; self.progress = progress }
    func cancel() { session?.invalidateAndCancel() }
    func start(_ url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 1800
                self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
                self.session!.downloadTask(with: url).resume()
            }
        } onCancel: { self.session?.invalidateAndCancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else { throw URLError(.badServerResponse) }
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination); continuation = nil
        } catch { continuation?.resume(throwing: error); continuation = nil }
        session.finishTasksAndInvalidate()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation?.resume(throwing: error); continuation = nil }
    }
}

@MainActor final class ModelManager: ObservableObject {
    @Published var selection: ModelChoice { didSet { defaults.set(selection.rawValue, forKey: "model") } }
    @Published var effort: Effort { didSet { defaults.set(effort.rawValue, forKey: "effort") } }
    @Published var downloading: ModelChoice?
    @Published private(set) var isVerifying = false
    @Published var progress: Double = 0
    @Published var status = ""
    @Published var revision = 0
    private let runtime = LocalModel()
    @Published private(set) var generating = false
    private var activeDownload: ModelDownload?
    private var downloadCancelled = false
    private let defaults: UserDefaults
    let directory: URL
    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        selection = ModelChoice(rawValue: defaults.string(forKey: "model") ?? "") ?? .defaultModel
        effort = Effort(rawValue: defaults.string(forKey: "effort") ?? "") ?? .standard
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        var excluded = self.directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
    }
    var resolved: ModelChoice {
        guard selection == .automatic else { return selection }
        #if targetEnvironment(simulator)
        return .small
        #else
        return ModelChoice.automaticModel(memoryBytes: ProcessInfo.processInfo.physicalMemory, isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled, thermalState: ProcessInfo.processInfo.thermalState)
        #endif
    }
    func file(_ model: ModelChoice) -> URL { directory.appendingPathComponent(model.filename) }
    func installed(_ model: ModelChoice) -> Bool {
        // The marker is only created after a full streaming SHA-256 check.
        FileManager.default.fileExists(atPath: file(model).path) && FileManager.default.fileExists(atPath: file(model).appendingPathExtension("verified").path)
    }
    func ensure(_ model: ModelChoice) async throws -> URL {
        if installed(model) { return file(model) }
        guard downloading == nil else { throw NSError(domain: "Download", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.string("A model is already downloading.")]) }
        downloading = model; progress = 0; status = L10n.format("Downloading %@", model.title)
        downloadCancelled = false
        defer { downloading = nil; isVerifying = false; activeDownload = nil; revision += 1 }
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let download = ModelDownload(destination: temporary) { [weak self] value in Task { @MainActor in self?.progress = value } }
        activeDownload = download
        do { _ = try await download.start(model.url) }
        catch { if downloadCancelled { throw CancellationError() }; throw error }
        if downloadCancelled { throw CancellationError() }
        try Task.checkCancellation()
        status = L10n.string("Verifying download")
        isVerifying = true
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: temporary)
            defer { try? handle.close() }
            var digest = SHA256(), size: Int64 = 0
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { digest.update(data: chunk); size += Int64(chunk.count) }
            let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == model.hash, size == model.size else { throw NSError(domain: "Download", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.string("The downloaded model failed verification. Please try again.")]) }
        }.value
        if downloadCancelled { throw CancellationError() }
        try Task.checkCancellation()
        let destination = file(model)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
        try Data(model.hash.utf8).write(to: destination.appendingPathExtension("verified"), options: .atomic)
        status = L10n.string("Ready"); return destination
    }
    func cancelDownload() { downloadCancelled = true; activeDownload?.cancel() }
    func generate(_ prompt: String, maxTokens: Int? = nil, allowedTools: [String]? = nil, responseGrammar: String? = nil, stopAtJSON: Bool = true, purpose: ModelPromptPurpose = .prose, model: ModelChoice? = nil) async throws -> String {
        guard !generating else { throw NSError(domain: "Inference", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.string("The model is already working on a request.")]) }
        generating = true
        defer { generating = false }
        guard allowedTools == nil || responseGrammar == nil else { throw ModelError.grammar }
        let grammar = try allowedTools.map { try ToolOutputGrammar.make(allowedTools: $0) } ?? responseGrammar
        let chosen = model ?? resolved
        guard chosen != .automatic else { throw ModelError.load }
        let url = try await ensure(chosen)
        status = L10n.string("Thinking")
        return try await runtime.generate(file: url, prompt: ModelPrompts.localized(prompt, language: language, purpose: purpose), maxTokens: maxTokens ?? effort.tokens, grammar: grammar, stopAtJSON: stopAtJSON, promptFormat: chosen.promptFormat)
    }
    /// The caller resolves Automatic once for the whole visit and supplies that
    /// same model and language for every stage. Existing chat generation is unchanged.
    func generateVisitStage(_ request: VisitStageRequest, model: ModelChoice, language: ModelLanguage) async throws -> VisitStageGeneration {
        guard model != .automatic, !generating else { throw ModelError.load }
        generating = true
        defer { generating = false }
        let logical = ModelPrompts.localized(request.prompt, language: language, purpose: .visit)
        let prepared = try model.promptFormat.prepare(logical)
        var generation = VisitStageGeneration(output: "", preparedPrompt: prepared, modelID: model.rawValue, configuration: [
            "modelSHA256": model.hash, "promptFormat": model.promptFormat == .qwen35 ? "qwen35" : "qwen25",
            "effort": effort.rawValue, "context": "4096", "batch": "512",
            "threads": String(max(1, min(4, ProcessInfo.processInfo.processorCount - 2))),
            "sampler": "greedy; grammar constraint", "stopAtJSON": "true"
        ])
        do {
            let url = try await ensure(model)
            status = L10n.string("Thinking")
            generation.output = try await runtime.generate(file: url, prompt: logical, maxTokens: request.maximumTokens, grammar: request.grammar, promptFormat: model.promptFormat)
        } catch { generation.error = error is CancellationError ? "cancelled" : error.localizedDescription }
        return generation
    }

    func chatDecision(_ input: String, hint: String? = nil, records: Records, history: [ConversationTurn] = []) async throws -> ToolDecision {
        let chosen = resolved
        let output = try await generate(ToolPlanner.prompt(input, hint: hint, records: records, history: history, profile: chosen.promptFormat.routingPromptProfile), allowedTools: ToolPlanner.availableTools.map(\.rawValue), purpose: .routing, model: chosen)
        let decision = try ToolPlanner.parse(output)
        var rejectedAction = false
        if decision.tool != .reply {
            do {
                _ = try ToolPlanner.validate(decision, original: input, records: records, language: language)
                return decision
            } catch { rejectedAction = true }
        }
        if let fallback = ToolPlanner.groundedReply(original: input, records: records, history: history, language: language)
            ?? ToolPlanner.replyFallback(original: input, records: records, language: language, rejectedAction: rejectedAction) { return fallback.decision }
        // An ordinary reply route retains the model's conversation path.
        try Task.checkCancellation()
        let answer = try await generate(ToolPlanner.conversationPrompt(input, records: records, history: history, language: language, compactProsePolicy: resolved.promptFormat.usesCompactProsePolicy), maxTokens: effort.chatTokens, stopAtJSON: false)
        return ToolDecision(tool: .reply, arg: answer)
    }
    private var language: ModelLanguage { L10n.isFrench ? .french : .english }
    func remove(_ model: ModelChoice) async throws {
        guard !generating else { throw NSError(domain: "Inference", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.string("Stop the current request before removing its model.")]) }
        await runtime.unload()
        if FileManager.default.fileExists(atPath: file(model).path) { try FileManager.default.removeItem(at: file(model)) }
        try? FileManager.default.removeItem(at: file(model).appendingPathExtension("verified")); revision += 1
    }
}


extension ModelManager {
    func title(for message: String) async throws -> String? {
        let prompt = try ModelPrompts.title(message, language: language)
        let output = try await generate(prompt, maxTokens: ModelPrompts.titleTokenBudget(language: language), responseGrammar: TitleOutputGrammar.make(), purpose: .title)
        return ModelPrompts.parseTitle(output)
    }
}
