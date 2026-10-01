import SwiftUI
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 10) {
            item("Today", symbol: "house.fill", index: 0)
            item("Chat", symbol: "bubble.left.and.bubble.right.fill", index: 1)
            item("Records", symbol: "heart.text.clipboard.fill", index: 2)
            item("Visits", symbol: "person.2.fill", index: 3)
        }.padding(7)
            .background {
                if reduceTransparency { Capsule().fill(Palette.surface) }
                else { Capsule().fill(.regularMaterial) }
            }
            .overlay(Capsule().strokeBorder(Palette.line.opacity(0.6)))
            .shadow(color: .black.opacity(0.10), radius: 16, y: 6).padding(.bottom, 12)
    }
    private func item(_ title: String, symbol: String, index: Int) -> some View {
        Button { selection = index } label: {
            Image(systemName: symbol).font(.system(size: 25, weight: .regular)).symbolRenderingMode(.monochrome)
                .foregroundStyle(index == 3 && recorder.active ? Palette.coral : Palette.ink).frame(width: 68, height: 48)
                .background(selection == index ? Palette.line.opacity(0.5) : .clear, in: Capsule())
        }.buttonStyle(PressFeedback()).accessibilityLabel(title).accessibilityIdentifier("nav-" + title.lowercased())
            .accessibilityAddTraits(selection == index ? .isSelected : [])
            .accessibilityShowsLargeContentViewer { Label(title, systemImage: symbol) }
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
                Label(latest?.kind.rawValue ?? "Readings", systemImage: latest?.kind.symbol ?? "waveform.path.ecg").font(.body.weight(.semibold))
                Spacer()
            }
            if let latest {
                let valueLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
                valueLayout {
                    Text(latest.value).font(.system(size: valueSize, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
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
                        .accessibilityLabel(latest.kind == .bloodPressure ? "Recorded systolic blood pressure over time" : "Recorded \(latest.kind.rawValue.lowercased()) over time")
                }
                let count = readings.filter { $0.kind == latest.kind }.count
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        Text(latest.date, format: .dateTime.month(.abbreviated).day().hour().minute()).fixedSize()
                        Spacer(minLength: 0)
                        Text("\(count) \(count == 1 ? "reading" : "readings")").fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(latest.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        Text("\(count) \(count == 1 ? "reading" : "readings")")
                    }
                }.font(.subheadline).foregroundStyle(Palette.muted)
            } else { Text("No readings yet").font(.title2.weight(.medium)) }
        }.padding(.horizontal, 22).padding(.bottom, 22).padding(.top, 12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 28))
            .accessibilityIdentifier("readingSummary")
    }
}
