import Foundation
import AVFoundation
import Speech
import HarbourCore

private final class VisitObservation: @unchecked Sendable {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

@MainActor private final class VisitPermission {
    private var continuation: CheckedContinuation<Bool, Never>?
    func wait(_ begin: (@escaping @Sendable (Bool) -> Void) -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            begin { [weak self] value in Task { @MainActor in self?.resolve(value) } }
        }
    }
    func resolve(_ value: Bool) { let pending = continuation; continuation = nil; pending?.resume(returning: value) }
}

private func visitError(_ message: String) -> NSError { NSError(domain: "Visit", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

/// The audio tap owns this locked writer. PCM stays off the UI actor; only meter values cross it.
private final class VisitAudioWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private let speech: @Sendable (AVAudioPCMBuffer) -> Void
    private let meter: @Sendable (Double) -> Void
    private let failure: @Sendable (String) -> Void
    private var meteredFrames: AVAudioFrameCount = 0
    private var paused = false
    init(url: URL, format: AVAudioFormat, speech: @escaping @Sendable (AVAudioPCMBuffer) -> Void, meter: @escaping @Sendable (Double) -> Void, failure: @escaping @Sendable (String) -> Void) throws {
        file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount, AVEncoderBitRateKey: 32_000], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        self.speech = speech; self.meter = meter; self.failure = failure
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let file, !paused else { return }
        do { try file.write(from: buffer) }
        catch { self.file = nil; failure(L10n.format("Recording stopped because the audio couldn’t be saved. %@", error.localizedDescription)); return }
        speech(buffer)
        meteredFrames += buffer.frameLength
        if meteredFrames >= AVAudioFrameCount(buffer.format.sampleRate / 8), let values = buffer.floatChannelData?[0] {
            meteredFrames = 0
            var power: Float = 0
            for index in 0..<Int(buffer.frameLength) { power += values[index] * values[index] }
            meter(min(1, Double(sqrt(power / Float(max(1, buffer.frameLength)))) * 9))
        }
    }
    func setPaused(_ paused: Bool) { lock.lock(); self.paused = paused; lock.unlock() }
    func close() { lock.lock(); file = nil; lock.unlock() }
}

@MainActor private protocol VisitSpeechSession: AnyObject {
    var append: @Sendable (AVAudioPCMBuffer) -> Void { get }
    func finish() async throws
    func cancel()
}

@available(iOS 26, *)
private final class ModernAudioBridge: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let failure: @Sendable (String) -> Void
    init(input: AVAudioFormat, output: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation, failure: @escaping @Sendable (String) -> Void) throws {
        guard let converter = AVAudioConverter(from: input, to: output) else { throw visitError(L10n.string("The microphone format isn’t supported for transcription.")) }
        self.converter = converter; self.outputFormat = output; self.continuation = continuation; self.failure = failure
    }
    // Called only by the writer's locked audio tap.
    func append(_ input: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * outputFormat.sampleRate / input.format.sampleRate)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var supplied = false, error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        if status == .error { failure(error?.localizedDescription ?? L10n.string("Transcription lost an audio segment.")); return }
        if output.frameLength > 0, case .dropped = continuation.yield(AnalyzerInput(buffer: output)) {
            failure(L10n.string("Live transcription fell behind. The audio is saved; transcribe it again after the visit."))
        }
    }
}

@available(iOS 26, *)
@MainActor private final class ModernVisitSpeech: VisitSpeechSession {
    let analyzer: SpeechAnalyzer
    let transcriber: SpeechTranscriber
    let continuation: AsyncStream<AnalyzerInput>.Continuation
    private var resultTask: Task<Void, Error>?
    private var pieces: [(start: Double, end: Double, text: String)] = []
    var append: @Sendable (AVAudioPCMBuffer) -> Void = { _ in }
    private init(analyzer: SpeechAnalyzer, transcriber: SpeechTranscriber, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.analyzer = analyzer; self.transcriber = transcriber; self.continuation = continuation
    }
    static func prepare(format: AVAudioFormat, transcript: @escaping (String) -> Void, status: @escaping (String) -> Void, failure: @escaping @Sendable (String) -> Void) async throws -> ModernVisitSpeech {
        guard SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: SpeechLanguage.locale) else { throw visitError(L10n.string("On-device transcription isn’t available in the app’s language. You can still save audio or type visit notes.")) }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            status(L10n.string("Downloading speech recognition"))
            let progress = Task { @MainActor in
                while !Task.isCancelled { status(L10n.format("Downloading speech recognition · %d%%", Int(request.progress.fractionCompleted * 100))); try? await Task.sleep(for: .milliseconds(250)) }
            }
            defer { progress.cancel() }
            try await request.downloadAndInstall()
        }
        guard let output = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: format) else { throw visitError(L10n.string("No supported transcription audio format was found.")) }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(128))
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let session = ModernVisitSpeech(analyzer: analyzer, transcriber: transcriber, continuation: continuation)
        let bridge = try ModernAudioBridge(input: format, output: output, continuation: continuation, failure: failure)
        session.append = { buffer in bridge.append(buffer) }
        try await analyzer.prepareToAnalyze(in: output)
        session.resultTask = Task { @MainActor [weak session] in
            do {
                for try await result in transcriber.results {
                    guard let session else { return }
                    let start = result.range.start.seconds, end = CMTimeRangeGetEnd(result.range).seconds
                    session.pieces.removeAll { $0.start < end && $0.end > start || abs($0.start - start) < 0.001 }
                    session.pieces.append((start, end, String(result.text.characters)))
                    transcript(session.pieces.sorted { $0.start < $1.start }.map(\.text).joined(separator: " "))
                }
            } catch { failure(L10n.format("Live transcription stopped. Your audio is still being saved. %@", error.localizedDescription)); throw error }
        }
        try await analyzer.start(inputSequence: stream)
        return session
    }
    func finish() async throws {
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await resultTask?.value
    }
    func cancel() { continuation.finish(); resultTask?.cancel(); Task { await analyzer.cancelAndFinishNow() } }
}

private final class LegacyAudioBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) { lock.lock(); self.request = request; lock.unlock() }
    func append(_ buffer: AVAudioPCMBuffer) { lock.lock(); request?.append(buffer); lock.unlock() }
}
@MainActor private final class LegacyVisitSpeech: VisitSpeechSession {
    private let recognizer: SFSpeechRecognizer
    private let bridge = LegacyAudioBridge()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var rotation: Task<Void, Never>?
    private var pieces: [Int: String] = [:]
    private var index = 0
    private var stopped = false
    private let transcript: (String) -> Void
    private let failure: @Sendable (String) -> Void
    var append: @Sendable (AVAudioPCMBuffer) -> Void { let bridge = bridge; return { bridge.append($0) } }
    init(transcript: @escaping (String) -> Void, failure: @escaping @Sendable (String) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(locale: SpeechLanguage.locale), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw visitError(L10n.string("On-device transcription isn’t available in the app’s language. Audio can still be recorded.")) }
        self.recognizer = recognizer; self.transcript = transcript; self.failure = failure
        beginSegment()
        rotation = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(45)) } catch { return }
                guard let self, !self.stopped else { return }; self.beginSegment()
            }
        }
    }
    private func beginSegment() {
        request?.endAudio()
        if let previous = task { Task { try? await Task.sleep(for: .seconds(3)); previous.cancel() } }
        index += 1; let current = index
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
        self.request = request; bridge.set(request)
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                if let result { self.pieces[current] = result.bestTranscription.formattedString; self.transcript(self.pieces.keys.sorted().compactMap { self.pieces[$0] }.joined(separator: " ")) }
                if error != nil && current == self.index { self.failure(L10n.string("Live transcription paused. The full audio is still being saved.")) }
            }
        }
    }
    func finish() async throws {
        rotation?.cancel(); bridge.set(nil); request?.endAudio()
        // Keep the final recognition callback alive briefly; preserve partial text if the service fails.
        for _ in 0..<15 where task?.state != .completed { try await Task.sleep(for: .milliseconds(100)) }
        stopped = true; task?.cancel()
    }
    func cancel() { stopped = true; rotation?.cancel(); bridge.set(nil); request?.endAudio(); task?.cancel() }
}

@MainActor final class VisitRecorder: ObservableObject {
    enum State { case idle, preparing, recording, paused, finishing }
    @Published private(set) var state: State = .idle
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var transcript = ""
    @Published private(set) var levels: [Double] = Array(repeating: 0.04, count: 48)
    @Published private(set) var status = ""
    @Published var error: String?
    @Published private(set) var visitID: UUID?
    private let engine = AVAudioEngine()
    private var writer: VisitAudioWriter?
    private var speech: (any VisitSpeechSession)?
    private var timer: Task<Void, Never>?
    private var generation = UUID()
    private var startDate: Date?
    private var elapsed: TimeInterval = 0
    private var visit: DoctorVisit?
    private var transcriptionWarning: String?
    private weak var store: AppStore?
    private var hasTap = false
    private var permission: VisitPermission?
    private var interruption: VisitObservation?
    var active: Bool { state != .idle }
    init() {
        interruption = VisitObservation(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let kind = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if kind == AVAudioSession.InterruptionType.began.rawValue { Task { @MainActor in self?.pause(); self?.status = L10n.string("Recording paused by an interruption") } }
        })
    }
    func start(into store: AppStore) async {
        guard state == .idle else { return }
        let current = UUID(); generation = current; state = .preparing; status = L10n.string("Preparing microphone"); self.store = store
        error = nil; transcriptionWarning = nil; transcript = ""; duration = 0; elapsed = 0; levels = Array(repeating: 0.04, count: 48)
        let microphone = VisitPermission(); permission = microphone
        let granted = await microphone.wait { AVAudioApplication.requestRecordPermission(completionHandler: $0) }
        guard generation == current else { return }
        guard granted else { state = .idle; error = L10n.string("Allow microphone access in iPhone Settings to record a visit."); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: []); try session.setActive(true)
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw visitError(L10n.string("No microphone is available.")) }
            let speechAccess = VisitPermission(); permission = speechAccess
            let speechGranted = await speechAccess.wait { completion in SFSpeechRecognizer.requestAuthorization { completion($0 == .authorized) } }
            guard generation == current else { return }
            let failed: @Sendable (String) -> Void = { [weak self] message in Task { @MainActor in
                guard let self, self.generation == current else { return }; self.status = message; self.transcriptionWarning = message
            } }
            let received: (String) -> Void = { [weak self] text in
                guard let self, self.generation == current else { return }; self.transcript = text
            }
            var preparedSpeech: (any VisitSpeechSession)?
            if speechGranted {
                do {
                    if #available(iOS 26, *) { preparedSpeech = try await ModernVisitSpeech.prepare(format: format, transcript: received, status: { [weak self] value in guard self?.generation == current else { return }; self?.status = value }, failure: failed) }
                    else { preparedSpeech = try LegacyVisitSpeech(transcript: received, failure: failed) }
                } catch { if generation == current { status = L10n.format("Audio only · %@", error.localizedDescription); transcriptionWarning = status } }
            } else { status = L10n.string("Audio only · Speech access is off"); transcriptionWarning = status }
            guard generation == current else { preparedSpeech?.cancel(); return }
            speech = preparedSpeech
            try FileManager.default.createDirectory(at: store.visitAudioDirectory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            var newVisit = DoctorVisit(title: L10n.string("Doctor visit"), interrupted: true)
            newVisit.transcriptionWarning = transcriptionWarning
            newVisit.audioFilename = newVisit.id.uuidString + ".m4a"
            guard store.saveVisit(newVisit) else { throw visitError(L10n.string("The visit couldn’t be saved. Recording has not started.")) }
            visit = newVisit; visitID = newVisit.id
            let handler: @Sendable (AVAudioPCMBuffer) -> Void
            if let speech { handler = speech.append } else { handler = { @Sendable _ in } }
            writer = try VisitAudioWriter(url: store.audioURL(for: newVisit)!, format: format, speech: handler, meter: { [weak self] value in Task { @MainActor in
                guard let self, self.generation == current, self.state == .recording else { return }
                self.levels.removeFirst(); self.levels.append(max(0.04, value))
            } }, failure: { [weak self] message in Task { @MainActor in
                guard let self, self.generation == current else { return }; self.error = message; await self.finish(interrupted: true)
            } })
            let writer = writer!
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in writer.append(buffer) }; hasTap = true
            engine.prepare(); try engine.start(); state = .recording; startDate = .now
            if speech != nil { status = L10n.string("Transcribing on this iPhone") }
            timer = Task { @MainActor [weak self] in
                var ticks = 0
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    guard let self else { return }
                    if self.state == .recording { self.duration = self.elapsed + Date.now.timeIntervalSince(self.startDate ?? .now) }
                    ticks += 1
                    if ticks % 40 == 0 { self.checkpoint(interrupted: true) }
                    if self.duration >= 5400 { self.status = L10n.string("90-minute recording limit reached"); await self.finish(); return }
                }
            }
        } catch { await finish(interrupted: true); state = .idle; self.error = L10n.string(error.localizedDescription) }
    }
    func pause() {
        guard state == .recording else { return }
        duration = elapsed + Date.now.timeIntervalSince(startDate ?? .now); elapsed = duration; startDate = nil
        writer?.setPaused(true); engine.pause(); state = .paused; checkpoint(interrupted: true)
    }
    func resume() {
        guard state == .paused else { return }
        do { try AVAudioSession.sharedInstance().setActive(true); try engine.start(); writer?.setPaused(false); startDate = .now; state = .recording }
        catch { self.error = L10n.string(error.localizedDescription) }
    }
    func finish(interrupted: Bool = false) async {
        guard state != .idle && state != .finishing else { return }
        if state == .preparing {
            generation = UUID(); permission?.resolve(false); permission = nil; speech?.cancel(); speech = nil; timer?.cancel(); timer = nil
            engine.stop(); if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
            writer?.close(); writer = nil; checkpoint(interrupted: true)
            state = .idle; try? AVAudioSession.sharedInstance().setActive(false); return
        }
        pause(); state = .finishing; timer?.cancel(); timer = nil
        engine.stop(); if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        writer?.close(); writer = nil; checkpoint(interrupted: interrupted)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if interrupted { speech?.cancel() }
        else {
            let session = speech
            let timeout = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                session?.cancel()
            }
            defer { timeout.cancel() }
            do { try await session?.finish() } catch { status = L10n.string("Transcript may be incomplete. The audio is saved."); transcriptionWarning = status }
        }
        speech?.cancel(); speech = nil; checkpoint(interrupted: interrupted); state = .idle; visitID = nil; generation = UUID()
    }
    private func checkpoint(interrupted: Bool) {
        guard var visit, let store else { return }
        visit.duration = duration; visit.transcript = transcript; visit.interrupted = interrupted; visit.transcriptionWarning = transcriptionWarning
        self.visit = visit
        if !store.saveVisit(visit) { error = L10n.string("The transcript couldn’t be saved. Finish recording before making other changes.") }
    }
}

@MainActor final class VisitPlayback: ObservableObject {
    @Published var playing = false
    @Published var position: TimeInterval = 0
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var timer: Task<Void, Never>?
    func toggle(url: URL) {
        if playing { stop(); return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url); player?.currentTime = position
            guard player?.play() == true else { throw visitError(L10n.string("The recording couldn’t be played.")) }
            playing = true
            timer = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                    guard let self else { return }; self.position = self.player?.currentTime ?? 0
                    if self.player?.isPlaying != true { self.stop(); self.position = 0; return }
                }
            }
        } catch { self.error = L10n.string(error.localizedDescription) }
    }
    func stop() { let owned = playing; player?.pause(); playing = false; timer?.cancel(); timer = nil; if owned { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) } }
}
