import SwiftUI
import UIKit

struct MainPageSwipeAction: Sendable {
    var canBegin: @MainActor @Sendable (Int) -> Bool = { _ in false }
    var perform: @MainActor @Sendable (Int, Int) -> Void = { _, _ in }
}
private struct MainPageSwipeKey: EnvironmentKey {
    static let defaultValue = MainPageSwipeAction()
}
extension EnvironmentValues {
    var mainPageSwipeAction: MainPageSwipeAction {
        get { self[MainPageSwipeKey.self] }
        set { self[MainPageSwipeKey.self] = newValue }
    }
}
private struct MainPageSwipes: ViewModifier {
    var page: Int
    @Environment(\.mainPageSwipeAction) private var action
    func body(content: Content) -> some View {
        content.background(SwipeScrollAnchor(page: page, action: action))
    }
}
private struct SwipeScrollAnchor: UIViewRepresentable {
    var page: Int
    var action: MainPageSwipeAction
    func makeUIView(context: Context) -> SwipeAnchorView { SwipeAnchorView() }
    func updateUIView(_ view: SwipeAnchorView, context: Context) { view.page = page; view.action = action; view.install() }
    static func dismantleUIView(_ view: SwipeAnchorView, coordinator: ()) { view.uninstall() }
}
private final class SwipeAnchorView: UIView, UIGestureRecognizerDelegate {
    var page = 0
    var action = MainPageSwipeAction()
    private weak var scroll: UIScrollView?
    private var pan: UIPanGestureRecognizer?
    override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false; isAccessibilityElement = false }
    required init?(coder: NSCoder) { fatalError("Created programmatically") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { uninstall() }
        else { DispatchQueue.main.async { [weak self] in self?.install() } }
    }
    func install() {
        guard window != nil else { return }
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let target = ancestor as? UIScrollView, scroll !== target else { return }
        uninstall()
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(moved(_:)))
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        target.addGestureRecognizer(recognizer)
        scroll = target; pan = recognizer
    }
    func uninstall() { if let pan { scroll?.removeGestureRecognizer(pan) }; pan = nil; scroll = nil }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard action.canBegin(page), let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: scroll)
        return abs(velocity.x) > abs(velocity.y) * 1.6
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        otherGestureRecognizer === scroll?.panGestureRecognizer
    }
    @objc private func moved(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let delta = recognizer.translation(in: scroll)
        guard abs(delta.x) > 70, abs(delta.x) > abs(delta.y) * 1.6 else { return }
        action.perform(page, delta.x < 0 ? 1 : -1)
    }
}
extension View {
    /// Apply to root scrolling content, before navigation destination modifiers.
    func mainPageSwipes(_ page: Int) -> some View { modifier(MainPageSwipes(page: page)) }
}
