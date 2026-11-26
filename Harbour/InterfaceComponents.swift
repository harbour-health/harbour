import SwiftUI

enum AppLayout {
    static let screenInset: CGFloat = 24
    static let sectionSpacing: CGFloat = 28
    static let surfaceInset: CGFloat = 22
    static let loadingMarkSize: CGFloat = 20
    static let controlSize: CGFloat = 52
    static let contentWidth: CGFloat = 760
}

struct ToolbarGlyph: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.body.weight(.medium))
            .frame(width: AppLayout.controlSize, height: AppLayout.controlSize)
            .contentShape(Rectangle())
    }
}

struct PrimaryActionRow: View {
    let title: String
    let symbol: String
    var prominent = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.blue)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(L10n.string(title))
                .font((prominent ? Font.title2 : .title3).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.body.weight(.medium))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: prominent ? 72 : 58)
        .background(prominent ? Palette.blueWash : Palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }
}

struct SelectionIndicator: View {
    let selected: Bool
    var colour: Color = Palette.blue
    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3).foregroundStyle(selected ? colour : Palette.muted)
            .accessibilityHidden(true)
    }
}

struct ActionButtonStyle: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .foregroundStyle(secondary ? Palette.ink : Palette.canvas)
            .background(secondary ? Palette.surface : Palette.ink, in: Capsule())
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
