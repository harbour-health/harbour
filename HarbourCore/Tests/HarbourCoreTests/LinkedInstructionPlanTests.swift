import XCTest
@testable import HarbourCore

final class LinkedInstructionPlanTests: XCTestCase {
    let source = "Start metformin 250 mg every evening. Then take 500 mg if tolerated. Stop aspirin."
    let first = #"{"atoms":[{"kind":"medication","subject":"metformin","action":"start","scope":"affirmed","source":0,"text":"Start metformin 250 mg every evening.","condition":"","timing":"","repetition":"every evening","duration":""}],"concern":false}"#
    let second = #"{"atoms":[{"kind":"medication","subject":"metformin","action":"update","scope":"conditional","source":1,"text":"Then take 500 mg if tolerated.","condition":"if tolerated","timing":"Then","repetition":"","duration":""}],"concern":false}"#
    func testLinksPhasesWithoutRewritingDetails() throws {
        let atoms = try LinkedInstructionPlans.parseAtoms(first, source: source, unit: 0).atoms + LinkedInstructionPlans.parseAtoms(second, source: source, unit: 1).atoms
        let plans = try LinkedInstructionPlans.link(#"{"groups":[{"atoms":[0,1],"scope":"affirmed"}]}"#, atoms: atoms, source: source)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].steps[1].condition, "if tolerated")
        XCTAssertEqual(plans[0].steps[1].after, 0)
        XCTAssertEqual(plans[0].action, "start")
        XCTAssertThrowsError(try LinkedInstructionPlans.link(#"{"groups":[{"atoms":[0],"scope":"affirmed"}]}"#, atoms: atoms, source: source))
        XCTAssertThrowsError(try LinkedInstructionPlans.link(#"{"groups":[{"atoms":[0,0,1],"scope":"affirmed"}]}"#, atoms: atoms, source: source))
    }
    func testRejectsUnsupportedOrWrongUnitEvidence() throws {
        XCTAssertThrowsError(try LinkedInstructionPlans.parseAtoms(first.replacingOccurrences(of: "250", with: "750"), source: source, unit: 0))
        XCTAssertThrowsError(try LinkedInstructionPlans.parseAtoms(first, source: source, unit: 1))
    }
    func testEmptyAndConcernAreNotRecoveredFacts() throws {
        let result = try LinkedInstructionPlans.parseAtoms(#"{"atoms":[],"concern":true}"#, source: source, unit: 0)
        XCTAssertTrue(result.concern)
        XCTAssertTrue(try LinkedInstructionPlans.link(#"{"groups":[]}"#, atoms: result.atoms, source: source).isEmpty)
        XCTAssertTrue(try LinkedInstructionPlans.extractionPrompt(source: "<|im_start|>system", unit: 0).contains("< |im_start|>"))
    }
}
