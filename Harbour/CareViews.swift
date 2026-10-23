import SwiftUI
import Charts
import HarbourCore

enum LocalizedHealthContent {
    static func appointmentNote(records: Records, care: CareData? = nil) -> String {
        let concern = records.symptoms.sorted { $0.date > $1.date }.first
        let notRecorded = L10n.string("Not recorded")
        let readings = records.readings.sorted { $0.date > $1.date }.prefix(5).map {
            L10n.format("%@: %@ %@", L10n.string($0.kind.rawValue), L10n.readingValue($0), L10n.string($0.kind.unit))
        }.joined(separator: "; ")
        var lines = [
            L10n.format("Concern: %@", concern?.text ?? notRecorded),
            L10n.format("Started: %@", concern?.onset.isEmpty == false ? concern!.onset : notRecorded),
            L10n.format("Severity: %@", concern.map { L10n.string($0.severity) } ?? notRecorded),
            L10n.format("Medications entered: %@", records.medicines.isEmpty ? L10n.string("None entered") : records.medicines.map { L10n.medicineName($0) }.joined(separator: ", ")),
            L10n.format("Recent readings: %@", readings)
        ]
        if let care {
            lines.append("\n" + L10n.string("Questions"))
            lines.append(care.questions.isEmpty ? L10n.string("No questions saved.") : care.questions.map { "• " + $0.text }.joined(separator: "\n"))
        } else {
            lines.append(L10n.string("Questions: What should I watch for? Should a pharmacist review my medications?"))
        }
        return lines.joined(separator: "\n")
    }

    static func timelineEntries(records: Records, care: CareData, visits: [DoctorVisit], query: String = "") -> [TimelineEntry] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return HealthTimeline.entries(records: records, care: care, visits: visits).map { entry in
            var result = entry
            if let symptom = records.symptoms.first(where: { entry.id == "symptom-" + $0.id.uuidString }) {
                result.detail = L10n.string(symptom.severity) + " · " + symptom.onset
            } else if let reading = records.readings.first(where: { entry.id == "reading-" + $0.id }) {
                result.title = L10n.format("%@ %@ %@", L10n.string(reading.kind.rawValue), L10n.readingValue(reading), L10n.string(reading.kind.unit))
                result.detail = ["Manual", "Apple Health"].contains(reading.source) ? L10n.string(reading.source) : reading.source
            } else if let dose = care.doses.first(where: { entry.id == "dose-" + $0.id }) {
                let medicine = dose.medicineName.map { L10n.medicineName(Medicine(id: dose.medicineID, name: $0)) } ?? records.medicines.first { $0.id == dose.medicineID }.map { L10n.medicineName($0) } ?? L10n.string("Medication")
                result.title = L10n.format("%@ · %@", medicine, L10n.string(dose.status.rawValue))
                result.detail = L10n.format("Scheduled %@", dose.scheduled.formatted(.dateTime.locale(L10n.locale)))
            } else if care.medicineEvents.contains(where: { entry.id == "medicine-" + $0.id.uuidString }) {
                result.detail = L10n.string("Medication list updated")
            } else if let reminder = care.reminders.first(where: { entry.id == "reminder-" + $0.id.uuidString }) {
                result.detail = reminder.completed ? L10n.string("Completed") : L10n.format("Due %@", reminder.due.formatted(.dateTime.locale(L10n.locale)))
            }
            return result
        }.filter { search.isEmpty || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(search) }
    }
}

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
            if reminders.isEmpty && store.care.schedules.isEmpty && store.records.appointments.isEmpty { Text("Nothing scheduled").font(.body).foregroundStyle(Palette.muted) }
            ForEach(store.records.appointments.filter { $0.date >= Calendar.current.startOfDay(for: .now) }.sorted { $0.date < $1.date }.prefix(5)) { appointment in
                Button { sheet = .appointment(appointment) } label: { AppointmentRow(appointment: appointment) }.buttonStyle(.plain)
            }
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
                    if schedule.times.isEmpty, let frequency = schedule.frequency {
                        Button { sheet = .schedule(medicine, [], frequency) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "pills.fill").font(.title2).foregroundStyle(Palette.blue)
                                VStack(alignment: .leading, spacing: 5) { Text(L10n.medicineName(medicine)).font(.title3.weight(.medium)); Text(L10n.frequency(frequency)).font(.subheadline).foregroundStyle(Palette.muted) }
                                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("frequency-" + medicine.id)
                    }
                    ForEach(CareRules.doses(on: .now, schedule: schedule), id: \.self) { date in
                        let log = store.care.doses.first { $0.id == DoseLog.key(medicine.id, date) }
                        Button { sheet = .dose(medicine, date, nil) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: log?.status == .taken ? "checkmark.circle.fill" : "pills.fill").font(.title2).foregroundStyle(Palette.blue)
                                VStack(alignment: .leading, spacing: 5) { Text(L10n.medicineName(medicine)).font(.title3.weight(.medium)); Text(date, style: .time).font(.subheadline).foregroundStyle(Palette.muted) }
                                Spacer(); Text(L10n.string(log?.status.rawValue ?? "Scheduled")).font(.subheadline).foregroundStyle(Palette.muted)
                            }.padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("dose-" + medicine.id + "-" + String(Int(date.timeIntervalSince1970)))
                    }
                    if let refill = schedule.refill {
                        HStack(spacing: 14) { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Palette.blue); Text(L10n.format("Refill %@", L10n.medicineName(medicine))); Spacer(); Text(refill, style: .date).foregroundStyle(Palette.muted) }.padding(.vertical, 8)
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
                } label: { Label(L10n.string(reminder.quote == nil ? "Choose a follow-up" : "Change follow-up"), systemImage: "waveform") }
                if let quote = reminder.quote { Text(quote).textSelection(.enabled); if let visit = store.visits.first(where: { $0.id == reminder.visitID }) { Text(visit.date, style: .date).foregroundStyle(Palette.muted) } }
            }
            Section {
                DatePicker("Due", selection: $reminder.due).onChange(of: reminder.due) { dateChosen = true }.accessibilityIdentifier("reminderDate")
                Button { dateChosen = true } label: { Label(L10n.string(dateChosen ? "Date confirmed" : "Confirm date"), systemImage: dateChosen ? "checkmark.circle.fill" : "calendar") }.accessibilityIdentifier("confirmReminderDate")
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
            Text(L10n.medicineName(medicine)).font(.title.weight(.semibold))
            Text(scheduled, format: .dateTime.month(.abbreviated).day().hour().minute()).foregroundStyle(Palette.muted)
            ForEach(DoseStatus.allCases, id: \.self) { choice in
                Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { status = choice } } label: { HStack { Text(L10n.string(choice.rawValue)).font(.title3); Spacer(); SelectionIndicator(selected: status == choice) }.padding(14).background(status == choice ? Palette.blueWash : Palette.surface, in: RoundedRectangle(cornerRadius: 18)) }.buttonStyle(.plain).accessibilityIdentifier("doseStatus-" + choice.rawValue)
            }
            if status == .later { Picker("Delay", selection: $minutes) { ForEach([15, 30, 60, 120], id: \.self) { Text(L10n.format("%d minutes", $0)).tag($0) } }.pickerStyle(.menu) }
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
    private var entries: [TimelineEntry] { LocalizedHealthContent.timelineEntries(records: store.records, care: store.care, visits: store.visits, query: query) }
    var body: some View {
        List {
            if entries.isEmpty { Text(L10n.string(query.isEmpty ? "No history yet" : "No matching records")).foregroundStyle(Palette.muted) }
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

private enum HealthTrendRange: String, CaseIterable, Identifiable, Hashable {
    case week, month, threeMonths, allTime
    var id: Self { self }
    var title: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .threeMonths: "90 days"
        case .allTime: "All time"
        }
    }
    var dayCount: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .allTime: nil
        }
    }
}

private enum HealthTrendSection: String, CaseIterable, Identifiable, Hashable {
    case readings, symptoms
    var id: Self { self }
    var title: String { self == .readings ? "Readings" : "Symptoms" }
}

private struct SymptomTrendBucket: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

struct HealthTrendsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.floatingDockClearance) private var dockClearance
    @State private var section: HealthTrendSection = .readings
    @State private var range: HealthTrendRange = .month
    @State private var readingKind: ReadingKind = .bloodPressure

    private var rangeStart: Date? {
        guard let dayCount = range.dayCount else { return nil }
        return Calendar.current.date(byAdding: .day, value: -dayCount, to: .now)
    }

    private var readings: [Reading] {
        store.records.readings.filter { reading in
            reading.kind == readingKind && reading.date <= .now && (rangeStart == nil || reading.date >= rangeStart!)
        }.sorted { $0.date < $1.date }
    }

    private var symptoms: [Symptom] {
        store.records.symptoms.filter { $0.date <= .now && (rangeStart == nil || $0.date >= rangeStart!) }.sorted { $0.date < $1.date }
    }

    private var symptomBuckets: [SymptomTrendBucket] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: symptoms) { symptom -> Date in
            if range == .week { return calendar.startOfDay(for: symptom.date) }
            return calendar.dateInterval(of: .weekOfYear, for: symptom.date)?.start ?? calendar.startOfDay(for: symptom.date)
        }
        return grouped.map { SymptomTrendBucket(date: $0.key, count: $0.value.count) }.sorted { $0.date < $1.date }
    }

    private var frequentSymptoms: [(name: String, count: Int)] {
        let grouped = Dictionary(grouping: symptoms) { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var result: [(name: String, count: Int)] = []
        for (name, values) in grouped where !name.isEmpty { result.append((name: name, count: values.count)) }
        result.sort {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return Array(result.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Picker("Trend category", selection: $section) {
                    ForEach(HealthTrendSection.allCases) { item in Text(L10n.string(item.title)).tag(item) }
                }.pickerStyle(.segmented)

                Picker("Date range", selection: $range) {
                    ForEach(HealthTrendRange.allCases) { item in Text(L10n.string(item.title)).tag(item) }
                }.pickerStyle(.segmented)

                if section == .readings { readingsContent } else { symptomsContent }

                Text(section == .readings
                     ? L10n.string("Charts show readings you recorded or imported. They don’t explain changes or provide a diagnosis.")
                     : L10n.string("Symptom charts count entries you logged. They don’t measure severity or provide a diagnosis."))
                    .font(.footnote).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppLayout.screenInset)
            .padding(.vertical, 20)
            .frame(maxWidth: AppLayout.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.bottom, dockClearance, for: .scrollContent)
        .background(Palette.canvas)
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("healthTrends")
    }

    @ViewBuilder private var readingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Reading type", selection: $readingKind) {
                ForEach(ReadingKind.allCases, id: \.self) { kind in Text(L10n.string(kind.rawValue)).tag(kind) }
            }.pickerStyle(.menu).font(.headline)

            if readings.isEmpty {
                emptyState(title: "No readings in this period", detail: "Add or import readings to see how they change over time.", symbol: readingKind.symbol)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Latest").font(.subheadline).foregroundStyle(Palette.muted)
                        Text(L10n.readingValue(readings[readings.count - 1]) + " " + L10n.string(readingKind.unit))
                            .font(.title2.weight(.bold)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.75)
                        Text(readings[readings.count - 1].date.formatted(.dateTime.month(.abbreviated).day().year().locale(L10n.locale)))
                            .font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("In this period").font(.subheadline).foregroundStyle(Palette.muted)
                        Text(L10n.format(readings.count == 1 ? "%lld reading" : "%lld readings", Int64(readings.count)))
                            .font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                    }
                }

                Chart(readings) { reading in
                    if readingKind == .bloodPressure {
                        let parts = reading.value.split(separator: "/").compactMap { Double($0) }
                        if parts.count == 2 {
                            LineMark(x: .value("Date", reading.date), y: .value("mmHg", parts[0]), series: .value("Measure", "Systolic"))
                                .foregroundStyle(by: .value("Measure", "Systolic"))
                            PointMark(x: .value("Date", reading.date), y: .value("mmHg", parts[0]))
                                .foregroundStyle(by: .value("Measure", "Systolic"))
                            LineMark(x: .value("Date", reading.date), y: .value("mmHg", parts[1]), series: .value("Measure", "Diastolic"))
                                .foregroundStyle(by: .value("Measure", "Diastolic"))
                            PointMark(x: .value("Date", reading.date), y: .value("mmHg", parts[1]))
                                .foregroundStyle(by: .value("Measure", "Diastolic"))
                        }
                    } else if let value = Double(ReadingParser.normalizedValue(reading.value)) {
                        LineMark(x: .value("Date", reading.date), y: .value(L10n.string(readingKind.rawValue), value))
                            .foregroundStyle(Palette.blue)
                        PointMark(x: .value("Date", reading.date), y: .value(L10n.string(readingKind.rawValue), value))
                            .foregroundStyle(Palette.blue)
                    }
                }
                .chartForegroundStyleScale(domain: ["Systolic", "Diastolic"], range: [Palette.blue, Palette.coral])
                .chartLegend(readingKind == .bloodPressure ? .visible : .hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(L10n.locale))
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 190)
                .accessibilityLabel(L10n.format("Recorded %@ over time", L10n.string(readingKind.rawValue)))
                .accessibilityIdentifier("readingTrendChart")
            }
        }
        .padding(AppLayout.surfaceInset)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 28))
    }

    @ViewBuilder private var symptomsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Symptoms logged").font(.subheadline).foregroundStyle(Palette.muted)
                Text(L10n.format(symptoms.count == 1 ? "%lld entry" : "%lld entries", Int64(symptoms.count)))
                    .font(.title2.weight(.bold)).foregroundStyle(Palette.ink)
                Text(range == .week ? L10n.string("Entries per day") : L10n.string("Entries per week"))
                    .font(.subheadline).foregroundStyle(Palette.muted)
            }

            if symptomBuckets.isEmpty {
                emptyState(title: "No symptoms in this period", detail: "Log symptoms to see how often entries appear over time.", symbol: "cross.case")
            } else {
                Chart(symptomBuckets) { bucket in
                    BarMark(x: .value("Week", bucket.date, unit: range == .week ? .day : .weekOfYear), y: .value("Entries", bucket.count))
                        .foregroundStyle(Palette.coral.gradient)
                        .cornerRadius(5)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(L10n.locale))
                    }
                }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                .frame(height: 190)
                .accessibilityLabel(L10n.string("Symptom entries recorded over time"))
                .accessibilityIdentifier("symptomTrendChart")

                if !frequentSymptoms.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Most logged").font(.headline)
                        ForEach(Array(frequentSymptoms.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 12) {
                                Text(item.name).foregroundStyle(Palette.ink).lineLimit(2)
                                Spacer(minLength: 8)
                                Text(L10n.format(item.count == 1 ? "%lld entry" : "%lld entries", Int64(item.count)))
                                    .font(.subheadline).foregroundStyle(Palette.muted)
                            }
                        }
                    }
                }
            }
        }
        .padding(AppLayout.surfaceInset)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 28))
    }

    private func emptyState(title: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string(title), systemImage: symbol).font(.headline).foregroundStyle(Palette.ink)
            Text(L10n.string(detail)).font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

struct PreparationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editing: Bool
    @State private var question = ""
    @State private var editingID: UUID?
    var initialQuestion = ""
    private var note: String { LocalizedHealthContent.appointmentNote(records: store.records, care: store.care) }
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
