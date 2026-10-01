import SwiftUI

private struct DrawerHeight: Equatable {
    let points: CGFloat
    let scalesWithText: Bool
}

private struct DrawerHeightKey: PreferenceKey {
    static let defaultValue: DrawerHeight? = nil
    static func reduce(value: inout DrawerHeight?, nextValue: () -> DrawerHeight?) {
        if let next = nextValue() { value = next }
    }
}

extension View {
    func drawerHeight(_ height: CGFloat) -> some View {
        preference(key: DrawerHeightKey.self, value: DrawerHeight(points: height, scalesWithText: true))
    }

    func floatingDrawer(height: CGFloat) -> some View {
        modifier(FloatingDrawer(defaultHeight: height))
    }

    func measuredDrawerHeight(chrome: CGFloat = 100) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: DrawerHeightKey.self, value: DrawerHeight(points: geometry.size.height + chrome, scalesWithText: false))
            }
        }
    }
}

private struct FloatingDrawer: ViewModifier {
    let defaultHeight: CGFloat
    @State private var contentHeight: DrawerHeight?
    @State private var windowHeight: CGFloat = 800
    @State private var windowWidth: CGFloat = 400
    @State private var topInset: CGFloat = 62
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0
    @AppStorage("appearance") private var appearance = AppearanceChoice.system.rawValue
    private var height: CGFloat {
        let request = contentHeight ?? DrawerHeight(points: defaultHeight, scalesWithText: true)
        return min(request.points * (request.scalesWithText ? textScale : 1), max(180, windowHeight - topInset - 60))
    }
    private var nativeDetached: Bool {
        if #available(iOS 26, *) { return verticalSizeClass != .compact && windowHeight > windowWidth }
        return false
    }
    private var corners: AnyShape {
        if #available(iOS 26, *), nativeDetached {
            return AnyShape(ConcentricRectangle(corners: .concentric, isUniform: true))
        }
        return AnyShape(RoundedRectangle(cornerRadius: 54, style: .continuous))
    }

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Palette.muted.opacity(0.35)).frame(width: 36, height: nativeDetached ? 0 : 5)
                .padding(.top, nativeDetached ? 0 : 10).padding(.bottom, nativeDetached ? 0 : 4).accessibilityHidden(true)
            content.safeAreaPadding(.bottom, nativeDetached ? 20 : 16)
        }
        .background(Palette.canvas)
        .clipShape(corners)
        .background { DrawerBounds() }
        .accessibilityElement(children: .contain).accessibilityIdentifier("floatingDrawer")
        .padding(.horizontal, nativeDetached ? 0 : 8)
        .padding(.bottom, nativeDetached ? 0 : 12)
        .ignoresSafeArea(.container, edges: nativeDetached ? [] : .bottom)
        .background(DrawerWindowReader { size, inset in
            windowHeight = size.height; windowWidth = size.width; topInset = inset
        })
        .onPreferenceChange(DrawerHeightKey.self) { contentHeight = $0 }
        .presentationDetents([.height(height)])
        .presentationBackground(nativeDetached ? Palette.canvas : .clear)
        .presentationDragIndicator(nativeDetached ? .visible : .hidden)
        .presentationCompactAdaptation(.none)
        .presentationBackgroundInteraction(.disabled)
        .preferredColorScheme((AppearanceChoice(rawValue: appearance) ?? .system).scheme)
    }

}

private struct DrawerBounds: View {
    @ViewBuilder var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--verify-drawers") {
            Color.clear.accessibilityElement(children: .ignore).accessibilityLabel("Drawer")
            .accessibilityIdentifier("drawerBounds").allowsHitTesting(false)
        }
    }
}

private struct DrawerWindowReader: UIViewRepresentable {
    let update: (CGSize, CGFloat) -> Void
    func makeUIView(context: Context) -> DrawerWindowView { DrawerWindowView() }
    func updateUIView(_ view: DrawerWindowView, context: Context) { view.update = update }
}

private final class DrawerWindowView: UIView {
    var update: ((CGSize, CGFloat) -> Void)?
    private var previousSize = CGSize.zero
    private var previousInset: CGFloat = -1
    override func didMoveToWindow() { super.didMoveToWindow(); refresh() }
    override func layoutSubviews() { super.layoutSubviews(); refresh() }
    private func refresh() {
        guard let window, window.bounds.size != previousSize || window.safeAreaInsets.top != previousInset else { return }
        previousSize = window.bounds.size; previousInset = window.safeAreaInsets.top
        let size = previousSize; let inset = previousInset
        DispatchQueue.main.async { [weak self] in self?.update?(size, inset) }
    }
}
