import XCTest
@testable import HarbourCore

final class FrenchRecordsTests: XCTestCase {
    func testFrenchReadingLabelsAndDecimalComma() {
        let fixtures: [(String, ReadingKind, String)] = [
            ("Mon pouls est de72", .heartRate, "72"),
            ("Ma fréquence cardiaque est de 72", .heartRate, "72"),
            ("Mon rythme cardiaque est de 72", .heartRate, "72"),
            ("tension120/80", .bloodPressure, "120/80"),
            ("Ma tension artérielle est de 120 / 80", .bloodPressure, "120/80"),
            ("Pression arterielle 120/80", .bloodPressure, "120/80"),
            ("température36,8", .temperature, "36.8"),
            ("Ma temperature est de 36.8", .temperature, "36.8")
        ]
        for (input, kind, value) in fixtures {
            let reading = ReadingParser.parse(input)
            XCTAssertEqual(reading?.kind, kind, input)
            XCTAssertEqual(reading?.value, value, input)
            XCTAssertEqual(reading?.source, "Manual", input)
        }
    }

    func testFrenchInputKeepsExistingReadingBounds() {
        for input in ["tension80/120", "tension999/80", "tension120//80", "tension120/80/90", "température nan", "température inf", "température36,8,9", "température -36,8", "pouls 12345", "pouls 1e72", "poulsons72", "J’ai 72 ans et je veux noter mon pouls"] {
            XCTAssertNil(ReadingParser.parse(input), input)
        }
        XCTAssertNil(ReadingParser.parse("pouls\n72"))
        XCTAssertNil(ReadingParser.parse("pouls " + String(repeating: "mot ", count: 12) + "72"))
        for input in ["nan", "inf", "-36,8", "36,8.4", "36,8,4"] { XCTAssertFalse(ReadingParser.valid(input, kind: .temperature), input) }
        for input in ["120//80", "120/80/", "80/120", "120/80/90"] { XCTAssertFalse(ReadingParser.valid(input, kind: .bloodPressure), input) }
        XCTAssertTrue(ReadingParser.valid("36,8", kind: .temperature))
        XCTAssertEqual(ReadingParser.normalizedValue(" 36,8 "), "36.8")
        XCTAssertEqual(ReadingParser.normalizedValue("120 / 80"), "120/80")
    }

    func testFrenchAliasesResolveToCanonicalFacts() {
        let fixtures = ["warfarine": "warfarin", "ibuprofène": "ibuprofen", "aspirine": "aspirin", "AAS": "aspirin", "acide acétylsalicylique": "aspirin", "naproxène": "naproxen", "acétaminophène": "acetaminophen", "metformine": "metformin"]
        for (alias, id) in fixtures {
            let expected = Catalog.medicines.first { $0.id == id }
            XCTAssertEqual(Catalog.resolve(alias), expected, alias)
            XCTAssertEqual(Catalog.mentioned(in: "Je prends de l’" + alias).map(\.id), [id], alias)
            XCTAssertTrue(Catalog.search(alias).contains { $0.id == id }, alias)
        }
        XCTAssertEqual(Catalog.resolve("  ACETAMINOPHENE  ")?.id, "acetaminophen")
        XCTAssertEqual(Catalog.resolve("Aspirin / ASA")?.id, "aspirin")
        XCTAssertEqual(Catalog.mentioned(in: "Aspirine, ASA et AAS").map(\.id), ["aspirin"])
        XCTAssertTrue(Catalog.search("acétaminophène").contains { $0.id == "tylenol" })
        XCTAssertEqual(Catalog.ingredientNames(for: "acetaminophen"), ["acetaminophen", "acétaminophène"])
    }

    func testAliasesRemainBoundedAndSavedFactsTakePrecedence() {
        for text in ["metformines", "ibuprofèneabc", "acétaminophène_extra", "AAS123"] {
            XCTAssertTrue(Catalog.mentioned(in: text).isEmpty, text)
            XCTAssertNil(Catalog.resolve(text), text)
        }
        XCTAssertNil(Catalog.resolve("Produit inconnu"))
        var saved = Catalog.medicines.first { $0.id == "metformin" }!
        saved.instructions = "500 mg avec un repas"
        XCTAssertEqual(Catalog.resolve("metformine", saved: [saved]), saved)
        XCTAssertEqual(Catalog.mentioned(in: "Je prends metformine", saved: [saved]), [saved])
        saved.name = "Metformine"
        XCTAssertEqual(Catalog.resolve("metformin", saved: [saved]), saved)
        let custom = Medicine(id: "my-medicine", name: "Produit inconnu")
        XCTAssertEqual(Catalog.resolve("Produit inconnu", saved: [custom]), custom)
        XCTAssertEqual(Catalog.mentioned(in: "Produit inconnu", saved: [custom]), [custom])
        XCTAssertTrue(Catalog.names(for: custom).allSatisfy { $0 == custom.name })
    }

    func testFrenchInputsDoNotChangeCodableRawValues() throws {
        XCTAssertEqual(ReadingKind.heartRate.rawValue, "Heart rate")
        XCTAssertEqual(ReadingKind.bloodPressure.rawValue, "Blood pressure")
        XCTAssertEqual(ReadingKind.temperature.rawValue, "Temperature")
        let reading = try XCTUnwrap(ReadingParser.parse("température36,8"))
        let data = try JSONEncoder().encode(reading)
        XCTAssertEqual(try JSONDecoder().decode(Reading.self, from: data), reading)
        XCTAssertEqual(Catalog.resolve("metformine")?.ingredients, ["metformin"])
        XCTAssertEqual(Catalog.resolve("metformine")?.name, "Metformin")
    }
}
