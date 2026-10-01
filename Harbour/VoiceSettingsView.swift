import SwiftUI
import AVFoundation

struct VoiceSettingsView: View {
    @EnvironmentObject var recorder: VisitRecorder
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var preview = VoiceService()
    @AppStorage(SpeechPreferences.speedKey) private var speed = 1.0
    @State private var selectedIdentifier = UserDefaults.standard.string(forKey: SpeechPreferences.voiceKey) ?? ""
    @State private var voices: [AVSpeechSynthesisVoice] = []
    private var selected: AVSpeechSynthesisVoice? { voices.first { $0.identifier == selectedIdentifier } ?? voices.first }
    private var selectionUnavailable: Bool { !selectedIdentifier.isEmpty && !voices.contains { $0.identifier == selectedIdentifier } }

    var body: some View {
        Form {
            Section {
                Button { select("") } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Automatic")
                            if let voice = voices.first { Text(voice.name + " · " + SpeechPreferences.details(voice)).font(.subheadline).foregroundStyle(Palette.muted) }
                        }
                        Spacer()
                        if selectedIdentifier.isEmpty || selectionUnavailable { Image(systemName: "checkmark") }
                    }.foregroundStyle(Palette.ink)
                }.accessibilityIdentifier("automaticVoice")
            } header: { Text("Voice") } footer: {
                Text("Automatic uses the best available voice in the app’s language, preferring Premium, then Enhanced. Canadian voices are preferred at the same quality.")
            }
            if voices.isEmpty {
                Section { Text("A voice isn’t available in the app’s language on this phone.") }
            } else if selectionUnavailable {
                Section { Text("Your saved voice is unavailable. Automatic is being used until it is available again.") }
            }
            Section {
                HStack { Text("Speaking speed"); Spacer(); Text(L10n.format("%.0f%%", SpeechPreferences.speed * 100)).foregroundStyle(Palette.muted) }
                Slider(value: $speed, in: 0.8...1.3, step: 0.05).accessibilityLabel("Speaking speed").accessibilityIdentifier("voiceSpeed")
                HStack { Text("Slower"); Spacer(); Text("Faster") }.font(.subheadline).foregroundStyle(Palette.muted)
                Button {
                    if preview.speaking { preview.stop() }
                    else if !recorder.active && scenePhase == .active { preview.speak(L10n.string("Hi, I’m Harbour. We can talk at your pace. How can I help today?")) }
                } label: { Label(L10n.string(preview.speaking ? "Stop preview" : "Preview voice"), systemImage: preview.speaking ? "stop.fill" : "play.fill") }
                    .disabled(recorder.active || selected == nil || scenePhase != .active).accessibilityIdentifier("previewVoice")
                if let error = preview.error { Text(error).foregroundStyle(Palette.coral) }
                if recorder.active { Text("Voice preview is unavailable while recording a visit.").font(.subheadline).foregroundStyle(Palette.muted) }
            }
            Section {
                ForEach(voices, id: \.identifier) { voice in
                    Button { select(voice.identifier) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(voice.name)
                                Text(SpeechPreferences.details(voice)).font(.subheadline).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            if selectedIdentifier == voice.identifier { Image(systemName: "checkmark") }
                        }.foregroundStyle(Palette.ink)
                    }
                }
            } header: { Text("Available voices") }
            Section {
                if !voices.contains(where: { $0.quality == .enhanced || $0.quality == .premium }) {
                    Text("Only standard voices are available for this language. Download an Enhanced or Premium voice in iPhone Settings for more natural speech.")
                }
                if #available(iOS 26.0, *) {
                    Text("Open iPhone Settings → Accessibility → Read & Speak → Voices. Choose English or French and download an Enhanced or Premium voice, if offered.")
                } else {
                    Text("Open iPhone Settings → Accessibility → Spoken Content → Voices. Choose English or French and download an Enhanced or Premium voice, if offered.")
                }
                Text("Return here after the download. Available voices refresh automatically; speech stays on this device.").font(.subheadline).foregroundStyle(Palette.muted)
                Button("Refresh voices") { refresh() }.accessibilityIdentifier("refreshVoices")
            } header: { Text("More natural voices") }
        }.scrollContentBackground(.hidden).background(Palette.canvas).navigationTitle("Voice").navigationBarTitleDisplayMode(.inline).drawerHeight(740)
            .onAppear { refresh() }
            .onDisappear { preview.stop() }
            .onChange(of: selectedIdentifier) { _, _ in preview.stop() }
            .onChange(of: speed) { _, _ in preview.stop() }
            .onChange(of: recorder.active) { _, active in if active { preview.stop() } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } else { preview.stop() } }
            .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in refresh() }
    }
    private func select(_ identifier: String) {
        preview.stop(); selectedIdentifier = identifier
        UserDefaults.standard.set(identifier, forKey: SpeechPreferences.voiceKey)
    }
    private func refresh() { voices = SpeechPreferences.availableVoices }
}
