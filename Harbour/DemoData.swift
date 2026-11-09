import Foundation
import HarbourCore

/// Authored fictional records. This is a demo fixture, never an inference result.
enum DemoData {
    static func make(now: Date = .now, french: Bool = L10n.isFrench, calendar: Calendar = .current) -> Archive {
        func t(_ en: String, _ fr: String) -> String {
            french ? fr : en
        }
        func day(_ offset: Int, hour: Int = 9) -> Date {
            let date = calendar.date(byAdding: .day, value: offset, to: now)!

            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
        }
        var archive = Archive()
        archive.demoData = true
        var metformin = Catalog.resolve("metformin")!
        metformin.instructions = t(
            "500 mg twice daily with breakfast and dinner",
            "500 mg deux fois par jour au déjeuner et au souper"
        )
        var amlodipine = Catalog.resolve("amlodipine")!
        amlodipine.instructions = t("5 mg once daily at 8 am", "5 mg une fois par jour à 8 h")
        var acetaminophen = Catalog.resolve("acetaminophen")!
        acetaminophen.instructions = t(
            "500 mg every 6 hours if needed for pain, maximum 4 tablets in 24 hours",
            "500 mg toutes les 6 heures au besoin pour la douleur, maximum 4 comprimés en 24 heures"
        )
        archive.records.medicines = [metformin, amlodipine, acetaminophen]
        for offset in -41 ... 0 {
            let sample = day(offset, hour: 7)
            archive.records.readings += [
                Reading(kind: .heartRate, value: String(68 + ((offset + 42) * 7 % 13)), date: sample, source: "Demo"),
                Reading(
                    kind: .bloodPressure,
                    value: "\(122 + (offset + 42) * 3 % 15)/\(76 + (offset + 42) % 7)",
                    date: sample,
                    source: "Demo"
                ),
                Reading(
                    kind: .temperature,
                    value: String(
                        format: "%.1f",
                        locale: Locale(identifier: "en_US_POSIX"),
                        36.5 + Double((offset + 42) % 5) / 10
                    ),
                    date: sample,
                    source: "Demo"
                )
            ]
        }
        archive.records.readings.sort { $0.date > $1.date }
        archive.records.symptoms = [
            Symptom(
                text: t("Sore right knee after a walk", "Douleur au genou droit après une promenade"),
                onset: t("This morning", "Ce matin"),
                severity: "Mild",
                date: day(0, hour: 8)
            ),
            Symptom(
                text: t("Dry cough in the evening", "Toux sèche le soir"),
                onset: t("For three days", "Depuis trois jours"),
                severity: "Mild",
                date: day(-2)
            ),
            Symptom(
                text: t("Headache after a poor night's sleep", "Mal de tête après une mauvaise nuit"),
                onset: t("Yesterday", "Hier"),
                severity: "Moderate",
                date: day(-5)
            ),
            Symptom(
                text: t("Stiff shoulders", "Raideur aux épaules"),
                onset: t("After gardening", "Après le jardinage"),
                severity: "Mild",
                date: day(-12)
            )
        ]

        // Current visit: pending medicine review, source-linked follow-up and appointment.
        let highlight = t(
            "We reviewed your home blood pressure readings and your morning walks.",
            "Nous avons revu vos mesures de tension à domicile et vos promenades matinales."
        )
        let directions = t("10 mg once daily at 8 am", "10 mg une fois par jour à 8 h")
        let medicineQuote = t("Change amlodipine to \(directions).", "Modifiez l'amlodipine à \(directions).")
        let followUp = t(
            "Bring your blood pressure log to the follow-up visit.",
            "Apportez votre relevé de tension à la consultation de suivi."
        )
        let appointmentQuote = t(
            "Your follow-up appointment is in two weeks at 10 am at the demo clinic.",
            "Votre rendez-vous de suivi est dans deux semaines à 10 h à la clinique fictive."
        )
        var visit = DoctorVisit(
            title: t("Demo · Blood pressure follow-up", "Démo · Suivi de la tension"),
            date: day(-1),
            transcript: [highlight, medicineQuote, followUp, appointmentQuote].joined(separator: " ")
        )
        var summary = VisitSummary()
        summary.highlights = [VisitQuote(
            quote: highlight,
            text: t("Home readings and daily activity reviewed.", "Mesures à domicile et activité quotidienne revues.")
        )]
        var changed = amlodipine
        changed.instructions = directions
        summary.medicines = [VisitMedicineChange(
            action: .update,
            medicine: changed,
            quote: medicineQuote,
            frequency: MedicationFrequency(count: 1, period: .day),
            times: [DoseTime(hour: 8, minute: 0)]
        )]
        summary.followUps = [VisitQuote(quote: followUp, text: followUp)]
        summary.appointments = [VisitQuote(quote: appointmentQuote, text: appointmentQuote)]
        visit.summary = summary
        visit.medicineBaseline = archive.records.medicines

        let sleep = t(
            "We discussed sleep habits and knee stiffness after longer walks.",
            "Nous avons discuté du sommeil et de la raideur du genou après les longues promenades."
        )
        let next = t(
            "Write down when the knee discomfort occurs before your next visit.",
            "Notez quand la gêne au genou survient avant votre prochaine consultation."
        )
        var previous = DoctorVisit(
            title: t("Demo · Routine check-up", "Démo · Bilan de routine"),
            date: day(-21),
            transcript: sleep + " " + next
        )
        var previousSummary = VisitSummary()
        previousSummary.highlights = [VisitQuote(
            quote: sleep,
            text: t("Sleep and knee stiffness discussed.", "Sommeil et raideur du genou discutés.")
        )]
        previousSummary.followUps = [VisitQuote(quote: next, text: next)]
        previous.summary = previousSummary
        previous.medicineBaseline = archive.records.medicines

        let unknown = t(
            "Start salbutamol 2 puffs every 4 to 6 hours if needed for wheezing, maximum 8 puffs in 24 hours.",
            "Commencez le salbutamol à 2 bouffées toutes les 4 à 6 heures au besoin pour une respiration sifflante, maximum 8 bouffées en 24 heures."
        )
        var review = DoctorVisit(
            title: t("Demo · Medication review", "Démo · Révision des médicaments"),
            date: day(-8),
            transcript: unknown
        )
        var reviewSummary = VisitSummary()
        reviewSummary.highlights = [VisitQuote(
            quote: unknown,
            text: t("Inhaler instructions recorded for review.", "Consignes de l’inhalateur notées pour révision.")
        )]
        reviewSummary.unconfirmedMedicines = [VisitQuote(
            quote: unknown,
            text: "salbutamol: " + t(
                "2 puffs every 4 to 6 hours if needed for wheezing, maximum 8 puffs in 24 hours",
                "2 bouffées toutes les 4 à 6 heures au besoin pour une respiration sifflante, maximum 8 bouffées en 24 heures"
            )
        )]
        review.summary = reviewSummary
        review.medicineBaseline = archive.records.medicines
        archive.visits = [visit, review, previous]
        archive.records.appointments = [
            Appointment(
                title: t("Blood pressure follow-up", "Suivi de la tension"),
                date: day(13, hour: 10),
                location: t("Demo clinic", "Clinique fictive"),
                notes: followUp,
                visitID: visit.id,
                quote: appointmentQuote
            ),
            Appointment(
                title: t("Pharmacist medication review", "Révision des médicaments avec le pharmacien"),
                date: day(4, hour: 14),
                location: t("Demo pharmacy", "Pharmacie fictive")
            ),
            Appointment(
                title: t("Routine check-up", "Bilan de routine"),
                date: previous.date,
                location: t("Demo clinic", "Clinique fictive")
            )
        ]
        var care = CareData()
        care.schedules = [
            MedicineSchedule(
                medicineID: metformin.id,
                times: [DoseTime(hour: 8, minute: 0), DoseTime(hour: 18, minute: 0)],
                frequency: MedicationFrequency(count: 2, period: .day),
                refill: day(10)
            ),
            MedicineSchedule(
                medicineID: amlodipine.id,
                times: [DoseTime(hour: 8, minute: 0)],
                frequency: MedicationFrequency(count: 1, period: .day),
                refill: day(17)
            )
        ]
        for offset in -14 ... 0 {
            for schedule in care.schedules {
                let medicine = archive.records.medicines.first { $0.id == schedule.medicineID }!
                for time in schedule.times {
                    let scheduled = calendar.date(
                        bySettingHour: time.hour,
                        minute: time.minute,
                        second: 0,
                        of: day(offset)
                    )!

                    guard scheduled <= now else {
                        continue
                    }

                    let log = DoseLog(
                        medicineID: medicine.id,
                        scheduled: scheduled,
                        status: offset == -3 && time.hour == 18 ? .skipped : .taken,
                        date: scheduled.addingTimeInterval(120)
                    )
                    care.doses.append(log.preservingSource(medicine: medicine, time: time, calendar: calendar))
                }
            }
        }
        care.reminders = [
            CareReminder(title: followUp, due: day(12), visitID: visit.id, quote: followUp),
            CareReminder(
                title: t("Prepare questions for the pharmacist", "Préparer les questions pour le pharmacien"),
                due: day(3)
            ),
            CareReminder(
                title: t("Collect the blood pressure log", "Rassembler les mesures de tension"),
                due: day(-2),
                completed: true
            )
        ]
        care.questions = [
            AppointmentQuestion(
                text: t(
                    "Could my medicine timing affect my sleep?",
                    "L’heure de prise de mes médicaments pourrait-elle nuire à mon sommeil?"
                ),
                date: day(-1)
            ),
            AppointmentQuestion(
                text: t(
                    "What should I track about my knee discomfort?",
                    "Que devrais-je noter concernant la gêne au genou?"
                ),
                date: day(-2)
            )
        ]
        care.medicineEvents = [
            MedicineEvent(text: t("Added Metformin", "Ajout de la metformine"), date: day(-30)),
            MedicineEvent(text: t("Updated Amlodipine", "Modification de l’amlodipine"), date: day(-21))
        ]
        archive.care = care
        // Saved authored examples, never used to answer live chat requests.
        var question = ChatMessage(isUser: true, text: t("Show my recent readings.", "Montre mes mesures récentes."))
        question.date = day(-1, hour: 11)
        var answer = ChatMessage(
            text: t(
                "Here are the readings saved in this fictional demo.",
                "Voici les mesures enregistrées dans cette démo fictive."
            ),
            readings: Array(archive.records.readings.prefix(6))
        )
        answer.date = question.date.addingTimeInterval(1)
        archive.chatHistory = [ChatConversation(
            id: UUID(),
            title: t("Demo · Recent readings", "Démo · Mesures récentes"),
            messages: [question, answer],
            updated: answer.date
        )]

        return archive
    }
}

extension AppStore {
    /// Called only after explicit replacement confirmation. Keep the old archive
    /// and recording directory together if the protected archive write fails.
    @discardableResult func loadDemoData(now: Date = .now, french: Bool = L10n.isFrench) -> Bool {
        let next = DemoData.make(now: now, french: french)
        let oldAudio = visitAudioDirectory
        let stagedAudio = oldAudio.deletingLastPathComponent().appendingPathComponent("DemoReset-" + UUID().uuidString)
        let fm = FileManager.default
        let hasAudio = fm.fileExists(atPath: oldAudio.path)
        do {
            if hasAudio {
                try fm.moveItem(at: oldAudio, to: stagedAudio)
            }

            guard update({ $0 = next }) else {
                if hasAudio {
                    try fm.moveItem(at: stagedAudio, to: oldAudio)
                }

                return false
            }

            shareFile = nil
            error = nil
            for url in try fm.contentsOfDirectory(
                at: oldAudio.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            ) where url.lastPathComponent.hasPrefix("DemoReset-") {
                try fm.removeItem(at: url)
            }
            for url in try fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil)
                where url.lastPathComponent.hasPrefix("HarbourReport-") {
                try fm.removeItem(at: url)
            }
            for name in ["Harbour-records.json", "Harbour-visit.txt"] {
                let url = fm.temporaryDirectory.appendingPathComponent(name)
                if fm.fileExists(atPath: url.path) {
                    try fm.removeItem(at: url)
                }
            }

            return true
        } catch {
            self.error = L10n.format("Couldn’t finish replacing local data. %@", error.localizedDescription)

            return false
        }
    }
}
