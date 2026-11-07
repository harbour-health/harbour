import SwiftUI

enum VoiceConversationPhase: String {
    case connecting, listening, finishing, thinking, speaking, paused
    var title: String {
        switch self {
        case .connecting: "Connecting…"
        case .listening: "Listening"
        case .finishing: "Finishing…"
        case .thinking: "Thinking…"
        case .speaking: "Speaking"
        case .paused: "Voice paused"
        }
    }
}

/// Kept separate from VoiceService's phase updates, so audio levels don't redraw chat history.
@MainActor final class VoiceVisualization: ObservableObject {
    @Published private(set) var level: Double = 0
    func update(_ rms: Double) {
        guard rms.isFinite else { return }
        let value = min(1, max(0, rms * 5))
        level += (value - level) * (value > level ? 0.55 : 0.22)
    }
    func reset() { level = 0 }
}

struct VoiceConversationView: View {
    var phase: VoiceConversationPhase
    var visualization: VoiceVisualization
    var error: String?
    var downloadProgress: Double?
    var toggleMicrophone: () -> Void
    var end: () -> Void
    var cancelDownload: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            if typeSize.isAccessibilitySize {
                ScrollView { layout(in: geometry.size).frame(minHeight: geometry.size.height) }
                    .scrollBounceBehavior(.basedOnSize)
            } else { layout(in: geometry.size) }
        }
        .background(Palette.canvas.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
        .accessibilityAction(.escape, end)
    }
    private func layout(in size: CGSize) -> some View {
        VStack(spacing: 20) {
            Text("Voice conversation").font(.headline).padding(.top, 20)
            if size.height < 500 {
                HStack(spacing: 28) {
                    orb.frame(width: min(size.width * 0.4, 240))
                    VStack(spacing: 20) { status; downloads; controls }
                }.frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
                orb.frame(height: min(typeSize.isAccessibilitySize ? 180 : 330, size.height * 0.43))
                status
                Spacer(minLength: 0)
                downloads
                controls
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var orb: some View {
        VoiceOrb(phase: phase, visualization: visualization)
            .frame(maxWidth: 380).frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
    private var status: some View {
        VStack(spacing: 12) {
            Text(L10n.string(downloadProgress == nil ? phase.title : "Downloading voice"))
                .font(.title2.weight(.medium)).contentTransition(.opacity)
                .accessibilityIdentifier("voiceConversationStatus")
            if let error {
                Text(error).font(.body).foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: phase)
    }
    @ViewBuilder private var downloads: some View {
        if let progress = downloadProgress {
            VStack(spacing: 10) {
                ProgressView(value: progress).tint(Palette.blue)
                HStack {
                    Text(L10n.format("%lld%% downloaded", Int64(progress * 100))).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("Cancel download", action: cancelDownload)
                }.font(.subheadline)
            }.frame(maxWidth: 320)
        }
    }
    private var controls: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(spacing: 10) {
                Button(action: toggleMicrophone) {
                    Image(systemName: phase == .listening ? "mic.fill" : phase == .speaking ? "waveform" : "mic.slash.fill")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(phase == .listening ? Palette.blue : Palette.ink)
                        .frame(width: 64, height: 64).background(Palette.surface, in: Circle())
                }
                .buttonStyle(PressFeedback())
                .disabled(phase == .connecting || phase == .finishing || phase == .thinking)
                .accessibilityLabel(L10n.string(phase == .listening ? "Pause microphone" : phase == .speaking ? "Interrupt response" : "Resume voice"))
                .accessibilityIdentifier("voiceConversationMicrophone")
                Text(L10n.string(phase == .listening ? "Pause" : phase == .speaking ? "Speak" : "Resume"))
                    .font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.65)
            }.frame(maxWidth: .infinity)
            VStack(spacing: 10) {
                Button(action: end) {
                    Image(systemName: "xmark").font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Palette.canvas).frame(width: 64, height: 64)
                        .background(Palette.ink, in: Circle())
                }.buttonStyle(PressFeedback()).accessibilityLabel("End voice").accessibilityIdentifier("endVoiceConversation")
                Text("End").font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.65)
            }.frame(maxWidth: .infinity)
        }
    }
}

private struct VoiceOrb: View {
    var phase: VoiceConversationPhase
    @ObservedObject var visualization: VoiceVisualization
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || phase == .paused)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let level = reduceMotion ? 0 : visualization.level
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.34
                let active = phase == .speaking || phase == .listening
                let energy = active ? level : 0
                let speed = phase == .thinking || phase == .finishing ? 1.6 : 0.65
                let amplitude = reduceMotion || phase == .paused ? 0 : 0.035 + energy * 0.13
                let scale = 1 + energy * 0.16
                context.fill(outline(center: center, radius: radius * 1.09 * scale, time: time * speed + 2, amplitude: amplitude), with: .color(Palette.blueWash))
                context.fill(outline(center: center, radius: radius * scale, time: time * speed, amplitude: amplitude), with: .color(phase == .paused ? Palette.muted.opacity(0.3) : Palette.blue))
                // An off-center, clipped highlight gives the shape volume without a neon gradient.
                var highlight = context
                highlight.clip(to: outline(center: center, radius: radius * scale, time: time * speed, amplitude: amplitude))
                let highlightCenter = CGPoint(x: center.x - radius * 0.58, y: center.y - radius * 0.6)
                highlight.fill(outline(center: highlightCenter, radius: radius * 0.88, time: time * 0.4, amplitude: amplitude), with: .color(.white.opacity(phase == .paused ? 0.06 : 0.15)))
                if phase == .thinking || phase == .connecting || phase == .finishing {
                    for index in 0..<3 {
                        let angle = time * 0.8 + Double(index) * .pi * 2 / 3
                        let distance = radius * 1.34
                        let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)), with: .color(Palette.blue.opacity(0.45)))
                    }
                }
            }
        }
    }
    private func outline(center: CGPoint, radius: Double, time: Double, amplitude: Double) -> Path {
        let points = (0..<80).map { index -> CGPoint in
            let angle = Double(index) * .pi * 2 / 80
            let wave = sin(angle * 3 + time) * 0.62 + sin(angle * 5 - time * 0.7) * 0.38
            let value = radius * (1 + amplitude * wave)
            return CGPoint(x: center.x + cos(angle) * value, y: center.y + sin(angle) * value)
        }
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var path = Path(); path.move(to: midpoint(points[79], points[0]))
        for index in points.indices { path.addQuadCurve(to: midpoint(points[index], points[(index + 1) % 80]), control: points[index]) }
        path.closeSubpath(); return path
    }
}
