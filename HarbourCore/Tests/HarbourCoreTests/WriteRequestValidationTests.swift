import XCTest
@testable import HarbourCore

final class WriteRequestValidationTests: XCTestCase {
    private var records: Records { var records = Records(); records.medicines = [Catalog.medicines.first { $0.id == "metformin" }!]; return records }

    func testNegatedRecordingAndReminderRequestsCannotOpenWriteActions() {
        let cases: [(Tool, String)] = [
            (.captureSymptom, "Do not record the sore shoulder."),
            (.captureSymptom, "N'enregistre pas ma douleur au dos."),
            (.logReading, "Never save my temperature of 37.1."),
            (.logReading, "Ne note pas mon pouls de 84."),
            (.createReminder, "Don't create a reminder to call the clinic."),
            (.createReminder, "Ne créez pas de rappel pour appeler la clinique."),
            (.saveQuestion, "Do not save this question: Should I bring my notes?"),
            (.saveQuestion, "N'enregistre pas cette question : Dois-je apporter mes notes?"),
            (.importReadings, "Do not import Apple Health readings."),
            (.importReadings, "N'importe pas mes relevés Apple Santé.")
        ]
        for (tool, original) in cases {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: tool), original: original, records: records), original)
        }
    }

    func testQuotedStatementsAndReportsCannotAuthorizeAnyWrite() {
        let cases: [(Tool, String)] = [
            (.captureSymptom, #"The note says "record a sore ankle"."#),
            (.captureSymptom, "‘Record my shoulder pain.’"),
            (.logReading, "The example is 'Log my pulse of 81.'"),
            (.logReading, "La note dit « Enregistre mon pouls de 81. »"),
            (.captureSymptom, "'My shoulder doesn't hurt.'"),
            (.captureSymptom, "Ma sœur a une douleur au bras."),
            (.logReading, "My father has a pulse of 81."),
            (.logDose, "Mon père a pris metformine."),
            (.addMedicine, "My doctor said to add Metformin."),
            (.clearData, #"The button label is "delete all records"."#)
        ]
        for (tool, original) in cases {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: tool), original: original, records: records), original)
        }
    }

    func testHypotheticalAndConceptualQuestionsCannotAuthorizeWrites() {
        let cases: [(Tool, String)] = [
            (.captureSymptom, "Suppose I had a sore shoulder."),
            (.captureSymptom, "Please imagine I have a sore wrist."),
            (.captureSymptom, "S'il vous plaît, imaginez que j'ai mal au poignet."),
            (.captureSymptom, "Et si j'avais mal au bras?"),
            (.captureSymptom, "What does shoulder pain mean?"),
            (.logReading, "What if my pulse were 81?"),
            (.logReading, "Pourquoi mon pouls serait-il de 81?"),
            (.createReminder, "Would a reminder to call the clinic help?"),
            (.saveQuestion, "Should I ask my doctor about sleep?"),
            (.scheduleMedicine, "Could Metformin be scheduled at 9 am?"),
            (.logDose, "Hypothetically, I took Metformin.")
        ]
        for (tool, original) in cases {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: tool), original: original, records: records), original)
        }
    }

    func testAffirmativeOuterQuestionRequestsPreserveQuotedMedicalContent() throws {
        for original in [
            #"Save this question for my doctor: "Should I avoid this medicine if my mother has a rash?""#,
            "Enregistre cette question pour mon médecin : « Ne devrais-je pas éviter ce médicament? »"
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .saveQuestion), original: original, records: records), .question(CareRules.question(from: original)))
        }
    }

    func testAffirmativeReminderRequestsPreserveConditionalOrNegativePayloads() throws {
        for original in [
            "Remind me not to forget the appointment if it rains.",
            "Rappelle-moi de ne pas oublier d'appeler la clinique si je me sens moins bien.",
            "Please create a reminder to ask why my brother should not take this medicine."
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .createReminder), original: original, records: records), .reminder(original))
        }
    }

    func testGenuineRecordingRequestsAndObservationsRemainAvailable() throws {
        for original in ["My shoulder hurts after walking.", "J'ai mal au bras depuis vendredi.", #"Please record this symptom: "My ankle aches.""#] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .captureSymptom), original: original, records: records), .symptom(original))
        }
        for original in ["Could you record my pulse of 81?", "Peux-tu enregistrer mon pouls de 81?", "Mon pouls est de 81."] {
            guard case .reading(let reading) = try ToolPlanner.validate(.init(tool: .logReading), original: original, records: records) else { return XCTFail(original) }
            XCTAssertEqual(reading.value, "81")
        }
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .clearData), original: "Please erase all my records", records: records), .clear)
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .importReadings), original: "Synchronise Apple Santé", records: records), .importHealth)
    }

    func testNegatedNumericObservationIsNotAReading() {
        for original in ["My pulse is not 81.", "Mon pouls n'est pas de 81."] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .logReading), original: original, records: records), original)
        }
    }

    func testScheduleRequiresExplicitValidTimesInTheOriginalRequest() throws {
        for original in ["Schedule Metformin", "Schedule Metformin in the morning", "Programme metformine à 28 h", "Programme metformine à 9 h 99"] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .scheduleMedicine, arg: "9 am"), original: original, records: records), original)
        }
        let medicine = records.medicines[0]
        for original in ["Schedule Metformin at 9 am and 9 pm", "Programme metformine à 9 h et 21 h"] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .scheduleMedicine), original: original, records: records), .schedule(medicine, [DoseTime(hour: 9, minute: 0), DoseTime(hour: 21, minute: 0)]))
        }
    }

    func testIndividualDeleteRequestsCannotBecomeClearAllProposals() throws {
        for original in ["Delete Metformin", "Delete the last reading", "Efface mon dernier relevé", "Delete all records about Metformin", "Delete all readings"] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .clearData), original: original, records: records), original)
        }
        for original in ["Clear all my records", "Efface toutes mes données", "Reset Harbour", "Réinitialise l'application"] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .clearData), original: original, records: records), .clear)
        }
    }

    func testWholeRecordRequestsAcceptEnglishAndFrenchNounNumber() throws {
        for original in ["Erase every record in this app.", "Supprimez tous les dossiers dans cette application.", "Efface tous mes enregistrements."] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .clearData), original: original, records: records), .clear)
        }
    }

    func testPoliteModalRequestsAndFrenchObjectPronounsRemainAvailable() throws {
        for original in ["Could you please record my pulse of 81?", "Peux-tu s'il te plaît me noter un pouls de 81?"] {
            guard case .reading(let reading) = try ToolPlanner.validate(.init(tool: .logReading), original: original, records: records) else { return XCTFail(original) }
            XCTAssertEqual(reading.value, "81", original)
        }
        for original in ["Pouvez-vous me rappeler d’appeler la clinique?", "Pourriez-vous s'il vous plaît nous rappeler de préparer les documents?"] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .createReminder), original: original, records: records), .reminder(original))
        }
        for original in ["Could you please not record my pulse of 81?", "Pouvez-vous ne pas me rappeler d’appeler la clinique?"] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .logReading), original: original, records: records), original)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createReminder), original: original, records: records), original)
        }
    }

    func testScopedDeletionCannotBroadenToTheWholeArchive() {
        for original in [
            "Delete all records from yesterday.", "Delete all records dated 2026-08-11.",
            "Delete all records about my knee.", "Delete all records except medicines.",
            "Delete all records but only the readings.", "Reset only the reminders in this app.",
            "Efface tous mes dossiers d'hier.", "Efface toutes mes données du 3 mai.",
            "Supprime tous les dossiers concernant mon genou.", "Efface tout sauf les médicaments.",
            "Efface tous les dossiers mais seulement les relevés.", "Réinitialise uniquement les rappels dans cette application."
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .clearData), original: original, records: records), original)
        }
    }

    func testWholeArchiveDeletionAllowsAppAndHealthDomainQualifiers() throws {
        for original in [
            "Clear all records from this app.", "Erase every record in this app.",
            "Clear all health data from Harbour.", "Clear all my records, please.",
            "Efface toutes mes données de santé.", "Supprimez tous les dossiers dans cette application.",
            "Efface tous les enregistrements de l'application.", "Efface toutes mes données de santé dans cette application.",
            "Reset the entire app.", "Réinitialise toute l'application."
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .clearData), original: original, records: records), .clear, original)
        }
    }
}
