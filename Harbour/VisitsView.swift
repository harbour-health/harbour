import SwiftUI
import HarbourCore

private func visitTime(_ seconds: TimeInterval) -> String {
    let value = max(0, Int(seconds)); return String(format: "%02d:%02d", value / 60, value % 60)
}
struct VisitsView: View {
    @Binding var sheet: AppSheet?
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var recorder: VisitRecorder
    @Environment(\.floatingDockClearance) private var dockClearance
    @State private var destination: UUID?
    @State private var showRecorder = false
    @State private var newVisit: DoctorVisit?
    @State private var deleting: DoctorVisit?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                Button { showRecorder = true } label: {
                    VStack(spacing: 22) {
                        VisitWaveform(levels: Array(repeating: 0.12, count: 38), decorative: true).frame(height: 76).padding(.horizontal, 30)
                        Image(systemName: "mic.fill").font(.system(size: 34)).foregroundStyle(.white)
                            .frame(width: 92, height: 92).background(Palette.coral, in: Circle())
                        Text(L10n.string(recorder.active ? "Recording in progress" : "Record a visit")).font(.system(.title2, design: .rounded, weight: .bold))
                    }.frame(maxWidth: .infinity).padding(.vertical, 36).background(Palette.coralWash, in: RoundedRectangle(cornerRadius: 32))
                }.buttonStyle(PressFeedback()).accessibilityIdentifier("recordVisit")
                Button { sheet = .note } label: { FeatureRow(title: "Appointment preparation", subtitle: nil, symbol: "text.bubble", colour: Palette.blue) }.buttonStyle(.plain).accessibilityIdentifier("prepareAppointment")
                Text("Recent visits").font(.title2.weight(.semibold))
                if store.visits.isEmpty { Text("No visits yet").font(.title3).foregroundStyle(Palette.muted).padding(.vertical, 20) }
                ForEach(store.visits) { visit in
                    Button {
                        if visit.id == recorder.visitID { showRecorder = true } else { destination = visit.id }
                    } label: {
                        HStack(spacing: 18) {
                            Image(systemName: visit.audioFilename == nil ? "note.text" : "waveform").font(.system(size: 25, weight: .medium)).foregroundStyle(Palette.coral).frame(width: 32)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(visit.title).font(.title3.weight(.semibold)).multilineTextAlignment(.leading)
                                HStack(spacing: 8) {
                                    Text(visit.date, format: .dateTime.month(.abbreviated).day())
                                    if visit.duration > 0 { Text("· " + visitTime(visit.duration)).monospacedDigit() }
                                }.font(.subheadline).foregroundStyle(Palette.muted)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
                        }.padding(.vertical, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("visit-row-" + visit.id.uuidString).contextMenu { Button("Delete visit", role: .destructive) { deleting = visit }.disabled(recorder.active) }
                    Divider().overlay(Palette.line)
                }
            }.padding(.horizontal, AppLayout.screenInset).padding(.top, 14).padding(.bottom, 32).frame(maxWidth: AppLayout.contentWidth).frame(maxWidth: .infinity)
        }.contentMargins(.bottom, dockClearance, for: .scrollContent)
            .background(Palette.canvas).foregroundStyle(Palette.ink).navigationTitle("Visits")
            .toolbar {
                if !showRecorder && destination == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { newVisit = DoctorVisit(title: L10n.string("Visit notes")) } label: { ToolbarGlyph(symbol: "square.and.pencil") }
                            .disabled(recorder.active).accessibilityLabel("Add notes").accessibilityIdentifier("addVisitNotes")
                    }
                    ToolbarItem(placement: .topBarTrailing) { SettingsButton(sheet: $sheet) }
                }
            }
            .navigationDestination(isPresented: $showRecorder) { VisitRecordingView() }
            .navigationDestination(item: $destination) { VisitDetailView(id: $0) }
            .sheet(item: $newVisit) { visit in
                NavigationStack { VisitTranscriptEditor(visit: visit, isNew: true) { destination = $0 } }.floatingDrawer(height: 520)
            }
            .confirmationDialog("Delete this visit and its recording?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete visit", role: .destructive) { if let deleting { store.deleteVisit(deleting) }; deleting = nil }
            }
    }
}
struct VisitWaveform: View {
    var levels: [Double]
    var decorative = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 4) {
                ForEach(levels.indices, id: \.self) { index in
                    let level = decorative ? 0.12 + abs(sin(Double(index) * 0.72)) * (0.2 + 0.6 * sin(Double(index) / Double(max(1, levels.count)) * .pi)) : levels[index]
                    Capsule().fill(Palette.coral).frame(height: max(5, geometry.size.height * level))
                }
            }.frame(height: geometry.size.height).animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: levels)
        }.accessibilityHidden(true)
    }
}
struct VisitRecordingView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var recorder: VisitRecorder
    @Environment(\.scenePhase) private var phase
    @Environment(\.floatingDockClearance) private var dockClearance
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var finished: UUID?
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    Text(L10n.string(recorder.state == .paused ? "Paused" : recorder.state == .recording ? "Recording" : "Doctor visit")).font(.system(.title, design: .rounded, weight: .bold))
                    Text(visitTime(recorder.duration)).font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                }.padding(.top, 32)
                VisitWaveform(levels: recorder.levels).frame(height: 112).padding(.horizontal, 18)
                if !recorder.transcript.isEmpty {
                    Text(recorder.transcript).font(.title3).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled).accessibilityIdentifier("liveVisitTranscript")
                }
                if recorder.state == .preparing || recorder.state == .finishing { ProgressView().controlSize(.large) }
                if !recorder.status.isEmpty { Text(recorder.status).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center) }
                HStack(spacing: 36) {
                    if recorder.state == .recording || recorder.state == .paused {
                        Button {
                            let id = recorder.visitID; saving = true
                            Task { await recorder.finish(); saving = false; finished = id }
                        } label: { Image(systemName: "stop.fill").font(.system(size: 24)).frame(width: 64, height: 64).background(Palette.surface, in: Circle()) }
                            .accessibilityLabel("Finish recording").accessibilityIdentifier("finishVisitRecording").disabled(saving)
                    }
                    Button {
                        switch recorder.state {
                        case .idle: Task { await recorder.start(into: store) }
                        case .recording: recorder.pause()
                        case .paused: recorder.resume()
                        case .preparing: Task { await recorder.finish() }
                        case .finishing: break
                        }
                    } label: {
                        Image(systemName: recorder.state == .recording ? "pause.fill" : recorder.state == .paused ? "play.fill" : recorder.state == .preparing ? "xmark" : "mic.fill")
                            .font(.system(size: 34, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 104, height: 104).background(Palette.coral, in: Circle())
                    }.buttonStyle(PressFeedback()).accessibilityLabel(L10n.string(recorder.state == .recording ? "Pause recording" : recorder.state == .paused ? "Resume recording" : recorder.state == .preparing ? "Cancel recording" : "Start recording"))
                        .accessibilityIdentifier("visitRecordingControl").disabled(saving || recorder.state == .finishing)
                }.padding(.vertical, 12)
                Text(L10n.string(recorder.state == .idle ? "Start recording" : recorder.state == .paused ? "Resume or finish" : "")).font(.body.weight(.medium))
            }.padding(.horizontal, 28).padding(.bottom, 32).frame(maxWidth: AppLayout.contentWidth).frame(maxWidth: .infinity)
        }.contentMargins(.bottom, dockClearance, for: .scrollContent)
            .background(Palette.canvas).foregroundStyle(Palette.ink).navigationTitle("Recorder").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $finished) { VisitDetailView(id: $0, automaticallySummarise: true) }
            .alert("Recording", isPresented: Binding(get: { recorder.error != nil }, set: { if !$0 { recorder.error = nil } })) { Button("OK") { recorder.error = nil } } message: { Text(recorder.error ?? "") }
    }
}
struct VisitDetailView: View {
    let id: UUID
    var automaticallySummarise = false
    @State private var startedAutomaticSummary = false
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var models: ModelManager
    @EnvironmentObject private var recorder: VisitRecorder
    @Environment(\.floatingDockClearance) private var dockClearance
    @StateObject private var playback = VisitPlayback()
    @State private var tab = 0
    @State private var editing = false
    @State private var reviewing = false
    @State private var appointmentDraft: Appointment?
    @State private var deleting = false
    @State private var task: Task<Void, Never>?
    @State private var busy = false
    @State private var status = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    private var visit: DoctorVisit? { store.visits.first { $0.id == id } }
    var body: some View {
        ScrollView {
            if let visit {
                VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(visit.date, format: .dateTime.month(.wide).day().year()).font(.body).foregroundStyle(Palette.muted)
                            if visit.duration > 0 { Text(visitTime(playback.playing ? playback.position : visit.duration)).font(.title2.weight(.semibold)).monospacedDigit() }
                        }
                        Spacer()
                        if let url = store.audioURL(for: visit) {
                            Button { playback.toggle(url: url) } label: {
                                Image(systemName: playback.playing ? "pause.fill" : "play.fill").font(.title2).foregroundStyle(Palette.canvas).frame(width: 60, height: 60).background(Palette.ink, in: Circle())
                            }.accessibilityLabel(L10n.string(playback.playing ? "Pause visit audio" : "Play visit audio")).disabled(recorder.active)
                        }
                    }
                    Picker("Visit view", selection: $tab) { Text("Summary").tag(0); Text("Transcript").tag(1) }.pickerStyle(.segmented).controlSize(.large).accessibilityIdentifier("visitDetailTabs")
                    if visit.interrupted { Label("Recording was interrupted. Review the audio and transcript.", systemImage: "exclamationmark.circle").font(.body).foregroundStyle(Palette.coral) }
                    if let warning = visit.transcriptionWarning { Label(L10n.string(warning), systemImage: "waveform.badge.exclamationmark").font(.body).foregroundStyle(Palette.coral) }
                    if tab == 1 {
                        if visit.transcript.isEmpty { Text("No transcript yet").font(.title3).foregroundStyle(Palette.muted) }
                        else { Text(visit.transcript).font(.title3).lineSpacing(8).textSelection(.enabled).accessibilityIdentifier("savedVisitTranscript") }
                        Button { editing = true } label: { Label("Edit transcript", systemImage: "square.and.pencil").font(.body.weight(.semibold)).frame(minHeight: AppLayout.controlSize) }.disabled(busy || recorder.active)
                        if store.audioURL(for: visit) != nil {
                            Button { transcribe(visit) } label: { Label("Transcribe audio", systemImage: "waveform").font(.body.weight(.semibold)).frame(minHeight: AppLayout.controlSize) }.disabled(busy || recorder.active)
                        }
                    } else if let summary = visit.summary {
                        if !summary.highlights.isEmpty { quotes(summary.highlights, title: "Notes", symbol: "note.text") }
                        if !summary.medicines.isEmpty {
                            VStack(alignment: .leading, spacing: 18) {
                                Label("Medications", systemImage: "pills").font(.title2.weight(.semibold)).foregroundStyle(Palette.blue)
                                ForEach(summary.medicines) { change in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(L10n.format("%@ %@", L10n.string(change.action.rawValue.capitalized), L10n.medicineName(change.medicine))).font(.title3.weight(.semibold))
                                        if !change.medicine.instructions.isEmpty { Text(change.medicine.instructions).font(.body) }
                                        if let frequency = change.frequency { Text(L10n.frequency(frequency)).font(.body.weight(.medium)) }
                                        if !change.times.isEmpty { Text(L10n.doseTimes(change.times)).font(.body).foregroundStyle(Palette.muted) }
                                        Text("“" + change.quote + "”").font(.body).foregroundStyle(Palette.muted)
                                    }
                                    Divider()
                                }
                                if visit.appliedChanges.isEmpty {
                                    Button { reviewing = true } label: { Label("Review medicine changes", systemImage: "checkmark.circle") }.buttonStyle(ActionButtonStyle()).disabled(recorder.active || busy).accessibilityIdentifier("reviewVisitMedicines")
                                } else { Label("Medication changes saved", systemImage: "checkmark.circle.fill").font(.body.weight(.medium)).foregroundStyle(Palette.blue) }
                            }
                        }
                        if !summary.followUps.isEmpty { quotes(summary.followUps, title: "Follow-up", symbol: "calendar") }
                        if let appointments = summary.appointments, !appointments.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Label("Appointments", systemImage: "calendar").font(.title2.weight(.semibold)).foregroundStyle(Palette.blue)
                                ForEach(appointments) { item in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(item.quote).font(.body)
                                        if store.records.appointments.contains(where: { $0.visitID == visit.id && $0.quote == item.quote }) {
                                            Label("Appointment saved", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.blue)
                                        } else {
                                            Button("Add appointment", systemImage: "calendar.badge.plus") { appointmentDraft = AppointmentRules.draft(from: item.quote, visitID: visit.id, now: visit.date) }
                                                .disabled(recorder.active || busy).accessibilityIdentifier("addVisitAppointment")
                                        }
                                    }
                                }
                            }
                        }
                        if summary.highlights.isEmpty && summary.followUps.isEmpty && summary.medicines.isEmpty { Text("No details extracted. Review the transcript.").font(.title3) }
                    } else {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(L10n.string(visit.transcript.isEmpty ? "Add a transcript to prepare a summary" : "Ready to summarise")).font(.system(.title2, design: .rounded, weight: .bold))
                            if visit.transcript.isEmpty { Button("Add notes") { editing = true }.font(.title3.weight(.semibold)).accessibilityIdentifier("editVisitTranscript") }
                        }.padding(.vertical, 24)
                    }
                    if busy {
                        HStack(spacing: 12) { HarbourMark(size: AppLayout.loadingMarkSize, spinning: true).foregroundStyle(Palette.blue); Text(status).font(.body); Spacer(); Button("Cancel") { task?.cancel(); models.cancelDownload() } }
                        if models.downloading != nil { ProgressView(value: models.progress).tint(Palette.blue) }
                    } else if !visit.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button { summarise(visit) } label: { Label(L10n.string(visit.summary == nil ? "Prepare summary" : "Refresh summary"), systemImage: "sparkles") }.buttonStyle(ActionButtonStyle(secondary: visit.summary != nil)).disabled(recorder.active).accessibilityIdentifier("summariseVisit")
                    }
                }.padding(.horizontal, AppLayout.screenInset).padding(.top, 16).padding(.bottom, 32).frame(maxWidth: AppLayout.contentWidth).frame(maxWidth: .infinity)
            }
        }.contentMargins(.bottom, dockClearance, for: .scrollContent)
            .background(Palette.canvas).foregroundStyle(Palette.ink).navigationTitle(visit?.title ?? L10n.string("Visit")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Menu {
                    Button("Edit visit", systemImage: "square.and.pencil") { editing = true }.disabled(busy || recorder.active)
                    Button("Share notes", systemImage: "square.and.arrow.up") { if let visit { store.shareVisit(visit) } }
                    Button("Delete visit", systemImage: "trash", role: .destructive) { deleting = true }.disabled(busy || recorder.active)
                } label: { ToolbarGlyph(symbol: "ellipsis") }.accessibilityLabel("Visit options") }
            }
            .sheet(isPresented: $editing) { if let visit { NavigationStack { VisitTranscriptEditor(visit: visit) }.floatingDrawer(height: 520) } }
            .sheet(isPresented: $reviewing) { NavigationStack { VisitMedicineReview(id: id) }.floatingDrawer(height: 520) }
            .sheet(item: $appointmentDraft) { draft in NavigationStack { AppointmentEditor(initial: draft) }.floatingDrawer(height: 620) }
            .confirmationDialog("Delete this visit and its recording?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete visit", role: .destructive) { if let visit { store.deleteVisit(visit) }; dismiss() } }
            .alert("Visit", isPresented: Binding(get: { error != nil || playback.error != nil }, set: { if !$0 { error = nil; playback.error = nil } })) { Button("OK") { error = nil; playback.error = nil } } message: { Text(error ?? playback.error ?? "") }
            .task {
                guard automaticallySummarise, !startedAutomaticSummary, let visit, visit.summary == nil, !visit.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                startedAutomaticSummary = true; summarise(visit)
            }
            .onDisappear { playback.stop(); task?.cancel() }
    }
    private func quotes(_ values: [VisitQuote], title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.string(title), systemImage: symbol).font(.title2.weight(.semibold)).foregroundStyle(Palette.coral)
            ForEach(values) { item in Text(item.quote).font(.title3).lineSpacing(5).textSelection(.enabled); Divider() }
        }
    }
    private func summarise(_ visit: DoctorVisit) {
        busy = true; status = L10n.string("Preparing summary"); playback.stop()
        let baseline = store.records.medicines
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let chunks = VisitReview.chunks(visit.transcript)
                var combined = VisitSummary()
                for (index, chunk) in chunks.enumerated() {
                    try Task.checkCancellation(); status = L10n.format("Preparing summary · %d of %d", index + 1, chunks.count)
                    let output = try await models.generate(VisitReview.prompt(chunk, medicines: baseline), maxTokens: 650)
                    try Task.checkCancellation()
                    combined.merge(try VisitReview.parse(output, transcript: chunk, medicines: baseline))
                }
                store.saveVisitSummary(combined, id: id, transcript: visit.transcript, baseline: baseline)
            } catch is CancellationError { }
            catch { self.error = L10n.string(error.localizedDescription) }
        }
    }
    private func transcribe(_ visit: DoctorVisit) {
        guard let url = store.audioURL(for: visit) else { return }; playback.stop(); busy = true; status = L10n.string("Transcribing audio")
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let text = try await VisitTranscription.transcribe(url) { status = $0 }; try Task.checkCancellation()
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NSError(domain: "Visit", code: 5, userInfo: [NSLocalizedDescriptionKey: L10n.string("No speech was recognised. The saved transcript and audio have been kept.")]) }
                guard var current = store.visits.first(where: { $0.id == id }), current.transcript == visit.transcript else { return }
                current.transcript = text; current.transcriptionWarning = nil; current.summary = nil; current.medicineBaseline = nil; store.saveVisit(current)
            } catch is CancellationError { }
            catch { self.error = L10n.string(error.localizedDescription) }
        }
    }
}
struct VisitTranscriptEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let visit: DoctorVisit
    var isNew = false
    var onSave: ((UUID) -> Void)?
    @State private var title: String
    @State private var transcript: String
    init(visit: DoctorVisit, isNew: Bool = false, onSave: ((UUID) -> Void)? = nil) { self.visit = visit; self.isNew = isNew; self.onSave = onSave; _title = State(initialValue: visit.title); _transcript = State(initialValue: visit.transcript) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TextField("Visit title", text: $title).font(.title2.weight(.semibold)).accessibilityIdentifier("visitTitleInput")
            Divider()
            TextEditor(text: $transcript).font(.title3).scrollContentBackground(.hidden).accessibilityLabel("Notes or transcript").accessibilityIdentifier("visitTranscriptInput")
                .overlay(alignment: .topLeading) {
                    if transcript.isEmpty { Text("Notes or transcript").font(.title3).foregroundStyle(Palette.muted).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false).accessibilityHidden(true) }
                }
        }.padding(24).background(Palette.canvas).foregroundStyle(Palette.ink).navigationTitle("Visit notes").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    guard isNew || store.visits.contains(where: { $0.id == visit.id }) else { dismiss(); return }
                    var current = store.visits.first(where: { $0.id == visit.id }) ?? visit
                    current.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if current.transcript != transcript { current.transcript = transcript; current.summary = nil; current.medicineBaseline = nil }
                    if store.saveVisit(current) { dismiss(); onSave?(current.id) }
                }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || transcript.count > 200_000 || (isNew && transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)).accessibilityIdentifier("saveVisitTranscript") }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
            }
    }
}
struct VisitMedicineReview: View {
    let id: UUID
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<UUID>()
    @State private var acknowledged = false
    private var visit: DoctorVisit? { store.visits.first { $0.id == id } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(visit?.summary?.medicines ?? []) { change in
                    Button {
                        if selected.contains(change.id) { selected.remove(change.id) }
                        else { selected.insert(change.id) }
                        acknowledged = false
                    } label: {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.format("%@ %@", L10n.string(change.action.rawValue.capitalized), L10n.medicineName(change.medicine))).font(.title3.weight(.semibold))
                                if !change.medicine.instructions.isEmpty { Text(change.medicine.instructions).font(.body) }
                                if let frequency = change.frequency { Text(L10n.frequency(frequency)).font(.body.weight(.medium)) }
                                if !change.times.isEmpty { Text(L10n.doseTimes(change.times)).font(.body).foregroundStyle(Palette.muted) }
                                Text("“" + change.quote + "”").font(.body).foregroundStyle(Palette.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            SelectionIndicator(selected: selected.contains(change.id))
                        }.padding(.vertical, 10).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("visit-change-" + change.medicine.id).accessibilityAddTraits(selected.contains(change.id) ? .isSelected : [])
                    Divider()
                }
                Button { acknowledged.toggle() } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Text("I checked the medicine names and instructions against my prescription or visit notes.").font(.body).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        SelectionIndicator(selected: acknowledged)
                    }.foregroundStyle(acknowledged ? Palette.blue : Palette.ink).padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                }.buttonStyle(.plain).accessibilityIdentifier("confirmVisitMedicines").accessibilityAddTraits(acknowledged ? .isSelected : [])
            }.padding(24).measuredDrawerHeight()
        }.background(Palette.canvas).foregroundStyle(Palette.ink).navigationTitle("Medication changes").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.applyVisitChanges(id: id, selected: selected) { dismiss() } }.disabled(selected.isEmpty || !acknowledged || visit?.appliedChanges.isEmpty != true).accessibilityIdentifier("saveVisitMedicines") }
            }
    }
}
