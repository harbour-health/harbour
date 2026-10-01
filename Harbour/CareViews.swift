import SwiftUI
import HarbourCore

struct AgendaView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var sheet: AppSheet?
    private var reminders: [CareReminder] { store.care.reminders.sorted { $0.due < $1.due } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Coming up").font(.title2.weight(.semibold)); Spacer()
                Button { sheet = .reminder(CareReminder()) } label: { ToolbarGlyph(symbol: "plus") }.accessibilityLabel("Add reminder")
            }
            if reminders.isEmpty && store.care.schedules.isEmpty { Text("Nothing scheduled").font(.body).foregroundStyle(Palette.muted) }
            ForEach(reminders.filter { !$0.completed }) { reminder in
                Button { sheet = .reminder(reminder) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "checklist").font(.title2).foregroundStyle(Palette.coral)
                        VStack(alignment: .leading, spacing: 5) { Text(reminder.title).font(.title3.weight(.medium)); Text(reminder.due, format: .dateTime.month(.abbreviated).day().hour().minute()).foregroundStyle(Palette.muted).font(.subheadline) }
                        Spacer(); Image(systemName: "chevron.right").font(.caption)
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("reminder-" + reminder.id.uuidString)
            }
            ForEach(store.care.schedules) { schedule in
                if let medicine = store.records.medicines.first(where: { $0.id == schedule.medicineID }) {
                    ForEach(CareRules.doses(on: .now, schedule: schedule), id: \.self) { date in
                        let log = store.care.doses.first { $0.id == DoseLog.key(medicine.id, date) }
                        Button { sheet = .dose(medicine, date, nil) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: log?.status == .taken ? "checkmark.circle.fill" : "pills.fill").font(.title2).foregroundStyle(Palette.blue)
                                VStack(alignment: .leading, spacing: 5) { Text(medicine.name).font(.title3.weight(.medium)); Text(date, style: .time).font(.subheadline).foregroundStyle(Palette.muted) }
                                Spacer(); Text(log?.status.rawValue ?? "Scheduled").font(.subheadline).foregroundStyle(Palette.muted)
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("dose-" + medicine.id + "-" + String(Int(date.timeIntervalSince1970)))
                    }
                    if let refill = schedule.refill {
                        HStack(spacing: 14) { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Palette.blue); Text("Refill " + medicine.name); Spacer(); Text(refill, style: .date).foregroundStyle(Palette.muted) }.padding(.vertical, 8)
                    }
                }
            }
            if !reminders.filter(\.completed).isEmpty {
                DisclosureGroup("Completed") { ForEach(reminders.filter(\.completed)) { reminder in Button(reminder.title) { sheet = .reminder(reminder) }.padding(.vertical, 6) } }
            }
        }.foregroundStyle(Palette.ink)
    }
}
struct ReminderEditor: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var alerts: CareNotifications
    @Environment(\.dismiss) private var dismiss
    @State private var reminder: CareReminder
    @State private var dateChosen: Bool
    @FocusState private var editing: Bool
    init(initial: CareReminder, saved: Bool = false) { _reminder = State(initialValue: initial); _dateChosen = State(initialValue: saved) }
    var body: some View {
        Form {
            Section { TextField("Reminder", text: $reminder.title, prompt: Text("Reminder").foregroundStyle(Palette.muted), axis: .vertical).lineLimit(1...4).focused($editing).accessibilityIdentifier("reminderTitle") }
            Section("From a visit") {
                Menu {
                    Button("No visit") { reminder.visitID = nil; reminder.quote = nil }
                    ForEach(store.visits) { visit in
                        ForEach(visit.summary?.followUps ?? []) { follow in
                            Button(visit.title + ": " + follow.quote) { reminder.visitID = visit.id; reminder.quote = follow.quote; reminder.title = follow.quote; dateChosen = false }
                        }
                    }
                } label: { Label(reminder.quote == nil ? "Choose a follow-up" : "Change follow-up", systemImage: "waveform") }
                if let quote = reminder.quote { Text(quote).textSelection(.enabled); if let visit = store.visits.first(where: { $0.id == reminder.visitID }) { Text(visit.date, style: .date).foregroundStyle(Palette.muted) } }
            }
            Section {
                DatePicker("Due", selection: $reminder.due).onChange(of: reminder.due) { dateChosen = true }.accessibilityIdentifier("reminderDate")
                Button { dateChosen = true } label: { Label(dateChosen ? "Date confirmed" : "Confirm date", systemImage: dateChosen ? "checkmark.circle.fill" : "calendar") }.accessibilityIdentifier("confirmReminderDate")
                Toggle("Notify me", isOn: $reminder.notify)
                if reminder.notify { Text(alerts.status).font(.footnote).foregroundStyle(Palette.muted) }
                Toggle("Completed", isOn: $reminder.completed)
            }
            if store.care.reminders.contains(where: { $0.id == reminder.id }) { Section { Button("Delete reminder", role: .destructive) { store.removeReminder(reminder.id); dismiss() } } }
        }.scrollContentBackground(.hidden).background(Palette.canvas)
            .navigationTitle("Reminder").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editing = false } }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { if reminder.notify { await alerts.requestAccess() }; if store.saveReminder(reminder) { dismiss() } } }.disabled(reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !dateChosen).accessibilityIdentifier("saveReminder") }
            }
    }
}
struct DoseEditor: View {
    let medicine: Medicine
    let scheduled: Date
    let proposed: DoseStatus?
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var alerts: CareNotifications
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var status: DoseStatus = .taken
    @State private var minutes = 30
    private var future: Bool { scheduled > Date.now.addingTimeInterval(300) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(medicine.name).font(.title.weight(.semibold))
            Text(scheduled, format: .dateTime.month(.abbreviated).day().hour().minute()).foregroundStyle(Palette.muted)
            ForEach(DoseStatus.allCases, id: \.self) { choice in
                Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { status = choice } } label: { HStack { Text(choice.rawValue).font(.title3); Spacer(); SelectionIndicator(selected: status == choice) }.padding(14).background(status == choice ? Palette.blueWash : Palette.surface, in: RoundedRectangle(cornerRadius: 18)) }.buttonStyle(.plain).accessibilityIdentifier("doseStatus-" + choice.rawValue)
            }
            if status == .later { Picker("Delay", selection: $minutes) { ForEach([15, 30, 60, 120], id: \.self) { Text("\($0) minutes").tag($0) } }.pickerStyle(.menu) }
            if future { Text("This dose is scheduled for later today.").foregroundStyle(Palette.muted) }
        }.padding(24).measuredDrawerHeight().background(Palette.canvas).navigationTitle("Dose").navigationBarTitleDisplayMode(.inline)
            .onAppear { status = proposed ?? store.care.doses.first { $0.id == DoseLog.key(medicine.id, scheduled) }?.status ?? .taken }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task {
                    if status == .later { await alerts.requestAccess() }
                    let log = DoseLog(medicineID: medicine.id, scheduled: scheduled, status: status, snooze: status == .later ? Date.now.addingTimeInterval(Double(minutes) * 60) : nil)
                    if store.logDose(log) { dismiss() }
                } }.disabled(future).accessibilityIdentifier("saveDose") }
            }
    }
}
struct HealthHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    var initialQuery = ""
    private var entries: [TimelineEntry] { HealthTimeline.entries(records: store.records, care: store.care, visits: store.visits, query: query) }
    var body: some View {
        List {
            if entries.isEmpty { Text(query.isEmpty ? "No history yet" : "No matching records").foregroundStyle(Palette.muted) }
            ForEach(entries.prefix(300)) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: entry.symbol).foregroundStyle(Palette.blue).frame(width: 24)
                        Text(entry.title).font(.headline)
                    }
                    Text(entry.date, format: .dateTime.month(.abbreviated).day().year().hour().minute()).padding(.leading, 36).font(.subheadline).foregroundStyle(Palette.muted)
                    if !entry.detail.isEmpty { Text(entry.detail).font(.body).foregroundStyle(Palette.muted).lineLimit(3).padding(.leading, 36) }
                }.padding(.vertical, 14).listRowBackground(Color.clear)
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(Palette.canvas).navigationTitle("Timeline")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your health history").onAppear { query = initialQuery }
            .contentMargins(.bottom, 86, for: .scrollContent)
    }
}
struct PreparationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editing: Bool
    @State private var question = ""
    @State private var editingID: UUID?
    var initialQuestion = ""
    private var note: String { CareRules.appointmentNote(records: store.records, care: store.care) }
    var body: some View {
        List {
            Section("Questions") {
                HStack(alignment: .top) {
                    TextField("Question for your doctor", text: $question, prompt: Text("Question for your doctor").foregroundStyle(Palette.muted), axis: .vertical).focused($editing).lineLimit(2...5).accessibilityIdentifier("appointmentQuestion")
                    Button { let q = AppointmentQuestion(id: editingID ?? UUID(), text: question.trimmingCharacters(in: .whitespacesAndNewlines)); if store.saveQuestion(q) { question = ""; editingID = nil; editing = false } } label: { ToolbarGlyph(symbol: "checkmark") }.disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Save question")
                }
                ForEach(store.care.questions) { q in Button { question = q.text; editingID = q.id } label: { Text(q.text).foregroundStyle(Palette.ink).padding(.vertical, 8) } }.onDelete { offsets in
                    let ids = offsets.map { store.care.questions[$0].id }
                    for id in ids { store.removeQuestion(id) }
                }
            }
            Section("Appointment note") { Text(note).textSelection(.enabled).accessibilityIdentifier("appointmentNoteContent") }
            Section { ShareLink(item: note) { Label("Share note", systemImage: "square.and.arrow.up") }; Button { UIPasteboard.general.string = note } label: { Label("Copy note", systemImage: "doc.on.doc") } }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(Palette.canvas)
            .navigationTitle("Appointment preparation").navigationBarTitleDisplayMode(.inline).onAppear { question = initialQuestion }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
