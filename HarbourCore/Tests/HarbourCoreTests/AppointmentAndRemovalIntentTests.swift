import Foundation
import XCTest
@testable import HarbourCore

final class AppointmentAndRemovalIntentTests: XCTestCase {
    private var medicine: Medicine { Catalog.medicines.first { $0.id == "metformin" }! }
    private var records: Records { var value = Records(); value.medicines = [medicine]; return value }

    func testAppointmentDocumentationWithOfDeAndQualifiedTargetsCannotCreateAppointments() throws {
        for original in [
            "Make a summary of my appointment.",
            "Create a detailed summary of my last dentist appointment.",
            "Write notes about my next cardiology appointment.",
            "Prepare a summary of Dr. Smith's appointment.",
            "Prépare un résumé de mon rendez-vous.",
            "Crée un bref résumé du dernier rendez-vous.",
            "Prépare un compte-rendu de ma dernière consultation.",
            "Prépare un résumé d'une prochaine consultation."
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createAppointment), original: original, records: records), original)
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .appointmentNote), original: original, records: records), .note, original)
        }
    }

    func testGenuineAppointmentRequestsKeepTheirOwnTrailingNotes() throws {
        for original in [
            "Add my dentist appointment Tuesday at 2 pm.",
            "Enregistre mon rendez-vous mardi à 14 h.",
            "Add my appointment Tuesday; notes: bring my test results.",
            "Add my appointment Tuesday; summary: bring my test results.",
            "Add my appointment Tuesday; notes: bring a summary of my last appointment.",
            "Enregistre mon rendez-vous mardi; notes : apporter un résumé du dernier rendez-vous."
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .createAppointment), original: original, records: records), .appointment(original), original)
        }
        for original in [
            #"The example says "Make a summary of my appointment.""#,
            "Maybe create an appointment summary.",
            "My doctor asked for a summary of my appointment.",
            "Record my reading; notes: bring a summary of my appointment."
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createAppointment), original: original, records: records), original)
        }
    }

    func testRemovalCannotDiscardAnApprovalConditionWhereverItAppears() {
        for original in [
            "Remove Metformin if my doctor approves.",
            "If my doctor approves, remove Metformin.",
            "Remove Metformin unless my doctor objects.",
            "Delete Metformin provided my pharmacist agrees.",
            "Please remove Metformin after my consultation.",
            "Retire la metformine si mon médecin approuve.",
            "Si mon médecin approuve, retire la metformine.",
            "Retire la metformine à condition que mon médecin approuve.",
            "Supprime la metformine après mon rendez-vous.",
            "Retire la metformine s'il donne son accord.",
            "Retire la metformine, sauf si mon médecin la maintient.",
            #"Remove Metformin "if my doctor approves"."#
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .removeMedicine), original: original, records: records), original)
        }
    }

    func testDirectRemovalStillRequiresOneSavedMedicineAndKeepsCourtesy() throws {
        for original in [
            "Remove Metformin.", "Please remove Metformin from my list.",
            "Retire la metformine.", "Retire la metformine, s'il vous plaît.",
            #"Remove "Metformin" from my list."#,
            "Retire « metformine » de ma liste."
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .removeMedicine), original: original, records: records), .remove(medicine), original)
        }
        for original in [
            "Do not remove Metformin.", "Ne retire pas la metformine.",
            #"The note says "Remove Metformin.""#,
            "My doctor said to remove Metformin."
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .removeMedicine), original: original, records: records), original)
        }
        XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .removeMedicine), original: "Remove Metformin.", records: Records()))
        var two = records
        two.medicines.append(Catalog.medicines.first { $0.id == "warfarin" }!)
        XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .removeMedicine), original: "Remove Metformin and Warfarin.", records: two))
    }

    func testPoliteAppointmentCommandsPrepareDraftsButAreNotTranscriptFacts() throws {
        for original in [
            "Could you record my dentist appointment Tuesday at 2 pm?",
            "Could you record my dentist appointment Tuesday at 2 pm.",
            "Can you record my appointment tomorrow?",
            "Would you please add my appointment tomorrow?",
            "Could you add my appointment Tuesday; notes: bring my test results?",
            "Please can you book me an appointment tomorrow?",
            "Peux-tu enregistrer mon rendez-vous mardi à 14 h ?",
            "Pourriez-vous s'il vous plaît enregistrer mon rendez-vous demain à 14 h ?",
            "Est-ce que vous pouvez enregistrer une consultation jeudi à 15 h ?"
        ] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .createAppointment, arg: "invented Friday at 4 pm"), original: original, records: records), .appointment(original), original)
        }
        for original in [
            "Could you record my dentist appointment Tuesday at 2 pm?",
            "Peux-tu enregistrer mon rendez-vous mardi à 14 h ?"
        ] {
            XCTAssertFalse(AppointmentRules.isAppointment(original), "A polite request must not become an asserted transcript fact: \(original)")
            XCTAssertTrue(AppointmentRules.quotes(in: original).isEmpty, original)
        }
    }

    func testPoliteWrapperCannotAuthorizeSpeculationDocumentationOrAdditionalActions() {
        for original in [
            "Could you record my appointment if my doctor approves?",
            "Could you book my appointment unless my doctor objects?",
            "Peux-tu enregistrer mon rendez-vous si le médecin confirme ?",
            "Pourriez-vous enregistrer mon rendez-vous s'il est confirmé ?",
            "Could you record my appointment that might happen tomorrow?",
            "Can I have an appointment on Friday?",
            "Should I book an appointment tomorrow?",
            "Could my doctor record an appointment tomorrow?",
            "Could you record a summary of my appointment?",
            "Peux-tu préparer un résumé de mon rendez-vous ?",
            "Could you record my appointment tomorrow and remove Metformin?",
            "Could you record my appointment tomorrow and stop Metformin?",
            "Could you record my appointment tomorrow and remind me to call the clinic?",
            "Could you record my appointment tomorrow and reset the app?",
            "Peux-tu enregistrer mon rendez-vous demain et supprimer la metformine ?",
            "Peux-tu enregistrer mon rendez-vous demain et arrêter la metformine ?",
            "Peux-tu enregistrer mon rendez-vous demain et rappelle-moi d'appeler la clinique ?",
            "Could you record my appointment tomorrow; export my records?",
            "Could you record my appointment tomorrow, remove Metformin?",
            "Peux-tu enregistrer mon rendez-vous demain et veuillez supprimer la metformine ?",
            "Could you record my appointment Tuesday or Wednesday?",
            #"Could you record "my appointment tomorrow"?"#,
            "Could you not record my appointment tomorrow?"
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .createAppointment), original: original, records: records), original)
        }
    }
}
