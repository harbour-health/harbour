import XCTest
@testable import HarbourRuntime

final class TitleOutputGrammarTests: XCTestCase {
    func testRootContractIsExactlyOneTitleString() {
        let grammar = TitleOutputGrammar.make()
        let root = grammar.components(separatedBy: "\n").first
        XCTAssertEqual(root, #"root ::= ws "{" ws "\"title\"" ws ":" ws string ws "}" ws"#)
        XCTAssertTrue(grammar.contains(#"string ::= "\"" character{1,60} "\""#))
        XCTAssertFalse(grammar.contains("tool")); XCTAssertFalse(grammar.contains("arg"))
        XCTAssertFalse(grammar.contains("Titre court en français")); XCTAssertFalse(grammar.contains("Short title"))
    }

    func testJSONStringEscapesAndControlCharactersHaveExplicitRules() {
        let grammar = TitleOutputGrammar.make()
        XCTAssertTrue(grammar.contains(#"[^"\\\x00-\x1F]"#))
        XCTAssertTrue(grammar.contains(#"(["\\/bfnrt] | "u" [0-9a-fA-F]{4})"#))
        XCTAssertTrue(grammar.contains(#"ws ::= [ \t\n\r]{0,4}"#))
        XCTAssertFalse(grammar.contains(".*")); XCTAssertFalse(grammar.contains("character*")); XCTAssertFalse(grammar.contains("ws*"))
    }

    func testFrenchTitleEnvelopePreservesEscapedQuotesBracesAndUnicode() throws {
        let fixtures = [
            (#"{"title":"Liste des médicaments"}"#, "Liste des médicaments"),
            (#"{"title":"Médicaments \"à revoir\" {demain}"}"#, "Médicaments \"à revoir\" {demain}"),
            (#"{"title":"M\u00e9dicaments \u00e0 revoir"}"#, "Médicaments à revoir"),
            (#"{"title":"Liste d’aujourd’hui / demain"}"#, "Liste d’aujourd’hui / demain")
        ]
        for (output, expected) in fixtures {
            let envelope = try XCTUnwrap(JSONEnvelope.completePrefix(in: output))
            XCTAssertEqual(envelope, output)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(envelope.utf8)) as? [String: String])
            XCTAssertEqual(Set(object.keys), ["title"]); XCTAssertEqual(object["title"], expected)
            XCTAssertLessThanOrEqual(expected.count, TitleOutputGrammar.maximumCharacters)
        }
        XCTAssertNil(JSONEnvelope.completePrefix(in: #"{"title":"Médicaments \"à revoir\""#))
    }
}
