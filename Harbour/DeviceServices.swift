import Foundation
import HealthKit
import Speech
import AVFoundation
import HarbourCore
import UIKit

/// Speech stays in the app's language; an unavailable local voice never changes languages.
enum SpeechLanguage {
    static var identifier: String { L10n.isFrench ? "fr-CA" : "en-CA" }
    static var locale: Locale { Locale(identifier: identifier) }
    static var voice: AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let language = L10n.isFrench ? "fr" : "en"
        return voices.first { $0.language == identifier }
            ?? voices.first { $0.language.split(separator: "-").first == Substring(language) }
    }
}

@MainActor final class HealthService: ObservableObject {
    @Published var busy = false
    @Published var status = ""
    private let health = HKHealthStore()
    private let types: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.bodyTemperature), HKQuantityType(.bloodPressureSystolic), HKQuantityType(.bloodPressureDiastolic)]
    func sync(into store: AppStore) async {
        guard HKHealthStore.isHealthDataAvailable() else { status = L10n.string("Apple Health is unavailable on this device."); return }
        busy = true; defer { busy = false }
        do {
            try await health.requestAuthorization(toShare: [], read: types)
            var imported: [Reading] = []
            for (identifier, kind, unit) in [(HKQuantityTypeIdentifier.heartRate, ReadingKind.heartRate, HKUnit.count().unitDivided(by: .minute())), (.bodyTemperature, .temperature, .degreeCelsius())] {
                let samples = try await query(HKQuantityType(identifier))
                imported += samples.compactMap { sample in
                    guard let quantity = sample as? HKQuantitySample else { return nil }
                    let number = quantity.quantity.doubleValue(for: unit)
                    return Reading(id: "health-" + sample.uuid.uuidString, kind: kind, value: String(format: kind == .temperature ? "%.1f" : "%.0f", number), date: sample.startDate, source: "Apple Health")
                }
            }
            let pressures = try await query(HKCorrelationType(.bloodPressure))
            imported += pressures.compactMap { sample in
                guard let correlation = sample as? HKCorrelation,
                      let systolic = correlation.objects(for: HKQuantityType(.bloodPressureSystolic)).first as? HKQuantitySample,
                      let diastolic = correlation.objects(for: HKQuantityType(.bloodPressureDiastolic)).first as? HKQuantitySample else { return nil }
                let value = String(format: "%.0f/%.0f", systolic.quantity.doubleValue(for: .millimeterOfMercury()), diastolic.quantity.doubleValue(for: .millimeterOfMercury()))
                return Reading(id: "health-" + sample.uuid.uuidString, kind: .bloodPressure, value: value, date: sample.startDate, source: "Apple Health")
            }
            imported = imported.filter { ReadingParser.valid($0.value, kind: $0.kind) }
            let newCount = imported.filter { r in !store.records.readings.contains { $0.id == r.id } }.count
            store.importReadings(imported)
            status = imported.isEmpty ? L10n.string("No readings available. Check Apple Health access and the last 30 days of data.") : L10n.format("%d new readings imported.", newCount)
        } catch { status = L10n.string("Couldn’t access Apple Health. Check access in Settings.") }
    }
    private func query(_ type: HKSampleType) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .day, value: -30, to: .now), end: .now)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 100, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            health.execute(query)
        }
    }
}

@MainActor final class VoiceService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
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
    private var speaker = AVSpeechSynthesizer()
    private var audioSessionOwned = false
    private var silence: Task<Void, Never>?
    private var finalTimeout: Task<Void, Never>?
    private var received: ((String) -> Void)?
    private var completed: ((String) -> Void)?
    private var spoken: (() -> Void)?
    private var activeUtterance: ObjectIdentifier?
    private var observers: [NSObjectProtocol] = []
    override init() {
        super.init(); speaker.delegate = self
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in self?.interrupt(L10n.string("Voice was interrupted. Start voice again when you’re ready.")) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.interrupt(L10n.string("The audio device disconnected. Start voice again when you’re ready.")) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.interrupt(L10n.string("Audio restarted. Start voice again when you’re ready."))
                self.engine = AVAudioEngine()
                self.speaker = AVSpeechSynthesizer(); self.speaker.delegate = self
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        })
    }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    private func interrupt(_ message: String) {
        guard audioSessionOwned || received != nil || spoken != nil else { return }
        stop(); error = message
    }
    func start(transcript: @escaping (String) -> Void, finished: ((String) -> Void)? = nil) async {
        stop(); let current = turn.begin(); generation = current
        received = transcript; completed = finished; self.transcript = ""; error = nil
        guard UIApplication.shared.applicationState == .active else { stop(); return }
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard generation == current else { return }
        guard speech == .authorized else { stop(); error = L10n.string("Enable speech access in Settings."); return }
        guard UIApplication.shared.applicationState == .active else { stop(); return }
        let microphone = await withCheckedContinuation { continuation in AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) } }
        guard generation == current else { return }
        guard microphone else { stop(); error = L10n.string("Enable microphone access in Settings."); return }
        guard UIApplication.shared.applicationState == .active else { stop(); return }
        guard let recognizer = SFSpeechRecognizer(locale: SpeechLanguage.locale), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { stop(); error = L10n.string("On-device speech isn’t available in the app’s language on this phone."); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers]); try session.setActive(true); audioSessionOwned = true
            let request = SFSpeechAudioBufferRecognitionRequest(); request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            self.request = request
            let input = engine.inputNode, format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { throw NSError(domain: "Audio", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.string("No microphone is available.")]) }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }; hasTap = true
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        let changed = self.turn.partial(text, id: current)
                        self.transcript = self.turn.text; self.received?(self.turn.text)
                        if changed { self.silence?.cancel() }
                        if changed && self.completed != nil && self.listening && !self.turn.text.isEmpty {
                            self.silence = Task { try? await Task.sleep(for: .seconds(1.8)); if !Task.isCancelled && self.generation == current { self.finishUtterance() } }
                        }
                        if result.isFinal { self.deliver(current); return }
                    }
                    if failure != nil && !self.finishing { self.stop(); self.error = L10n.string("Voice input stopped. Please try again.") }
                }
            }
            engine.prepare(); try engine.start(); listening = true
        } catch { stop(); self.error = L10n.string(error.localizedDescription) }
    }
    func finishUtterance() {
        guard listening else { return }
        listening = false; finishing = true; silence?.cancel(); stopMicrophone(); request?.endAudio()
        let current = generation
        finalTimeout = Task { try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled && self.generation == current { self.deliver(current) } }
    }
    private func deliver(_ current: UUID) {
        guard current == generation else { return }
        let value = turn.finish(id: current), callback = completed
        stop()
        if let value { callback?(value) }
        else if callback != nil { error = L10n.string("No speech was recognized. Please try again.") }
    }
    private func stopMicrophone() { engine.stop(); if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false } }
    func stop() {
        generation = UUID(); turn.cancel(); silence?.cancel(); finalTimeout?.cancel()
        activeUtterance = nil; spoken = nil; speaker.stopSpeaking(at: .immediate); speaking = false
        stopMicrophone(); request?.endAudio(); recognition?.cancel(); recognition = nil; request = nil
        listening = false; finishing = false; received = nil; completed = nil
        if audioSessionOwned { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); audioSessionOwned = false }
    }
    func speak(_ text: String, finished: (() -> Void)? = nil) {
        stop(); error = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { finished?(); return }
        guard UIApplication.shared.applicationState == .active else { return }
        guard let voice = SpeechLanguage.voice else { error = L10n.string("A voice isn’t available in the app’s language on this phone."); return }
        spoken = finished
        do {
            let session = AVAudioSession.sharedInstance(); try session.setCategory(.playback, mode: .spokenAudio); try session.setActive(true); audioSessionOwned = true
            let utterance = AVSpeechUtterance(string: text); utterance.voice = voice; utterance.rate = 0.45
            activeUtterance = ObjectIdentifier(utterance); speaking = true; speaker.speak(utterance)
        } catch { stop(); self.error = L10n.format("Couldn’t play the response. %@", error.localizedDescription) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard self.activeUtterance == identifier else { return }
            let callback = self.spoken; self.activeUtterance = nil; self.spoken = nil; self.speaking = false
            if self.audioSessionOwned { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); self.audioSessionOwned = false }
            callback?()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard self.activeUtterance == identifier else { return }
            self.stop(); self.error = L10n.string("Voice playback stopped. Start voice again when you’re ready.")
        }
    }
}
