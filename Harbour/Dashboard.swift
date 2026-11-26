import SwiftUI

private struct FloatingDockClearance: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
extension EnvironmentValues {
    var floatingDockClearance: CGFloat {
        get { self[FloatingDockClearance.self] }
        set { self[FloatingDockClearance.self] = newValue }
    }
}

struct NavigationDock: View {
    @EnvironmentObject private var recorder: VisitRecorder
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 4) {
            tab(0, title: "Today", symbol: "house")
            tab(1, title: "Chat", symbol: "bubble.left")
            tab(2, title: "Records", symbol: "list.clipboard")
            tab(3, title: "Visits", symbol: "person.2")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: AppLayout.contentWidth)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            Palette.canvas.ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Divider() }
        }
    }

    private func tab(_ index: Int, title: String, symbol: String) -> some View {
        let selected = index == selection
        return Button {
            selection = index
        } label: {
            VStack(spacing: 3) {
                Image(systemName: selected ? symbol + ".fill" : symbol)
                    .font(.title3.weight(.semibold))
                    .overlay(alignment: .topTrailing) {
                        if index == 3 && recorder.active {
                            Circle().fill(Palette.coral).frame(width: 8, height: 8).offset(x: 5, y: -3)
                        }
                    }
                Text(L10n.string(title))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .foregroundStyle(selected ? Palette.blue : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(selected ? Palette.blueWash : .clear, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedback())
        .accessibilityLabel(L10n.string(title))
        .accessibilityIdentifier("nav-" + title.lowercased())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(index == 3 && recorder.active ? L10n.string("Recording") : "")
    }
}
