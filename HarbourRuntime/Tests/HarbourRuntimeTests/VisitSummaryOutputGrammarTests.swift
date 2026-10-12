import Foundation
import XCTest
@testable import HarbourRuntime

final class VisitSummaryOutputGrammarTests: XCTestCase {
    func testRootRequiresAllCategoriesAndBoundedCollections() {
        let grammar = VisitSummaryOutputGrammar.make()
        XCTAssertTrue(grammar.contains(#"root ::= ws "{" ws "\"highlights\"" ws ":" ws quotes ws "," ws "\"medicines\"" ws ":" ws medicines ws "," ws "\"followUps\"" ws ":" ws quotes ws "," ws "\"appointments\"" ws ":" ws quotes ws "}" ws"#))
        XCTAssertTrue(grammar.contains(#"quotes ::= "[" ws (quote (ws "," ws quote){0,11})? ws "]""#))
        XCTAssertTrue(grammar.contains(#"medicines ::= "[" ws (medicine (ws "," ws medicine){0,11})? ws "]""#))
        XCTAssertTrue(grammar.contains(#"medicine ::= active_medicine | stop_medicine"#))
        XCTAssertTrue(grammar.contains(#"active_action ::= "\"start\"" | "\"update\"""#))
        XCTAssertTrue(grammar.contains(#"character{4,600}"#))
        XCTAssertTrue(grammar.contains(#"character{1,100}"#))
        XCTAssertTrue(grammar.contains(#"character{1,180}"#))
        XCTAssertTrue(grammar.contains(#""\"stop\"" ws "," ws "\"name\"" ws ":" ws name_string ws "," ws "\"instructions\"" ws ":" ws "\"\"""#))
        XCTAssertFalse(grammar.contains(".*"))
    }

    func testEscapedUnicodeAndEmptyCategoriesAreValidJSON() throws {
        let outputs = [
            #"{"highlights":[],"medicines":[],"followUps":[],"appointments":[]}"#,
            #"{"highlights":[{"quote":"Médicament \"à revoir\""}],"medicines":[{"action":"start","name":"médicament","instructions":"dose à confirmer","quote":"Débuter le médicament demain."}],"followUps":[],"appointments":[]}"#,
            #"{"highlights":[],"medicines":[],"followUps":[{"quote":"M\u00e9dicament à revoir"}],"appointments":[]}"#
        ]
        for output in outputs {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["highlights", "medicines", "followUps", "appointments"])
            XCTAssertNotNil(object["highlights"] as? [Any])
            XCTAssertNotNil(object["medicines"] as? [Any])
            XCTAssertNotNil(object["followUps"] as? [Any])
            XCTAssertNotNil(object["appointments"] as? [Any])
        }
    }

    func testGrammarContainsOnlyTheSupportedMedicationFields() {
        let grammar = VisitSummaryOutputGrammar.make()
        XCTAssertTrue(grammar.contains(#"active_medicine ::= "{" ws "\"action\"" ws ":" ws active_action ws "," ws "\"name\"" ws ":" ws name_string ws "," ws "\"instructions\"" ws ":" ws instruction_string ws "," ws "\"quote\"" ws ":" ws quote_string ws "}""#))
        XCTAssertFalse(grammar.contains("metformin"))
        XCTAssertFalse(grammar.contains("twice daily"))
    }
}
