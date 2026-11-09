import SwiftUI

struct DeveloperSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var models: ModelManager
    @EnvironmentObject private var health: HealthService
    @EnvironmentObject private var recorder: VisitRecorder
    @State private var confirming = false
    @State private var loaded = false
    private var busy: Bool { recorder.active || models.generating || health.busy }
    var body: some View {
        List {
            Section {
                Button { confirming = true } label: {
                    Label("Replace with demo data", systemImage: "sparkles.rectangle.stack")
                        .foregroundStyle(Palette.ink).padding(.vertical, 6)
                }.disabled(busy).accessibilityIdentifier("loadDemoData")
                if loaded || store.archive.demoData == true {
                    Label("Demo data loaded", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.blue).accessibilityIdentifier("demoDataLoaded")
                }
            } footer: {
                Text("Fictional records, trends, schedules, appointments, chat history and completed visit summaries. Visits use preset transcripts without audio. Notifications are off for demo records.")
            }
            Section {
                Label("Models and app settings are kept", systemImage: "internaldrive")
            } footer: {
                Text("Export any records you want to keep before replacing them. This removes existing records, chat and visit recordings from this device.")
            }
        }
        .scrollContentBackground(.hidden).background(Palette.canvas)
        .navigationTitle("Developer").navigationBarTitleDisplayMode(.inline)
        .drawerHeight(560)
        .alert("Replace all local data?", isPresented: $confirming) {
            Button("Replace with demo data", role: .destructive) {
                guard !busy else { return }
                loaded = store.loadDemoData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your records, chat history and visit recordings will be deleted and replaced with fictional demo data. This cannot be undone.")
        }
    }
}
