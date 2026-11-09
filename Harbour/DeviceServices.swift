import Foundation
import HealthKit
import Speech
import AVFoundation
import HarbourCore
import UIKit
import HarbourSpeech

/// Speech stays in the app's language; an unavailable local voice never changes languages.
enum SpeechLanguage {
    static var identifier: String {
        L10n.isFrench ? "fr-CA" : "en-CA"
    }

    static var locale: Locale {
        Locale(identifier: identifier)
    }
}

@MainActor final class HealthService: ObservableObject {
    @Published var busy = false
    @Published var status = ""
    private let health = HKHealthStore()
    private let types: Set<HKObjectType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.bodyTemperature),
        HKQuantityType(.bloodPressureSystolic),
        HKQuantityType(.bloodPressureDiastolic)
    ]
    func sync(into store: AppStore) async {
        guard HKHealthStore.isHealthDataAvailable()
        else {
            status = L10n.string("Apple Health is unavailable on this device.")

            return }

        busy = true
        defer { busy = false }
        do {
            try await health.requestAuthorization(toShare: [], read: types)
            var imported: [Reading] = []
            for (identifier, kind, unit) in [
                (HKQuantityTypeIdentifier.heartRate, ReadingKind.heartRate, HKUnit.count().unitDivided(by: .minute())),
                (.bodyTemperature, .temperature, .degreeCelsius())
            ] {
                let samples = try await query(HKQuantityType(identifier))
                imported += samples.compactMap { sample in

                    guard let quantity = sample as? HKQuantitySample else {
                        return nil
                    }

                    let number = quantity.quantity.doubleValue(for: unit)

                    return Reading(
                        id: "health-" + sample.uuid.uuidString,
                        kind: kind,
                        value: String(format: kind == .temperature ? "%.1f" : "%.0f", number),
                        date: sample.startDate,
                        source: "Apple Health"
                    )
                }
            }
            let pressures = try await query(HKCorrelationType(.bloodPressure))
            imported += pressures.compactMap { sample in

                guard
                    let correlation = sample as? HKCorrelation,
                    let systolic = correlation.objects(for: HKQuantityType(.bloodPressureSystolic))
                        .first as? HKQuantitySample,
                    let diastolic = correlation.objects(for: HKQuantityType(.bloodPressureDiastolic))
                        .first as? HKQuantitySample else {
                    return nil
                }

                let value = String(
                    format: "%.0f/%.0f",
                    systolic.quantity.doubleValue(for: .millimeterOfMercury()),
                    diastolic.quantity.doubleValue(for: .millimeterOfMercury())
                )

                return Reading(
                    id: "health-" + sample.uuid.uuidString,
                    kind: .bloodPressure,
                    value: value,
                    date: sample.startDate,
                    source: "Apple Health"
                )
            }
            imported = imported.filter { ReadingParser.valid($0.value, kind: $0.kind) }
            let newCount = imported.filter { r in !store.records.readings.contains { $0.id == r.id } }.count
            store.importReadings(imported)
            status = imported.isEmpty ? L10n
                .string("No readings available. Check Apple Health access and the last 30 days of data.") : L10n.format(
                    "%d new readings imported.",
                    newCount
                )
        } catch { status = L10n.string("Couldn’t access Apple Health. Check access in Settings.") }
    }

    private func query(_ type: HKSampleType) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: Calendar.current.date(byAdding: .day, value: -30, to: .now),
                end: .now
            )
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 100,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            health.execute(query)
        }
    }
}

@MainActor final class VoiceService: NSObject, ObservableObject {
    let visualization = VoiceVisualization()
    @Published private(set) var preparingInput = false
    @Published private(set) var listening = false
    @Published private(set) var speaking = false
    @Published private(set) var finishing = false
    @Published private(set) var transcript = ""
    @Published var error: String?
    private var engine = AVAudioEngine()
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var hasTap = false
    private var turn = VoiceTurn()
    private var generation = UUID()
    @Published private(set) var preparingSpeech = false
    private var hasPlaybackTap = false
    private var playback = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var speechTask: Task<Void, Never>?
    private var queuedBuffers = 0
    private var allSpeechScheduled = false
    private var audioSessionOwned = false
    private var silence: Task<Void, Never>?
    private var finalTimeout: Task<Void, Never>?
    private var received: ((String) -> Void)?
    private var completed: ((String) -> Void)?
    private var spoken: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in

            guard
                let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                AVAudioSession.InterruptionType(rawValue: raw) == .began else {
                return
            }

            Task { @MainActor in
                self?.interrupt(L10n.string("Voice was interrupted. Start voice again when you’re ready.")) }
        })
        observers
            .append(center
                .addObserver(
                    forName: AVAudioSession.routeChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in

                    guard
                        let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                        AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else {
                        return
                    }

                    Task { @MainActor in
                        self?
                            .interrupt(L10n
                                .string("The audio device disconnected. Start voice again when you’re ready.")) }
                })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in

                guard let self else {
                    return
                }

                self.interrupt(L10n.string("Audio restarted. Start voice again when you’re ready."))
                self.engine = AVAudioEngine()
                self.playback = AVAudioEngine()
                self.player = AVAudioPlayerNode()
            }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        })
    }

    deinit { for observer in observers {
        NotificationCenter.default.removeObserver(observer)
    } }
    private func interrupt(_ message: String) {
        guard audioSessionOwned || received != nil || spoken != nil else {
            return
        }

        stop()
        error = message
    }

    func start(transcript: @escaping (String) -> Void, finished: ((String) -> Void)? = nil) async {
        stop()
        let current = turn.begin()
        generation = current
        received = transcript
        completed = finished
        self.transcript = ""
        error = nil
        preparingInput = true

        guard UIApplication.shared.applicationState == .active else {
            stop()

            return }

        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }

        guard generation == current else {
            return
        }
        guard speech == .authorized else {
            stop()
            error = L10n.string("Enable speech access in Settings.")

            return }
        guard UIApplication.shared.applicationState == .active else {
            stop()

            return }

        let microphone = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) } }

        guard generation == current else {
            return
        }
        guard microphone else {
            stop()
            error = L10n.string("Enable microphone access in Settings.")

            return }
        guard UIApplication.shared.applicationState == .active else {
            stop()

            return }
        guard
            let recognizer = SFSpeechRecognizer(locale: SpeechLanguage.locale), recognizer.isAvailable,
            recognizer.supportsOnDeviceRecognition else {
            stop()
            error = L10n.string("On-device speech isn’t available in the app’s language on this phone.")

            return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
            audioSessionOwned = true
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            let input = engine.inputNode, format = input.outputFormat(forBus: 0)

            guard format.sampleRate > 0 else {
                throw NSError(
                    domain: "Audio",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: L10n.string("No microphone is available.")]
                ) }

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                let level = Self.audioLevel(buffer)
                Task { @MainActor in

                    guard let self, self.generation == current, self.listening else {
                        return
                    }

                    self.visualization.update(level)
                }
            }
            hasTap = true
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                Task { @MainActor in

                    guard let self, self.generation == current else {
                        return
                    }

                    if let result {
                        let text = result.bestTranscription.formattedString
                        let changed = self.turn.partial(text, id: current)
                        self.transcript = self.turn.text
                        self.received?(self.turn.text)
                        if changed {
                            self.silence?.cancel()
                        }
                        if changed && self.completed != nil && self.listening && !self.turn.text.isEmpty {
                            self.silence = Task { try? await Task.sleep(for: .seconds(1.8))
                                if !Task.isCancelled && self.generation == current {
                                    self.finishUtterance()
                                } }
                        }
                        if result.isFinal {
                            self.deliver(current)

                            return }
                    }
                    if failure != nil && !self.finishing {
                        self.stop()
                        self.error = L10n.string("Voice input stopped. Please try again.") }
                }
            }
            engine.prepare()
            try engine.start()
            preparingInput = false
            listening = true
        } catch { stop()
            self.error = L10n.string(error.localizedDescription) }
    }

    func finishUtterance() {
        guard listening else {
            return
        }

        listening = false
        finishing = true
        silence?.cancel()
        stopMicrophone()
        request?.endAudio()
        let current = generation
        finalTimeout = Task { try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled && self.generation == current {
                self.deliver(current)
            } }
    }

    private func deliver(_ current: UUID) {
        guard current == generation else {
            return
        }

        let value = turn.finish(id: current), callback = completed
        stop()
        if let value {
            callback?(value)
        }
        else if callback != nil {
            error = L10n.string("No speech was recognized. Please try again.")
        }
    }

    private func stopMicrophone() {
        visualization.reset()
        engine.stop()
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false } }

    func stop() {
        generation = UUID()
        turn.cancel()
        silence?.cancel()
        finalTimeout?.cancel()
        speechTask?.cancel()
        speechTask = nil
        spoken = nil
        player.stop()
        playback.stop()
        if hasPlaybackTap {
            playback.mainMixerNode.removeTap(onBus: 0)
            hasPlaybackTap = false }
        playback.reset()
        queuedBuffers = 0
        allSpeechScheduled = false
        preparingSpeech = false
        speaking = false
        stopMicrophone()
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        request = nil
        preparingInput = false
        listening = false
        finishing = false
        received = nil
        completed = nil
        if audioSessionOwned {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            audioSessionOwned = false }
    }

    func speak(_ text: String, finished: (() -> Void)? = nil) {
        stop()
        error = nil

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finished?()

            return }
        guard UIApplication.shared.applicationState == .active else {
            return
        }

        let current = UUID()
        generation = current
        let voice = SpeechPreferences.voice, speed = Float(SpeechPreferences.speed)
        let language: KokoroLanguage = L10n.isFrench ? .french : .english
        spoken = finished
        speaking = true
        preparingSpeech = true
        speechTask = Task { @MainActor in
            do {
                let model = try await KokoroAssets.shared.ensure()
                try Task.checkCancellation()

                guard generation == current else {
                    return
                }

                let format = AVAudioFormat(standardFormatWithSampleRate: KokoroSpeechEngine.sampleRate, channels: 1)!
                if player.engine == nil {
                    playback.attach(player)
                    playback.connect(player, to: playback.mainMixerNode, format: format) }
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio)
                try session.setActive(true)
                audioSessionOwned = true
                playback.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                    let level = Self.audioLevel(buffer)
                    Task { @MainActor in

                        guard let self, self.generation == current, self.speaking else {
                            return
                        }

                        self.visualization.update(level)
                    }
                }
                hasPlaybackTap = true
                try playback.start()
                for chunk in KokoroText.chunks(text) {
                    try Task.checkCancellation()
                    let samples = try await KokoroSpeechEngine.shared.synthesize(
                        chunk,
                        language: language,
                        model: model,
                        voiceFile: KokoroAssets.shared.voiceFile(voice),
                        speed: speed
                    )
                    try Task.checkCancellation()

                    guard generation == current else {
                        return
                    }
                    guard let buffer = AVAudioPCMBuffer(
                        pcmFormat: format,
                        frameCapacity: AVAudioFrameCount(samples.count)
                    ), let channel = buffer.floatChannelData?[0] else {
                        throw KokoroError.output
                    }

                    buffer.frameLength = buffer.frameCapacity
                    samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
                    queuedBuffers += 1
                    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                        Task { @MainActor in

                            guard let self, self.generation == current else {
                                return
                            }

                            self.queuedBuffers -= 1
                            self.finishSpeechIfNeeded(current)
                        }
                    }
                    preparingSpeech = false
                    if !player.isPlaying {
                        player.play()
                    }
                    // Bound queued audio as well as individual model requests.
                    while queuedBuffers >= 2 {
                        try await Task.sleep(for: .milliseconds(80))
                        try Task.checkCancellation() }
                }
                allSpeechScheduled = true
                finishSpeechIfNeeded(current)
            } catch is CancellationError { }
            catch {
                if generation == current {
                    stop()
                    self.error = L10n.format("Couldn’t play the response. %@", L10n.string(error.localizedDescription))
                }
            }
        }
    }

    nonisolated private static func audioLevel(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return 0
        }

        var sum: Double = 0
        for index in 0 ..< Int(buffer.frameLength) {
            let value = Double(samples[index])
            sum += value * value }

        return sqrt(sum / Double(buffer.frameLength))
    }

    private func finishSpeechIfNeeded(_ current: UUID) {
        guard generation == current, allSpeechScheduled, queuedBuffers == 0 else {
            return
        }

        let callback = spoken
        stop()
        callback?()
    }
}
