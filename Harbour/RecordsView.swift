import SwiftUI
import HarbourCore

struct RecordsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.floatingDockClearance) private var dockClearance
    @Binding var sheet: AppSheet?
    @Binding var category: Int?
    var body: some View {
        List {
            categoryRow("Symptoms", count: store.records.symptoms.count, symbol: "cross.case.fill", colour: Palette.coral, index: 0)
            categoryRow("Medications", count: store.records.medicines.count, symbol: "pills.fill", colour: Palette.blue, index: 1)
            categoryRow("Readings", count: store.records.readings.count, symbol: "waveform.path.ecg", colour: Palette.coral, index: 2)
            categoryRow("Appointments", count: store.records.appointments.count, symbol: "calendar", colour: Palette.blue, index: 3)
        }
        .contentMargins(.bottom, dockClearance, for: .scrollContent)
        .listStyle(.plain).scrollContentBackground(.hidden).background(Palette.canvas)
        .navigationTitle("Records")
        .toolbar { if category == nil { ToolbarItem(placement: .topBarTrailing) { SettingsButton(sheet: $sheet) } } }
        .navigationDestination(item: $category) { selected in
            RecordList(sheet: $sheet, category: selected)
        }
    }
    private func categoryRow(_ title: String, count: Int, symbol: String, colour: Color, index: Int) -> some View {
        Button { category = index } label: {
            HStack(spacing: 18) {
                Image(systemName: symbol).font(.system(size: 27, weight: .medium)).foregroundStyle(colour).frame(width: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string(title)).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text(L10n.format(count == 1 ? "%d record" : "%d records", count)).font(.body).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right").font(.body.weight(.medium)).foregroundStyle(Palette.muted)
            }.padding(.vertical, 22).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("record-category-\(index)")
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
            .listRowBackground(Color.clear)
    }
}

private struct RecordList: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.floatingDockClearance) private var dockClearance
    @Binding var sheet: AppSheet?
    let category: Int
    private var title: String { L10n.string(["Symptoms", "Medications", "Readings", "Appointments"][category]) }
    var body: some View {
        List {
            if category == 0 {
                Section {
                    if store.records.symptoms.isEmpty { RecordEmptyState(kind: .symptoms, title: "No symptoms") }
                    ForEach(store.records.symptoms) { symptom in
                        NavigationLink { SymptomDetail(symptom: symptom) } label: { SymptomRow(symptom: symptom) }
                    }.onDelete { indexes in let ids = indexes.map { store.records.symptoms[$0].id }; for id in ids { store.removeSymptom(id) } }
                }
            } else if category == 1 {
                Section {
                    if store.records.medicines.isEmpty { RecordEmptyState(kind: .medicines, title: "No medications") }
                    ForEach(store.records.medicines) { medicine in
                        Button { sheet = .medicine(medicine) } label: {
                            HStack(spacing: 14) {
                                FeatureIcon(symbol: "pills.fill", colour: Palette.blue)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(L10n.medicineName(medicine)).foregroundStyle(Palette.ink).fontWeight(.medium)
                                    Text(medicine.ingredients.isEmpty ? L10n.string("Ingredients unconfirmed") : L10n.ingredientNames(medicine.ingredients)).font(.body).foregroundStyle(Palette.muted)
                                    if !medicine.instructions.isEmpty { Text(medicine.instructions).font(.body).foregroundStyle(Palette.muted) }
                                    if let schedule = store.care.schedules.first(where: { $0.medicineID == medicine.id }),
                                       let frequency = schedule.frequency ?? (schedule.times.isEmpty ? nil : MedicationFrequency(count: schedule.times.count, period: .day)) {
                                        Text(L10n.frequency(frequency)).font(.body).foregroundStyle(Palette.muted)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                            }.padding(.vertical, 12)
                        }
                    }.onDelete { indexes in let ids = indexes.map { store.records.medicines[$0].id }; for id in ids { store.removeMedicine(id) } }
                }
                if !store.records.medicines.isEmpty { Section { Button { sheet = .interactions(store.records.medicines) } label: { Label("Check interactions", systemImage: "arrow.triangle.branch") } } }
            } else if category == 3 {
                Section {
                    if store.records.appointments.isEmpty { Text("No appointments").foregroundStyle(Palette.muted).padding(.vertical, 24) }
                    ForEach(store.records.appointments.sorted { $0.date < $1.date }) { appointment in
                        Button { sheet = .appointment(appointment) } label: { AppointmentRow(appointment: appointment) }.buttonStyle(.plain)
                    }.onDelete { indexes in
                        let sorted = store.records.appointments.sorted { $0.date < $1.date }
                        for index in indexes { store.removeAppointment(sorted[index].id) }
                    }
                }
            } else {
                Section {
                    if store.records.readings.isEmpty { RecordEmptyState(kind: .readings, title: "No readings") }
                    ForEach(store.records.readings) { reading in ReadingRow(reading: reading) }
                        .onDelete { indexes in let ids = indexes.map { store.records.readings[$0].id }; for id in ids { store.removeReading(id) } }
                }
            }
        }
        .contentMargins(.bottom, dockClearance, for: .scrollContent)
        .listStyle(.plain).listSectionSpacing(24).scrollContentBackground(.hidden).background(Palette.canvas).navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { switch category { case 0: sheet = .symptom(""); case 1: sheet = .medicine(nil); case 3: sheet = .appointment(Appointment()); default: sheet = .reading(nil) } } label: { ToolbarGlyph(symbol: "plus") }.accessibilityLabel("Add record") }
        }
    }
}

struct SymptomEditor: View {
    let initial: String
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var onset = ""
    @State private var severity = "Not specified"
    @State private var signs = Set<EmergencySign>()
    @State private var none = false
    @State private var reviewed = false
    @FocusState private var editing: Bool
    private var symptom: Symptom { Symptom(text: text.trimmingCharacters(in: .whitespacesAndNewlines), onset: onset, severity: severity, signs: EmergencySign.allCases.filter { signs.contains($0) }) }
    var body: some View {
        Form {
            Section("What’s happening?") {
                TextField("Describe the symptom", text: $text, prompt: Text("Describe the symptom").foregroundStyle(Palette.muted), axis: .vertical).lineLimit(3...7).focused($editing).accessibilityIdentifier("symptomText")
                TextField("When did it start?", text: $onset, prompt: Text("When did it start?").foregroundStyle(Palette.muted)).focused($editing).accessibilityIdentifier("symptomOnset")
                Picker("Severity", selection: $severity) { ForEach(["Not specified", "Mild", "Moderate", "Severe"], id: \.self) { Text(L10n.string($0)).tag($0) } }
            }
            Section("Emergency signs") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(EmergencySign.allCases) { sign in
                        choice(sign.rawValue, selected: signs.contains(sign)) { none = false; if signs.contains(sign) { signs.remove(sign) } else { signs.insert(sign) }; reviewed = false }
                    }
                    choice("None of these apply", selected: none) { signs.removeAll(); none.toggle(); reviewed = false }
                }.padding(.vertical, 8).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            if reviewed { Section("Next step") { GuidanceView(symptom: symptom) } }
        }
        .scrollContentBackground(.hidden).background(Palette.canvas)
        .navigationTitle("Symptom").navigationBarTitleDisplayMode(.inline)
        .onAppear { text = initial }
        .onChange(of: text) { reviewed = false }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editing = false } }
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.string(reviewed ? "Save" : "Review")) {
                    editing = false
                    if reviewed { store.add(symptom); store.append(ChatMessage(text: L10n.string("Symptom saved.") + " " + L10n.string(HealthRules.guidance(symptom)))); dismiss() }
                    else { withAnimation { reviewed = true } }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (signs.isEmpty && !none)).accessibilityIdentifier("saveSymptom")
            }
        }
    }
    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) { Text(L10n.string(title)).font(.body).multilineTextAlignment(.leading); Spacer(); SelectionIndicator(selected: selected, colour: Palette.coral) }
                .foregroundStyle(Palette.ink).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Palette.coralWash : Palette.surface, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(title == "None of these apply" ? "noEmergencySigns" : title)
    }
}
struct GuidanceView: View {
    let symptom: Symptom
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.string(HealthRules.isEmergency(symptom) ? "Emergency care" : "Health811"), systemImage: HealthRules.isEmergency(symptom) ? "exclamationmark.circle.fill" : "phone").font(.headline).foregroundStyle(HealthRules.isEmergency(symptom) ? Color.red : Color.primary)
            Text(L10n.string(HealthRules.guidance(symptom))).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 24) {
                Link(L10n.string(HealthRules.isEmergency(symptom) ? "Call 911" : "Call 811"), destination: URL(string: HealthRules.isEmergency(symptom) ? "tel:911" : "tel:811")!)
                Link("Ontario source", destination: URL(string: HealthRules.isEmergency(symptom) ? HealthRules.emergencySource : HealthRules.helpSource)!).foregroundStyle(Palette.muted)
            }.font(.subheadline.weight(.medium))
        }.padding(.vertical, 8)
    }
}
struct SymptomDetail: View {
    let symptom: Symptom
    @Environment(\.floatingDockClearance) private var dockClearance
    var body: some View {
        List {
            Section { SymptomRow(symptom: symptom); LabeledContent("Started", value: symptom.onset.isEmpty ? L10n.string("Not recorded") : symptom.onset); LabeledContent("Severity", value: L10n.string(symptom.severity)) }
            if !symptom.signs.isEmpty { Section("Signs recorded") { ForEach(symptom.signs) { Text(L10n.string($0.rawValue)) } } }
            Section("Next step") { GuidanceView(symptom: symptom) }
        }.contentMargins(.bottom, dockClearance, for: .scrollContent)
            .scrollContentBackground(.hidden).background(Palette.canvas).navigationTitle("Symptom").navigationBarTitleDisplayMode(.inline)
    }
}

struct MedicineEditor: View {
    let initial: Medicine?
    var suggestedTimes: [DoseTime] = []
    var suggestedFrequency: MedicationFrequency? = nil
    @StateObject private var scanner = MedicineScanner()
    @EnvironmentObject private var alerts: CareNotifications
    @State private var times: [DoseTime] = []
    @State private var frequencyEnabled = false
    @State private var frequencyCount = 1
    @State private var frequencyPeriod: MedicationFrequencyPeriod = .day
    @State private var notify = false
    @State private var refillEnabled = false
    @State private var refill = Date.now.addingTimeInterval(86400 * 30)
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var chosen: Medicine?
    @State private var instructions = ""
    @State private var confirmed = false
    @FocusState private var editing: Bool
    private var savedFrequency: MedicationFrequency? {
        if frequencyEnabled { return MedicationFrequency(count: frequencyCount, period: frequencyPeriod) }
        return times.isEmpty ? nil : MedicationFrequency(count: times.count, period: .day)
    }
    private var frequencyMatchesTimes: Bool {
        !frequencyEnabled || (MedicationFrequency(count: frequencyCount, period: frequencyPeriod).valid && (times.isEmpty || (frequencyPeriod == .day && frequencyCount == times.count)))
    }
    var body: some View {
        Form {
            Section("Medication label") {
                MedicineScanButtons(scanner: scanner)
                if scanner.busy { ProgressView("Reading label…") }
                if let error = scanner.error { Text(error).foregroundStyle(.red) }
                if !scanner.text.isEmpty {
                    ForEach(CareRules.labelCandidates(scanner.text)) { candidate in Button(L10n.format("Use %@", L10n.medicineName(candidate))) { chosen = candidate; confirmed = false } }
                    DisclosureGroup("Label text") { Text(scanner.text).textSelection(.enabled) }
                }
            }
            if let chosen {
                Section {
                    Text(L10n.medicineName(chosen)).font(.title3.weight(.semibold))
                    LabeledContent("Active ingredients", value: chosen.ingredients.isEmpty ? L10n.string("Unconfirmed") : L10n.ingredientNames(chosen.ingredients))
                    if initial == nil { Button("Choose another medicine") { self.chosen = nil; confirmed = false } }
                }
                Section {
                    Button { confirmed.toggle() } label: {
                        HStack(spacing: 14) {
                            Text("I checked the exact product and ingredients").foregroundStyle(Palette.ink)
                            Spacer(minLength: 8)
                            SelectionIndicator(selected: confirmed)
                        }.padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("confirmMedicine").accessibilityValue(L10n.string(confirmed ? "Confirmed" : "Not confirmed")).accessibilityAddTraits(confirmed ? .isSelected : [])
                } footer: { Text(L10n.string(chosen.ingredients.isEmpty ? "This medicine will be saved with unconfirmed ingredients. Its interactions cannot be assessed." : "Brand formulations can differ. Check the active ingredients on your package.")) }
                Section("Instructions from your label") { TextField("Dose or notes (optional)", text: $instructions, prompt: Text("Dose or notes (optional)").foregroundStyle(Palette.muted), axis: .vertical).lineLimit(2...4).focused($editing) }
                ScheduleFields(times: $times, frequencyEnabled: $frequencyEnabled, frequencyCount: $frequencyCount, frequencyPeriod: $frequencyPeriod, notify: $notify, refillEnabled: $refillEnabled, refill: $refill)
            } else {
                Section {
                    TextField("Medication name", text: $query, prompt: Text("Medication name").foregroundStyle(Palette.muted)).autocorrectionDisabled().focused($editing).accessibilityIdentifier("medicineSearch")
                }
                Section("Medications") {
                    ForEach(Catalog.search(query)) { medicine in
                        Button { chosen = medicine } label: { VStack(alignment: .leading, spacing: 4) { Text(L10n.medicineName(medicine)).foregroundStyle(Palette.ink); Text(L10n.ingredientNames(medicine.ingredients)).font(.body).foregroundStyle(Palette.muted) } }.accessibilityIdentifier("catalog-" + medicine.id)
                    }
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Catalog.resolve(query) == nil {
                        Button(L10n.format("Add %@ with unconfirmed ingredients", query)) { chosen = Medicine(name: query.trimmingCharacters(in: .whitespacesAndNewlines)) }.accessibilityIdentifier("addUnlistedMedicine")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(Palette.canvas)
        .drawerHeight(chosen == nil ? 600 : 690)
        .navigationTitle(L10n.string(initial == nil ? "Add medicine" : "Medication")).navigationBarTitleDisplayMode(.inline)
        .onAppear {
            chosen = initial; instructions = initial?.instructions ?? ""; times = suggestedTimes
            if let suggestedFrequency { frequencyEnabled = true; frequencyCount = suggestedFrequency.count; frequencyPeriod = suggestedFrequency.period }
            if let schedule = store.care.schedules.first(where: { $0.medicineID == initial?.id }) {
                if suggestedTimes.isEmpty { times = schedule.times }
                if suggestedFrequency == nil, let frequency = schedule.frequency { frequencyEnabled = true; frequencyCount = frequency.count; frequencyPeriod = frequency.period }
                notify = schedule.notify; refillEnabled = schedule.refill != nil; refill = schedule.refill ?? refill
            }
        }
        .onChange(of: frequencyPeriod) { frequencyCount = min(frequencyCount, frequencyPeriod == .day ? 24 : 31) }
        .onChange(of: scanner.text) { confirmed = false; let candidates = CareRules.labelCandidates(scanner.text); chosen = candidates.count == 1 ? candidates[0] : nil; instructions = CareRules.labelInstructions(scanner.text) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editing = false } }
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { if var chosen { chosen.instructions = instructions; Task { if notify { await alerts.requestAccess() }; if store.saveMedicine(chosen, schedule: MedicineSchedule(medicineID: chosen.id, times: times, frequency: savedFrequency, notify: notify, refill: refillEnabled ? refill : nil)) { dismiss() } } } }.disabled(chosen == nil || !confirmed || !frequencyMatchesTimes).accessibilityIdentifier("saveMedicine") }
        }
    }
}

struct ReadingEditor: View {
    let initial: Reading?
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ReadingKind = .heartRate
    @State private var value = ""
    @State private var date = Date.now
    @FocusState private var editing: Bool
    init(initial: Reading?) {
        self.initial = initial
        _kind = State(initialValue: initial?.kind ?? .heartRate)
        _value = State(initialValue: initial.map { L10n.readingValue($0) } ?? "")
        _date = State(initialValue: initial?.date ?? .now)
    }
    private var example: String { kind == .bloodPressure ? "120/80" : kind == .temperature ? (L10n.isFrench ? "36,8" : "36.8") : "72" }
    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $kind) { ForEach(ReadingKind.allCases, id: \.self) { Text(L10n.string($0.rawValue)).tag($0) } }.accessibilityIdentifier("readingKind")
                HStack { TextField(example, text: $value, prompt: Text(example).foregroundStyle(Palette.muted)).focused($editing).keyboardType(kind == .bloodPressure ? .numbersAndPunctuation : .decimalPad).accessibilityIdentifier("readingValue"); Text(L10n.string(kind.unit)).foregroundStyle(Palette.muted) }
                DatePicker("Date", selection: $date, in: ...Date.now)
            }
            if !value.isEmpty && !ReadingParser.valid(value, kind: kind) { Section { Text(L10n.string(kind == .bloodPressure ? "Enter systolic/diastolic, such as 120/80." : "Check the number and unit.")).foregroundStyle(Palette.muted) } }
        }
        .scrollContentBackground(.hidden).background(Palette.canvas)
        .drawerHeight(!value.isEmpty && !ReadingParser.valid(value, kind: kind) ? 390 : 320)
        .navigationTitle("Add reading").navigationBarTitleDisplayMode(.inline)
        .onChange(of: kind) { value = "" }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editing = false } }
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { store.add(Reading(kind: kind, value: ReadingParser.normalizedValue(value), date: date)); dismiss() }.disabled(!ReadingParser.valid(value, kind: kind)).accessibilityIdentifier("saveReading") }
        }
    }
}

struct InteractionView: View {
    let report: InteractionReport
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(report.alerts.indices, id: \.self) { index in
                let alert = report.alerts[index]
                VStack(alignment: .leading, spacing: 10) {
                    Label(alert.pair.map { L10n.string($0).capitalized }.joined(separator: " + "), systemImage: "exclamationmark.circle.fill").font(.headline).foregroundStyle(Palette.coral)
                    Text(L10n.string(alert.summary)).fixedSize(horizontal: false, vertical: true)
                    Link("NHS source", destination: URL(string: alert.source)!).font(.body).foregroundStyle(Palette.muted).accessibilityIdentifier("interactionSource")
                }
            }
            if !report.duplicates.isEmpty { Label(L10n.format("Repeated ingredients: %@", L10n.ingredientNames(report.duplicates)), systemImage: "pills.fill").foregroundStyle(Palette.coral) }
            if !report.unresolved.isEmpty { VStack(alignment: .leading, spacing: 6) { Text("Unconfirmed ingredients").font(.headline); Text(report.unresolved.joined(separator: ", ")).foregroundStyle(Palette.muted) } }
            if !report.unassessed.isEmpty { VStack(alignment: .leading, spacing: 10) { Text("Not assessed").font(.headline); ForEach(report.unassessed.indices, id: \.self) { Text(report.unassessed[$0].map { L10n.string($0) }.joined(separator: " + ")).foregroundStyle(Palette.muted) } } }
            if report.alerts.isEmpty && report.unassessed.isEmpty && report.duplicates.isEmpty && report.unresolved.isEmpty { Text("Add at least two medications to compare.").foregroundStyle(Palette.muted) }
            Text("Coverage: four source-listed ingredient pairs. An absent alert does not establish safety. Ask a pharmacist before changing medications.").font(.footnote).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NoteView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    private var text: String { LocalizedHealthContent.appointmentNote(records: store.records) }
    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                Text(text).font(.body).lineSpacing(5).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }.accessibilityIdentifier("appointmentNoteContent")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { noteActions }
                VStack(spacing: 12) { noteActions }
            }
        }.padding(.horizontal, AppLayout.screenInset).padding(.bottom, 12)
            .background(Palette.canvas).foregroundStyle(Palette.ink).navigationTitle("Appointment note").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
    }
    @ViewBuilder private var noteActions: some View {
        Button { UIPasteboard.general.string = text; copied = true } label: { Label(L10n.string(copied ? "Copied" : "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc") }
            .buttonStyle(ActionButtonStyle()).accessibilityLabel("Copy note").accessibilityValue(L10n.string(copied ? "Copied" : "Not copied"))
        ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }.buttonStyle(ActionButtonStyle(secondary: true))
    }
}

struct RecordEmptyState: View {
    var kind: IllustrationKind
    var title: String
    var body: some View {
        VStack(spacing: 20) {
            HarbourIllustration(kind: kind).frame(width: 260, height: 200)
            Text(L10n.string(title)).font(.title2.weight(.medium))

        }.frame(maxWidth: .infinity).padding(.vertical, 30).listRowBackground(Color.clear).listRowSeparator(.hidden)
    }
}
