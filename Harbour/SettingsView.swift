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
    @State private var importing = false
    @State private var deleting = false
    var body: some View {
        List {
            Section {
                NavigationLink { AppLockSettings() } label: { HStack { Label("App lock", systemImage: "lock"); Spacer(); Text(lock.modeName).foregroundStyle(Palette.muted) } }
                NavigationLink { AppearanceView() } label: { Label("Appearance", systemImage: "circle.lefthalf.filled") }
                NavigationLink { ModelsView() } label: { Label("Models", systemImage: "cpu") }
                Button { Task { await health.sync(into: store) } } label: { HStack { Label("Import from Apple Health", systemImage: "heart.fill").foregroundStyle(Palette.ink); Spacer(); if health.busy { ProgressView() } } }.disabled(health.busy)
                if !health.status.isEmpty { Text(health.status).font(.subheadline).foregroundStyle(Palette.muted) }
            }
            Section("Data") {
                Button { store.export() } label: { Label("Export records", systemImage: "square.and.arrow.up") }
                Button { importing = true } label: { Label("Import records", systemImage: "square.and.arrow.down") }
                Button("Delete all records and chat", role: .destructive) { deleting = true }.disabled(recorder.active)
            }
            Section { NavigationLink { EvaluationView() } label: { Label("Evaluation", systemImage: "checkmark.seal") } }
        }.scrollContentBackground(.hidden).background(Palette.canvas).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .drawerHeight(health.status.isEmpty ? 640 : 690)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in switch result { case .success(let url): store.importFile(url); case .failure(let error): store.error = error.localizedDescription } }
        .alert("Delete all records and chat?", isPresented: $deleting) { Button("Delete all", role: .destructive) { store.clear() }; Button("Cancel", role: .cancel) {} } message: { Text("This includes doctor visits and their recordings.") }
    }
}
struct ModelsView: View {
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var downloadTask: Task<Void, Never>?
    var body: some View {
        Form {
            Section("Model") {
                ForEach(ModelChoice.allCases) { choice in
                    Button { models.selection = choice } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) { Text(choice.title).fontWeight(.medium); Text(choice == .automatic ? "For this device: \(models.resolved.title)" : ByteCountFormatter.string(fromByteCount: choice.size, countStyle: .file)).font(.subheadline).foregroundStyle(Palette.muted) }
                            Spacer(); if models.selection == choice { Image(systemName: "checkmark").fontWeight(.semibold) }
                        }.foregroundStyle(Palette.ink).padding(.vertical, 5)
                    }.disabled(models.downloading != nil || models.generating)
                }
            }
            Section {
                Text(models.effort.rawValue).font(.headline)
                EffortSlider(value: Binding(get: { Double(Effort.allCases.firstIndex(of: models.effort) ?? 1) }, set: { models.effort = Effort.allCases[Int($0.rounded())] })).frame(height: 48).padding(.vertical, 6)
                HStack { Text("Quick"); Spacer(); Text("Extended") }.font(.subheadline).foregroundStyle(Palette.muted)
            } header: { Text("Effort") } footer: { Text("Effort changes the maximum output length. It does not establish better medical judgement.") }
            Section("Downloads") {
                ForEach([ModelChoice.small, .balanced]) { choice in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(choice.title); Spacer()
                            if models.installed(choice) {
                                Button("Remove", role: .destructive) { Task { do { try await models.remove(choice) } catch { store.error = error.localizedDescription } } }.disabled(models.downloading != nil || models.generating)
                            } else if models.downloading == choice {
                                Button("Cancel") { downloadTask?.cancel(); models.cancelDownload() }
                            } else {
                                Button("Download") { downloadTask = Task { do { _ = try await models.ensure(choice) } catch { if !Task.isCancelled { store.error = error.localizedDescription } } } }.disabled(models.downloading != nil)
                            }
                        }
                        if models.downloading == choice { ProgressView(value: models.progress); Text(models.status == "Verifying download" ? models.status : "\(Int(models.progress * 100))%").font(.caption).foregroundStyle(Palette.muted) }
                    }.padding(.vertical, 8)
                }
            }
        }.scrollContentBackground(.hidden).background(Palette.canvas).navigationTitle("Models").navigationBarTitleDisplayMode(.inline)
        .drawerHeight(models.downloading == nil ? 680 : 730)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
