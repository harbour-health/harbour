import SwiftUI
import HarbourSpeech

struct VoiceSettingsView: View {
    @EnvironmentObject var recorder: VisitRecorder
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var preview = VoiceService()
    @ObservedObject private var assets = KokoroAssets.shared
    @AppStorage(SpeechPreferences.speedKey) private var speed = 1.0
    @AppStorage(SpeechPreferences.voiceKey) private var identifier = KokoroVoice.female.rawValue
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(spacing: 0) {
                ForEach(KokoroVoice.allCases, id: \.rawValue) { voice in
                    Button { preview.stop(); identifier = voice.rawValue } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "waveform").font(.title2).foregroundStyle(Palette.blue).frame(width: 32)
                            Text(L10n.string(voice == .female ? "Female" : "Male")).font(.title3.weight(.medium))
                            Spacer()
                            if KokoroVoice.restored(identifier) == voice { Image(systemName: "checkmark").font(.body.weight(.semibold)) }
                        }.foregroundStyle(Palette.ink).padding(.vertical, 16).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("voice-" + voice.rawValue)
                    if voice == .female { Divider() }
                }
            }
            VStack(spacing: 12) {
                HStack { Text("Speaking speed"); Spacer(); Text(L10n.format("%.0f%%", SpeechPreferences.speed * 100)).foregroundStyle(Palette.muted) }
                Slider(value: $speed, in: 0.8...1.3, step: 0.05).accessibilityLabel("Speaking speed").accessibilityIdentifier("voiceSpeed")
                HStack { Text("Slower"); Spacer(); Text("Faster") }.font(.subheadline).foregroundStyle(Palette.muted)
            }
            if assets.downloading {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Downloading voice"); Spacer(); Text(L10n.format("%lld%% downloaded", Int64(assets.progress * 100))).foregroundStyle(Palette.muted) }
                    ProgressView(value: assets.progress)
                    Button("Cancel download") { preview.stop(); assets.cancel() }
                }
            }
            Button {
                if preview.speaking { preview.stop() }
                else { preview.speak(L10n.string("Hi, I’m Harbour. We can talk at your pace. How can I help today?")) }
            } label: {
                Label(L10n.string(preview.speaking ? "Stop preview" : "Preview voice"), systemImage: preview.speaking ? "stop.fill" : "play.fill")
                    .font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 18)
            }.buttonStyle(.plain).background(Palette.surface, in: Capsule()).disabled(recorder.active || scenePhase != .active).accessibilityIdentifier("previewVoice")
            if preview.preparingSpeech && !assets.downloading { HStack(spacing: 12) { ProgressView(); Text("Preparing voice…").foregroundStyle(Palette.muted) } }
            if let error = preview.error ?? assets.error { Text(error).foregroundStyle(Palette.coral) }
            if recorder.active { Text("Voice preview is unavailable while recording a visit.").font(.subheadline).foregroundStyle(Palette.muted) }
        }.padding(24).frame(maxWidth: .infinity, alignment: .topLeading).background(Palette.canvas)
            .navigationTitle("Voice").navigationBarTitleDisplayMode(.inline).measuredDrawerHeight(chrome: 80)
            .onDisappear { preview.stop() }
            .onChange(of: speed) { preview.stop() }
            .onChange(of: recorder.active) { if recorder.active { preview.stop() } }
            .onChange(of: scenePhase) { if scenePhase != .active { preview.stop() } }
    }
}
