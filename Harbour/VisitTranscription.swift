import Foundation
import AVFoundation
import Speech

@MainActor enum VisitTranscription {
    static func transcribe(_ url: URL, status: @escaping (String) -> Void) async throws -> String {
        let permission = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard permission == .authorized else { throw NSError(domain: "Visit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Allow Speech Recognition access in iPhone Settings, or edit the transcript manually."]) }
        if #available(iOS 26, *) { return try await modern(url, status: status) }
        return try await legacy(url, status: status)
    }
    @available(iOS 26, *)
    private static func modern(_ url: URL, status: @escaping (String) -> Void) async throws -> String {
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-CA")) else { throw NSError(domain: "Visit", code: 3, userInfo: [NSLocalizedDescriptionKey: "On-device English transcription is unavailable on this phone."]) }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            status("Downloading speech recognition")
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        return try await withTaskCancellationHandler {
            let result = Task { @MainActor in
                var text: [String] = []
                for try await value in transcriber.results {
                    try Task.checkCancellation()
                    text.append(String(value.text.characters))
                    status("Transcribing · \(min(100, Int(value.range.start.seconds / max(1, Double(file.length) / file.processingFormat.sampleRate) * 100)))%")
                }
                return text.joined(separator: " ")
            }
            do { try await analyzer.start(inputAudioFile: file, finishAfterFile: true); return try await result.value }
            catch { result.cancel(); await analyzer.cancelAndFinishNow(); throw error }
        } onCancel: { Task { await analyzer.cancelAndFinishNow() } }
    }
    private static func legacy(_ url: URL, status: @escaping (String) -> Void) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-CA")), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw NSError(domain: "Visit", code: 3, userInfo: [NSLocalizedDescriptionKey: "On-device English transcription is unavailable on this phone."]) }
        let file = try AVAudioFile(forReading: url), format = file.processingFormat
        let capacity = AVAudioFrameCount(format.sampleRate * 44)
        var result: [String] = []
        while file.framePosition < file.length {
            try Task.checkCancellation()
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw CocoaError(.fileReadUnknown) }
            try file.read(into: buffer, frameCount: min(capacity, AVAudioFrameCount(min(Int64(capacity), file.length - file.framePosition))))
            let chunk = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
            defer { try? FileManager.default.removeItem(at: chunk) }
            do {
                let output = try AVAudioFile(forWriting: chunk, settings: format.settings)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: chunk.path)
                try output.write(from: buffer)
            }
            status("Transcribing · \(Int(Double(file.framePosition) / Double(file.length) * 100))%")
            let request = SFSpeechURLRecognitionRequest(url: chunk)
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = false
            let operation = LegacyFileRecognition()
            result.append(try await operation.run(request: request, recognizer: recognizer))
        }
        return result.joined(separator: " ")
    }
}
@MainActor private final class LegacyFileRecognition {
    private var continuation: CheckedContinuation<String, Error>?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    func run(request: SFSpeechURLRecognitionRequest, recognizer: SFSpeechRecognizer) async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                task = recognizer.recognitionTask(with: request) { [weak self] result, error in Task { @MainActor in
                    if let error { self?.complete(.failure(error)) }
                    else if let result, result.isFinal { self?.complete(.success(result.bestTranscription.formattedString)) }
                } }
                timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    self?.complete(.failure(NSError(domain: "Visit", code: 4, userInfo: [NSLocalizedDescriptionKey: "Transcription timed out. Audio and the previous transcript are preserved."])))
                }
            }
        } onCancel: { Task { @MainActor in self.complete(.failure(CancellationError())) } }
    }
    private func complete(_ result: Result<String, Error>) {
        guard let continuation else { return }; self.continuation = nil
        timeout?.cancel(); timeout = nil; task?.cancel(); task = nil
        continuation.resume(with: result)
    }
}
