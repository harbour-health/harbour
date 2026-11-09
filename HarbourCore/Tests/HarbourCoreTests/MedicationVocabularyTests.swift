import XCTest
@testable import HarbourCore

final class MedicationVocabularyTests: XCTestCase {
    func testOfficialHumanVocabularyLoadsAndFindsDifficultGenericNames() {
        let vocabulary = MedicationVocabulary.shared
        XCTAssertEqual(vocabulary.publicationDate, "2026-11-02")
        XCTAssertGreaterThan(vocabulary.entries.count, 8000)
        for name in [
            "hydrochlorothiazide",
            "levothyroxine",
            "rosuvastatin",
            "empagliflozin",
            "rivaroxaban",
            "pantoprazole",
            "candesartan",
            "gliclazide"
        ] {
            XCTAssertNotNil(Catalog.resolve(name), name)
        }
    }

    func testDatabaseLabelsTranslateWithoutOverwritingCustomNames() throws {
        let vocabulary = MedicationVocabulary.shared
        var medicine = try XCTUnwrap(vocabulary.resolve("rosuvastatin"))
        XCTAssertEqual(vocabulary.localizedName(for: medicine, french: true), "Rosuvastatine")
        XCTAssertTrue(vocabulary.speechHints(saved: [medicine], french: true).contains("Rosuvastatine"))
        medicine.name = "My evening medicine"
        XCTAssertNil(vocabulary.localizedName(for: medicine, french: true))
    }

    func testPhoneticSuggestionsDoNotEnableMisspelledWrites() {
        for query in ["hydroclorothiazide", "levo thyroxine", "rosuvastatine"] {
            let suggestions = MedicationVocabulary.shared.suggestions(query)
            XCTAssertFalse(suggestions.isEmpty, query)
            XCTAssertEqual(Set(suggestions.map { $0.name + $0.ingredients.sorted().joined() }).count, suggestions.count)
        }
        XCTAssertNil(Catalog.resolve("hydroclorothiazide"))
        XCTAssertThrowsError(try ToolPlanner.validate(
            .init(tool: .addMedicine),
            original: "Add hydroclorothiazide",
            records: Records()
        ))
        XCTAssertTrue(MedicationVocabulary.shared.suggestions("Li").isEmpty)
    }

    func testBothNamedMedicinesAreRetainedAndCompoundWordsStayBounded() {
        XCTAssertEqual(Catalog.mentioned(in: "Compare warfarin and hydrochlorothiazide").count, 2)
        for query in ["acétaminophène_extra", "metformineuse", "xhydrochlorothiazidex"] {
            XCTAssertTrue(Catalog.mentioned(in: query).isEmpty, query)
        }
    }

    func testFictionalPersonalNamesDoNotBecomeMedicationRecords() throws {
        for person in [
            "Amira Hassan",
            "Jean-François Nguyen",
            "Gurpreet Singh",
            "María García",
            "Wei Chen",
            "Aïcha Diallo",
            "Łukasz Kowalski"
        ] {
            XCTAssertTrue(Catalog.mentioned(in: "My name is " + person).isEmpty, person)
            let request = "My name is \(person). Add hydrochlorothiazide to my list."

            guard case let .add(medicine, _, _) = try ToolPlanner.validate(
                .init(tool: .addMedicine),
                original: request,
                records: Records()
            ) else {
                return XCTFail(request)
            }

            XCTAssertEqual(MedicationVocabulary.key(medicine.name), "hydrochlorothiazide")
        }
    }

    func testSpeechHintsAreBoundedAndPrioritizeSavedNamesWithoutTouchingDoses() {
        let saved = Medicine(
            name: "Levothyroxine",
            ingredients: [],
            instructions: "Do not take on Sunday. 25 mcg at 8 am."
        )
        let hints = MedicationVocabulary.shared.speechHints(saved: [saved], french: false)
        XCTAssertLessThanOrEqual(hints.count, 100)
        XCTAssertEqual(hints.first, "Levothyroxine")
        XCTAssertFalse(hints.contains { $0.contains("25") || $0.contains("Sunday") })
        XCTAssertFalse(MedicationVocabulary.shared.speechHints(saved: [], french: true).isEmpty)
    }
}
