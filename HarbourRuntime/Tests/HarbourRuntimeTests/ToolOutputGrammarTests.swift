import XCTest
@testable import HarbourRuntime

final class ToolOutputGrammarTests: XCTestCase {
    func testExactToolObjectWithEmptyArgument() throws {
        XCTAssertEqual(try ToolOutputGrammar.make(allowedTools: ["capture_symptom", "reply"]), #"""
        root ::= "{\"tool\":\"" tool "\",\"arg\":\"\"}"
        tool ::= "capture_symptom" | "reply"
        """#)
    }
    func testDuplicateToolsPreserveFirstOrder() throws {
        XCTAssertEqual(try ToolOutputGrammar.make(allowedTools: ["reply", "log_dose", "reply"]),
                       try ToolOutputGrammar.make(allowedTools: ["reply", "log_dose"]))
    }
    func testEmptyToolsAreRejected() {
        XCTAssertThrowsError(try ToolOutputGrammar.make(allowedTools: [])) {
            XCTAssertEqual($0 as? ToolOutputGrammarError, .emptyTools)
        }
    }
    func testUnsafeNamesCannotInjectGrammarOrJSON() {
        for name in ["", "reply\"", "reply\\", "reply\nroot ::= \"x\"", "reply|other", "reply name", "reply\0", "réply", "Reply", "1reply", "_reply"] {
            XCTAssertThrowsError(try ToolOutputGrammar.make(allowedTools: ["reply", name]), name) {
                XCTAssertEqual($0 as? ToolOutputGrammarError, .invalidToolName)
            }
        }
    }
    func testInvalidGrammarFailsBeforeLoadingModel() async {
        let runtime = LocalModel()
        for grammar in ["", " \n", "root ::= \"reply\"\0"] {
            do {
                _ = try await runtime.generate(file: URL(fileURLWithPath: "/missing-model.gguf"), prompt: "test", grammar: grammar)
                XCTFail("Invalid grammar should fail")
            } catch ModelError.grammar {
            } catch {
                XCTFail("Expected grammar error, got \(error)")
            }
        }
    }
}
