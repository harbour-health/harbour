import SwiftUI
import PDFKit
import HarbourCore
import HarbourReports

enum VisitReportSection: String, CaseIterable, Identifiable {
    case readings = "Readings", symptoms = "Symptoms", medications = "Current medications", visits = "Visit notes", questions = "Saved questions"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .readings: "waveform.path.ecg"
        case .symptoms: "cross.case.fill"
        case .medications: "pills.fill"
        case .visits: "person.2.fill"
        case .questions: "text.bubble.fill"
        }
    }
    var colour: Color { self == .readings || self == .symptoms ? Palette.coral : Palette.blue }
}

struct VisitReportSnapshot: Encodable {
    struct Item: Encodable { var title: String; var detail: String }
    struct Chart: Encodable { var title: String; var svg: String; var caption: String }
    struct Section: Encodable { var title: String; var items: [Item]; var charts: [Chart] = [] }
    var title: String
    var language: String
    var period: String
    var generated: String
    var context: String
    var empty: String
    var sections: [Section]

    init(records: Records, care: CareData, visits: [DoctorVisit], from: Date, through: Date,
         selected: Set<VisitReportSection>, detailed: Bool = false, now: Date = .now, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: from)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: through))!
        func included(_ date: Date) -> Bool { date >= start && date < end && date <= now }
        title = L10n.string("Doctor visit report")
        language = L10n.isFrench ? "fr" : "en"
        period = L10n.date(start) + " – " + L10n.date(through)
        generated = L10n.date(now)
        context = L10n.string("Readings, symptoms, and visit notes use the selected dates. Medications and questions reflect the current saved list. Recorded information only; this report does not provide a diagnosis.")
        empty = L10n.string("No records to include.")
        sections = VisitReportSection.allCases.filter { selected.contains($0) }.map { section in
            var result = Section(title: L10n.string(section.rawValue), items: [])
            switch section {
            case .readings:
                let readings = records.readings.filter { included($0.date) }.sorted { $0.date < $1.date }
                if detailed {
                result.items = readings.map { reading in
                    Item(title: L10n.date(reading.date, time: true) + " · " + L10n.string(reading.kind.rawValue) + ": " + L10n.readingValue(reading) + " " + reading.kind.unit,
                         detail: L10n.string("Source") + ": " + L10n.string(reading.source))
                }
                } else {
                    result.items = ReadingKind.allCases.compactMap { kind in
                        let values = readings.filter { $0.kind == kind && ReadingParser.valid($0.value, kind: kind) }
                        guard let latest = values.last else { return nil }
                        let series = (0..<(kind == .bloodPressure ? 2 : 1)).map { index in
                            values.map { Double(ReadingParser.normalizedValue($0.value).split(separator: "/")[index])! }
                        }
                        func range(_ values: [Double]) -> String {
                            let format = kind == .temperature ? "%.1f" : "%.0f"
                            return String(format: format, locale: L10n.locale, values.min()!) + "–" + String(format: format, locale: L10n.locale, values.max()!)
                        }
                        let span = kind == .bloodPressure ? L10n.format("Systolic: %@; diastolic: %@ mmHg", range(series[0]), range(series[1])) : L10n.format("Range: %@ %@", range(series[0]), kind.unit)
                        return Item(title: L10n.string(kind.rawValue), detail: [L10n.format("%lld readings", Int64(values.count)),
                            L10n.format("Latest: %@ (%@)", L10n.readingValue(latest) + " " + kind.unit, L10n.date(latest.date, time: true)), span].joined(separator: " · "))
                    }
                }
                result.charts = ReadingKind.allCases.compactMap { kind in
                    let values = readings.filter { $0.kind == kind && ReadingParser.valid($0.value, kind: kind) }
                    guard !values.isEmpty else { return nil }
                    return Chart(title: L10n.string(kind.rawValue) + " (" + kind.unit + ")", svg: Self.chart(values, kind: kind),
                                 caption: L10n.string("Dots show recorded values. Lines connect consecutive readings; gaps do not imply measurements.") + (kind == .bloodPressure ? " " + L10n.string("Blue: systolic. Coral: diastolic.") : ""))
                }
            case .symptoms:
                let symptoms = records.symptoms.filter { included($0.date) }.sorted { $0.date > $1.date }
                let chosen = detailed ? symptoms : Array(symptoms.prefix(5))
                result.items = chosen.map {
                    Item(title: L10n.date($0.date) + " · " + $0.text,
                         detail: L10n.format("Severity: %@", L10n.string($0.severity)) + " · " + L10n.format("Started: %@", $0.onset.isEmpty ? L10n.string("Not recorded") : $0.onset))
                }
                if chosen.count < symptoms.count { result.items.insert(Item(title: L10n.format("%lld symptoms recorded", Int64(symptoms.count)), detail: L10n.format("Showing the %lld most recent entries. Enable Full history to include every entry.", Int64(chosen.count))), at: 0) }
            case .medications:
                result.items = records.medicines.map { medicine in
                    var details = [medicine.instructions]
                    if let schedule = care.schedules.first(where: { $0.medicineID == medicine.id }) {
                        if let frequency = schedule.frequency { details.append(L10n.frequency(frequency)) }
                        if !schedule.times.isEmpty { details.append(L10n.doseTimes(schedule.times)) }
                    }
                    return Item(title: L10n.medicineName(medicine), detail: details.filter { !$0.isEmpty }.joined(separator: detailed ? "\n" : " · "))
                }
            case .visits:
                let history = visits.filter { included($0.date) }.sorted { $0.date > $1.date }
                let chosen = detailed ? history : Array(history.prefix(3))
                result.items = chosen.map {
                    Item(title: L10n.date($0.date) + " · " + $0.title,
                         detail: $0.summary.map { summary in (summary.highlights.compactMap(\.text) + summary.medicines.map { L10n.medicineName($0.medicine) + ": " + $0.medicine.instructions } + summary.followUps.map { $0.text ?? VisitFollowUp.title(for: $0.quote, french: L10n.isFrench) }).joined(separator: "\n") } ?? L10n.string("No summary yet"))
                }
                if chosen.count < history.count { result.items.insert(Item(title: L10n.format("%lld visits recorded", Int64(history.count)), detail: L10n.format("Showing the %lld most recent entries. Enable Full history to include every entry.", Int64(chosen.count))), at: 0) }
            case .questions:
                let questions = detailed ? care.questions : Array(care.questions.prefix(10))
                result.items = questions.map { Item(title: $0.text, detail: "") }
                if questions.count < care.questions.count { result.items.append(Item(title: L10n.format("%lld additional questions", Int64(care.questions.count - questions.count)), detail: L10n.string("Enable Full history to include every entry."))) }
            }
            return result
        }
    }

    /// All coordinates are generated from validated numeric readings; labels are XML escaped.
    private static func chart(_ readings: [Reading], kind: ReadingKind) -> String {
        func number(_ value: Double) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value) }
        func xml(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let series = (0..<(kind == .bloodPressure ? 2 : 1)).map { index in
            readings.map { reading in Double(ReadingParser.normalizedValue(reading.value).split(separator: "/")[index])! }
        }
        let values = series.flatMap { $0 }, low = values.min()!, high = values.max()!
        let padding = max((high - low) * 0.15, kind == .temperature ? 0.5 : 5)
        let minimum = low - padding, maximum = high + padding
        let first = readings.first!.date.timeIntervalSince1970, last = readings.last!.date.timeIntervalSince1970
        var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"640\" height=\"140\" viewBox=\"0 0 640 140\"><rect width=\"640\" height=\"140\" fill=\"#f5f5f5\"/>"
        for tick in 0...4 {
            let y = 10 + Double(tick) * 25.5
            let label = maximum - Double(tick) * (maximum - minimum) / 4
            let axisLabel = String(format: kind == .temperature ? "%.1f" : "%.0f", locale: L10n.locale, label)
            svg += "<line x1=\"34\" y1=\"\(number(y))\" x2=\"630\" y2=\"\(number(y))\" stroke=\"#e5e5e5\"/><text x=\"28\" y=\"\(number(y + 4))\" text-anchor=\"end\" font-size=\"11\" font-family=\"Lato\">\(xml(axisLabel))</text>"
        }
        for (index, points) in series.enumerated() {
            let color = index == 0 ? "#365dce" : "#b94831"
            let coordinates = points.enumerated().map { item -> (String, String) in
                let x = first == last ? 332 : 34 + (readings[item.offset].date.timeIntervalSince1970 - first) / (last - first) * 596
                let y = 112 - (item.element - minimum) / (maximum - minimum) * 102
                return (number(x), number(y))
            }
            svg += "<polyline points=\"\(coordinates.map { $0.0 + "," + $0.1 }.joined(separator: " "))\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"2\"/>"
            for (x, y) in coordinates { svg += "<circle cx=\"\(x)\" cy=\"\(y)\" r=\"3\" fill=\"\(color)\"/>" }
        }
        svg += "<text x=\"34\" y=\"133\" font-size=\"11\" font-family=\"Lato\">\(xml(L10n.date(readings.first!.date, time: true)))</text>"
        if first != last { svg += "<text x=\"630\" y=\"133\" text-anchor=\"end\" font-size=\"11\" font-family=\"Lato\">\(xml(L10n.date(readings.last!.date, time: true)))</text>" }
        return svg + "</svg>"
    }
}

struct VisitReportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.floatingDockClearance) private var dockClearance
    @State private var from = Calendar.current.date(byAdding: .day, value: -29, to: .now)!
    @State private var through = Date.now
    @State private var selected = Set(VisitReportSection.allCases)
    @State private var detailed = false
    @State private var generating = false
    @State private var error: String?
    @State private var preview: ShareFile?
    @State private var temporaryFolder: URL?
    @State private var generation: Task<Void, Never>?
    private var valid: Bool { !selected.isEmpty && Calendar.current.startOfDay(for: from) <= Calendar.current.startOfDay(for: through) }

    var body: some View {
        Form {
            Section("Date range") {
                HStack {
                    Button("30 days") { from = Calendar.current.date(byAdding: .day, value: -29, to: .now)!; through = .now }
                    Spacer()
                    Button("All time") {
                        from = min((store.records.readings.map(\.date) + store.records.symptoms.map(\.date) + store.visits.map(\.date)).min() ?? .now, .now)
                        through = .now
                    }.accessibilityIdentifier("reportAllTime")
                }.buttonStyle(.borderless)
                DatePicker("From", selection: $from, in: ...Date.now, displayedComponents: .date).accessibilityIdentifier("reportFrom")
                DatePicker("Through", selection: $through, in: ...Date.now, displayedComponents: .date).accessibilityIdentifier("reportThrough")
                Toggle("Full history", isOn: $detailed).harbourSwitch().accessibilityIdentifier("reportFullHistory")
                if Calendar.current.startOfDay(for: from) > Calendar.current.startOfDay(for: through) { Text("Choose an end date on or after the start date.").foregroundStyle(Palette.coral) }
            }
            Section {
                ForEach(VisitReportSection.allCases) { section in
                    Toggle(isOn: Binding(get: { selected.contains(section) }, set: { if $0 { selected.insert(section) } else { selected.remove(section) } })) {
                        HStack(spacing: 14) {
                            FeatureIcon(symbol: section.symbol, colour: section.colour)
                            Text(L10n.string(section.rawValue)).foregroundStyle(Palette.ink)
                        }
                    }
                        .harbourSwitch().accessibilityIdentifier("reportSection-" + section.id.rawValue)
                }
            } header: { Text("Include in report") } footer: {
                Text("The date range applies to readings, symptoms, and visit notes. Current medications and saved questions are included as they are today. Visit notes include saved transcripts, not audio.")
            }
            Section {
                Button { generate() } label: {
                    HStack(spacing: 12) { if generating { ProgressView().tint(Palette.canvas) }; Label("Preview report", systemImage: "doc.richtext") }
                }.buttonStyle(ActionButtonStyle()).listRowBackground(Color.clear)
                    .disabled(!valid || generating).accessibilityIdentifier("previewVisitReport")
                if let error { Text(error).foregroundStyle(Palette.coral).accessibilityIdentifier("reportError") }
            }
        }
        .disabled(generating).tint(Palette.ink)
        .contentMargins(.bottom, dockClearance, for: .scrollContent)
        .scrollContentBackground(.hidden).background(Palette.canvas)
        .navigationTitle("Doctor visit report").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preview, onDismiss: cleanup) { file in
            NavigationStack { VisitReportPreview(url: file.url) }.floatingDrawer(height: 760)
        }
        .onDisappear { generation?.cancel(); cleanup() }
        .onChange(of: phase) { if phase == .background { generation?.cancel(); preview = nil; cleanup() } }
    }

    private func generate() {
        error = nil; generating = true
        let snapshot = VisitReportSnapshot(records: store.records, care: store.care, visits: store.visits, from: from, through: through, selected: selected, detailed: detailed)
        generation = Task {
            defer { generating = false }
            do {
                let json = try JSONEncoder().encode(snapshot)
                let pdf = try await ReportCompiler.shared.compile(json: json)
                try Task.checkCancellation()
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HarbourReport-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
                temporaryFolder = folder
                let url = folder.appendingPathComponent("Harbour-visit-report.pdf")
                try pdf.write(to: url, options: [.atomic, .completeFileProtection])
                preview = ShareFile(url: url)
            } catch is CancellationError { cleanup() }
            catch { cleanup(); self.error = L10n.string("Couldn’t create the report. Try a shorter date range or fewer sections.") }
        }
    }
    private func cleanup() {
        if let temporaryFolder { try? FileManager.default.removeItem(at: temporaryFolder) }
        temporaryFolder = nil
    }
}

private struct VisitReportPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var sharing = false
    var body: some View {
        ReportPDFView(url: url).privacySensitive().accessibilityIdentifier("visitReportPDF")
            .overlay { if phase != .active { Palette.canvas.ignoresSafeArea() } }
            .navigationTitle("Report preview").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { sharing = true } label: { Label("Share PDF", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("shareVisitReport")
                }
            }
            .sheet(isPresented: $sharing) { ShareView(url: url) }
    }
}

private struct ReportPDFView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url); view.backgroundColor = .secondarySystemBackground
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}
