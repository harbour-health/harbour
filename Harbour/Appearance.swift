import SwiftUI

// Semantic colours resolve against the active appearance, including a user override.
enum Palette {
    static let canvas = adaptive(0xFFFFFF, 0x171717)
    static let surface = adaptive(0xF5F5F5, 0x262626)
    static let ink = adaptive(0x181818, 0xF7F7F7)
    static let muted = adaptive(0x606060, 0xBFBFBF)
    static let line = adaptive(0xE5E5E5, 0x404040)
    static let blue = adaptive(0x365DCE, 0xA0B6FF)
    static let coral = adaptive(0xB94831, 0xFFAE98)
    static let blueWash = adaptive(0xE3E9FC, 0x303C5B)
    static let coralWash = adaptive(0xF6DFD3, 0x50362C)
    static let ochreWash = adaptive(0xEFE2BD, 0x49412C)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            let value = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
    var symbol: String { switch self { case .system: "circle.lefthalf.filled"; case .light: "sun.max"; case .dark: "moon" } }
}

struct AppearanceView: View {
    @AppStorage("appearance") private var appearance = AppearanceChoice.system.rawValue
    var body: some View {
        List {
            ForEach(AppearanceChoice.allCases) { choice in
                Button { appearance = choice.rawValue } label: {
                    HStack(spacing: 16) {
                        Image(systemName: choice.symbol).font(.title2).frame(width: 30)
                        Text(choice.rawValue).font(.title3.weight(.medium))
                        Spacer()
                        if appearance == choice.rawValue { Image(systemName: "checkmark").font(.headline) }
                    }.foregroundStyle(Palette.ink).padding(.vertical, 12).contentShape(Rectangle())
                }.accessibilityIdentifier("appearance-" + choice.rawValue.lowercased())
                    .accessibilityAddTraits(appearance == choice.rawValue ? .isSelected : [])
                    .listRowBackground(Palette.surface)
            }
        }.scrollContentBackground(.hidden).background(Palette.canvas)
            .drawerHeight(350).navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline)
    }
}

struct PressFeedback: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

// Retain UISlider's drag, keyboard, and VoiceOver behaviour with a larger track.
struct EffortSlider: UIViewRepresentable {
    @Binding var value: Double
    @Environment(\.colorScheme) private var scheme
    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }
    func makeUIView(context: Context) -> WideTrackSlider {
        let slider = WideTrackSlider()
        slider.minimumValue = 0; slider.maximumValue = 2
        slider.accessibilityLabel = "Generation effort"
        slider.accessibilityIdentifier = "Generation effort"
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return slider
    }
    func updateUIView(_ slider: WideTrackSlider, context: Context) {
        context.coordinator.value = $value
        slider.value = Float(value)
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        slider.setMinimumTrackImage(track(UIColor(Palette.blue).resolvedColor(with: traits)), for: .normal)
        slider.setMaximumTrackImage(track(UIColor(Palette.line).resolvedColor(with: traits)), for: .normal)
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { ctx in
            UIColor(Palette.surface).resolvedColor(with: traits).setFill()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 26, height: 26)).fill()
            UIColor(Palette.ink).resolvedColor(with: traits).withAlphaComponent(0.2).setStroke()
            let border = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 26, height: 26)); border.lineWidth = 1; border.stroke()
        }
        slider.setThumbImage(thumb, for: .normal)
        slider.accessibilityValue = Effort.allCases[Int(value.rounded())].rawValue
    }
    private func track(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { _ in
            color.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 28, height: 28), cornerRadius: 14).fill()
        }.resizableImage(withCapInsets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
    }
    @MainActor final class Coordinator: NSObject {
        var value: Binding<Double>
        init(value: Binding<Double>) { self.value = value }
        @objc func changed(_ slider: UISlider) { value.wrappedValue = Double(slider.value.rounded()) }
    }
}
final class WideTrackSlider: UISlider {
    override func trackRect(forBounds bounds: CGRect) -> CGRect { CGRect(x: 0, y: bounds.midY - 14, width: bounds.width, height: 28) }
}
