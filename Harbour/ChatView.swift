import SwiftUI
import HarbourCore

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var models: ModelManager
    @EnvironmentObject var health: HealthService
    @Binding var sheet: AppSheet?
    @StateObject private var voice = VoiceService()
    @State private var draft = ""
    @State private var hint: String?
    @State private var task: Task<Void, Never>?
    @State private var operationID = UUID()
    @State private var busy = false
    @State private var modelSheet = false
    @State private var toolSheet = false
    @State private var deleteConfirmation = false
    @State private var removal: Medicine?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if store.messages.isEmpty {
                        VStack(spacing: 16) {
                            HarbourIllustration(kind: .conversation, animated: true).frame(width: 240, height: 200)
                            Text("What’s on your mind?").font(.largeTitle.weight(.medium)).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.top, 26).padding(.bottom, 16)
                        VStack(alignment: .leading, spacing: 4) {
                            starter("Check medicines", symbol: "pills", colour: Palette.blue, hint: "Interactions")
                            starter("Record a symptom", symbol: "cross.case", colour: Palette.coral, hint: "Symptoms")
                            starter("Add a reading", symbol: "waveform.path.ecg", colour: Palette.coral, hint: "Readings")
                        }.padding(.horizontal, 20).frame(maxWidth: 400).frame(maxWidth: .infinity)
                    }
                    ForEach(store.messages) { message in MessageView(message: message, speak: { voice.speak(message.text) }).id(message.id).transition(.opacity.combined(with: .move(edge: .bottom))) }
                    if busy {
                        HStack(spacing: 12) { HarbourMark(size: 32, spinning: true).foregroundStyle(Palette.blue); Text(models.downloading == nil ? "Thinking…" : models.status).font(.subheadline).foregroundStyle(Palette.muted) }.id("pending")
                        if models.downloading != nil { VStack(alignment: .leading, spacing: 8) { ProgressView(value: models.progress); Text(models.status == "Verifying download" ? models.status : "\(Int(models.progress * 100))% downloaded").font(.caption).foregroundStyle(Palette.muted) } }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: store.messages.count).padding(.horizontal, 24).padding(.bottom, 16).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.count) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: busy) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
            composer
        }
        .background(Palette.canvas).foregroundStyle(Palette.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false } }
            ToolbarItem(placement: .principal) { Text("Harbour").font(.body.weight(.medium)) }
            ToolbarItem(placement: .topBarTrailing) { Button { cancel(); focused = false; draft = ""; hint = nil; store.newChat() } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("New chat") }
        }
        .sheet(isPresented: $modelSheet) { NavigationStack { ModelsView() } }
        .sheet(isPresented: $toolSheet) { topicPicker.presentationDetents([.height(420)]).presentationDragIndicator(.visible) }
        .confirmationDialog("Delete all records and chat?", isPresented: $deleteConfirmation, titleVisibility: .visible) { Button("Delete all", role: .destructive) { store.clear() }; Button("Cancel", role: .cancel) {} }
        .confirmationDialog("Remove \(removal?.name ?? "medicine") from your list?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) { Button("Remove", role: .destructive) { if let removal { store.removeMedicine(removal.id); store.append(ChatMessage(text: "Removed \(removal.name) from your list.")) }; removal = nil } }
        .alert("Voice input", isPresented: Binding(get: { voice.error != nil }, set: { if !$0 { voice.error = nil } })) { Button("OK") { voice.error = nil } } message: { Text(voice.error ?? "") }
        .onDisappear { voice.stop() }
    }
    private func starter(_ title: String, symbol: String, colour: Color, hint: String) -> some View {
        Button { self.hint = hint; focused = true } label: {
            HStack(spacing: 14) { Image(systemName: symbol).font(.title2).foregroundStyle(colour).frame(width: 32); Text(title).font(.title3.weight(.medium)).foregroundStyle(Palette.ink); Spacer(); Image(systemName: "arrow.up.left").font(.body).foregroundStyle(Palette.muted) }
                .padding(.vertical, 14).contentShape(Rectangle())
        }.buttonStyle(PressFeedback())
    }
    private var composer: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Ask, record, or check something…", text: $draft, prompt: Text("Ask, record, or check something…").foregroundStyle(Palette.muted), axis: .vertical)
                    .lineLimit(1...6).font(.title3).focused($focused).accessibilityIdentifier("chatInput")
                    .padding(.horizontal, 6).padding(.top, 6)
                if let hint {
                    Button { self.hint = nil } label: { HStack(spacing: 5) { Text(hint).font(.subheadline); Image(systemName: "xmark").font(.caption2) }.padding(.horizontal, 10).padding(.vertical, 7).background(Palette.blueWash, in: Capsule()).foregroundStyle(Palette.ink) }.accessibilityLabel("Clear \(hint) topic")
                }
                HStack(spacing: 4) {
                    Button { focused = false; toolSheet = true } label: { Image(systemName: "plus").font(.title3).frame(width: 42, height: 44) }.accessibilityLabel("Choose a topic")
                    Spacer(minLength: 0)
                    Button { focused = false; modelSheet = true } label: {
                        HStack(spacing: 5) { Text(models.resolved == .balanced ? "Qwen 1.5B" : "Qwen 0.5B").font(.body.weight(.medium)); Text(models.effort.rawValue).font(.body).foregroundStyle(Palette.muted); Image(systemName: "chevron.down").font(.caption2) }
                            .padding(.horizontal, 10).frame(minHeight: 48).contentShape(RoundedRectangle(cornerRadius: 10))
                    }.accessibilityLabel("Choose model").accessibilityIdentifier("modelSelector")
                    Button {
                        if voice.listening { voice.stop() } else {
                            let original = draft
                            Task { await voice.start { transcript in draft = original.isEmpty ? transcript : original + " " + transcript } }
                        }
                    } label: { Image(systemName: voice.listening ? "mic.fill" : "mic").foregroundStyle(voice.listening ? Color.red : Color.primary).frame(width: 44, height: 48) }.accessibilityLabel(voice.listening ? "Stop recording" : "Record voice").disabled(busy)
                    Button { busy ? cancel() : send() } label: {
                        Image(systemName: busy ? "stop.fill" : "arrow.up").font(.body.weight(.semibold))
                            .foregroundStyle(Palette.canvas).frame(width: 44, height: 44).background(Palette.ink, in: Circle())
                    }.accessibilityLabel(busy ? "Stop" : "Send message").disabled(!busy && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Palette.line.opacity(0.7)))
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
            .frame(maxWidth: 760)
        }.frame(maxWidth: .infinity).background(Palette.canvas).foregroundStyle(Palette.ink)
    }
    private var topicPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Topic").font(.title2.weight(.semibold)).padding(.bottom, 12)
            ForEach([("Symptoms", "cross.case", Color.orange), ("Medicines", "pills", .indigo), ("Interactions", "arrow.triangle.branch", .blue), ("Readings", "waveform.path.ecg", .red)], id: \.0) { item in
                Button { hint = item.0; toolSheet = false; focused = true } label: { FeatureRow(title: item.0, subtitle: nil, symbol: item.1, colour: item.2) }.buttonStyle(.plain).padding(.vertical, 4)
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Palette.canvas)
    }
    private func cancel() { operationID = UUID(); task?.cancel(); task = nil; busy = false; voice.stop() }
    private func send() {
        let input = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        voice.stop(); focused = false; draft = ""
        store.append(ChatMessage(isUser: true, text: input))
        // Emergency wording is checked before any download or model inference.
        if HealthRules.emergencyCue(input) {
            store.append(ChatMessage(text: HealthRules.guidance(Symptom(text: input))))
            sheet = .symptom(input); return
        }
        busy = true
        let currentID = UUID(); operationID = currentID
        let chosenHint = hint
        task = Task {
            defer { if operationID == currentID { busy = false; task = nil } }
            do {
                let output = try await models.generate(ToolPlanner.prompt(input, hint: chosenHint))
                try Task.checkCancellation()
                let decision = try ToolPlanner.parse(output)
                let action = try ToolPlanner.validate(decision, original: input, records: store.records)
                execute(action)
            } catch is CancellationError { }
            catch { if !Task.isCancelled { store.append(ChatMessage(text: error.localizedDescription)) } }
        }
    }
    private func execute(_ action: ValidatedAction) {
        switch action {
        case .reply(let text): store.append(ChatMessage(text: text))
        case .symptom(let text): sheet = .symptom(text); store.append(ChatMessage(text: "Review the symptom details and emergency signs before saving."))
        case .add(let medicine): sheet = .medicine(medicine); store.append(ChatMessage(text: "Confirm the exact product and instructions for \(medicine.name)."))
        case .remove(let medicine): removal = medicine
        case .medicines: store.append(ChatMessage(text: store.records.medicines.isEmpty ? "No medicines recorded." : "Your medicines", medicines: store.records.medicines))
        case .interactions(let medicines): store.append(ChatMessage(text: "Medicine check", report: HealthRules.check(medicines)))
        case .reading(let reading): sheet = .reading(reading); store.append(ChatMessage(text: "Confirm \(reading.kind.rawValue.lowercased()): \(reading.value) \(reading.kind.unit)."))
        case .readings: store.append(ChatMessage(text: store.records.readings.isEmpty ? "No readings recorded." : "Recent readings", readings: Array(store.records.readings.prefix(10))))
        case .importHealth: Task { await health.sync(into: store); store.append(ChatMessage(text: health.status)) }
        case .export: store.export()
        case .note: sheet = .note
        case .clear: deleteConfirmation = true
        }
    }
}

struct MessageView: View {
    let message: ChatMessage
    var speak: () -> Void
    private var rich: Bool { message.report != nil || message.readings != nil || message.medicines != nil }
    var body: some View {
        if message.isUser {
            HStack { Spacer(minLength: 36); Text(message.text).padding(.horizontal, 18).padding(.vertical, 15).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24)).textSelection(.enabled) }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) { HarbourMark(size: 24).foregroundStyle(Palette.blue); Text("Harbour").font(.body.weight(.semibold)) }
                if rich {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(message.text).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            HarbourIllustration(kind: message.readings != nil ? .readings : .medicines).frame(width: 125, height: 100)
                        }.padding(.leading, 22).background(message.readings != nil ? Palette.coralWash : Palette.blueWash)
                        VStack(alignment: .leading, spacing: 18) {
                            if let report = message.report { InteractionView(report: report) }
                            if let readings = message.readings {
                                ForEach(readings) { reading in ReadingRow(reading: reading); if reading.id != readings.last?.id { Divider().overlay(Palette.line) } }
                            }
                            if let medicines = message.medicines {
                                ForEach(medicines) { medicine in
                                    HStack(alignment: .top, spacing: 14) {
                                        Image(systemName: "pills.fill").font(.title2).foregroundStyle(Palette.blue).frame(width: 28)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(medicine.name).font(.title3.weight(.medium))
                                            Text(medicine.ingredients.isEmpty ? "Ingredients unconfirmed" : medicine.ingredients.joined(separator: ", ")).font(.body).foregroundStyle(Palette.muted)
                                            if !medicine.instructions.isEmpty { Text(medicine.instructions).foregroundStyle(Palette.muted) }
                                        }
                                    }
                                    if medicine.id != medicines.last?.id { Divider().overlay(Palette.line) }
                                }
                            }
                        }.padding(22)
                    }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 26)).clipShape(RoundedRectangle(cornerRadius: 26))
                } else { Text(message.text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                Button(action: speak) { Image(systemName: "speaker.wave.2").font(.body).foregroundStyle(Palette.muted).frame(width: 44, height: 44) }.accessibilityLabel("Read response aloud")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
