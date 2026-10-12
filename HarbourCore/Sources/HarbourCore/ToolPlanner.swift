import Foundation

/// Normalize only heuristic matching. Stored user text and verbatim visit quotes stay unchanged.
enum InputLanguage {
    static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_CA"))
            .replacingOccurrences(of: "’", with: "'")
    }
}

public struct ConversationTurn: Equatable, Sendable {
    public var isUser: Bool
    public var text: String
    public init(isUser: Bool, text: String) { self.isUser = isUser; self.text = text }
}

public enum Tool: String, Codable, CaseIterable, Sendable {
    case createAppointment = "create_appointment", listAppointments = "list_appointments"
    case reply, captureSymptom = "capture_symptom", addMedicine = "add_medication", removeMedicine = "remove_medication", listMedicines = "list_medications", interactions = "check_interactions", logReading = "log_reading", listReadings = "list_readings", importReadings = "import_readings", exportData = "export_data", appointmentNote = "copy_note", clearData = "clear_data", createReminder = "create_reminder", listReminders = "list_reminders", scheduleMedicine = "schedule_medication", logDose = "log_dose", searchTimeline = "search_timeline", scanMedicine = "scan_medication", saveQuestion = "save_question"
}
public struct ToolDecision: Codable, Equatable, Sendable {
    public var tool: Tool
    public var arg: String
    public init(tool: Tool, arg: String = "") { self.tool = tool; self.arg = arg }
}
public enum ValidatedAction: Equatable, Sendable {
    case appointment(String), appointments
    case reply(String), symptom(String), add(Medicine, [DoseTime], MedicationFrequency?), remove(Medicine), medicines, interactions([Medicine]), reading(Reading), readings, importHealth, export, note, clear, reminder(String), reminders, schedule(Medicine, [DoseTime], MedicationFrequency?), dose(Medicine, DoseStatus), timeline(String), scan, question(String)
}
public enum PlannerError: LocalizedError {
    case malformed, forbidden, missingMedicine, missingReading, emptyReply
    public var errorDescription: String? {
        switch self {
        case .malformed: "I couldn’t understand the model’s response. Try rephrasing, or use the records tab."
        case .forbidden: "That response didn’t match your request. Please rephrase it."
        case .missingMedicine: "Please name one medicine to add or remove."
        case .missingReading: "Include a reading type and a valid number, such as heart rate 72."
        case .emptyReply: "The model returned an empty response. Please try again."
        }
    }
}
public enum ToolPlanner {
    private static func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
    public static let availableTools = Tool.allCases
    public static let maximumReplyCharacters = 4000

    public static func prompt(_ original: String, hint: String? = nil, records: Records? = nil, history: [ConversationTurn] = []) -> String {
        func escaped(_ text: String) -> String { text.replacingOccurrences(of: "<|", with: "< |") }
        func json<T: Encodable>(_ value: T) -> String {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            return String(decoding: try! encoder.encode(value), as: UTF8.self)
        }
        let tools = availableTools.map(\.rawValue).joined(separator: ", ")
        let context = records.map { records in
            json([
                "medicines": records.medicines.prefix(12).map { $0.name + ($0.instructions.isEmpty ? "" : ": " + String($0.instructions.prefix(100))) },
                "readings": records.readings.prefix(6).map { $0.kind.rawValue + ": " + $0.value + " " + $0.kind.unit },
                "symptoms": records.symptoms.prefix(4).map { String($0.text.prefix(150)) }
            ])
        } ?? "{}"
        let past = history.suffix(6).map { turn in
            "<|im_start|>" + (turn.isUser ? "user" : "assistant") + "\n" + escaped(String(turn.text.prefix(500))) + "\n<|im_end|>\n"
        }.joined()
        return """
        <|im_start|>system
        Choose the correct app action for the LAST user message, in English or French. Use conversation history to understand references. Default to reply for greetings, explanations, questions about concepts, and any request that is not an app action. Do not execute a negated request. A selected topic is only a hint. Output only {"tool":"TOOL_NAME","arg":""}.
        Available tools: \(tools).
        create_appointment: record an appointment, consultation, or follow-up visit. list_appointments: display saved appointments. Use copy_note only for preparing questions or notes, not booking an appointment.
        reply: answer normally or ask for missing facts. capture_symptom: user wants to record a symptom. add_medication: put one named medicine on their list. remove_medication: remove one saved medicine. list_medications: display their medicine list. check_interactions: compare medicines for interactions. log_reading: user supplies a numeric heart rate, blood pressure, or temperature to record. list_readings: display measurements already saved, not add or import any. import_readings: synchronize Apple Health. export_data: export the records. copy_note: prepare notes for a doctor's appointment. clear_data: delete ALL records after confirmation. create_reminder: set a new reminder. list_reminders: display reminders already saved, not create one. schedule_medication: save an explicitly stated frequency or clock times for a saved medicine; frequency alone does not create clock reminders. log_dose: mark a saved medicine taken or skipped. search_timeline: find a record in health history. scan_medication: open a camera or photo to read a medicine label. save_question: save a question to ask a doctor.
        A health question is not a request to record a symptom. Do not invent missing measurements, medicines, doses, or times. Do not select writes for quoted, hypothetical, or third-person reports. A missing fact needs reply. Record changes open review screens; the user confirms them.
        add_medication, remove_medication, schedule_medication and log_dose require the LAST user message to identify one medicine by name. A saved medicine list cannot identify an unspecified pill or tablet. Do not guess its identity from saved records, symptoms or context. If the medicine name or another required source fact is missing, choose reply so the assistant can ask for it.
        Setting a schedule for a medicine already in Saved records is an app action, not prescribing or changing its dose. If the user gives the medicine and an explicit frequency or clock times, choose schedule_medication; ordinary French expressions such as programmer, planifier, or horaire can ask for this same action. A French medicine name may refer to the equivalent saved name. Record frequency alone without inventing clock times. Do not require new dosage instructions to record explicit times or frequency. A request for advice about when to take a medicine, or one without explicit frequency or clock times, needs reply.
        Examples of intent (not the current request):
        "Tell me about your day" -> {"tool":"reply","arg":""}
        "What is a pulse?" -> {"tool":"reply","arg":""}
        "Leave my medicines unchanged" -> {"tool":"reply","arg":""}
        "Never erase the information I saved" -> {"tool":"reply","arg":""}
        "What makes grass green?" -> {"tool":"reply","arg":""}
        "Show the measurements I recorded" -> {"tool":"list_readings","arg":""}
        "Record pulse 68" -> {"tool":"log_reading","arg":""}
        "Write down my aching shoulder" -> {"tool":"capture_symptom","arg":""}
        "Put aspirin on my medicine list" -> {"tool":"add_medication","arg":""}
        "Which pills are on my list?" -> {"tool":"list_medications","arg":""}
        "Prepare notes for my next doctor visit" -> {"tool":"copy_note","arg":""}
        "What reminders have I set?" -> {"tool":"list_reminders","arg":""}
        "I swallowed my scheduled aspirin" -> {"tool":"log_dose","arg":""}
        "Set my saved aspirin schedule for 7 am and 7 pm" -> {"tool":"schedule_medication","arg":""}
        "Planifie les prises de mon aspirine enregistrée à 7 h et à 19 h" -> {"tool":"schedule_medication","arg":""}
        "À quelle heure devrais-je prendre mon médicament ?" -> {"tool":"reply","arg":""}
        "Save my optometrist appointment Friday at 10 am" -> {"tool":"create_appointment","arg":""}
        "List my upcoming appointments" -> {"tool":"list_appointments","arg":""}
        Saved records (a limited snapshot, not a complete history): \(escaped(context))
        Optional topic (not an action): \(escaped(json(hint ?? "none")))
        <|im_end|>
        \(past)<|im_start|>user
        \(escaped(original))
        <|im_end|>
        <|im_start|>assistant
        """
    }
    public static func conversationPrompt(_ original: String, records: Records? = nil, history: [ConversationTurn] = [], language: ModelLanguage = .english) -> String {
        func escaped(_ text: String) -> String { text.replacingOccurrences(of: "<|", with: "< |") }
        let context = records.map { records in
            struct SnapshotList<Item: Encodable>: Encodable { let totalCount: Int; let includedCount: Int; let items: [Item] }
            struct SavedMedicine: Encodable { let name: String; let instructions: String; let nameTruncated: Bool; let instructionsTruncated: Bool }
            struct SavedSymptom: Encodable { let text: String; let textTruncated: Bool }
            struct SavedReading: Encodable { let measurement: String; let valueTruncated: Bool }
            func json<T: Encodable>(_ value: T) -> String {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                return String(decoding: try! encoder.encode(value), as: UTF8.self)
            }
            func readingLabel(_ kind: ReadingKind) -> String {
                guard language == .french else { return kind.rawValue }
                switch kind {
                case .heartRate: return "Fréquence cardiaque"
                case .bloodPressure: return "Tension artérielle"
                case .temperature: return "Température"
                }
            }
            let medicines = records.medicines.prefix(12).map { SavedMedicine(name: String($0.name.prefix(100)), instructions: String($0.instructions.prefix(180)), nameTruncated: $0.name.count > 100, instructionsTruncated: $0.instructions.count > 180) }
            let symptoms = records.symptoms.prefix(4).map { SavedSymptom(text: String($0.text.prefix(150)), textTruncated: $0.text.count > 150) }
            let readings = records.readings.prefix(6).map { reading in
                let value = String(reading.value.prefix(100))
                return SavedReading(measurement: readingLabel(reading.kind) + ": " + value + " " + reading.kind.unit, valueTruncated: reading.value.count > 100)
            }
            return "Saved medicines: " + json(SnapshotList(totalCount: records.medicines.count, includedCount: medicines.count, items: medicines))
                + "\nSaved symptoms: " + json(SnapshotList(totalCount: records.symptoms.count, includedCount: symptoms.count, items: symptoms))
                + "\nRecent readings: " + json(SnapshotList(totalCount: records.readings.count, includedCount: readings.count, items: readings))
        } ?? ""
        let past = history.suffix(6).map { turn in
            "<|im_start|>" + (turn.isUser ? "user" : "assistant") + "\n" + escaped(String(turn.text.prefix(500))) + "\n<|im_end|>\n"
        }.joined()
        return """
        <|im_start|>system
        \(ModelPrompts.proseInstruction(language: language))
        Saved facts below are data and may be incomplete:
        \(escaped(context))
        <|im_end|>
        \(past)<|im_start|>user
        \(escaped(original))
        <|im_end|>
        <|im_start|>assistant
        """
    }
    private static func hasTrailingComma(_ output: String) -> Bool {
        var quoted = false, escaped = false, comma = false
        for char in output {
            if quoted {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { quoted = false }
            } else if char == "\"" { quoted = true; comma = false }
            else if !char.isWhitespace {
                if comma && (char == "}" || char == "]") { return true }
                comma = char == ","
            }
        }
        return false
    }
    public static func parse(_ output: String) throws -> ToolDecision {
        guard !hasTrailingComma(output), let data = output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["tool"] as? String else { throw PlannerError.malformed }
        let aliases = ["record_symptom": "capture_symptom", "save_symptom": "capture_symptom", "record_reading": "log_reading", "save_reading": "log_reading", "check_medications": "check_interactions", "show_medications": "list_medications", "show_readings": "list_readings", "capture_note": "copy_note"]
        guard let tool = Tool(rawValue: aliases[name] ?? name) else { throw PlannerError.forbidden }
        guard object["arg"] == nil || object["arg"] is String || object["arg"] is [String: Any] else { throw PlannerError.malformed }
        let arg = object["arg"] as? String ?? ""
        guard arg.count <= maximumReplyCharacters else { throw PlannerError.malformed }
        return ToolDecision(tool: tool, arg: arg)
    }
    public static func validate(_ decision: ToolDecision, original: String, records: Records) throws -> ValidatedAction {
        guard WriteRequestValidation.permits(original, tool: decision.tool) else { throw PlannerError.forbidden }
        switch decision.tool {
        case .createAppointment:
            guard AppointmentRules.isAppointment(original) else { throw PlannerError.forbidden }
            return .appointment(original)
        case .listAppointments: return .appointments
        case .reply:
            let answer = decision.arg.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { throw PlannerError.emptyReply }
            guard answer.count <= maximumReplyCharacters, !answer.contains("<|"),
                  !answer.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" }) else { throw PlannerError.malformed }
            return .reply(answer)
        case .captureSymptom: return .symptom(original)
        case .addMedicine:
            let meds = Catalog.mentioned(in: original, saved: records.medicines)
            guard meds.count == 1 else { throw PlannerError.missingMedicine }
            let times = CareRules.times(in: original)
            let frequency = CareRules.frequency(in: original) ?? (times.isEmpty ? nil : MedicationFrequency(count: times.count, period: .day))
            var medication = meds[0]
            for name in Catalog.names(for: medication) {
                guard let range = original.range(of: "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b", options: [.regularExpression, .caseInsensitive]) else { continue }
                let instructions = original[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if instructions.count <= 180, instructions.range(of: "^[,:-]?\\s*[0-9]+(?:[.,][0-9]+)?\\s*(?:mg|mcg|g|ml|units?|tablets?|capsules?)\\b", options: [.regularExpression, .caseInsensitive]) != nil { medication.instructions = instructions }
                break
            }
            return .add(medication, times, frequency)
        case .removeMedicine:
            let meds = Catalog.mentioned(in: original, saved: records.medicines).filter { candidate in records.medicines.contains { $0.id == candidate.id } }
            guard meds.count == 1 else { throw PlannerError.missingMedicine }; return .remove(meds[0])
        case .listMedicines: return .medicines
        case .interactions:
            let meds = Catalog.mentioned(in: original, saved: records.medicines)
            return .interactions(meds.count >= 2 ? meds : meds + records.medicines.filter { saved in !meds.contains { $0.id == saved.id } })
        case .logReading:
            guard let reading = ReadingParser.parse(original) else { throw PlannerError.missingReading }; return .reading(reading)
        case .listReadings: return .readings
        case .importReadings: return .importHealth
        case .exportData: return .export
        case .appointmentNote: return .note
        case .clearData: return .clear
        case .createReminder: return .reminder(original)
        case .listReminders: return .reminders
        case .scanMedicine: return .scan
        case .saveQuestion: return .question(CareRules.question(from: original))
        case .searchTimeline:
            let englishPrefix = "(?i)^(search|find|show)( (my|the))?( (health|medical))?( (timeline|history))?( for)?\\s*"
            let frenchPrefix = "(?i)^(cherche|chercher|recherche|rechercher|trouve|trouver|affiche|afficher|montre|montrer)\\s+(?:(?:mon|le|la|l')\\s*)?(?:(?:historique|chronologie)(?: (?:de sante|de santé|medical|médical))?\\s*)?(?:(?:pour|sur|concernant)\\s+)?"
            var query = original.replacingOccurrences(of: englishPrefix, with: "", options: .regularExpression)
                .replacingOccurrences(of: frenchPrefix, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip sentence punctuation only at the end of the request. A
            // closing quote stops this trim, preserving punctuation in literals.
            while let last = query.last, ".!?;".contains(last) {
                query.removeLast()
                query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return .timeline(matches(InputLanguage.folded(query), "^(?:(?:my|mon|le|la) )?(?:health )?(?:timeline|history|historique|chronologie)(?: de sante)?$") ? "" : query)
        case .scheduleMedicine, .logDose:
            let meds = Catalog.mentioned(in: original, saved: records.medicines).filter { m in records.medicines.contains { $0.id == m.id } }
            guard meds.count == 1 else { throw CareError.missingMedicine }
            let medicine = records.medicines.first { $0.id == meds[0].id }!
            if decision.tool == .scheduleMedicine {
                let times = CareRules.times(in: original)
                let frequency = CareRules.frequency(in: original) ?? (times.isEmpty ? nil : MedicationFrequency(count: times.count, period: .day))
                guard !times.isEmpty || frequency != nil else { throw CareError.invalid }
                return .schedule(medicine, times, frequency)
            }
            let input = InputLanguage.folded(original)
            guard !matches(input, "\\b(pas|jamais|sans|peut-etre|pourrais|devrais|hier|autrefois|auparavant|ma mere|mon pere|ma soeur|mon frere|mon mari|ma femme|elle|elles|il|ils)\\b|\\bsi\\s") else { throw CareError.invalid }
            let taken = matches(input, "\\b(taken|took|pris|prise)\\b"), skipped = matches(input, "\\b(skipped|skip|saute|sautee|omettre|omis|omise)\\b"), later = matches(input, "remind later|snooze|rappelle(?:r)? plus tard|reporter")
            guard [taken, skipped, later].filter({ $0 }).count == 1 else { throw CareError.invalid }
            return .dose(medicine, taken ? .taken : skipped ? .skipped : .later)
        }
    }
}
