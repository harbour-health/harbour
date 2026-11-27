import SwiftUI
import UniformTypeIdentifiers
import HarbourCore

struct SettingsView: View {
    @EnvironmentObject var recorder: VisitRecorder
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var health: HealthService
    @EnvironmentObject var lock: AppLock
    @Environment(\.dismiss) private var dismiss
    @AppStorage("liveActivitiesEnabled") private var liveActivities = true
    @AppStorage("interfaceMode") private var interfaceMode = AppInterface.simple.rawValue
    @State private var importing = false
    @State private var deleting = false
    var body: some View {
        List {
            Section {
                NavigationLink { InterfaceSettingsView() } label: {
                    HStack { Label("Interface", systemImage: "person.crop.rectangle")
                        Spacer()
                        Text((AppInterface(rawValue: interfaceMode) ?? .simple).title).foregroundStyle(Palette.muted) }
                }.accessibilityIdentifier("interfaceSettings")
                NavigationLink { AppLockSettings() } label: { HStack { Label("App lock", systemImage: "lock")
                    Spacer()
                    Text(lock.modeName).foregroundStyle(Palette.muted) } }.accessibilityIdentifier("appLockSettings")
                NavigationLink { AppearanceView() } label: { Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                if interfaceMode == AppInterface.caregiver.rawValue {
                    NavigationLink { ModelsView() } label: { Label(
                        "Models",
                        systemImage: "cpu"
                    ) } }
                NavigationLink { VoiceSettingsView() } label: { Label("Voice", systemImage: "waveform") }
                    .accessibilityIdentifier("voiceSettings")
                if interfaceMode == AppInterface.caregiver.rawValue {
                    Toggle(isOn: $liveActivities) { Label("Live Activities", systemImage: "waveform.path") }
                        .harbourSwitch()
                        .onChange(of: liveActivities) { SessionActivities.shared.refreshPreferences() }
                    Button { Task { await health.sync(into: store) } } label: { HStack { Label(
                        "Import from Apple Health",
                        systemImage: "heart.fill"
                    ).foregroundStyle(Palette.ink)
                    Spacer()
                    if health.busy {
                        ProgressView()
                    } } }.disabled(health.busy)
                    if !health.status.isEmpty {
                        Text(health.status).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                }
            }
            if interfaceMode == AppInterface.caregiver.rawValue {
                Section("Data") {
                    Button { store.export() } label: { Label("Export records", systemImage: "square.and.arrow.up") }
                    Button { importing = true } label: { Label("Import records", systemImage: "square.and.arrow.down") }
                    Button("Delete all records and chat", role: .destructive) { deleting = true }
                        .disabled(recorder.active)
                }
                Section {
                    NavigationLink { DeveloperSettingsView() } label: { Label("Developer", systemImage: "hammer") }
                        .accessibilityIdentifier("developerSettings") }
                Section {
                    NavigationLink { EvaluationView() } label: { Label("Evaluation", systemImage: "checkmark.seal") }
                }
            }
        }
        .environment(\.defaultMinListRowHeight, 58)
        .scrollContentBackground(.hidden).background(Palette.canvas).navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .drawerHeight(interfaceMode == AppInterface.simple.rawValue ? 390 : health.status.isEmpty ? 750 : 790)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result { case .success(let url): store.importFile(url)
            case .failure(let error): store.error = L10n.string(error.localizedDescription) } }
        .alert("Delete all records and chat?", isPresented: $deleting) {
            Button("Delete all", role: .destructive) { store.clear() }
            Button("Cancel", role: .cancel) {} } message: {
            Text("This includes doctor visits and their recordings.") }
    }
}

struct ModelsView: View {
    var standalone = false
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var downloadTask: Task<Void, Never>?
    var body: some View {
        Form {
            Section {
                ForEach(ModelChoice.allCases) { choice in
                    Button { models.selection = choice } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) { Text(choice.title).fontWeight(.medium)
                                Text(choice == .automatic ? L10n
                                    .format("For this device: %@", models.automaticModel.title) : choice
                                    .technicalName + " · " + ByteCountFormatter.string(
                                        fromByteCount: choice.size,
                                        countStyle: .file
                                    )).font(.subheadline).foregroundStyle(Palette.muted) }
                            Spacer()
                            if models.selection == choice {
                                Image(systemName: "checkmark").fontWeight(.semibold)
                            }
                        }.foregroundStyle(Palette.ink).padding(.vertical, 5)
                    }.accessibilityIdentifier("model-" + choice.rawValue)
                        .disabled(models.downloading != nil || models.generating)
                }
            } header: { Text("Model") } footer: { Text("Camille uses more memory and may not run on every device.") }
            Section {
                Text(models.effort.title).font(.headline)
                EffortSlider(value: Binding(
                    get: { Double(Effort.allCases.firstIndex(of: models.effort) ?? 1) },
                    set: { models.effort = Effort.allCases[Int($0.rounded())] }
                )).frame(height: 48).padding(.vertical, 6)
                HStack { Text("Quick")
                    Spacer()
                    Text("Extended") }.font(.subheadline).foregroundStyle(Palette.muted)
            } header: { Text("Effort") } footer: {
                Text("Effort changes the maximum output length. It does not establish better medical judgement.") }
            Section("Downloads") {
                ForEach(ModelChoice.downloadable) { choice in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) { Text(choice.title)
                                Text(choice.technicalName).font(.caption).foregroundStyle(Palette.muted) }
                            Spacer()
                            if models.installed(choice) {
                                Button("Remove", role: .destructive) {
                                    Task {
                                        do { try await models.remove(choice) } catch {
                                            store.error = L10n.string(error.localizedDescription) } } }
                                    .disabled(models.downloading != nil || models.generating)
                            } else if models.downloading == choice {
                                Button("Cancel") { downloadTask?.cancel()
                                    models.cancelDownload() }
                            } else {
                                Button("Download") {
                                    downloadTask = Task {
                                        do { _ = try await models.ensure(choice) } catch {
                                            if !Task.isCancelled {
                                                store.error = L10n.string(error.localizedDescription)
                                            } } } }
                                            .disabled(models.downloading != nil)
                            }
                        }
                        if models.downloading == choice {
                            ProgressView(value: models.progress)
                            Text(models.isVerifying ? models.status : L10n.format(
                                "%lld%%",
                                Int64(models.progress * 100)
                            ))
                            .font(.caption).foregroundStyle(Palette.muted) }
                    }.padding(.vertical, 8)
                }
            }
        }.scrollContentBackground(.hidden).background(Palette.canvas).navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .drawerHeight(models.downloading == nil ? 680 : 730)
            .toolbar {
                if standalone {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
    }
}
