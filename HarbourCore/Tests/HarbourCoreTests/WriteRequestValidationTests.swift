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

    func testMedicineAddRejectsDoseReportsAndBareNames() throws {
        for original in [
            "I took Metformin.", "I have taken Metformin.", "I take Metformin daily.",
            "J'ai pris metformine.", "Je prends metformine chaque jour.",
            "Metformin", "metformine", "Should I start Metformin?", "Dois-je commencer metformine ?",
            "Do not add Metformin.", "N'ajoute pas metformine.",
            #"The note says "Add Metformin.""#, "La note dit « Ajoute metformine. »"
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .addMedicine, arg: "metformin"), original: original, records: records), original)
        }
        let medicine = records.medicines[0]
        for original in ["I took Metformin.", "J'ai pris metformine."] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .logDose), original: original, records: records), .dose(medicine, .taken), original)
        }
    }

    func testAffirmativeMedicineAddRequestsRetainIdentityAndRoutingAlternatives() throws {
        let medicine = records.medicines[0]
        for original in [
            "Add Metformin to my medication list.", "Could you please add Metformin?",
            "Put Metformin on my list.", "Start Metformin.", "Begin Metformin.",
            "Ajoute metformine à ma liste de médicaments.", "Pourriez-vous ajouter metformine ?",
            "Commence metformine.", "Débute metformine.", "Enregistre metformine."
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .addMedicine, arg: "warfarin"), original: original, records: records), .add(medicine, [], nil), original)
            let prompt = ToolPlanner.prompt(original, records: records)
            for tool in Tool.allCases { XCTAssertTrue(prompt.contains(tool.rawValue), "\(original): \(tool.rawValue)") }
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

    func testScheduleRequiresExplicitValidTimesOrFrequencyInTheOriginalRequest() throws {
        for original in ["Schedule Metformin", "Schedule Metformin in the morning", "Programme metformine à 28 h", "Programme metformine à 9 h 99"] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .scheduleMedicine, arg: "9 am"), original: original, records: records), original)
        }
        let medicine = records.medicines[0]
        for original in ["Schedule Metformin at 9 am and 9 pm", "Programme metformine à 9 h et 21 h"] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .scheduleMedicine), original: original, records: records), .schedule(medicine, [DoseTime(hour: 9, minute: 0), DoseTime(hour: 21, minute: 0)], MedicationFrequency(count: 2, period: .day)))
        }
    }

    func testAppointmentWritesRejectQuotedReportsWhilePreservingAffirmativeRequests() throws {
        for original in [
            "Record my optometrist appointment Thursday at 11 am.",
            "Enregistre mon rendez-vous chez l'optométriste jeudi à 11 h."
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .createAppointment, arg: "an invented date"), original: original, records: records), .appointment(original), original)
        }
        for original in [
            #"The example says "Add an optometrist appointment Thursday.""#,
            "L'exemple dit « Ajoute un rendez-vous jeudi. »",
            "My brother has an optometrist appointment Thursday at 11 am.",
            "Ma sœur a un rendez-vous jeudi à 11 h."
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createAppointment), original: original, records: records), original)
        }
    }

    func testAppointmentNotePreparationCannotAuthorizeAnAppointmentWrite() throws {
        for original in [
            "Make an appointment note", "Create appointment notes for my doctor.",
            "Prepare notes for my appointment.", "Write a question about the appointment.",
            "Crée une note pour mon rendez-vous.", "Prépare un compte rendu pour la consultation.",
            "Ajoute une question pour mon rendez-vous."
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createAppointment), original: original, records: records), original)
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .appointmentNote), original: original, records: records), .note, original)
        }
        for original in [
            "Add my dentist appointment Tuesday at 2 pm.",
            "Enregistre mon rendez-vous mardi à 14 h.",
            "Add my appointment Tuesday; notes: bring my test results."
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .createAppointment), original: original, records: records), .appointment(original), original)
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

    func testWholeArchiveDeletionAllowsSavedModifiersAroundDomainAndLocation() throws {
        for original in [
            "Erase all records saved in this app.", "Delete all my stored health records.",
            "Clear every record recorded within Harbour.", "Erase all records in this app, please.",
            "Effacez toutes mes données de santé enregistrées.",
            "Supprimez tous les dossiers sauvegardés dans cette application.",
            "Efface toutes mes données stockées de santé dans Harbour.",
            "Efface tout enregistré dans l'application."
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .clearData), original: original, records: records), .clear, original)
        }
    }

    func testSavedModifiersCannotAuthorizeADeletionSubset() {
        for original in [
            "Delete all records saved yesterday.", "Delete all records stored about my knee.",
            "Delete all records saved in this app except medicines.",
            "Delete all stored health records but only the readings.",
            "Efface toutes mes données de santé enregistrées hier.",
            "Efface tous mes dossiers sauvegardés du 3 mai.",
            "Supprime tous les dossiers enregistrés concernant mon genou.",
            "Efface toutes mes données stockées dans cette application sauf les médicaments."
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .clearData), original: original, records: records), original)
        }
    }

    func testNamedMedicineRegistrationCommandsGeneralizeWithoutAuthorizingReportsOrQuotes() throws {
        let medicine = records.medicines[0]
        for input in [
            "Register Metformin on my medicine list.", "Please include Metformin in my saved medicines.",
            "Inscris metformine dans ma liste.", "Inscrivez metformine dans mes médicaments enregistrés.",
            "Pourriez-vous inscrire metformine dans ma liste de médicaments ?"
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .addMedicine, arg: "aspirin"), original: input, records: records), .add(medicine, [], nil), input)
        }
        for input in [
            "Do not register Metformin.", "N'inscrivez pas metformine.",
            "If I ask, include Metformin.", "Si je le demande, inscris metformine.",
            "My doctor said to register Metformin.", "Mon frère a inscrit metformine.",
            "I registered Metformin yesterday.", "J'ai inscrit metformine hier.",
            #"The note says "Register Metformin.""#, "La note dit « Inscrivez metformine. »",
            "Could I register Metformin?", "Devrais-je inscrire metformine ?",
            "Inscrivez le comprimé sans nom.", "Inscris metformine et aspirine."
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .addMedicine), original: input, records: records), input)
        }
    }

    func testHealthImportAndMedicineCameraRequestsCannotAuthorizeEachOthersFlows() throws {
        let imports = [
            "Import my readings from Apple Health.", "Could you sync Apple Health?",
            "Synchronize my measurements.", "Synchronise Apple Santé",
            "Importe mes relevés Apple Santé.", "Veuillez importer mes mesures depuis Apple Santé.",
            "Sync Health.", "Importe mes données de Santé (app)."
        ]
        let scans = [
            "Scan my medicine label.", "Read the medication label.", "Open the camera.",
            "Take a photo of the medicine label.", "Scanne l'étiquette du médicament.",
            "Photographiez la boîte de mon médicament.", "Ouvre l'appareil photo."
        ]
        for input in imports {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .importReadings, arg: "camera"), original: input, records: records), .importHealth, input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .scanMedicine), original: input, records: records), input)
        }
        for input in scans {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .scanMedicine, arg: "import"), original: input, records: records), .scan, input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .importReadings), original: input, records: records), input)
        }
        for input in [
            "Do not scan my medicine label.", "Ne scanne pas l'étiquette du médicament.",
            "Do not import my readings.", "N'importe pas mes mesures Apple Santé.",
            "How do I scan a medicine label?", "Comment importer mes mesures ?",
            "My sister wants to scan a medicine label.", "Mon père veut importer Apple Santé.",
            "If I ask, open the camera.", "Si je le demande, importe mes mesures.",
            #""Open the camera.""#, "« Importe Apple Santé. »",
            "Import my readings and open the camera.", "Scanne l'étiquette puis importe mes mesures.",
            "Import the medicine label.", "Scan Apple Health.",
            "Import my bank data.", "Ouvre mes données Apple Santé."
        ] {
            for tool in [Tool.importReadings, .scanMedicine] {
                XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: tool), original: input, records: records), "\(tool): \(input)")
            }
        }
    }

    func testCurrentDoseStatusesAndFutureSchedulesKeepDistinctSourceIntent() throws {
        let medicine = records.medicines[0]
        let doses: [(String, DoseStatus)] = [
            ("I took my Metformin dose today at 7:15 am.", .taken),
            ("I swallowed my scheduled Metformin.", .taken),
            ("I've taken Metformin.", .taken),
            ("I have skipped my dose of Metformin this morning.", .skipped),
            ("Please mark Metformin as taken.", .taken),
            ("Could you record my Metformin dose as skipped?", .skipped),
            ("J'ai pris ma dose de metformine aujourd'hui à 7 h 15.", .taken),
            ("J'ai avalé metformine.", .taken),
            ("J’ai sauté ma dose de metformine ce matin.", .skipped),
            ("Marquez ma dose de metformine comme prise.", .taken),
            ("Pourriez-vous marquer metformine comme sautée ?", .skipped),
            ("Snooze my Metformin dose.", .later),
            ("Remind me later for Metformin.", .later),
            ("Reporte ma dose de metformine.", .later),
            ("Rappelle plus tard pour metformine", .later)
        ]
        for (input, status) in doses {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .logDose, arg: "invented status"), original: input, records: records), .dose(medicine, status), input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .scheduleMedicine), original: input, records: records), input)
        }
        for input in [
            "Set Metformin at 7:15 am and 7:15 pm.",
            "Pourriez-vous programmer metformine à 7 h 15 et 19 h 15 ?"
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .scheduleMedicine, arg: "taken"), original: input, records: records), .schedule(medicine, [DoseTime(hour: 7, minute: 15), DoseTime(hour: 19, minute: 15)], MedicationFrequency(count: 2, period: .day)), input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .logDose), original: input, records: records), input)
        }
    }

    func testDoseAndScheduleSourceCompatibilityRejectsHistoryQuotesConditionsAndMixedActions() {
        for input in [
            "I took Metformin yesterday at 7 am.", "Hier, j'ai pris metformine à 7 h.",
            "My father took Metformin at 7 am.", "Mon père a pris metformine à 7 h.",
            "If I took Metformin at 7 am, mark it taken.", "Si j'ai pris metformine, marque-la comme prise.",
            "I did not take Metformin at 7 am.", "Je n'ai pas pris metformine à 7 h.",
            "Did I take Metformin at 7 am?", "J'ai pris metformine ?",
            #"The note says "I took Metformin at 7 am.""#, "« Programme metformine à 7 h. »",
            "Schedule Metformin as taken at 7 am.", "Programme metformine comme prise à 7 h.",
            "Mark Metformin taken tomorrow.", "Marque metformine comme prise demain.",
            "I took Metformin at 27 am.", "J'ai pris metformine à 7 h 99.",
            "I took and skipped Metformin.", "J'ai pris et sauté metformine.",
            "Mark Metformin taken and delete my records.", "Marque metformine comme prise et efface mes données.",
            "I took Metformin at 7 am. Schedule it daily.",
            "J'ai pris metformine à 7 h. Programme-la deux fois par jour."
        ] {
            for tool in [Tool.logDose, .scheduleMedicine] {
                XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: tool), original: input, records: records), "\(tool): \(input)")
            }
        }
    }

    func testMedicineCameraPurposeClausesCannotAuthorizeImportOrMixedActions() throws {
        for input in [
            "Open the camera to scan a medication label.",
            "Use my camera to read the medicine label.",
            "Ouvre l'appareil photo pour scanner une boîte de médicament.",
            "Ouvrez l'appareil photo pour lire l'étiquette du médicament."
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .scanMedicine), original: input, records: records), .scan, input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .importReadings), original: input, records: records), input)
        }
        for input in [
            "Do not open the camera to scan a medication label.",
            "N'ouvre pas l'appareil photo pour scanner une boîte de médicament.",
            "Why open the camera to scan a medication label?",
            "Si je le demande, ouvre l'appareil photo pour lire l'étiquette du médicament.",
            "My father wants to open the camera to scan a medication label.",
            #""Open the camera to scan a medication label.""#,
            "Open the camera to import my readings.",
            "Ouvre l'appareil photo pour importer mes mesures Apple Santé.",
            "Open the camera to scan a medication label and add Aleve.",
            "Ouvre l'appareil photo pour scanner une boîte de médicament puis efface mes données.",
            "Open the camera to scan a medication label unless I object."
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .scanMedicine), original: input, records: records), input)
        }
    }

    func testProviderFirstImportsAcceptDeterminersWithoutAuthorizingOtherEntryFlows() throws {
        for input in [
            "Please synchronize the Apple Health measurements.",
            "Could you import my Apple Health data?",
            "Import my measurements from the Health app.",
            "Veuillez synchroniser mes relevés depuis Apple Santé.",
            "Importez les données de l'application Santé."
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .importReadings, arg: "camera"), original: input, records: records), .importHealth, input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .scanMedicine), original: input, records: records), input)
        }
        for input in [
            "Do not import my Apple Health data.",
            "N'importez pas les données Apple Santé.",
            "If I ask later, synchronize my Apple Health measurements.",
            "Si je le demande, importe mes relevés Apple Santé.",
            "How can I import my Apple Health measurements?",
            "My father wants to import Apple Health data.",
            "I imported my Apple Health readings yesterday.",
            #"The example says "Import my Apple Health data.""#,
            "« Importez les données Apple Santé. »",
            "Import my Apple Health data and open the camera.",
            "Importez mes données Apple Santé puis effacez mes dossiers.",
            "Import my Apple Health data unless I object.",
            "Import my bank data.", "Import this medication label.",
            "Scan my Apple Health measurements."
        ] {
            for tool in [Tool.importReadings, .scanMedicine] {
                XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: tool), original: input, records: records), "\(tool): \(input)")
            }
        }
    }

    func testLabelScanInstrumentsAndPhotoPurposesKeepWholeRequestScope() throws {
        for input in [
            "Please read that medication label using my camera.",
            "Photograph this pill label with the camera.",
            "Veuillez numériser cette boîte de médicament avec la caméra.",
            "Lisez cette étiquette avec mon appareil photo.",
            "Open my photo so I can read a medication label.",
            "Use this picture to scan the medicine label.",
            "Open the image so that we can photograph the pill label.",
            "Ouvrez cette photo pour numériser une étiquette de médicament.",
            "Utilise ma photo afin de lire la boîte du médicament.",
            "Ouvre la caméra pour lire cette étiquette."
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .scanMedicine, arg: "import"), original: input, records: records), .scan, input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .importReadings), original: input, records: records), input)
        }
        for input in [
            "Do not read that medication label using my camera.",
            "Ne numérisez pas cette boîte avec la caméra.",
            "If I ask later, open my photo to read the medicine label.",
            "Si je le demande, numérise cette étiquette avec la caméra.",
            "How can I scan this medication label?",
            "Comment numériser cette boîte avec la caméra ?",
            "My father wants to open my photo to scan the label.",
            "Mon père veut numériser cette étiquette.",
            "I scanned this label with my camera yesterday.",
            "J'ai numérisé cette boîte hier.",
            #"The example says "Open my photo to scan the medicine label.""#,
            "« Numérisez cette étiquette avec la caméra. »",
            "Scan the label with the camera unless I object.",
            "Ouvrez cette photo pour lire le médicament puis effacez mes données.",
            "Open my photo to scan the label and add Aleve.",
            "Read this medication label using my camera and import my readings.",
            "Open my photo to import Apple Health measurements.",
            "Ouvre cette image pour importer mes relevés.",
            "Open my photo.", "Use this picture to read a bank statement.",
            "Scan Apple Health data.", "Import the medicine label."
        ] {
            for tool in [Tool.importReadings, .scanMedicine] {
                XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: tool), original: input, records: records), "\(tool): \(input)")
            }
        }
    }
}
