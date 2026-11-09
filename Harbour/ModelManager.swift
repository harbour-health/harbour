import Foundation
import CryptoKit
import HarbourRuntime
import HarbourCore

struct ModelAsset: Sendable {
    let filename: String
    let size: Int64
    let hash: String
    let url: URL

    init(_ filename: String, size: Int64, hash: String, repository: String, revision: String) {
        self.filename = filename; self.size = size; self.hash = hash
        url = URL(string: "https://huggingface.co/Qwen/\(repository)/resolve/\(revision)/\(filename)")!
    }
    func verified(in directory: URL) -> Bool {
        let file = directory.appendingPathComponent(filename)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              (attributes[.size] as? NSNumber)?.int64Value == size,
              let marker = try? Data(contentsOf: file.appendingPathExtension("verified")) else { return false }
        return marker == Data(hash.utf8)
    }
    func verify(_ file: URL) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var digest = SHA256(), count: Int64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            digest.update(data: chunk); count += Int64(chunk.count)
        }
        let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == hash, count == size else {
            throw NSError(domain: "Download", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.string("The downloaded model failed verification. Please try again.")])
        }
    }
}

enum ModelChoice: String, CaseIterable, Identifiable, Codable {
    case automatic, small, balanced, large
    static let downloadable: [ModelChoice] = [.small, .balanced, .large]
    var id: String { rawValue }
    var title: String { switch self {
        case .automatic: L10n.string("Automatic")
        case .small: "Alex"
        case .balanced: "Sam"
        case .large: "Camille"
    } }
    var compactTitle: String { title }
    var technicalName: String { switch self {
        case .automatic: L10n.string("Automatic")
        case .small: "Qwen2.5 · 0.5B · Q4_K_M"
        case .balanced: "Qwen2.5 · 1.5B · Q4_K_M"
        case .large: "Qwen2.5 · 7B · Q4_K_M"
    } }
    var parameterTitle: String { title }
    var personality: String { switch self {
        case .automatic: ""
        case .small: "Use brief, practical wording and short sentences."
        case .balanced: "Use friendly, conversational wording with plain explanations."
        case .large: "Use calm, thoughtful wording. Add useful context when requested, while staying concise."
    } }
    func styleConversation(_ prompt: String) -> String {
        guard self != .automatic, let systemEnd = prompt.range(of: "<|im_end|>") else { return prompt }
        var styled = prompt
        styled.insert(contentsOf: "\nConversation style only: Your selected name is \(title). \(personality) This changes wording only. All existing limits, source requirements and confirmation rules still apply.\n", at: systemEnd.lowerBound)
        if let end = styled.range(of: "<|im_end|>"),
           let identity = styled.range(of: "You are Harbour, a helpful conversational assistant.", range: styled.startIndex..<end.lowerBound) {
            styled.replaceSubrange(identity, with: "You are \(title), a helpful conversational assistant in Harbour.")
        }
        return styled
    }
    var size: Int64 { assets.reduce(0) { $0 + $1.size } }
    // llama.cpp discovers the second shard beside the first using these original names.
    var filename: String { assets[0].filename }
    var assets: [ModelAsset] {
        switch self {
        case .automatic, .small:
            return [ModelAsset("qwen2.5-0.5b-instruct-q4_k_m.gguf", size: 491_400_032,
                hash: "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db",
                repository: "Qwen2.5-0.5B-Instruct-GGUF", revision: "9217f5db79a29953eb74d5343926648285ec7e67")]
        case .balanced:
            return [ModelAsset("qwen2.5-1.5b-instruct-q4_k_m.gguf", size: 1_117_320_736,
                hash: "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
                repository: "Qwen2.5-1.5B-Instruct-GGUF", revision: "91cad51170dc346986eccefdc2dd33a9da36ead9")]
        case .large:
            let repository = "Qwen2.5-7B-Instruct-GGUF", revision = "bb5d59e06d9551d752d08b292a50eb208b07ab1f"
            return [
                ModelAsset("qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf", size: 3_993_201_344,
                    hash: "dfce12e3862a5283ccfb88221b48480e58745165de856439950d0f22590580db", repository: repository, revision: revision),
                ModelAsset("qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf", size: 689_872_288,
                    hash: "539cf93f78e887edea1c04e2d7d8cdaca9d01dae9c9025bcb8accbe29df3d72a", repository: repository, revision: revision)
            ]
        }
    }
}
enum Effort: String, CaseIterable, Identifiable {
    case quick = "Quick", standard = "Standard", extended = "Extended"
    var id: String { rawValue }
    var title: String { L10n.string(rawValue) }
    var tokens: Int { switch self { case .quick: 96; case .standard: 160; case .extended: 256 } }
    var chatTokens: Int { switch self { case .quick: 256; case .standard: 512; case .extended: 768 } }
}

final class ModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
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
                config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 7200
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
    @Published var selection: ModelChoice { didSet { UserDefaults.standard.set(selection.rawValue, forKey: "model") } }
    @Published var effort: Effort { didSet { UserDefaults.standard.set(effort.rawValue, forKey: "effort") } }
    @Published var downloading: ModelChoice?
    @Published private(set) var isVerifying = false
    @Published var progress: Double = 0
    @Published var status = ""
    @Published var revision = 0
    private let runtime = LocalModel()
    @Published private(set) var generating = false
    let chatRequests = ChatRequestLifecycle()
    @Published private(set) var chatRequestState: ChatRequestLifecycle.State = .idle
    private var activeDownload: ModelDownload?
    private var downloadCancelled = false
    let directory: URL
    init(directory overrideDirectory: URL? = nil) {
        selection = ModelChoice(rawValue: UserDefaults.standard.string(forKey: "model") ?? "") ?? .automatic
        effort = Effort(rawValue: UserDefaults.standard.string(forKey: "effort") ?? "") ?? .standard
        directory = overrideDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        chatRequests.onStateChange = { [weak self] state in self?.chatRequestState = state }
    }
    var resolved: ModelChoice {
        selection == .automatic ? automaticModel : selection
    }
    var automaticModel: ModelChoice {
        #if targetEnvironment(simulator)
        return .balanced
        #else
        return ProcessInfo.processInfo.physicalMemory >= 8_000_000_000 && !ProcessInfo.processInfo.isLowPowerModeEnabled && ProcessInfo.processInfo.thermalState == .nominal ? .balanced : .small
        #endif
    }
    var visitModel: ModelChoice { resolved == .small ? .balanced : resolved }
    func file(_ model: ModelChoice) -> URL { directory.appendingPathComponent(model.filename) }
    func installed(_ model: ModelChoice) -> Bool {
        let chosen = model == .automatic ? resolved : model
        return chosen.assets.allSatisfy { $0.verified(in: directory) }
    }
    func ensure(_ model: ModelChoice) async throws -> URL {
        let model = model == .automatic ? resolved : model
        if installed(model) { return file(model) }
        guard downloading == nil else { throw NSError(domain: "Download", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.string("A model is already downloading.")]) }
        downloading = model; progress = 0; downloadCancelled = false
        defer { downloading = nil; isVerifying = false; activeDownload = nil; revision += 1 }
        // Keep the original shard names together, but never expose a partial model as installed.
        let staging = directory.appendingPathComponent(UUID().uuidString + ".partial", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        var completed: Int64 = 0
        for asset in model.assets {
            try Task.checkCancellation()
            if downloadCancelled { throw CancellationError() }
            isVerifying = false; status = L10n.format("Downloading %@", model.title)
            let offset = completed, total = model.size
            let temporary = staging.appendingPathComponent(asset.filename)
            let download = ModelDownload(destination: temporary) { [weak self] value in
                Task { @MainActor in self?.progress = (Double(offset) + min(1, max(0, value)) * Double(asset.size)) / Double(total) }
            }
            activeDownload = download
            do { _ = try await download.start(asset.url) }
            catch { if downloadCancelled { throw CancellationError() }; throw error }
            if downloadCancelled { throw CancellationError() }
            try Task.checkCancellation()
            status = L10n.string("Verifying download"); isVerifying = true
            let verification = Task.detached(priority: .utility) { try asset.verify(temporary) }
            try await withTaskCancellationHandler { try await verification.value } onCancel: { verification.cancel() }
            if downloadCancelled { throw CancellationError() }
            completed += asset.size; progress = Double(completed) / Double(total)
        }
        try Task.checkCancellation()
        if downloadCancelled { throw CancellationError() }
        // Invalidate old markers before replacing any shard. Commit markers only after all moves.
        for asset in model.assets {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(asset.filename).appendingPathExtension("verified"))
        }
        for asset in model.assets {
            let destination = directory.appendingPathComponent(asset.filename)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: staging.appendingPathComponent(asset.filename), to: destination)
        }
        for asset in model.assets {
            try Data(asset.hash.utf8).write(to: directory.appendingPathComponent(asset.filename).appendingPathExtension("verified"), options: .atomic)
        }
        status = L10n.string("Ready"); return file(model)
    }
    func cancelDownload() { downloadCancelled = true; activeDownload?.cancel() }
    func generate(_ prompt: String, maxTokens: Int? = nil, allowedTools: [String]? = nil, responseGrammar: String? = nil, stopAtJSON: Bool = true, model overrideModel: ModelChoice? = nil, sampling: ModelSampling = .greedy) async throws -> String {
        guard !generating else { throw NSError(domain: "Inference", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.string("The model is already working on a request.")]) }
        generating = true
        defer { generating = false }
        guard allowedTools == nil || responseGrammar == nil else { throw ModelError.grammar }
        let grammar = try allowedTools.map { try ToolOutputGrammar.make(allowedTools: $0) } ?? responseGrammar
        let chosen = overrideModel ?? resolved, url = try await ensure(chosen)
        status = L10n.string("Thinking")
        return try await runtime.generate(file: url, prompt: localizedPrompt(prompt), maxTokens: maxTokens ?? effort.tokens, grammar: grammar, stopAtJSON: stopAtJSON, sampling: sampling)
    }
    func chatDecision(_ input: String, hint: String? = nil, records: Records, history: [ConversationTurn] = []) async throws -> ToolDecision {
        let output = try await generate(ToolPlanner.prompt(input, hint: hint, records: records, history: history), allowedTools: ToolPlanner.availableTools.map(\.rawValue))
        let decision = try ToolPlanner.parse(output)
        if decision.tool != .reply {
            do { _ = try ToolPlanner.validate(decision, original: input, records: records); return decision }
            catch {
                if [.addMedicine, .updateMedicine, .removeMedicine, .scheduleMedicine, .clearData].contains(decision.tool) {
                    let answer = try await generate(ToolPlanner.medicineClarificationPrompt(tool: decision.tool, records: records), maxTokens: 96, stopAtJSON: false)
                    let reply = ToolDecision(tool: .reply, arg: answer)
                    _ = try ToolPlanner.validate(reply, original: input, records: records)
                    return reply
                }
            }
        }
        // A tool with missing source facts cannot run. Let the model answer or clarify normally.
        try Task.checkCancellation()
        let answer = try await generate(resolved.styleConversation(ToolPlanner.conversationPrompt(input, records: records, history: history)), maxTokens: effort.chatTokens, stopAtJSON: false)
        return ToolDecision(tool: .reply, arg: answer)
    }
    func toolResponse(_ payload: String, history: [ConversationTurn]) async throws -> String {
        let prompt = ToolPlanner.toolResultPrompt(payload, history: history)
        let chosen = resolved
        let sampling = chosen == .balanced ? ModelSampling(temperature: 0.2) : .greedy
        let answer = try await generate(prompt, maxTokens: effort.chatTokens, stopAtJSON: false, model: chosen, sampling: sampling)
        _ = try ToolPlanner.validate(ToolDecision(tool: .reply, arg: answer), original: "", records: Records())
        return answer
    }
    /// Only generated prose changes language. Source evidence and machine formats stay exact.
    private func localizedPrompt(_ prompt: String) -> String { ModelLanguage.prompt(prompt, french: L10n.isFrench) }
    func remove(_ model: ModelChoice) async throws {
        guard !generating else { throw NSError(domain: "Inference", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.string("Stop the current request before removing its model.")]) }
        await runtime.unload()
        let chosen = model == .automatic ? resolved : model
        for asset in chosen.assets {
            let file = directory.appendingPathComponent(asset.filename)
            try? FileManager.default.removeItem(at: file.appendingPathExtension("verified"))
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
        revision += 1
    }
}


extension ModelManager {
    func title(for message: String) async throws -> String? {
        let output = try await generate(ChatTitles.prompt(message, french: L10n.isFrench), maxTokens: L10n.isFrench ? 96 : 48, responseGrammar: L10n.isFrench ? TitleOutputGrammar.make() : nil)
        return ChatTitles.parse(output)
    }
}
