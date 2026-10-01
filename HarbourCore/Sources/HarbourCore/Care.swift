import Foundation

public struct CareReminder: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var due: Date
    public var notify: Bool
    public var completed: Bool
    public var visitID: UUID?
    public var quote: String?
    public init(id: UUID = UUID(), title: String = "", due: Date = .now.addingTimeInterval(3600), notify: Bool = false, completed: Bool = false, visitID: UUID? = nil, quote: String? = nil) {
        self.id = id; self.title = title; self.due = due; self.notify = notify; self.completed = completed; self.visitID = visitID; self.quote = quote
    }
}
public struct DoseTime: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var hour: Int
    public var minute: Int
    public var id: String { "\(hour):\(minute)" }
    public init(hour: Int, minute: Int) { self.hour = hour; self.minute = minute }
    public var valid: Bool { (0..<24).contains(hour) && (0..<60).contains(minute) }
}
public struct MedicineSchedule: Codable, Equatable, Sendable, Identifiable {
    public var medicineID: String
    public var times: [DoseTime]
    public var notify: Bool
    public var refill: Date?
    public var id: String { medicineID }
    public init(medicineID: String, times: [DoseTime] = [], notify: Bool = false, refill: Date? = nil) {
        self.medicineID = medicineID; self.times = times; self.notify = notify; self.refill = refill
    }
}
public enum DoseStatus: String, Codable, CaseIterable, Sendable { case taken = "Taken", skipped = "Skipped", later = "Remind later" }
public struct DoseLog: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var medicineID: String
    public var scheduled: Date
    public var status: DoseStatus
    public var date: Date
    public var snooze: Date?
    public var medicineName: String?
    public var scheduledTime: DoseTime?
    public var timeZoneIdentifier: String?
    public init(medicineID: String, scheduled: Date, status: DoseStatus, date: Date = .now, snooze: Date? = nil) {
        id = Self.key(medicineID, scheduled); self.medicineID = medicineID; self.scheduled = scheduled; self.status = status; self.date = date; self.snooze = snooze
    }
    public static func key(_ medicineID: String, _ scheduled: Date) -> String {
        let seconds = scheduled.timeIntervalSince1970
        guard seconds.isFinite, seconds > Double(Int.min), seconds < Double(Int.max) else { return medicineID + ":invalid" }
        return medicineID + ":" + String(Int(seconds))
    }
    public func preservingSource(medicine: Medicine, time: DoseTime, calendar: Calendar = .current) -> DoseLog {
        var log = self; log.medicineName = medicine.name; log.scheduledTime = time; log.timeZoneIdentifier = calendar.timeZone.identifier
        return log
    }
}
public struct AppointmentQuestion: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var date: Date
    public init(id: UUID = UUID(), text: String, date: Date = .now) { self.id = id; self.text = text; self.date = date }
}
public struct MedicineEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var date: Date
    public init(text: String, date: Date = .now) { id = UUID(); self.text = text; self.date = date }
}
public struct CareData: Codable, Equatable, Sendable {
    public var reminders: [CareReminder] = []
    public var schedules: [MedicineSchedule] = []
    public var doses: [DoseLog] = []
    public var questions: [AppointmentQuestion] = []
    public var medicineEvents: [MedicineEvent] = []
    public init() {}
}
public enum CareError: LocalizedError {
    case invalid, sourceChanged, missingMedicine
    public var errorDescription: String? { switch self {
    case .invalid: "Check the name, dates, and reminder times."
    case .sourceChanged: "The visit note has changed. Choose the follow-up again."
    case .missingMedicine: "Choose a saved medicine and a scheduled dose."
    } }
}
public enum CareRules {
    public static func validate(_ reminder: CareReminder, visits: [DoctorVisit]) throws {
        guard !reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reminder.title.count <= 500, reminder.due.timeIntervalSince1970.isFinite else { throw CareError.invalid }
        if let id = reminder.visitID {
            guard let visit = visits.first(where: { $0.id == id }), let quote = reminder.quote, !VisitReview.normalise(quote).isEmpty,
                  VisitReview.normalise(visit.transcript).contains(VisitReview.normalise(quote)), visit.summary?.followUps.contains(where: { $0.quote == quote }) == true else { throw CareError.sourceChanged }
        } else if reminder.quote != nil { throw CareError.sourceChanged }
    }
    public static func validate(_ schedule: MedicineSchedule, medicines: [Medicine]) throws {
        guard medicines.contains(where: { $0.id == schedule.medicineID }) else { throw CareError.missingMedicine }
        guard schedule.times.count <= 8, schedule.times.allSatisfy(\.valid), Set(schedule.times).count == schedule.times.count,
              schedule.refill == nil || schedule.refill!.timeIntervalSince1970.isFinite else { throw CareError.invalid }
    }
    public static func doses(on day: Date, schedule: MedicineSchedule, calendar: Calendar = .current) -> [Date] {
        guard day.timeIntervalSince1970.isFinite else { return [] }
        return schedule.times.compactMap { time in
            guard time.valid else { return nil }
            return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }.sorted()
    }
    public static func validate(_ log: DoseLog, care: CareData, medicines: [Medicine], calendar: Calendar = .current) throws {
        try validateHistory(log, calendar: calendar)
        guard let schedule = care.schedules.first(where: { $0.medicineID == log.medicineID }), medicines.contains(where: { $0.id == log.medicineID }),
              doses(on: log.scheduled, schedule: schedule, calendar: calendar).contains(log.scheduled) else { throw CareError.invalid }
    }
    public static func validateHistory(_ log: DoseLog, calendar: Calendar = .current) throws {
        guard !log.medicineID.isEmpty, log.scheduled.timeIntervalSince1970.isFinite, log.date.timeIntervalSince1970.isFinite,
              log.snooze == nil || log.snooze!.timeIntervalSince1970.isFinite,
              log.id == DoseLog.key(log.medicineID, log.scheduled), !log.id.hasSuffix(":invalid"),
              log.scheduled <= log.date.addingTimeInterval(300),
              log.status == .later ? (log.snooze != nil && log.snooze! > log.date && log.snooze! <= log.date.addingTimeInterval(86400)) : log.snooze == nil else { throw CareError.invalid }
        if log.medicineName != nil || log.scheduledTime != nil || log.timeZoneIdentifier != nil {
            guard let name = log.medicineName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 500,
                  let time = log.scheduledTime, time.valid, let zone = log.timeZoneIdentifier, let timeZone = TimeZone(identifier: zone) else { throw CareError.invalid }
            var originalCalendar = calendar; originalCalendar.timeZone = timeZone
            guard doses(on: log.scheduled, schedule: MedicineSchedule(medicineID: log.medicineID, times: [time]), calendar: originalCalendar).contains(log.scheduled) else { throw CareError.invalid }
        }
    }
    public static func preservingDoseSources(_ care: CareData, medicines: [Medicine], calendar: Calendar = .current) -> CareData {
        var result = care
        result.doses = care.doses.map { log in
            guard log.medicineName == nil, let medicine = medicines.first(where: { $0.id == log.medicineID }),
                  let schedule = care.schedules.first(where: { $0.medicineID == log.medicineID }),
                  let time = schedule.times.first(where: { doses(on: log.scheduled, schedule: MedicineSchedule(medicineID: medicine.id, times: [$0]), calendar: calendar).contains(log.scheduled) }) else { return log }
            return log.preservingSource(medicine: medicine, time: time, calendar: calendar)
        }
        return result
    }
    public static func question(from text: String) -> String {
        let english = "(?i)^(save|add|remember)\\s+(this\\s+)?(question\\s*:?\\s*)?(for (my |the )?(doctor|appointment)\\s*:?\\s*)?"
        let french = "(?i)^(enregistre|enregistrer|sauve|sauvegarde|sauvegarder|ajoute|ajouter|garde|garder)\\s+(?:(?:cette|une|la)\\s+)?(?:question\\s*:?\\s*)?(?:pour (?:mon |le |un |la |ma )?(?:médecin|medecin|docteur|rendez-vous)\\s*:?\\s*)?"
        return text.replacingOccurrences(of: english, with: "", options: .regularExpression)
            .replacingOccurrences(of: french, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func times(in text: String) -> [DoseTime] {
        let ns = text as NSString
        var times: [DoseTime] = []
        let english = try! NSRegularExpression(pattern: "(?i)\\b(1[0-2]|0?[1-9])(?::([0-5][0-9]))?\\s*(am|pm)\\b")
        for match in english.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let h = Int(ns.substring(with: match.range(at: 1)))! % 12
            let m = match.range(at: 2).location == NSNotFound ? 0 : Int(ns.substring(with: match.range(at: 2)))!
            times.append(DoseTime(hour: h + (ns.substring(with: match.range(at: 3)).lowercased() == "pm" ? 12 : 0), minute: m))
        }
        // Accept literal French 24-hour notation; never infer times from "morning" or frequency.
        let clocks = ["(?i)\\b([01]?[0-9]|2[0-3])\\s*h(?:\\s*([0-5][0-9]))?(?![0-9]|\\s+[0-9])\\b", "(?i)\\b([01]?[0-9]|2[0-3]):([0-5][0-9])\\b(?!\\s*(?:am|pm)\\b)"]
        for pattern in clocks {
            let regex = try! NSRegularExpression(pattern: pattern)
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let h = Int(ns.substring(with: match.range(at: 1)))!
                let m = match.range(at: 2).location == NSNotFound ? 0 : Int(ns.substring(with: match.range(at: 2)))!
                times.append(DoseTime(hour: h, minute: m))
            }
        }
        return Array(Set(times)).sorted { $0.hour * 60 + $0.minute < $1.hour * 60 + $1.minute }
    }
    public static func labelInstructions(_ text: String) -> String {
        text.components(separatedBy: .newlines).filter {
            InputLanguage.folded($0).range(of: "^(take|directions|dosage|apply|use|prendre|prenez|posologie|appliquer|appliquez|utiliser|utilisez|mode d'emploi)\\b", options: .regularExpression) != nil
        }.prefix(4).joined(separator: "\n")
    }
    public static func labelCandidates(_ text: String) -> [Medicine] { Catalog.mentioned(in: String(text.prefix(12_000))) }
    public static func appointmentNote(records: Records, care: CareData) -> String {
        records.appointmentNote.components(separatedBy: "\nQuestions:").first! + "\n\nQuestions\n" + (care.questions.isEmpty ? "No questions saved." : care.questions.map { "• " + $0.text }.joined(separator: "\n"))
    }
}
public struct TimelineEntry: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var date: Date
    public var symbol: String
}
public enum HealthTimeline {
    public static func entries(records: Records, care: CareData, visits: [DoctorVisit], query: String = "") -> [TimelineEntry] {
        var entries = records.symptoms.map { TimelineEntry(id: "symptom-\($0.id)", title: $0.text, detail: $0.severity + " · " + $0.onset, date: $0.date, symbol: "cross.case") }
        entries += records.readings.map { TimelineEntry(id: "reading-" + $0.id, title: $0.kind.rawValue + " " + $0.value + " " + $0.kind.unit, detail: $0.source, date: $0.date, symbol: $0.kind.symbol) }
        entries += visits.map { TimelineEntry(id: "visit-\($0.id)", title: $0.title, detail: $0.transcript, date: $0.date, symbol: "waveform") }
        entries += care.doses.map { log in TimelineEntry(id: "dose-" + log.id, title: (log.medicineName ?? records.medicines.first { $0.id == log.medicineID }?.name ?? "Medicine") + " · " + log.status.rawValue, detail: "Scheduled " + log.scheduled.formatted(), date: log.date, symbol: "pills") }
        entries += care.medicineEvents.map { TimelineEntry(id: "medicine-\($0.id)", title: $0.text, detail: "Medicine list updated", date: $0.date, symbol: "pills") }
        entries += care.reminders.map { TimelineEntry(id: "reminder-\($0.id)", title: $0.title, detail: $0.completed ? "Completed" : "Due " + $0.due.formatted(), date: $0.due, symbol: "checklist") }
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { search.isEmpty || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(search) }.sorted { $0.date > $1.date }
    }
}
public struct CareBackup: Codable, Sendable {
    public var version = 2
    public var records: Records
    public var care: CareData
    public var visits: [DoctorVisit]
    public init(records: Records, care: CareData, visits: [DoctorVisit]) { self.records = records; self.care = CareRules.preservingDoseSources(care, medicines: records.medicines); self.visits = visits.map { var v = $0; v.audioFilename = nil; return v } }
    public func validated() throws -> CareBackup {
        func unique<T: Hashable>(_ ids: [T]) -> Bool { Set(ids).count == ids.count }
        func finite(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite }
        guard version == 2, records.schemaVersion == 1,
              unique(records.medicines.map(\.id)), unique(records.medicines.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }),
              records.medicines.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 500 }),
              unique(records.readings.map(\.id)), records.readings.allSatisfy({ !$0.id.isEmpty && finite($0.date) && ReadingParser.valid($0.value, kind: $0.kind) }),
              unique(records.symptoms.map(\.id)), records.symptoms.allSatisfy({ finite($0.date) }),
              unique(visits.map(\.id)), visits.allSatisfy({ finite($0.date) && $0.duration.isFinite && $0.duration >= 0 }),
              unique(care.reminders.map(\.id)), unique(care.schedules.map(\.id)), unique(care.doses.map(\.id)),
              unique(care.questions.map(\.id)), care.questions.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.count <= 1000 && finite($0.date) }),
              unique(care.medicineEvents.map(\.id)), care.medicineEvents.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && finite($0.date) }) else { throw CareError.invalid }
        for reminder in care.reminders { try CareRules.validate(reminder, visits: visits) }
        for schedule in care.schedules { try CareRules.validate(schedule, medicines: records.medicines) }
        for log in care.doses {
            try CareRules.validateHistory(log)
            if log.medicineName == nil { try CareRules.validate(log, care: care, medicines: records.medicines) }
        }
        var result = self; result.care = CareRules.preservingDoseSources(care, medicines: records.medicines)
        return result
    }
    public func merging(into existing: CareBackup) throws -> CareBackup {
        let incoming = try validated()
        var result = existing
        var mapping: [String: String] = [:]
        for imported in incoming.records.medicines {
            if let collision = result.records.medicines.first(where: { $0.id == imported.id }), collision.name.caseInsensitiveCompare(imported.name) != .orderedSame { throw CareError.invalid }
            if let saved = result.records.medicines.first(where: { $0.name.caseInsensitiveCompare(imported.name) == .orderedSame }) { mapping[imported.id] = saved.id; continue }
            var medicine = Catalog.medicines.first { $0.name.caseInsensitiveCompare(imported.name) == .orderedSame } ?? Medicine(name: imported.name)
            medicine.id = imported.id; medicine.instructions = imported.instructions
            mapping[imported.id] = medicine.id; result.records.medicines.append(medicine)
        }
        for reading in incoming.records.readings where !result.records.readings.contains(where: { $0.id == reading.id }) { result.records.readings.append(reading) }
        for symptom in incoming.records.symptoms where !result.records.symptoms.contains(where: { $0.id == symptom.id }) { result.records.symptoms.append(symptom) }
        for visit in incoming.visits where !result.visits.contains(where: { $0.id == visit.id }) { var sanitized = visit; sanitized.audioFilename = nil; result.visits.append(sanitized) }
        for reminder in incoming.care.reminders where !result.care.reminders.contains(where: { $0.id == reminder.id }) {
            try CareRules.validate(reminder, visits: result.visits)
            result.care.reminders.append(reminder)
        }
        for var schedule in incoming.care.schedules {
            guard let mapped = mapping[schedule.medicineID] else { throw CareError.invalid }; schedule.medicineID = mapped
            if !result.care.schedules.contains(where: { $0.id == schedule.id }) { result.care.schedules.append(schedule) }
        }
        for var log in incoming.care.doses {
            if mapping[log.medicineID] == nil, let medicine = result.records.medicines.first(where: { $0.id == log.medicineID }), let name = log.medicineName, medicine.name.caseInsensitiveCompare(name) != .orderedSame { throw CareError.invalid }
            log.medicineID = mapping[log.medicineID] ?? log.medicineID; log.id = DoseLog.key(log.medicineID, log.scheduled)
            if !result.care.doses.contains(where: { $0.id == log.id }) { result.care.doses.append(log) }
        }
        for question in incoming.care.questions where !result.care.questions.contains(where: { $0.id == question.id }) { result.care.questions.append(question) }
        for event in incoming.care.medicineEvents where !result.care.medicineEvents.contains(where: { $0.id == event.id }) { result.care.medicineEvents.append(event) }
        result.records.readings.sort { $0.date > $1.date }; result.records.symptoms.sort { $0.date > $1.date }
        return result
    }
}

public struct CareNotificationPlan: Sendable {
    public var id: String
    public var components: DateComponents
    public var repeating: Bool
    public static func make(care: CareData, medicineIDs: Set<String>, now: Date = .now, calendar: Calendar = .current) -> [CareNotificationPlan] {
        var result: [(Date, CareNotificationPlan)] = []
        func once(_ id: String, _ date: Date) {
            guard date.timeIntervalSince1970.isFinite, date > now else { return }
            result.append((date, CareNotificationPlan(id: "harbour-care-" + id, components: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date), repeating: false)))
        }
        for reminder in care.reminders where reminder.notify && !reminder.completed { once("reminder-\(reminder.id)", reminder.due) }
        for schedule in care.schedules where medicineIDs.contains(schedule.medicineID) && schedule.notify {
            for time in schedule.times where time.valid {
                let parts = DateComponents(hour: time.hour, minute: time.minute)
                let next = calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) ?? now
                result.append((next, CareNotificationPlan(id: "harbour-care-dose-" + schedule.medicineID + "-" + time.id, components: parts, repeating: true)))
            }
            if let refill = schedule.refill { once("refill-" + schedule.medicineID, refill) }
        }
        for dose in care.doses where dose.status == .later && medicineIDs.contains(dose.medicineID) { if let date = dose.snooze { once("snooze-" + dose.id, date) } }
        var seen = Set<String>()
        return Array(result.sorted { $0.0 == $1.0 ? $0.1.id < $1.1.id : $0.0 < $1.0 }.filter { seen.insert($0.1.id).inserted }.prefix(60).map(\.1))
    }
}
