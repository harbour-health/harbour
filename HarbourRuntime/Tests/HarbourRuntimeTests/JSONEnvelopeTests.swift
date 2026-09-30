import XCTest
@testable import HarbourRuntime

final class JSONEnvelopeTests: XCTestCase {
    func testNestedArgumentDoesNotStopGenerationEarly() {
        XCTAssertNil(JSONEnvelope.completePrefix(in: #"{"tool":"list_medications","arg":{}"#))
        XCTAssertEqual(JSONEnvelope.completePrefix(in: #"{"tool":"list_medications","arg":{}}"#), #"{"tool":"list_medications","arg":{}}"#)
    }
    func testBracesInsideStrings() {
        XCTAssertNil(JSONEnvelope.completePrefix(in: #"{"tool":"reply","arg":"}""#))
        XCTAssertEqual(JSONEnvelope.completePrefix(in: #"{"tool":"reply","arg":"}"}"#), #"{"tool":"reply","arg":"}"}"#)
    }
    func testEscapedQuoteDoesNotEndString() {
        let object = #"{"tool":"reply","arg":"a \" } quoted"}"#
        XCTAssertEqual(JSONEnvelope.completePrefix(in: object), object)
    }
    func testLeadingAndTrailingTextAndIncompleteInput() {
        XCTAssertNil(JSONEnvelope.completePrefix(in: "no object"))
        XCTAssertNil(JSONEnvelope.completePrefix(in: #"{"tool":"log_reading""#))
        XCTAssertEqual(JSONEnvelope.completePrefix(in: #"prefix: {"tool":"log_reading","arg":""} trailing"#), #"{"tool":"log_reading","arg":""}"#)
    }
}
