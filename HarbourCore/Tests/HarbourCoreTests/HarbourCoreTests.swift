import XCTest
@testable import HarbourCore

final class HarbourCoreTests: XCTestCase {
    func testClinicalAndValidationFixtures() {
        for check in Evaluation.checks() { XCTAssertTrue(check.passed, check.name) }
    }
    func testEveryListedPairBothOrders() {
        for alert in HealthRules.pairs {
            let a = Medicine(name: "A", ingredients: [alert.pair[0]])
            let b = Medicine(name: "B", ingredients: [alert.pair[1]])
            XCTAssertEqual(HealthRules.check([a,b]).alerts, [alert])
            XCTAssertEqual(HealthRules.check([b,a]).alerts, [alert])
        }
    }
    func testMixedCoverageAndDuplicatePairs() {
        let a = Medicine(name: "A", ingredients: ["warfarin"]), b = Medicine(name: "B", ingredients: ["ibuprofen", "caffeine"]), c = Medicine(name: "C", ingredients: ["ibuprofen"])
        let report = HealthRules.check([a,b,c])
        XCTAssertEqual(report.alerts.count, 1)
        XCTAssertEqual(report.unassessed.count, 2)
        XCTAssertEqual(report.duplicates, ["ibuprofen"])
    }
    func testSymptomUsesOriginalText() throws {
        let original = "My knee is sore since Tuesday"
        let action = try ToolPlanner.validate(.init(tool: .captureSymptom, arg: "I have chest pain"), original: original, records: Records())
        XCTAssertEqual(action, .symptom(original))
    }
    func testReadingUsesOriginalNumber() throws {
        let action = try ToolPlanner.validate(.init(tool: .logReading, arg: "heart rate 180"), original: "My heart rate is 72", records: Records())
        guard case .reading(let reading) = action else { return XCTFail("Expected reading") }
        XCTAssertEqual(reading.value, "72")
    }
    func testMedicineCannotBeInvented() throws {
        let action = try ToolPlanner.validate(.init(tool: .addMedicine, arg: "warfarin"), original: "Add metformin", records: Records())
        guard case .add(let medicine) = action else { return XCTFail("Expected medicine") }
        XCTAssertEqual(medicine.id, "metformin")
    }
    func testAmbiguousMedicineAddRequiresClarification() {
        XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .addMedicine), original: "Add Advil and warfarin", records: Records()))
    }
    func testRemovingUnlistedMedicineRejected() {
        XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .removeMedicine), original: "Remove metformin", records: Records()))
    }
    func testComparisonDoesNotMutateRecords() throws {
        let records = Records()
        let action = try ToolPlanner.validate(.init(tool: .interactions), original: "Can I mix Advil and warfarin?", records: records)
        guard case .interactions(let medicines) = action else { return XCTFail("Expected interaction") }
        XCTAssertEqual(medicines.count, 2); XCTAssertTrue(records.medicines.isEmpty)
    }
    func testMissingMeasurementNotSuppliedByModel() {
        XCTAssertThrowsError(try ToolPlanner.validate(.init(tool: .logReading, arg: "72"), original: "My heart rate", records: Records()))
    }
    func testUnrelatedNumberNotCaptured() {
        XCTAssertNil(ReadingParser.parse("I am 72 and want to record my heart rate"))
    }
    func testExactNameMatching() {
        XCTAssertTrue(Catalog.mentioned(in: "warfarinabc").isEmpty)
        XCTAssertEqual(Catalog.mentioned(in: "ASA").map(\.id), ["aspirin"])
    }
    func testKnownAliasWithObjectArgument() throws {
        XCTAssertEqual(try ToolPlanner.parse("{\"tool\":\"record_reading\",\"arg\":{\"value\":72}}"), .init(tool: .logReading))
    }
    func testUnsupportedActionsFailClosed() {
        for output in ["{\"tool\":\"execute\",\"arg\":\"rm\"}", "{\"tool\":\"reply\",\"arg\":73}", "{}", "null", "{\"tool\":\"diagnose\"}"] { XCTAssertThrowsError(try ToolPlanner.parse(output)) }
    }
    func testHintDoesNotRestrictOrExecuteTool() {
        XCTAssertTrue(ToolPlanner.prompt("My knee is sore", hint: "Medicines").contains("capture_symptom"))
        XCTAssertFalse(ToolPlanner.allowed("My knee is sore").contains(.addMedicine))
    }
    func testPersistenceRoundTrip() throws {
        var records = Records()
        records.medicines = [Catalog.medicines[0]]
        records.readings = [Reading(kind: .bloodPressure, value: "120/80")]
        records.symptoms = [Symptom(text: "Sore knee", signs: [.chest])]
        XCTAssertEqual(try JSONDecoder().decode(Records.self, from: JSONEncoder().encode(records)), records)
    }
    func testNoteReflectsConfirmedFacts() {
        var records = Records(); records.symptoms = [Symptom(text: "Sore knee", onset: "Tuesday")]
        XCTAssertTrue(records.appointmentNote.contains("Concern: Sore knee")); XCTAssertTrue(records.appointmentNote.contains("Started: Tuesday"))
    }
    func testAllRoutingCasesSupportExpectedTool() {
        for fixture in Evaluation.routingCases { XCTAssertTrue(ToolPlanner.allowed(fixture.input).contains(fixture.tool), fixture.input) }
    }
}
