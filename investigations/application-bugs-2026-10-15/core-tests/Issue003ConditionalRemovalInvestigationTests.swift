import XCTest
@testable import HarbourCore

/// Characterizes HEAD 5158710, including the defect; passing is not a fix.
final class Issue003ConditionalRemovalReproductionTests: XCTestCase {
    private var medicine: Medicine { Catalog.medicines.first { $0.id == "metformin" }! }
    private var records: Records { var result = Records(); result.medicines = [medicine]; return result }

    func testTrailingApprovalConditionCurrentlyBecomesUnconditionalRemovalAction() throws {
        for input in [
            "Remove Metformin if my doctor approves.",
            "Retire la metformine si mon médecin approuve."
        ] {
            let originalRecords = records
            XCTAssertTrue(WriteRequestValidation.permits(input, tool: .removeMedicine), input)
            let action = try ToolPlanner.validate(.init(tool: .removeMedicine), original: input, records: originalRecords)
            XCTAssertEqual(action, .remove(medicine), input)
            XCTAssertNil(ToolPlanner.replyFallback(original: input, records: originalRecords), input)
            XCTAssertEqual(originalRecords, records, "Validation returns an action without changing storage")
            guard case .remove(let selected) = action else { return XCTFail("Expected current erroneous removal action") }
            XCTAssertEqual(selected, medicine, "The action carries the medicine, not the conditional request")
        }
    }

    func testEquivalentLeadingConditionsAreRejected() {
        for input in [
            "If my doctor approves, remove Metformin.",
            "Si mon médecin approuve, retire la metformine."
        ] {
            XCTAssertFalse(WriteRequestValidation.permits(input, tool: .removeMedicine), input)
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .removeMedicine), original: input, records: records), input)
        }
    }

    func testDirectRemovalStillAllowedAndNegativeQuotedOrReportedRequestsRejected() throws {
        for input in ["Remove Metformin.", "Retire la metformine."] {
            XCTAssertEqual(try ToolPlanner.validate(.init(tool: .removeMedicine), original: input, records: records), .remove(medicine), input)
        }
        for input in [
            "Do not remove Metformin.",
            "Ne retire pas la metformine.",
            #"The note says "Remove Metformin.""#,
            "My doctor said to remove Metformin."
        ] {
            XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .removeMedicine), original: input, records: records), input)
        }
    }

    func testSavedIdentityAndSingleMedicineRequirementsStillApply() {
        XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .removeMedicine), original: "Remove Metformin if my doctor approves.", records: Records()))
        XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .removeMedicine), original: "Remove Warfarin.", records: records))
        var two = records
        two.medicines.append(Catalog.medicines.first { $0.id == "warfarin" }!)
        XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .removeMedicine), original: "Remove Metformin and Warfarin.", records: two))
    }
}
