import SwiftUI
import HarbourCore

enum AppSheet: Identifiable {
    case symptom(String), medicine(Medicine?), reading(Reading?), interactions([Medicine]), settings, note
    var id: String { switch self { case .symptom: "symptom"; case .medicine: "medicine"; case .reading: "reading"; case .interactions: "interactions"; case .settings: "settings"; case .note: "note" } }
}

@main struct HarbourApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var models = ModelManager()
    @StateObject private var health = HealthService()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(models).environmentObject(health)
                .tint(.primary)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var models: ModelManager
    @State private var tab = 1
    @State private var sheet: AppSheet?
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayView(sheet: $sheet, openChat: { tab = 1 }) }
                .tabItem { Label("Today", systemImage: "house") }.tag(0)
            NavigationStack { ChatView(sheet: $sheet) }
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }.tag(1)
            NavigationStack { RecordsView(sheet: $sheet) }
                .tabItem { Label("Records", systemImage: "heart.text.square") }.tag(2)
        }
        .sheet(item: $sheet) { item in
            NavigationStack {
                switch item {
                case .symptom(let text): SymptomEditor(initial: text)
                case .medicine(let medicine): MedicineEditor(initial: medicine)
                case .reading(let reading): ReadingEditor(initial: reading)
                case .interactions(let medicines): ScrollView { InteractionView(report: HealthRules.check(medicines)).padding(24) }.navigationTitle("Interactions").navigationBarTitleDisplayMode(.inline).toolbar { closeButton }
                case .settings: SettingsView()
                case .note: NoteView()
                }
            }
            .sheet(item: $store.shareFile) { ShareView(url: $0.url) }
        }
        .sheet(item: Binding(get: { if case nil = sheet { return store.shareFile }; return nil }, set: { store.shareFile = $0 })) { ShareView(url: $0.url) }
        .alert("Couldn’t complete that", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .task { if ProcessInfo.processInfo.arguments.contains("--evaluate-model") { await SimulatorEvaluation.run(models: models, store: store) } }
    }
    private var closeButton: some ToolbarContent { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
}

struct HarbourMark: View {
    var size: CGFloat = 30
    var spinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false
    var body: some View {
        ZStack {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: size * 0.11)
                    .frame(width: size * 0.393, height: size * 0.393)
                    .offset(x: index % 2 == 0 ? -size * 0.303 : size * 0.303, y: index < 2 ? -size * 0.303 : size * 0.303)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(animate && spinning && !reduceMotion ? 348 : -12))
        .animation(spinning && !reduceMotion ? .linear(duration: 2.8).repeatForever(autoreverses: false) : nil, value: animate)
        .onAppear { animate = true }
        .accessibilityHidden(true)
    }
}
struct FeatureIcon: View {
    var symbol: String
    var colour: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(colour)
            .frame(width: 30, height: 42)
    }
}
struct FeatureRow: View {
    var title: String
    var subtitle: String?
    var symbol: String
    var colour: Color
    var body: some View {
        HStack(spacing: 14) {
            FeatureIcon(symbol: symbol, colour: colour)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(.vertical, 6).contentShape(Rectangle())
    }
}
struct SettingsButton: View {
    @Binding var sheet: AppSheet?
    var body: some View { Button { sheet = .settings } label: { Image(systemName: "gearshape").frame(width: 36, height: 36) }.accessibilityLabel("Settings") }
}
struct TodayView: View {
    @EnvironmentObject var store: AppStore
    @Binding var sheet: AppSheet?
    var openChat: () -> Void
    var body: some View {
        List {
            Section("Readings") {
                if store.records.readings.isEmpty {
                    Button { sheet = .reading(nil) } label: { FeatureRow(title: "Add a reading", subtitle: nil, symbol: "waveform.path.ecg", colour: .red) }.accessibilityIdentifier("addReading")
                } else {
                    ForEach(ReadingKind.allCases, id: \.self) { kind in
                        if let reading = store.records.readings.first(where: { $0.kind == kind }) { ReadingRow(reading: reading) }
                    }
                }
            }
            Section("Health") {
                Button { sheet = .symptom("") } label: { FeatureRow(title: "Record a symptom", subtitle: nil, symbol: "cross.case", colour: .orange) }.accessibilityIdentifier("addSymptom")
                Button { sheet = .medicine(nil) } label: { FeatureRow(title: "Add a medicine", subtitle: nil, symbol: "pills", colour: .indigo) }
                Button { sheet = .interactions(store.records.medicines) } label: { FeatureRow(title: "Check interactions", subtitle: nil, symbol: "arrow.triangle.branch", colour: .blue) }
                Button { sheet = .note } label: { FeatureRow(title: "Appointment note", subtitle: nil, symbol: "note.text", colour: .purple) }
            }
            if !store.records.symptoms.isEmpty {
                Section("Recent symptoms") {
                    ForEach(store.records.symptoms.prefix(3)) { symptom in SymptomRow(symptom: symptom) }
                }
            }
        }
        .listStyle(.plain).listSectionSpacing(28)
        .navigationTitle("Today")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton(sheet: $sheet) } }
    }
}
struct ReadingRow: View {
    let reading: Reading
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: reading.kind.symbol).foregroundStyle(.red).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) { Text(reading.kind.rawValue).font(.subheadline.weight(.medium)); Text(reading.date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) { Text(reading.value).font(.title2.weight(.semibold)); Text(reading.kind.unit).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}
struct SymptomRow: View {
    let symptom: Symptom
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(symptom.text).font(.body).fixedSize(horizontal: false, vertical: true)
            HStack { Text(symptom.date, style: .date); if !symptom.onset.isEmpty { Text("· " + symptom.onset) } }.font(.caption).foregroundStyle(.secondary)
            if HealthRules.isEmergency(symptom) { Label("Emergency sign recorded", systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red) }
        }.padding(.vertical, 10)
    }
}

struct ShareView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
