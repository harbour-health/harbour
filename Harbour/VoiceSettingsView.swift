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
            VoicePreviewButton(speaking: preview.speaking, preparing: preview.preparingSpeech,
                               downloadProgress: assets.downloading ? assets.progress : nil) {
                if preview.speaking || assets.downloading {
                    preview.stop()
                    if assets.downloading { assets.cancel() }
                } else {
                    preview.speak(L10n.string("Hi, I’m Harbour. We can talk at your pace. How can I help today?"))
                }
            }.disabled(recorder.active || scenePhase != .active)
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

/// Loading, download progress and cancellation occupy the same fixed button footprint.
struct VoicePreviewButton: View {
    let speaking: Bool
    let preparing: Bool
    let downloadProgress: Double?
    let action: () -> Void
    private var busy: Bool { preparing || downloadProgress != nil }
    private var active: Bool { speaking || busy }
    private var title: String {
        if downloadProgress != nil { return L10n.string("Downloading voice") }
        if preparing { return L10n.string("Preparing voice…") }
        return L10n.string(speaking ? "Stop preview" : "Preview voice")
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Image(systemName: active ? "stop.fill" : "play.fill").opacity(busy ? 0 : 1)
                    if busy { ProgressView().tint(Palette.ink) }
                }.frame(width: 24, height: 24)
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
                if let progress = downloadProgress {
                    Text(L10n.format("%lld%%", Int64(progress * 100))).monospacedDigit().foregroundStyle(Palette.muted)
                }
            }
            .font(.title3.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 60)
            .padding(.horizontal, 18)
            .background(Palette.surface, in: Capsule())
            .overlay(alignment: .bottom) {
                if let progress = downloadProgress {
                    ProgressView(value: progress).tint(Palette.blue).padding(.horizontal, 30).padding(.bottom, 7)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string(downloadProgress != nil ? "Cancel download" : (active ? "Stop preview" : "Preview voice")))
        .accessibilityValue(busy ? title : "")
        .accessibilityIdentifier("previewVoice")
    }
}
