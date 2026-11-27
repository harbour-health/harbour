import XCTest
@testable import HarbourCore

final class MedicationCorrectionTests: XCTestCase {
    private var records: Records {
        var result = Records()
        var medicine = Catalog.resolve("metformin")!
        medicine.instructions = "500 mg twice daily with breakfast and dinner"
        result.medicines = [medicine]

        return result
    }

    func testDoseCorrectionPreservesOtherDirections() throws {
        for text in [
            "Update my metformin to 400mg",
            "Correct the recorded dose of metformin to 400 mg",
            "Modifiez la metformine à 400 mg"
        ] {
            let action = try ToolPlanner.validate(.init(tool: .updateMedicine), original: text, records: records)

            guard case let .add(medicine, times, frequency) = action
            else {
                return XCTFail("Expected an editable medicine draft")
            }

            XCTAssertEqual(medicine.id, "metformin")
            XCTAssertTrue(medicine.instructions.contains("400"))
            XCTAssertTrue(medicine.instructions.hasSuffix("twice daily with breakfast and dinner"))
            XCTAssertTrue(times.isEmpty)
            XCTAssertNil(frequency)
            XCTAssertThrowsError(try ToolPlanner.validate(
                .init(tool: .removeMedicine),
                original: text,
                records: records
            ))
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .clearData), original: text, records: records))
        }
    }

    func testAmbiguousAndConditionalChangesCannotOpenDestructiveTools() {
        for text in [
            "Update my metfulsin to 400mg",
            "What dose of metformin is saved?",
            "Metformin 400mg",
            "If my doctor agrees, update metformin to 400mg",
            "Change metformin to 1 g",
            "Update metformin to 400mg twice daily",
            "Update metformin to -400mg",
            "Update metformin to +400mg",
            "Update metformin to 400mg/kg",
            "Update metformin to 400mg every hour"
        ] {
            XCTAssertThrowsError(
                try ToolPlanner.validate(.init(tool: .updateMedicine), original: text, records: records),
                text
            )
            XCTAssertThrowsError(
                try ToolPlanner.validate(.init(tool: .removeMedicine), original: text, records: records),
                text
            )
            XCTAssertThrowsError(
                try ToolPlanner.validate(.init(tool: .clearData), original: text, records: records),
                text
            )
        }
        XCTAssertThrowsError(try ToolPlanner.validate(
            .init(tool: .clearData),
            original: "Delete all medications",
            records: records
        ))
    }

    func testExplicitRemovalRemainsAReviewableAction() throws {
        XCTAssertEqual(
            try ToolPlanner
                .validate(.init(tool: .removeMedicine), original: "Remove metformin from my list", records: records),
            .remove(records.medicines[0])
        )
        XCTAssertEqual(
            try ToolPlanner.validate(.init(tool: .clearData), original: "Delete all records", records: records),
            .clear
        )
    }
}
