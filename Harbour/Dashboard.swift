import SwiftUI
import UIKit
import Charts
import HarbourCore

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: Int
    var body: some View {
        NativeNavigationDock(selection: $selection, recording: recorder.active, reduceMotion: reduceMotion)
            .frame(width: 278, height: 62)
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6).padding(.bottom, 12)
    }
}

private struct NativeNavigationDock: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: Int
    let recording: Bool
    let reduceMotion: Bool
    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeUIView(context: Context) -> DockView {
        let view = DockView()
        for button in view.buttons { button.addTarget(context.coordinator, action: #selector(Coordinator.select(_:)), for: .touchUpInside) }
        return view
    }
    func updateUIView(_ view: DockView, context: Context) {
        context.coordinator.selection = $selection
        view.update(selection: selection, recording: recording, reduceMotion: reduceMotion, dark: colorScheme == .dark)
    }
    final class Coordinator: NSObject {
        var selection: Binding<Int>
        init(selection: Binding<Int>) { self.selection = selection }
        @objc func select(_ sender: UIButton) { selection.wrappedValue = sender.tag }
    }
}

private final class DockButton: UIButton {
    var reduceMotion = false
    override var isHighlighted: Bool {
        didSet {
            let changes = {
                self.alpha = self.isHighlighted ? 0.75 : 1
                self.transform = self.isHighlighted && !self.reduceMotion ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
            }
            if reduceMotion { changes() }
            else { UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes) }
        }
    }
}

private final class DockSymbols: UIView {
    var images: [UIImage] = [] { didSet { render() } }
    override func layoutSubviews() { super.layoutSubviews(); render() }
    private func render() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let rendered = UIGraphicsImageRenderer(size: bounds.size).image { _ in
            for (index, image) in images.enumerated() {
                let size = image.size
                let centre = CGPoint(x: 45.25 + CGFloat(index) * 62.5, y: 31)
                image.draw(in: CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height))
            }
        }
        layer.contents = rendered.cgImage
        layer.contentsScale = rendered.scale
    }
}

private final class DockView: UIView {
    private static let titles = ["Today", "Chat", "Records", "Visits"]
    private static let symbols = ["house", "bubble.left.and.bubble.right", "heart.text.clipboard", "person.2"]
    private let marker = UIView()
    private let symbols = DockSymbols()
    private let recordingDot = UIView()
    private var selectedIndex = 0
    private var configured = false
    let buttons = (0..<4).map { index in let button = DockButton(type: .custom); button.tag = index; return button }
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 31; layer.borderWidth = 0.8
        marker.layer.cornerRadius = 27
        marker.isUserInteractionEnabled = false; marker.isAccessibilityElement = false; addSubview(marker)
        symbols.backgroundColor = .clear; symbols.isOpaque = false
        symbols.isUserInteractionEnabled = false; symbols.isAccessibilityElement = false; addSubview(symbols)
        for button in buttons {
            button.imageView?.contentMode = .center
            button.accessibilityIdentifier = "nav-" + Self.titles[button.tag].lowercased()
            button.showsLargeContentViewer = true
            addSubview(button)
        }
        addInteraction(UILargeContentViewerInteraction())
        recordingDot.backgroundColor = UIColor(Palette.coral); recordingDot.layer.cornerRadius = 3
        recordingDot.isUserInteractionEnabled = false; recordingDot.isAccessibilityElement = false; addSubview(recordingDot)
    }
    required init?(coder: NSCoder) { fatalError("DockView is created programmatically") }
    override var intrinsicContentSize: CGSize { CGSize(width: 278, height: 62) }
    override func layoutSubviews() {
        super.layoutSubviews()
        symbols.frame = bounds
        for button in buttons { button.frame = CGRect(x: 14 + CGFloat(button.tag) * 62.5, y: 4, width: 62.5, height: 54) }
        if marker.layer.animationKeys()?.isEmpty != false { marker.frame = markerFrame(selectedIndex) }
        recordingDot.frame = CGRect(x: 14 + 3 * 62.5 + 62.5 - 13, y: 11, width: 6, height: 6)
    }
    private func markerFrame(_ index: Int) -> CGRect { CGRect(x: 3.75 + CGFloat(index) * 62.5, y: 4, width: 83, height: 54) }
    func update(selection: Int, recording: Bool, reduceMotion: Bool, dark: Bool) {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        func resolved(_ color: Color) -> UIColor { UIColor(color).resolvedColor(with: traits) }
        backgroundColor = resolved(Palette.dockBackground)
        marker.backgroundColor = resolved(Palette.dockSelection)
        layer.borderColor = (dark ? UIColor.white.withAlphaComponent(0.11) : UIColor.black.withAlphaComponent(0.07)).cgColor
        recordingDot.backgroundColor = resolved(Palette.coral)
        let changed = selection != selectedIndex
        selectedIndex = selection
        let configuration = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        var images: [UIImage] = []
        for button in buttons {
            let selected = button.tag == selection
            let symbol = Self.symbols[button.tag] + (selected ? ".fill" : "")
            let tint = resolved(selected ? Palette.dockActive : Palette.dockInactive)
            let image = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(tint, renderingMode: .alwaysOriginal)
            if let image { images.append(image) }
            button.accessibilityLabel = L10n.string(Self.titles[button.tag])
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
            button.accessibilityValue = button.tag == 3 && recording ? L10n.string("Recording") : ""
            button.largeContentTitle = L10n.string(Self.titles[button.tag]); button.largeContentImage = image
            button.reduceMotion = reduceMotion
        }
        symbols.images = images
        recordingDot.isHidden = !recording
        if configured && changed && !reduceMotion {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut, .allowUserInteraction]) { self.marker.frame = self.markerFrame(selection) }
        } else { marker.frame = markerFrame(selection) }
        configured = true
        setNeedsLayout()
    }
}

struct ReadingSummary: View {
    let readings: [Reading]
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 46
    private var latest: Reading? { readings.first }
    private var samples: [Reading] { guard let kind = latest?.kind else { return [] }; return readings.filter { $0.kind == kind }.prefix(30).sorted { $0.date < $1.date } }
    private func numeric(_ reading: Reading) -> Double? { Double(reading.value.split(separator: "/").first.map(String.init) ?? reading.value) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(L10n.string(latest?.kind.rawValue ?? "Readings"), systemImage: latest?.kind.symbol ?? "waveform.path.ecg").font(.body.weight(.semibold))
                Spacer()
            }
            if let latest {
                let valueLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
                valueLayout {
                    Text(L10n.readingValue(latest)).font(.system(size: valueSize, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(latest.kind.unit).font(.title3.weight(.medium))
                }.foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
                if samples.count > 1 {
                    if latest.kind == .bloodPressure { Text("Systolic").font(.subheadline).foregroundStyle(Palette.muted) }
                    Chart(samples) { reading in
                        if let value = numeric(reading) {
                            LineMark(x: .value("Recorded", reading.date), y: .value(latest.kind == .bloodPressure ? "Systolic" : latest.kind.rawValue, value)).foregroundStyle(Palette.blue)
                            PointMark(x: .value("Recorded", reading.date), y: .value("Value", value)).foregroundStyle(Palette.blue)
                        }
                    }.chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: .automatic(includesZero: false)).frame(height: 58)
                        .accessibilityLabel(latest.kind == .bloodPressure ? L10n.string("Recorded systolic blood pressure over time") : L10n.format("Recorded %@ over time", L10n.string(latest.kind.rawValue)))
                }
                let count = readings.filter { $0.kind == latest.kind }.count
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        Text(latest.date, format: .dateTime.month(.abbreviated).day().hour().minute()).fixedSize()
                        Spacer(minLength: 0)
                        Text(L10n.format(count == 1 ? "%lld reading" : "%lld readings", Int64(count))).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(latest.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        Text(L10n.format(count == 1 ? "%lld reading" : "%lld readings", Int64(count)))
                    }
                }.font(.subheadline).foregroundStyle(Palette.muted)
            } else { Text("No readings yet").font(.title2.weight(.medium)) }
        }.padding(.horizontal, 22).padding(.bottom, 22).padding(.top, 12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 28))
            .accessibilityIdentifier("readingSummary")
    }
}
