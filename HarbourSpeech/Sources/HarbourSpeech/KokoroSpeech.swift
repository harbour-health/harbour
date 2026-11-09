import Foundation
import CPhonemizer
@preconcurrency import OnnxRuntimeBindings

public enum KokoroVoice: String, CaseIterable, Codable, Sendable {
    case female = "af_heart", male = "am_liam"
    public static func restored(_ raw: String?) -> Self {
        raw.flatMap(Self.init(rawValue:)) ?? .female
    }
}

public enum KokoroLanguage: String, Sendable { case english = "en-us", french = "fr-fr" }

public enum KokoroError: LocalizedError {
    case phonemizer, input, assets, output
    public var errorDescription: String? {
        switch self {
        case .phonemizer: "Couldn’t prepare speech pronunciation."
        case .input: "Couldn’t pronounce this text."
        case .assets: "The downloaded voice files are incomplete. Download them again."
        case .output: "Couldn’t generate voice audio."
        }
    }
}

public enum KokoroText {
    /// Keep requests short enough for bounded memory, cancellation and quick first audio.
    /// Decimal punctuation stays attached to numbers.
    public static func chunks(_ text: String, maximumCharacters: Int = 180) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace)
        var chunks: [String] = [], current = ""
        for word in words {
            if !current.isEmpty && current.count + word.count + 1 > maximumCharacters {
                chunks.append(current)
                current = ""
            }
            if !current.isEmpty {
                current += " "
            }
            current += word
            if word.last.map({ ".!?".contains($0) }) == true {
                chunks.append(current)
                current = "" }
        }
        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }
}

/// One actor owns ONNX and eSpeak's process-global phonemizer state. No Apple TTS fallback.
public actor KokoroSpeechEngine {
    public static let shared = KokoroSpeechEngine()
    public static let sampleRate: Double = 24_000
    private var initialized = false
    private var environment: ORTEnv?
    private var session: ORTSession?
    private var loadedPath: String?
    private var vocabulary: [String: Int64] = [:]
    private init() {}

    public func phonemes(_ text: String, language: KokoroLanguage) throws -> String {
        if !initialized {
            guard
                let source = Bundle.module.url(forResource: "espeak-ng-data", withExtension: nil),
                let file = Bundle.module.url(forResource: "vocab", withExtension: "json")
            else {
                throw KokoroError.phonemizer
            }

            // eSpeak has legacy fixed-size internal path buffers. Apple simulator
            // and SwiftPM bundle paths can exceed them; use a short, non-health cache.
            #if os(macOS) || targetEnvironment(simulator)
                let parent = URL(fileURLWithPath: "/tmp/harbour-espeak-4870adfa", isDirectory: true)
            #else
                let parent = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent(
                        "Pronunciation",
                        isDirectory: true
                    )
            #endif
            let data = parent.appendingPathComponent("espeak-ng-data", isDirectory: true)
            if !FileManager.default.fileExists(atPath: data.appendingPathComponent("fr_dict").path) {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: data)
            }

            guard harbour_phonemizer_initialize(parent.path) > 0 else {
                throw KokoroError.phonemizer
            }

            vocabulary = try JSONDecoder().decode([String: Int64].self, from: Data(contentsOf: file))
            initialized = true
        }
        // eSpeak consumes clause punctuation. Restore it as Kokoro prosody tokens,
        // using the same preservation policy as the local ONNX audition frontend.
        let characters = Array(text)
        var pieces: [String] = [], segment = ""
        func appendSegment() throws {
            guard !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                segment = ""

                return }
            guard let result = harbour_phonemize(segment, language.rawValue) else {
                throw KokoroError.input
            }

            defer { harbour_phonemizer_free(result) }
            pieces.append(String(cString: result).trimmingCharacters(in: .whitespacesAndNewlines))
            segment = ""
        }
        for (index, character) in characters.enumerated() {
            let decimal = ".,".contains(character) && index > 0 && index + 1 < characters.count && characters[index - 1]
                .isNumber && characters[index + 1].isNumber
            if ";:,.!?—…".contains(character) && !decimal {
                try appendSegment()
                if !pieces.isEmpty {
                    pieces[pieces.count - 1] += String(character)
                }
            } else {
                segment.append(character)
            }
        }
        try appendSegment()
        let joined = pieces.joined(separator: " ")

        return String(String.UnicodeScalarView(joined.unicodeScalars.filter { vocabulary[String($0)] != nil }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func synthesize(
        _ text: String,
        language: KokoroLanguage,
        model: URL,
        voiceFile: URL,
        speed: Float = 1
    ) throws -> [Float] {
        try Task.checkCancellation()

        guard speed.isFinite, (0.8 ... 1.3).contains(speed) else {
            throw KokoroError.input
        }

        let phonemes = try phonemes(text, language: language)
        let ids = phonemes.unicodeScalars.compactMap { vocabulary[String($0)] }

        guard !ids.isEmpty, ids.count <= 510 else {
            throw KokoroError.input
        }

        if loadedPath != model.path || session == nil {
            let env = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()
            try options.setIntraOpNumThreads(2)
            // CPU ONNX inference deliberately avoids the Core ML Kokoro crash path.
            session = try ORTSession(env: env, modelPath: model.path, sessionOptions: options)
            environment = env
            loadedPath = model.path
        }

        guard let session else {
            throw KokoroError.assets
        }

        let styles = try Data(contentsOf: voiceFile, options: .mappedIfSafe)

        guard styles.count == 510 * 256 * MemoryLayout<Float>.size else {
            throw KokoroError.assets
        }

        let row = min(ids.count, 510) - 1
        let style = styles.subdata(in: (row * 1024) ..< ((row + 1) * 1024))
        let tokens = [Int64(0)] + ids + [Int64(0)]
        let tokenData = tokens.withUnsafeBytes { NSMutableData(bytes: $0.baseAddress!, length: $0.count) }
        var speed = speed
        let speedData = withUnsafeBytes(of: &speed) { NSMutableData(bytes: $0.baseAddress!, length: $0.count) }
        let names = try session.inputNames()
        let input = names.contains("input_ids") ? "input_ids" : "tokens"
        let outputs = try session.outputNames()

        guard let outputName = outputs.first else {
            throw KokoroError.output
        }

        let result = try session.run(withInputs: [
            input: try ORTValue(tensorData: tokenData, elementType: .int64, shape: [1, NSNumber(value: tokens.count)]),
            "style": try ORTValue(tensorData: NSMutableData(data: style), elementType: .float, shape: [1, 256]),
            "speed": try ORTValue(tensorData: speedData, elementType: .float, shape: [1])
        ], outputNames: Set([outputName]), runOptions: nil)
        try Task.checkCancellation()

        guard let value = result[outputName] else {
            throw KokoroError.output
        }

        let bytes = try value.tensorData() as Data
        let samples = bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }

        guard
            !samples.isEmpty, samples.count <= 24_000 * 90,
            samples.allSatisfy(\.isFinite) else {
            throw KokoroError.output
        }

        return samples
    }

    public func unload() {
        session = nil
        environment = nil
        loadedPath = nil }
}
