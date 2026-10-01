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
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 10) {
            item("Today", symbol: "house", selectedSymbol: "house.fill", index: 0)
            item("Chat", symbol: "bubble.left.and.bubble.right", selectedSymbol: "bubble.left.and.bubble.right.fill", index: 1)
            item("Records", symbol: "heart.text.square", selectedSymbol: "heart.text.square.fill", index: 2)
            item("Visits", symbol: "waveform", selectedSymbol: "waveform", index: 3)
        }.padding(7).background(.regularMaterial, in: Capsule()).overlay(Capsule().strokeBorder(Palette.line.opacity(0.6)))
            .shadow(color: .black.opacity(0.10), radius: 16, y: 6).padding(.bottom, 12)
    }
    private func item(_ title: String, symbol: String, selectedSymbol: String, index: Int) -> some View {
        Button { selection = index } label: {
            Image(systemName: selection == index ? selectedSymbol : symbol).font(.system(size: 26, weight: .medium))
                .foregroundStyle(index == 3 && recorder.active ? Palette.coral : Palette.ink).frame(width: 68, height: 48)
                .background(selection == index ? Palette.line.opacity(0.5) : .clear, in: Capsule())
        }.buttonStyle(PressFeedback()).accessibilityLabel(title).accessibilityIdentifier("nav-" + title.lowercased())
            .accessibilityAddTraits(selection == index ? .isSelected : [])
    }
}

struct ReadingSummary: View {
    let readings: [Reading]
    var add: () -> Void
    private var latest: Reading? { readings.first }
    private var samples: [Reading] { guard let kind = latest?.kind else { return [] }; return readings.filter { $0.kind == kind }.prefix(30).sorted { $0.date < $1.date } }
    private func numeric(_ reading: Reading) -> Double? { Double(reading.value.split(separator: "/").first.map(String.init) ?? reading.value) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(latest?.kind.rawValue ?? "Readings", systemImage: latest?.kind.symbol ?? "waveform.path.ecg").font(.body.weight(.semibold))
                Spacer(); Button(action: add) { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("Add a reading").accessibilityIdentifier("addReading")
            }
            if let latest {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(latest.value).font(.system(size: 46, weight: .bold, design: .rounded)).minimumScaleFactor(0.7)
                    Text(latest.kind.unit).font(.title3.weight(.medium))
                    Spacer()
                }.foregroundStyle(Palette.ink)
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
                HStack {
                    Text(latest.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    Spacer(); let count = readings.filter { $0.kind == latest.kind }.count
                    Text("\(count) \(count == 1 ? "reading" : "readings")")
                }.font(.subheadline).foregroundStyle(Palette.muted)
            } else { Text("No readings yet").font(.title2.weight(.medium)) }
        }.padding(.horizontal, 22).padding(.bottom, 22).padding(.top, 12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 28))
            .accessibilityIdentifier("readingSummary")
    }
}
