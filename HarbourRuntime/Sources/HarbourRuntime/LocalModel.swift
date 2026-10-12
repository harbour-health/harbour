import Foundation
import llama

public enum ModelError: LocalizedError {
    case load, context, promptTooLong, tokenize, decode, sampler, grammar, promptFormat
    public var errorDescription: String? {
        switch self {
        case .load: "The model could not be opened. Remove it and download it again."
        case .context: "There isn’t enough memory to start this model. Choose Qwen Small."
        case .promptTooLong: "The message is too long. Please shorten it."
        case .tokenize: "The model could not read this message."
        case .decode: "The model stopped unexpectedly. Please try again."
        case .sampler: "The model could not start generating a response. Please try again."
        case .grammar: "The model could not prepare the required response format. Please try again."
        case .promptFormat: "The model could not prepare this request. Please try again."
        }
    }
}

/// All C pointers and inference work stay inside this actor, off the UI actor.
public actor LocalModel {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var path: String?
    private var backendStarted = false
    public init() {}
    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }
    public func unload() {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil; model = nil; path = nil
    }
    private func load(_ file: URL) throws {
        if path == file.path && context != nil { return }
        unload()
        if !backendStarted { llama_backend_init(); backendStarted = true }
        var mp = llama_model_default_params()
        #if targetEnvironment(simulator)
        mp.n_gpu_layers = 0
        #else
        mp.n_gpu_layers = 99
        #endif
        guard let loaded = llama_model_load_from_file(file.path, mp) else { throw ModelError.load }
        var cp = llama_context_default_params()
        cp.n_ctx = 4096; cp.n_batch = 512
        cp.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.processorCount - 2)))
        cp.n_threads_batch = cp.n_threads
        guard let ctx = llama_init_from_model(loaded, cp) else { llama_model_free(loaded); throw ModelError.context }
        model = loaded; context = ctx; path = file.path
    }
    public func generate(file: URL, prompt: String, maxTokens: Int = 160, grammar: String? = nil, stopAtJSON: Bool = true, promptFormat: ModelPromptFormat = .qwen25) throws -> String {
        try Task.checkCancellation()
        let prompt = try promptFormat.prepare(prompt)
        if let grammar, grammar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || grammar.contains("\0") {
            throw ModelError.grammar
        }
        try load(file)
        guard let model, let context else { throw ModelError.load }
        let vocab = llama_model_get_vocab(model)
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 16)
        let count = tokens.withUnsafeMutableBufferPointer { buffer in
            llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), buffer.baseAddress, Int32(buffer.count), false, true)
        }
        guard count > 0 else { throw ModelError.tokenize }
        guard Int(count) + maxTokens < 4096 else { throw ModelError.promptTooLong }
        tokens = Array(tokens.prefix(Int(count)))
        llama_memory_clear(llama_get_memory(context), true)
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else { throw ModelError.sampler }
        defer { llama_sampler_free(sampler) }
        if let grammar {
            guard let constrained = llama_sampler_init_grammar(vocab, grammar, "root") else { throw ModelError.grammar }
            llama_sampler_chain_add(sampler, constrained)
        }
        guard let greedy = llama_sampler_init_greedy() else { throw ModelError.sampler }
        llama_sampler_chain_add(sampler, greedy)
        var batch = llama_batch_init(512, 0, 1)
        defer { llama_batch_free(batch) }
        func decode(_ items: [llama_token], start: Int) throws {
            batch.n_tokens = Int32(items.count)
            for i in items.indices {
                batch.token[i] = items[i]; batch.pos[i] = Int32(start + i)
                batch.n_seq_id[i] = 1; batch.seq_id[i]![0] = 0
                batch.logits[i] = Int8(i == items.count - 1 ? 1 : 0)
            }
            guard llama_decode(context, batch) == 0 else { throw ModelError.decode }
        }
        for offset in stride(from: 0, to: tokens.count, by: 512) {
            try Task.checkCancellation()
            try decode(Array(tokens[offset..<min(offset + 512, tokens.count)]), start: offset)
        }
        var bytes: [UInt8] = [], position = tokens.count
        for _ in 0..<maxTokens {
            try Task.checkCancellation()
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            var piece = [CChar](repeating: 0, count: 256)
            var length = piece.withUnsafeMutableBufferPointer { llama_token_to_piece(vocab, token, $0.baseAddress, 256, 0, false) }
            if length < 0 {
                piece = [CChar](repeating: 0, count: Int(-length))
                length = piece.withUnsafeMutableBufferPointer { llama_token_to_piece(vocab, token, $0.baseAddress, Int32($0.count), 0, false) }
            }
            if length > 0 { bytes.append(contentsOf: piece.prefix(Int(length)).map { UInt8(bitPattern: $0) }) }
            let current = String(decoding: bytes, as: UTF8.self)
            if stopAtJSON, let complete = JSONEnvelope.completePrefix(in: current) { return complete }
            try decode([token], start: position); position += 1
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
