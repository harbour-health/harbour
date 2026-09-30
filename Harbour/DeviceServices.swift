import Foundation
import HealthKit
import Speech
import AVFoundation
import HarbourCore

@MainActor final class HealthService: ObservableObject {
    @Published var busy = false
    @Published var status = ""
    private let health = HKHealthStore()
    private let types: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.bodyTemperature), HKQuantityType(.bloodPressureSystolic), HKQuantityType(.bloodPressureDiastolic)]
    func sync(into store: AppStore) async {
        guard HKHealthStore.isHealthDataAvailable() else { status = "Apple Health is unavailable on this device."; return }
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
            status = imported.isEmpty ? "No readings available. Check Apple Health access and the last 30 days of data." : "\(newCount) new readings imported."
        } catch { status = "Couldn’t access Apple Health. Check access in Settings." }
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

@MainActor final class VoiceService: ObservableObject {
    @Published var listening = false
    @Published var error: String?
    private let engine = AVAudioEngine()
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var hasTap = false
    private var generation = UUID()
    private let speaker = AVSpeechSynthesizer()
    func start(transcript: @escaping (String) -> Void) async {
        let current = UUID(); generation = current
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard generation == current else { return }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard generation == current else { return }
        guard speech == .authorized, microphone else { error = "Enable microphone and speech access in Settings."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-CA")), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { error = "On-device speech isn’t available for English on this phone."; return }
        do {
            stop(); generation = current; speaker.stopSpeaking(at: .immediate)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers]); try session.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            self.request = request
            let input = engine.inputNode, format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { throw NSError(domain: "Audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone is available."]) }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }; hasTap = true
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    if let result { transcript(result.bestTranscription.formattedString) }
                    if error != nil || result?.isFinal == true { self.stop() }
                }
            }
            engine.prepare(); try engine.start(); listening = true
        } catch { stop(); self.error = error.localizedDescription }
    }
    func stop() {
        generation = UUID()
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio(); recognition?.cancel(); recognition = nil; request = nil; listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func speak(_ text: String) {
        stop(); speaker.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let utterance = AVSpeechUtterance(string: text); utterance.voice = AVSpeechSynthesisVoice(language: "en-CA"); utterance.rate = 0.45
        speaker.speak(utterance)
    }
}
