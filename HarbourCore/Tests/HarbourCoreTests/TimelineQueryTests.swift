import XCTest
@testable import HarbourCore

final class TimelineQueryTests: XCTestCase {
    func testSentencePunctuationDoesNotPreventEnglishOrFrenchHistoryMatches() throws {
        let cases = [
            ("Search my history for wrist pain.", "wrist pain", "Reported wrist pain after walking"),
            ("Find my history for wrist pain ?  ", "wrist pain", "Reported wrist pain after walking"),
            ("Cherche mon historique pour douleur au poignet!", "douleur au poignet", "Une douleur au poignet après la marche"),
            ("Recherche mon historique concernant douleur au poignet;", "douleur au poignet", "Une douleur au poignet après la marche")
        ]
        for (request, expected, saved) in cases {
            var records = Records()
            records.symptoms = [Symptom(text: saved)]
            guard case .timeline(let query) = try ToolPlanner.validate(.init(tool: .searchTimeline, arg: "invented query"), original: request, records: records) else { return XCTFail(request) }
            XCTAssertEqual(query, expected, request)
            XCTAssertEqual(HealthTimeline.entries(records: records, care: CareData(), visits: [], query: query).map(\.title), [saved], request)
        }
    }

    func testSearchKeepsLeadingInternalDecimalAndQuotedLiteralPunctuation() throws {
        let cases = [
            ("Search my history for !wrist pain.", "!wrist pain"),
            ("Find my history for 37.4.", "37.4"),
            ("Cherche mon historique pour 37,4 ?", "37,4"),
            ("Search my history for wrist; elbow!", "wrist; elbow"),
            (#"Search my history for "wrist pain?"."#, #""wrist pain?""#),
            ("Cherche mon historique pour « douleur au poignet! ».", "« douleur au poignet! »"),
            ("Cherche mon historique pour l'endormissement; la fatigue.", "l'endormissement; la fatigue"),
            ("Find my history for wrist pain…", "wrist pain…")
        ]
        for (request, expected) in cases {
            var records = Records()
            let saved = "Source literal " + expected + " after activity"
            records.symptoms = [Symptom(text: saved)]
            guard case .timeline(let query) = try ToolPlanner.validate(.init(tool: .searchTimeline), original: request, records: records) else { return XCTFail(request) }
            XCTAssertEqual(query, expected, request)
            XCTAssertEqual(HealthTimeline.entries(records: records, care: CareData(), visits: [], query: query).map(\.title), [saved], request)
        }
    }
}
