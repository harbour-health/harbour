import SwiftUI
import HarbourCore

enum AppSheet: Identifiable {
    case appointment(Appointment)
    case symptom(String), medicine(Medicine?), medicineDraft(Medicine, [DoseTime], MedicationFrequency?), reading(Reading?), interactions([Medicine]), settings, note, reminder(CareReminder), dose(Medicine, Date, DoseStatus?), timeline(String), question(String), scanMedicine, schedule(Medicine, [DoseTime], MedicationFrequency?)
    var drawerHeight: CGFloat { switch self { case .appointment: 620; case .symptom: 690; case .medicine, .medicineDraft: 600; case .reading: 320; case .interactions: 420; case .settings: 640; case .note, .question: 640; case .reminder: 590; case .dose: 450; case .timeline: 720; case .scanMedicine, .schedule: 690 } }
    var id: String { switch self { case .appointment: "appointment"; case .symptom: "symptom"; case .medicine: "medicine"; case .medicineDraft: "medicineDraft"; case .reading: "reading"; case .interactions: "interactions"; case .settings: "settings"; case .note: "note"; case .reminder: "reminder"; case .dose: "dose"; case .timeline: "timeline"; case .question: "question"; case .scanMedicine: "scan"; case .schedule: "schedule" } }
}

@main struct HarbourApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var models = ModelManager()
    @StateObject private var health = HealthService()
    @StateObject private var recorder = VisitRecorder()
    @StateObject private var lock = AppLock()
    @StateObject private var alerts = CareNotifications()
    @AppStorage("appearance") private var appearance = AppearanceChoice.system.rawValue
    var body: some Scene {
        WindowGroup {
            LockShell().environmentObject(lock).environmentObject(store).environmentObject(models).environmentObject(health).environmentObject(recorder).environmentObject(alerts)
                .tint(Palette.ink)
                .environment(\.locale, L10n.locale)
                .preferredColorScheme((AppearanceChoice(rawValue: appearance) ?? .system).scheme)
        }
    }
}

struct LockShell: View {
    @EnvironmentObject var lock: AppLock
    @EnvironmentObject var recorder: VisitRecorder
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group { if lock.locked { LockScreen() } else { RootView() } }
            .background(PrivacyCurtain(covered: phase != .active && !(phase == .inactive && lock.presentingAuthentication)))
            .accessibilityHidden(phase != .active)
            .transaction { if lock.locked { $0.disablesAnimations = true } }
            .onChange(of: phase) { if phase == .background { Task { await recorder.finish(interrupted: true) }; lock.lock(); store.shareFile = nil } }
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject private var alerts: CareNotifications
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var sheet: AppSheet?
    @State private var recordCategory: Int?
    @State private var keyboardVisible = false
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayView(sheet: $sheet, openMedicines: { recordCategory = 1; tab = 2 }).toolbar(.hidden, for: .tabBar) }
                .tabItem { Label("Today", systemImage: tab == 0 ? "house.fill" : "house") }.tag(0)
            NavigationStack { ChatView(sheet: $sheet).toolbar(.hidden, for: .tabBar) }
                .tabItem { Label("Chat", systemImage: tab == 1 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right") }.tag(1)
            NavigationStack { RecordsView(sheet: $sheet, category: $recordCategory).toolbar(.hidden, for: .tabBar) }
                .tabItem { Label("Records", systemImage: tab == 2 ? "heart.text.clipboard.fill" : "heart.text.clipboard") }.tag(2)
            NavigationStack { VisitsView(sheet: $sheet).toolbar(.hidden, for: .tabBar) }
                .tabItem { Label("Visits", systemImage: tab == 3 ? "person.2.fill" : "person.2") }.tag(3)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible {
                NavigationDock(selection: $tab)
                    .transaction { $0.disablesAnimations = true }
            }
        }
        .background(Palette.canvas)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .sheet(item: $sheet) { item in
            NavigationStack {
                switch item {
                case .appointment(let appointment): AppointmentEditor(initial: appointment, saved: store.records.appointments.contains { $0.id == appointment.id })
                case .symptom(let text): SymptomEditor(initial: text)
                case .medicine(let medicine): MedicineEditor(initial: medicine)
                case .medicineDraft(let medicine, let times, let frequency): MedicationDraftReview(medication: medicine, times: times, frequency: frequency)
                case .reading(let reading): ReadingEditor(initial: reading)
                case .interactions(let medicines): ScrollView { InteractionView(report: HealthRules.check(medicines)).padding(24).measuredDrawerHeight() }.navigationTitle("Interactions").navigationBarTitleDisplayMode(.inline).toolbar { closeButton }
                case .settings: SettingsView()
                case .note: PreparationView()
                case .question(let text): PreparationView(initialQuestion: text)
                case .reminder(let reminder): ReminderEditor(initial: reminder, saved: store.care.reminders.contains { $0.id == reminder.id })
                case .dose(let medicine, let date, let status): DoseEditor(medicine: medicine, scheduled: date, proposed: status)
                case .timeline(let query): HealthHistoryView(initialQuery: query).toolbar { closeButton }
                case .scanMedicine: MedicineEditor(initial: nil)
                case .schedule(let medicine, let times, let frequency): MedicineEditor(initial: medicine, suggestedTimes: times, suggestedFrequency: frequency)
                }
            }
            .background(Palette.canvas)
            .floatingDrawer(height: item.drawerHeight)
            .sheet(item: $store.shareFile) { ShareView(url: $0.url) }
        }
        .sheet(item: Binding(get: { if case nil = sheet { return store.shareFile }; return nil }, set: { store.shareFile = $0 })) { ShareView(url: $0.url) }
        .alert("Couldn’t complete that", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .task(id: store.archive.care) { await alerts.sync(care: store.care, medicines: store.records.medicines) }
        .onChange(of: store.records.medicines.map(\.id)) { Task { await alerts.sync(care: store.care, medicines: store.records.medicines) } }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await alerts.sync(care: store.care, medicines: store.records.medicines) } } }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--medicine-review-fixture") { store.prepareMedicineReviewScreenshot() }
            if ProcessInfo.processInfo.arguments.contains("--medication-draft-fixture"),
               let action = try? ToolPlanner.validate(.init(tool: .addMedicine), original: "Add Metformin 500 mg 2 times daily", records: store.records),
               case .add(let medication, let times, let frequency) = action { sheet = .medicineDraft(medication, times, frequency) }
            #endif
            if ProcessInfo.processInfo.arguments.contains("--evaluate-model") { await SimulatorEvaluation.run(models: models, store: store) }
        }
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
        .animation(animate && spinning && !reduceMotion ? .linear(duration: 2.8).repeatForever(autoreverses: false) : nil, value: animate)
        .onAppear { animate = true }
        .onDisappear { animate = false }
        .accessibilityHidden(true)
    }
}
struct FeatureIcon: View {
    var symbol: String
    var colour: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(colour)
            .frame(width: 32, height: 48)
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
                Text(L10n.string(title)).font(.title3.weight(.medium)).foregroundStyle(Palette.ink)
                if let subtitle { Text(L10n.string(subtitle)).font(.subheadline).foregroundStyle(Palette.muted) }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
        }.padding(.vertical, 6).contentShape(Rectangle())
    }
}
struct SettingsButton: View {
    @Binding var sheet: AppSheet?
    var body: some View { Button { sheet = .settings } label: { ToolbarGlyph(symbol: "gearshape") }.accessibilityLabel("Settings") }
}
struct TodayView: View {
    @Binding var sheet: AppSheet?
    var openMedicines: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            actions.fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .top)
            ScrollView { actions }
        }
        .background(Palette.canvas)
        .navigationTitle("Today")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton(sheet: $sheet) } }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button { sheet = .reading(nil) } label: {
                PrimaryActionRow(title: "Add a reading", symbol: "waveform.path.ecg", prominent: true)
            }.accessibilityIdentifier("openReadings")
            Button { sheet = .symptom("") } label: {
                PrimaryActionRow(title: "Log a symptom", symbol: "cross.case", prominent: true)
            }.accessibilityIdentifier("addSymptom")
            Button(action: openMedicines) {
                PrimaryActionRow(title: "My medicines", symbol: "pills")
            }.accessibilityIdentifier("openMedicines")
            NavigationLink {
                ScrollView {
                    AgendaView(sheet: $sheet)
                        .padding(AppLayout.screenInset)
                        .frame(maxWidth: AppLayout.contentWidth)
                        .frame(maxWidth: .infinity)
                }
                .background(Palette.canvas)
                .navigationTitle("Reminders and doses")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                PrimaryActionRow(title: "Reminders and doses", symbol: "calendar")
            }.accessibilityIdentifier("openAgenda")
        }
        .buttonStyle(PressFeedback())
        .padding(.horizontal, AppLayout.screenInset)
        .padding(.vertical, 10)
        .frame(maxWidth: AppLayout.contentWidth)
        .frame(maxWidth: .infinity)
    }
}

struct ReadingRow: View {
    let reading: Reading
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: reading.kind.symbol).foregroundStyle(.red).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) { Text(L10n.string(reading.kind.rawValue)).font(.body.weight(.medium)); Text(reading.date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.subheadline).foregroundStyle(Palette.muted) }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) { Text(L10n.readingValue(reading)).font(.title2.weight(.semibold)); Text(reading.kind.unit).font(.subheadline).foregroundStyle(Palette.muted) }
        }.foregroundStyle(Palette.ink).padding(.vertical, 12).listRowBackground(Color.clear).accessibilityElement(children: .combine)
    }
}
struct SymptomRow: View {
    let symptom: Symptom
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(symptom.text).font(.body).fixedSize(horizontal: false, vertical: true)
            HStack { Text(symptom.date, style: .date); if !symptom.onset.isEmpty { Text("· " + symptom.onset) } }.font(.subheadline).foregroundStyle(Palette.muted)
            if HealthRules.isEmergency(symptom) { Label("Emergency sign recorded", systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red) }
        }.foregroundStyle(Palette.ink).padding(.vertical, 14).listRowBackground(Color.clear)
    }
}

struct ShareView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
