import XCTest
@testable import HarbourCore

final class MedicationSearchTests: XCTestCase {
    private func entry(
        _ id: String,
        name: String = "Zelmate",
        french: String = "",
        aliases: [String] = [],
        ingredients: [String] = ["fixture ingredient"]
    ) -> MedicationVocabulary.Entry {
        .init(id: id, name: name, fr: french, aliases: aliases, ingredients: ingredients)
    }

    func testCommonGenericAndBrandTyposRemainSuggestionsOnly() throws {
        let fixtures = [
            ("metfomrin", "metformin"),
            ("metfornin", "metformin"),
            ("metforminn", "metformin"),
            ("metfomin", "metformin"),
            ("netformin", "metformin"),
            ("emtformin", "metformin"),
            ("aleev", "Aleve"),
            ("alvee", "Aleve"),
            ("advli", "Advil"),
            ("tyelnol", "Tylenol"),
            ("ibuprofne", "ibuprofen"),
            ("hydroclorothiazide", "hydrochlorothiazide"),
            ("rosuvastatnie", "rosuvastatine"),
            ("acétaminophènne", "acetaminophen")
        ]
        for (query, expectedName) in fixtures {
            let expected = try XCTUnwrap(Catalog.resolve(expectedName), expectedName)
            let suggestions = MedicationVocabulary.shared.suggestions(query)
            XCTAssertTrue(suggestions.contains {
                MedicationVocabulary.key($0.name) == MedicationVocabulary.key(expected.name)
            }, "\(query): \(suggestions.map(\.name))")
            XCTAssertNil(Catalog.resolve(query), query)
            XCTAssertThrowsError(try ToolPlanner.validate(
                .init(tool: .addMedicine), original: "Add \(query)", records: Records()
            ), query)
        }
    }

    func testShortNameSuggestionsRequireAtMostOneSpellingEditAndPreserveAmbiguity() {
        let vocabulary = MedicationVocabulary(entries: [
            entry("z", name: "Zelma", ingredients: ["ingredient one"]),
            entry("a", name: "Zelma", ingredients: ["ingredient two"])
        ], publicationDate: "fixture")
        XCTAssertEqual(vocabulary.suggestions("ezlma").map(\.id), ["a", "z"])
        XCTAssertNil(vocabulary.resolve("ezlma"))
        XCTAssertNil(vocabulary.resolve("zelma"))
        XCTAssertTrue(vocabulary.suggestions("ezmla").isEmpty)
        XCTAssertTrue(vocabulary.suggestions("zel").isEmpty)
    }

    func testOfficialFrenchAliasesAndIngredientOnlySearchAreRanked() {
        let vocabulary = MedicationVocabulary(entries: [
            entry("brand", name: "Zebra", ingredients: ["Zelma"]),
            entry("substring", name: "Azelma"),
            entry("prefix", name: "Zelmate"),
            entry("exact", name: "Zelma", french: "Zélma", aliases: ["Zelma alternative"])
        ], publicationDate: "fixture")
        XCTAssertEqual(vocabulary.search("ZÉLMA").map(\.id), ["exact", "brand", "prefix", "substring"])
        XCTAssertEqual(vocabulary.search("  zelma  ").map(\.id), vocabulary.search("ZÉLMA").map(\.id))
        XCTAssertEqual(vocabulary.search("zelma alternative").first?.id, "exact")
        XCTAssertEqual(vocabulary.search("fixture ingredient").map(\.id), ["substring", "exact", "prefix"])
        XCTAssertEqual(Catalog.search("ibuprofen").first?.id, "ibuprofen")
        XCTAssertEqual(Catalog.search("acétaminophène").first?.id, "acetaminophen")
    }

    func testAmbiguousAliasesReturnCandidatesWithoutResolvingAnIdentity() {
        let entries = [
            entry("z", ingredients: ["ingredient one"]),
            entry("a", ingredients: ["ingredient two"])
        ]
        let vocabulary = MedicationVocabulary(entries: entries, publicationDate: "fixture")
        XCTAssertNil(vocabulary.resolve("zelmate"))
        XCTAssertEqual(vocabulary.search("zelmate").map(\.id), ["a", "z"])
        XCTAssertEqual(vocabulary.suggestions("zelmtae").map(\.id), ["a", "z"])
        let reversed = MedicationVocabulary(entries: Array(entries.reversed()), publicationDate: "fixture")
        XCTAssertEqual(reversed.search("zelmate").map(\.id), vocabulary.search("zelmate").map(\.id))
        XCTAssertEqual(reversed.suggestions("zelmtae").map(\.id), vocabulary.suggestions("zelmtae").map(\.id))
    }

    func testEquivalentSuggestionsDeduplicateAndPreferGenericIdentity() {
        let vocabulary = MedicationVocabulary(entries: [
            entry("dpd-brand:z", aliases: ["ZELMATE", "zélmate"]),
            entry("dpd-ingredient:z", aliases: ["zelmate"])
        ], publicationDate: "fixture")
        XCTAssertEqual(vocabulary.resolve("zelmate")?.id, "dpd-ingredient:z")
        XCTAssertEqual(vocabulary.suggestions("zelmtae").map(\.id), ["dpd-ingredient:z"])
    }

    func testUnrelatedAndOutOfBoundsQueriesDoNotCreateCandidates() {
        let vocabulary = MedicationVocabulary.shared
        for query in ["zzqx", "zzqvx", "zzzzzzzzzzzz", "garden furniture", "bicycle helmet"] {
            XCTAssertTrue(Catalog.search(query).isEmpty, query)
            XCTAssertTrue(vocabulary.suggestions(query).isEmpty, query)
        }
        for query in ["", "Li", String(repeating: "a", count: 81), "one two three four five"] {
            XCTAssertTrue(vocabulary.suggestions(query).isEmpty, query)
        }
        XCTAssertTrue(vocabulary.search("").isEmpty)
        XCTAssertTrue(vocabulary.search(String(repeating: "a", count: 81)).isEmpty)
        XCTAssertTrue(vocabulary.search("metformin", limit: 0).isEmpty)
        XCTAssertTrue(vocabulary.search("metformin", limit: -1).isEmpty)
        XCTAssertTrue(vocabulary.suggestions("metfomrin", limit: 0).isEmpty)
        XCTAssertTrue(vocabulary.suggestions("metfomrin", limit: -1).isEmpty)
        XCTAssertTrue(Catalog.search(String(repeating: "a", count: 81)).isEmpty)
        XCTAssertEqual(Catalog.search("   ").map(\.id), Catalog.medicines.map(\.id))
    }

    func testLimitedSearchIsStableAcrossAliasAndEntryOrder() {
        let entries = (0 ..< 16).map { index in
            entry(String(format: "fixture-%02d", index), name: "Zelmate", aliases: ["ZELMATE", "zélmate"])
        }
        let expected = Array(entries.map(\.id).prefix(12))
        for source in [entries, Array(entries.reversed())] {
            let vocabulary = MedicationVocabulary(entries: source, publicationDate: "fixture")
            XCTAssertEqual(vocabulary.search("zelmate").map(\.id), expected)
            XCTAssertEqual(Set(vocabulary.search("zelmate").map(\.id)).count, 12)
        }
        let expectedCatalog = Catalog.search("metformin").map(\.id)
        for _ in 0 ..< 5 {
            XCTAssertEqual(Catalog.search("metformin").map(\.id), expectedCatalog)
            XCTAssertEqual(Set(expectedCatalog).count, expectedCatalog.count)
        }
    }
}
