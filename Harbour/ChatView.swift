import SwiftUI
import HarbourCore

struct ChatView: View {
    @EnvironmentObject var recorder: VisitRecorder
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var health: HealthService
    @Binding var sheet: AppSheet?
    @StateObject private var voice = VoiceService()
    @State private var voiceMode = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    @State private var hint: String?
    private var busy: Bool { models.chatRequestState.isBusy }
    @State private var modelSheet = false
    @State private var toolSheet = false
    @State private var deleteConfirmation = false
    @State private var removal: Medicine?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.floatingDockClearance) private var dockClearance
    var body: some View {
        VStack(spacing: 0) {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if store.messages.isEmpty {
                        VStack(spacing: 16) {
                            HarbourIllustration(kind: .conversation, animated: true).frame(width: 204, height: 160)
                            Text("What’s on your mind?").font(.largeTitle.weight(.medium)).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.top, 12).padding(.bottom, 16)
                        VStack(alignment: .leading, spacing: 4) {
                            starter("Check medications", symbol: "pills", colour: Palette.blue, hint: "Interactions")
                            starter("Record a symptom", symbol: "cross.case", colour: Palette.coral, hint: "Symptoms")
                            starter("Add a reading", symbol: "waveform.path.ecg", colour: Palette.coral, hint: "Readings")
                        }.frame(maxWidth: 400).frame(maxWidth: .infinity)
                    }
                    ForEach(store.messages) { message in MessageView(message: message, speak: { if !recorder.active { voice.speak(message.spokenText) } }).id(message.id).transition(.opacity.combined(with: .move(edge: .bottom))) }
                    if busy {
                        HStack(spacing: 12) { HarbourMark(size: AppLayout.loadingMarkSize, spinning: true).foregroundStyle(Palette.blue); Text(models.chatRequestState.isCancelling ? L10n.string("Please wait before trying again.") : models.downloading == nil ? L10n.string("Thinking…") : models.status).font(.subheadline).foregroundStyle(Palette.muted) }.id("pending")
                        if models.downloading != nil { VStack(alignment: .leading, spacing: 8) { ProgressView(value: models.progress); Text(models.isVerifying ? models.status : L10n.format("%lld%% downloaded", Int64(models.progress * 100))).font(.caption).foregroundStyle(Palette.muted) } }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: store.messages.count).padding(.horizontal, AppLayout.screenInset).padding(.bottom, 16).frame(maxWidth: AppLayout.contentWidth).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.count) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: busy) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
            composer
        }
        .padding(.bottom, dockClearance)
        .background(Palette.canvas).foregroundStyle(Palette.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
            ToolbarItem(placement: .principal) { Text(store.chatTitle).font(.body.weight(.medium)).lineLimit(1).accessibilityIdentifier("chatTitle") }
            ToolbarItem(placement: .topBarLeading) { Button { cancel(); focused = false; draft = ""; hint = nil; store.newChat() } label: { ToolbarGlyph(symbol: "square.and.pencil") }.accessibilityLabel("New chat") }
            ToolbarItem(placement: .topBarTrailing) { SettingsButton(sheet: $sheet) }
        }
        .sheet(isPresented: $modelSheet) { NavigationStack { ModelsView(standalone: true) }.floatingDrawer(height: 680) }
        .sheet(isPresented: $toolSheet) { topicPicker.floatingDrawer(height: 420) }
        .confirmationDialog("Delete all records and chat?", isPresented: $deleteConfirmation, titleVisibility: .visible) { Button("Delete all", role: .destructive) { store.clear() }; Button("Cancel", role: .cancel) {} }
        .confirmationDialog(L10n.format("Remove %@ from your list?", removal.map(L10n.medicineName) ?? L10n.string("medicine")), isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) { Button("Remove", role: .destructive) { if let removal { store.removeMedicine(removal.id); store.append(ChatMessage(text: L10n.format("Removed %@ from your list.", L10n.medicineName(removal)))) }; removal = nil } }
        .alert("Voice input", isPresented: Binding(get: { voice.error != nil }, set: { if !$0 { voice.error = nil } })) { Button("OK") { voice.error = nil } } message: { Text(voice.error ?? "") }
        .onChange(of: sheet?.id) { voice.stop() }
        .onChange(of: modelSheet) { if modelSheet { voice.stop() } }
        .onChange(of: toolSheet) { if toolSheet { voice.stop() } }
        .onChange(of: scenePhase) { if scenePhase == .background || (scenePhase == .inactive && (voice.listening || voice.finishing || voice.speaking)) { cancel() } }
        .onChange(of: recorder.active) { if recorder.active { cancel() } }
        .onChange(of: voice.error) { if voice.error != nil { voiceMode = false } }
        .onDisappear { cancel() }
    }
    private func starter(_ title: String, symbol: String, colour: Color, hint: String) -> some View {
        Button { self.hint = hint; focused = true } label: {
            HStack(spacing: 14) { Image(systemName: symbol).font(.title2).foregroundStyle(colour).frame(width: 32); Text(L10n.string(title)).font(.title3.weight(.medium)).foregroundStyle(Palette.ink); Spacer(); Image(systemName: "arrow.up.left").font(.body).foregroundStyle(Palette.muted) }
                .padding(.vertical, 14).contentShape(Rectangle())
        }.buttonStyle(PressFeedback()).accessibilityIdentifier("starter-" + hint.lowercased())
    }
    private var composer: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if voiceMode {
                    HStack {
                        Label(L10n.string(voice.listening ? "Listening" : voice.finishing ? "Finishing…" : voice.speaking ? "Speaking" : busy ? "Thinking…" : "Voice paused"), systemImage: "waveform").symbolEffect(.variableColor, options: .repeating, isActive: !reduceMotion && (voice.listening || voice.speaking)).foregroundStyle(Palette.coral)
                        Spacer(); Button("End voice") { voiceMode = false; voice.stop() }.font(.body.weight(.medium)).frame(minHeight: AppLayout.controlSize).contentShape(Rectangle())
                    }.accessibilityIdentifier("voiceModeStatus")
                }
                TextField("Ask, record, or check something…", text: $draft, prompt: Text("Ask, record, or check something…").foregroundStyle(Palette.muted), axis: .vertical)
                    .lineLimit(2...6).font(.title3).focused($focused).accessibilityIdentifier("chatInput")
                    .padding(.horizontal, 6).padding(.top, 6)
                    .frame(minHeight: verticalSize == .compact ? 54 : 82, alignment: .topLeading)
                if let hint {
                    Button { self.hint = nil } label: { HStack(spacing: 5) { Text(L10n.string(hint)).font(.subheadline); Image(systemName: "xmark").font(.caption2) }.padding(.horizontal, 10).padding(.vertical, 7).background(Palette.blueWash, in: Capsule()).foregroundStyle(Palette.ink) }.accessibilityLabel(L10n.format("Clear %@ topic", L10n.string(hint)))
                }
                HStack(spacing: 4) {
                    Button { focused = false; toolSheet = true } label: { ToolbarGlyph(symbol: "plus") }.accessibilityLabel("Choose a topic")
                    Spacer(minLength: 0)
                    Button { focused = false; modelSheet = true } label: {
                        HStack(spacing: 5) {
                            ViewThatFits(in: .horizontal) {
                                modelLabel(compact: false).fixedSize(horizontal: true, vertical: false)
                                modelLabel(compact: true).fixedSize(horizontal: true, vertical: false)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(models.resolved.compactTitle).font(.body.weight(.medium))
                                    Text(models.effort.title).font(.body).foregroundStyle(Palette.muted)
                                }
                            }
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                            .padding(.horizontal, 10).frame(minHeight: 48).contentShape(RoundedRectangle(cornerRadius: 10))
                    }.layoutPriority(-1).accessibilityLabel("Choose model").accessibilityValue(L10n.string(models.resolved.title) + ", " + models.effort.title).accessibilityIdentifier("modelSelector")
                    if voiceMode {
                        Button {
                            if voice.listening { voice.finishUtterance() }
                            else if voice.speaking { voice.stop(); startVoiceTurn() }
                            else if !busy { startVoiceTurn() }
                        } label: { Image(systemName: voice.listening ? "mic.fill" : "waveform").foregroundStyle(Palette.coral).frame(width: 44, height: 48) }.accessibilityLabel(L10n.string(voice.listening ? "Finish speaking" : "Resume voice"))
                    } else {
                        Menu {
                            Button("Voice conversation", systemImage: "waveform") { focused = false; voiceMode = true; startVoiceTurn() }
                            Button(L10n.string(voice.listening ? "Finish dictation" : "Dictate message"), systemImage: "mic") {
                                if voice.listening { voice.finishUtterance() }
                                else { let original = draft; Task { await voice.start { transcript in draft = original.isEmpty ? transcript : original + " " + transcript } } }
                            }
                        } label: { Image(systemName: voice.listening ? "mic.fill" : "mic").foregroundStyle(voice.listening ? Palette.coral : Palette.ink).frame(width: 44, height: 48) }.accessibilityLabel("Voice options").disabled(busy || recorder.active)
                    }
                    Button { busy ? cancel() : send() } label: {
                        Image(systemName: busy ? "stop.fill" : "arrow.up").font(.body.weight(.semibold))
                            .foregroundStyle(Palette.canvas).frame(width: 44, height: 44).background(Palette.ink, in: Circle())
                    }.accessibilityLabel(L10n.string(busy ? "Stop" : "Send message")).disabled(models.chatRequestState.isCancelling || (!busy && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            .padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Palette.line.opacity(0.7)))
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
            .frame(maxWidth: AppLayout.contentWidth)
        }.frame(maxWidth: .infinity).background(Palette.canvas).foregroundStyle(Palette.ink)
    }
    private func modelLabel(compact: Bool) -> some View {
        HStack(spacing: 5) {
            Text(compact ? models.resolved.compactTitle : models.resolved.chatTitle).font(.body.weight(.medium))
            Text(models.effort.title).font(.body).foregroundStyle(Palette.muted)
        }
    }
    private var topicPicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Topic").font(.title2.weight(.semibold)).padding(.bottom, 12)
                ForEach([("Symptoms", "cross.case.fill", Palette.coral), ("Medications", "pills.fill", Palette.blue), ("Interactions", "arrow.triangle.branch", Palette.blue), ("Readings", "waveform.path.ecg", Palette.coral), ("Appointments", "calendar", Palette.blue)], id: \.0) { item in
                    Button { hint = item.0; toolSheet = false; focused = true } label: { FeatureRow(title: item.0, subtitle: nil, symbol: item.1, colour: item.2) }.buttonStyle(.plain).padding(.vertical, 4)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .topLeading).measuredDrawerHeight(chrome: 24)
        }.background(Palette.canvas)
    }
    private func startVoiceTurn() {
        guard voiceMode, !busy, sheet == nil, !modelSheet, !toolSheet, !recorder.active, scenePhase == .active else { return }
        Task { guard voiceMode, !busy, sheet == nil, !modelSheet, !toolSheet, !recorder.active, scenePhase == .active else { return }; await voice.start(transcript: { draft = $0 }, finished: { text in draft = text; send() }) }
    }
    private func speakReply() {
        guard voiceMode, let reply = store.messages.last, !reply.isUser else { return }
        voice.speak(reply.spokenText, finished: { startVoiceTurn() })
    }
    private func cancel() { voiceMode = false; models.chatRequests.cancel(); voice.stop() }
    private func send() {
        let input = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !models.chatRequests.state.isBusy else { return }
        let firstMessage = !store.messages.contains(where: \.isUser)
        let message = ChatMessage(isUser: true, text: input)
        // Emergency wording is checked before any download or model inference.
        if HealthRules.emergencyCue(input) {
            voice.stop(); focused = false; draft = ""; store.append(message)
            store.append(ChatMessage(text: L10n.string(HealthRules.guidance(Symptom(text: input)))))
            sheet = .symptom(input); speakReply(); return
        }
        let chosenHint = hint
        let history = store.messages.map { ConversationTurn(isUser: $0.isUser, text: $0.spokenText) }
        guard models.chatRequests.start(operation: { currentID in
            do {
                let decision = try await models.chatDecision(input, hint: chosenHint, records: store.records, history: history)
                try Task.checkCancellation()
                guard models.chatRequests.canApplyResult(for: currentID) else { return }
                let action = try ToolPlanner.validate(decision, original: input, records: store.records, language: L10n.isFrench ? .french : .english)
                execute(action)
                if firstMessage, let title = try? await models.title(for: input), !Task.isCancelled, models.chatRequests.canApplyResult(for: currentID) { store.nameChat(title, firstMessage: message.id) }
            } catch is CancellationError { }
            catch { if !Task.isCancelled, models.chatRequests.canApplyResult(for: currentID) { store.append(ChatMessage(text: L10n.string(error.localizedDescription))); if firstMessage, let title = try? await models.title(for: input), !Task.isCancelled, models.chatRequests.canApplyResult(for: currentID) { store.nameChat(title, firstMessage: message.id) } } }
        }, onCompletion: { accepted in if accepted { speakReply() } }) != nil else { return }
        // Admission precedes every composer/message mutation. The operation runs
        // on MainActor after this synchronous send has appended its user input.
        voice.stop(); focused = false; draft = ""; store.append(message)
    }
    private func execute(_ action: ValidatedAction) {
        switch action {
        case .reply(let text): store.append(ChatMessage(text: text))
        case .appointment(let text): sheet = .appointment(AppointmentRules.draft(from: text))
        case .appointments: store.append(ChatMessage(text: L10n.string(store.records.appointments.isEmpty ? "No appointments" : "Appointments"), appointments: store.records.appointments.sorted { $0.date < $1.date }))
        case .symptom(let text): sheet = .symptom(text); store.append(ChatMessage(text: L10n.string("Review the symptom details and emergency signs before saving.")))
        case .add(let medicine, let times, let frequency):
            sheet = times.isEmpty && frequency == nil ? .medicine(medicine) : .medicineDraft(medicine, times, frequency)
            store.append(ChatMessage(text: L10n.format("Confirm the exact product and instructions for %@.", L10n.medicineName(medicine))))
        case .remove(let medicine): removal = medicine
        case .medicines: store.append(ChatMessage(text: L10n.string(store.records.medicines.isEmpty ? "No medications recorded." : "Your medications"), medicines: store.records.medicines))
        case .interactions(let medicines): store.append(ChatMessage(text: L10n.string("Medication check"), report: HealthRules.check(medicines)))
        case .reading(let reading): sheet = .reading(reading); store.append(ChatMessage(text: L10n.format("Confirm %@: %@ %@.", L10n.string(reading.kind.rawValue), L10n.readingValue(reading), reading.kind.unit)))
        case .readings: store.append(ChatMessage(text: L10n.string(store.records.readings.isEmpty ? "No readings recorded." : "Recent readings"), readings: Array(store.records.readings.prefix(10))))
        case .importHealth: Task { await health.sync(into: store); store.append(ChatMessage(text: health.status)) }
        case .export: store.export()
        case .note: sheet = .note
        case .clear: deleteConfirmation = true
        case .reminder(let text): sheet = .reminder(CareReminder(title: text)); store.append(ChatMessage(text: L10n.string("Review the reminder and choose its date.")))
        case .reminders: store.append(ChatMessage(text: L10n.string(store.care.reminders.isEmpty ? "No reminders saved." : "Reminders"), reminders: store.care.reminders.sorted { $0.due < $1.due }))
        case .schedule(let medicine, let times, let frequency): sheet = .schedule(medicine, times, frequency); store.append(ChatMessage(text: L10n.string("Confirm the frequency, times, and refill date from your prescription.")))
        case .dose(let medicine, let status):
            guard let schedule = store.care.schedules.first(where: { $0.medicineID == medicine.id }), let date = CareRules.doses(on: .now, schedule: schedule).last(where: { $0 <= Date.now }) ?? CareRules.doses(on: .now, schedule: schedule).first else { store.append(ChatMessage(text: L10n.format("Save a schedule for %@ first.", L10n.medicineName(medicine)))); return }
            sheet = .dose(medicine, date, status); store.append(ChatMessage(text: L10n.format("Confirm the scheduled dose before saving %@.", L10n.string(status.rawValue))))
        case .timeline(let query):
            let results = LocalizedHealthContent.timelineEntries(records: store.records, care: store.care, visits: store.visits, query: query)
            store.append(ChatMessage(text: L10n.string(results.isEmpty ? "No matching records." : "Health history"), timeline: results.prefix(20).map(ChatTimelineEntry.init)))
        case .scan: sheet = .scanMedicine; store.append(ChatMessage(text: L10n.string("Choose a label photo, then confirm the product and instructions.")))
        case .question(let text): sheet = .question(text); store.append(ChatMessage(text: L10n.string("Review your question before saving it.")))
        }
    }
}

struct MessageView: View {
    @EnvironmentObject private var recorder: VisitRecorder
    let message: ChatMessage
    var speak: () -> Void
    private var rich: Bool { message.report != nil || message.readings?.isEmpty == false || message.medicines?.isEmpty == false }
    private var careResult: Bool { message.reminders?.isEmpty == false || message.timeline?.isEmpty == false || message.appointments?.isEmpty == false }
    var body: some View {
        if message.isUser {
            HStack { Spacer(minLength: 36); Text(message.text).padding(.horizontal, 18).padding(.vertical, 15).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24)).textSelection(.enabled) }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) { HarbourMark(size: 24).foregroundStyle(Palette.blue); Text("Harbour").font(.body.weight(.semibold)) }
                if careResult {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(message.text).font(.title3.weight(.semibold))
                        if let appointments = message.appointments {
                            ForEach(appointments) { appointment in AppointmentRow(appointment: appointment, showsDisclosure: false) }
                        }
                        if let reminders = message.reminders {
                            ForEach(reminders) { reminder in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: reminder.completed ? "checkmark.circle.fill" : "checklist").foregroundStyle(Palette.coral).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 6) { Text(reminder.title); Text(reminder.due, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.subheadline).foregroundStyle(Palette.muted) }
                                }
                            }
                        }
                        if let timeline = message.timeline {
                            ForEach(timeline) { entry in
                                VStack(alignment: .leading, spacing: 6) { Text(entry.title).font(.body.weight(.medium)); Text(entry.date, format: .dateTime.month(.abbreviated).day().year()).font(.subheadline).foregroundStyle(Palette.muted); if !entry.detail.isEmpty { Text(entry.detail).font(.subheadline).lineLimit(3).foregroundStyle(Palette.muted) } }
                                    .padding(.leading, 16).overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Palette.blue).frame(width: 3) }
                            }
                        }
                    }
                } else if rich {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(message.text).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            HarbourIllustration(kind: message.readings != nil ? .readings : .medicines).frame(width: 125, height: 100)
                        }.padding(.leading, 22).background(message.readings != nil ? Palette.coralWash : Palette.blueWash)
                        VStack(alignment: .leading, spacing: 18) {
                            if let reminders = message.reminders { ForEach(reminders) { reminder in VStack(alignment: .leading, spacing: 6) { Label(reminder.title, systemImage: reminder.completed ? "checkmark.circle" : "checklist"); Text(reminder.due, style: .date).foregroundStyle(Palette.muted) }.padding(.vertical, 8) } }
                            if let timeline = message.timeline { ForEach(timeline) { entry in VStack(alignment: .leading, spacing: 6) { Text(entry.title).font(.headline); Text(entry.date, style: .date).foregroundStyle(Palette.muted); Text(entry.detail).lineLimit(3).foregroundStyle(Palette.muted) }.padding(.vertical, 8) } }
                            if let report = message.report { InteractionView(report: report) }
                            if let readings = message.readings {
                                ForEach(readings) { reading in ReadingRow(reading: reading); if reading.id != readings.last?.id { Divider().overlay(Palette.line) } }
                            }
                            if let medicines = message.medicines {
                                ForEach(medicines) { medicine in
                                    HStack(alignment: .top, spacing: 14) {
                                        Image(systemName: "pills.fill").font(.title2).foregroundStyle(Palette.blue).frame(width: 28)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(L10n.medicineName(medicine)).font(.title3.weight(.medium))
                                            Text(medicine.ingredients.isEmpty ? L10n.string("Ingredients unconfirmed") : L10n.ingredientNames(medicine.ingredients)).font(.body).foregroundStyle(Palette.muted)
                                            if !medicine.instructions.isEmpty { Text(medicine.instructions).foregroundStyle(Palette.muted) }
                                        }
                                    }
                                    if medicine.id != medicines.last?.id { Divider().overlay(Palette.line) }
                                }
                            }
                        }.padding(AppLayout.surfaceInset)
                    }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 26)).clipShape(RoundedRectangle(cornerRadius: 26))
                } else { Text(message.text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("chatReply") }
                Button(action: speak) { Image(systemName: "speaker.wave.2").font(.body).foregroundStyle(Palette.muted).frame(width: 44, height: 44) }.accessibilityLabel("Read response aloud").disabled(recorder.active)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}


extension ChatMessage {
    var spokenText: String {
        var text = self.text
        if let medicines = self.medicines { text += ". " + medicines.map { $0.name + ($0.instructions.isEmpty ? "" : ", " + $0.instructions) }.joined(separator: ". ") }
        if let readings = self.readings { text += ". " + readings.map { L10n.string($0.kind.rawValue) + " " + L10n.readingValue($0) + " " + $0.kind.unit }.joined(separator: ". ") }
        if let report = self.report { text += ". " + report.alerts.map { L10n.string($0.summary) }.joined(separator: ". "); if !report.unassessed.isEmpty || !report.unresolved.isEmpty { text += ". " + L10n.string("Some interactions could not be assessed.") }; if !report.duplicates.isEmpty { text += ". " + L10n.format("Duplicate ingredients: %@", L10n.ingredientNames(report.duplicates)) } }
        if let reminders = self.reminders {
            text += ". " + reminders.map { $0.title + ", " + L10n.date($0.due, time: true) + ($0.completed ? ", " + L10n.string("completed") : "") }.joined(separator: ". ")
        }
        if let appointments = self.appointments {
            text += ". " + appointments.map { $0.title + ", " + L10n.date($0.date, time: $0.includesTime) + ($0.location.isEmpty ? "" : ", " + $0.location) }.joined(separator: ". ")
        }
        if let timeline = self.timeline {
            text += ". " + timeline.map { $0.title + ", " + L10n.date($0.date, time: true) + ($0.detail.isEmpty ? "" : ", " + $0.detail) }.joined(separator: ". ")
        }
        return text
    }
}
