import SwiftUI

/// Real view bounds for the local presentation companion. No visible overlay or input handling.
private struct PresentationAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
extension View {
    func presentationTarget(_ id: String) -> some View {
        transformAnchorPreference(key: PresentationAnchors.self, value: .bounds) { values, anchor in values[id] = anchor }
    }
    func presentationStage() -> some View { modifier(PresentationCapture()) }
}
private struct PresentationCapture: ViewModifier {
    #if DEBUG
    private let enabled = ProcessInfo.processInfo.environment["HARBOUR_PRESENTATION_CAPTURE"] == "1"
    #else
    private let enabled = false
    #endif
    func body(content: Content) -> some View {
        content.overlayPreferenceValue(PresentationAnchors.self) { anchors in
            if enabled {
                GeometryReader { geometry in
                    let origin = geometry.frame(in: .global).origin
                    let visible = anchors.mapValues { geometry[$0].offsetBy(dx: origin.x, dy: origin.y) }
                        .filter { $0.value.intersects(CGRect(origin: origin, size: geometry.size)) }
                    Color.clear.task(id: snapshotKey(visible)) { save(visible) }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
    private func snapshotKey(_ rectangles: [String: CGRect]) -> String {
        rectangles.keys.sorted().map { "\($0):\(rectangles[$0]!)" }.joined(separator: "|")
    }
    private func save(_ rectangles: [String: CGRect]) {
        guard enabled else { return }
        let values = rectangles.mapValues { ["x": $0.minX, "y": $0.minY, "width": $0.width, "height": $0.height] }
        guard let bytes = try? JSONSerialization.data(withJSONObject: ["regions": values, "capturedAt": Date().timeIntervalSince1970]),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? bytes.write(to: documents.appendingPathComponent("presentation-regions.json"), options: .atomic)
    }
}
