import XCTest
@testable import HarbourCore

final class DoseReportRecordingClauseTests: XCTestCase {
    private var metformin: Medicine { Catalog.medicines.first { $0.id == "metformin" }! }

    func testCurrentNamedDoseReportsCanRequestRecordingOfThatSameEvent() throws {
        var records = Records(); records.medicines = [metformin]
        let reports: [(String, DoseStatus)] = [
            ("I took my Metformin dose this morning; record that dose.", .taken),
            ("I've swallowed my dose of Metformin at 8:35 am, please log it.", .taken),
            ("I skipped Metformin today and note this dose.", .skipped),
            ("I missed my Metformin dose. Record that intake.", .skipped),
            ("J'ai pris mon metformine ce matin; note cette prise.", .taken),
            ("J’ai avalé ma dose de metformine à 8 h 35, enregistrez cette dose.", .taken),
            ("J'ai omis ma dose de metformine aujourd'hui et consigne cette dose.", .skipped),
            ("J'ai sauté metformine ce soir; note-la.", .skipped)
        ]
        for (input, status) in reports {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .logDose, arg: "warfarin tomorrow"), original: input, records: records), .dose(metformin, status), input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .scheduleMedicine), original: input, records: records), input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .logDose), original: input, records: Records()), input)
        }
        // Established standalone status and snooze forms remain available.
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .logDose), original: "Mark Metformin taken.", records: records), .dose(metformin, .taken))
        XCTAssertEqual(try ToolPlanner.validate(.init(tool: .logDose), original: "Snooze my Metformin dose.", records: records), .dose(metformin, .later))
    }

    func testRecordingPronounsCannotSupplyMissingOrConflictingDoseAuthority() {
        var records = Records(); records.medicines = [metformin]
        for input in [
            "Record that dose.", "Note cette prise.",
            "I took my medicine this morning; record that dose.",
            "J'ai pris mon médicament ce matin; note cette prise.",
            "I took warfarin this morning; record that dose.",
            "I took Metformin yesterday; record that dose.",
            "Hier, j'ai pris metformine; note cette prise.",
            "My father took Metformin; record that dose.",
            "Mon père a pris metformine; note cette prise.",
            "If I took Metformin, record that dose.",
            "Si j'ai pris metformine, note cette prise.",
            "I did not take Metformin; record that dose.",
            "Je n'ai pas pris metformine; note cette prise.",
            "I took and skipped Metformin; record that dose.",
            "J'ai pris et sauté metformine; note cette prise.",
            "I took Metformin; record that dose as skipped.",
            "J'ai pris metformine; note cette dose comme omise.",
            "I took Metformin; record my warfarin dose.",
            "I took Metformin and warfarin; record that dose.",
            "J'ai pris metformine; note la prise de warfarine.",
            "I took Metformin; record that dose and delete my records.",
            "J'ai pris metformine; note cette prise et ajoute aspirine.",
            "I took Metformin; record that dose; open the camera.",
            "I took Metformin; do not record that dose.",
            "J'ai pris metformine; ne note pas cette prise.",
            "I took Metformin tomorrow; record that dose.",
            "I took Metformin at 27 am; record that dose.",
            "J'ai pris metformine à 8 h 99; note cette prise.",
            "I took Metformin; record that dose at 9 am.",
            "I took Metformin; record that dose?",
            "J'ai pris metformine; note cette prise ?",
            #"The note says "I took Metformin"; record that dose."#,
            "« J'ai pris metformine »; note cette prise.",
            "I took Metformin\nrecord that dose."
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .logDose, arg: "metformin taken"), original: input, records: records), input)
        }
    }
}
