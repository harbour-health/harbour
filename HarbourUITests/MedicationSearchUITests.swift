import XCTest

@MainActor final class MedicationSearchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openSearch(_ language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-unlocked", "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "en" ? "en_CA" : "fr_CA"
        ]
        app.launchEnvironment["HARBOUR_INITIAL_INTERFACE"] = "caregiver"
        app.launch()
        let records = app.buttons["nav-records"]
        XCTAssertTrue(records.waitForExistence(timeout: 10))
        records.tap()
        let category = app.buttons["record-category-1"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap()
        let add = app.buttons[language == "en" ? "Add record" : "Ajouter une entrée"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.textFields["medicineSearch"].waitForExistence(timeout: 5))
        return app
    }

    private func finishTyping(_ app: XCUIApplication, language: String) {
        let done = app.buttons[language == "en" ? "Done" : "Terminé"]
        if done.exists { done.tap() }
    }

    func testBilingualNoMatchClearsPreviousCandidatesAndRetainsManualEntry() {
        for language in ["en", "fr-CA"] {
            let app = openSearch(language)
            let search = app.textFields["medicineSearch"]
            search.tap()
            search.typeText("metformin")
            XCTAssertTrue(app.buttons["catalog-metformin"].waitForExistence(timeout: 5))
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "metformin".count))
            search.typeText("zzzzzzzzzzzz")
            finishTyping(app, language: language)
            let empty = app.staticTexts["medicineSearchNoMatches"]
            XCTAssertTrue(empty.waitForExistence(timeout: 5))
            XCTAssertEqual(empty.label, language == "en" ? "No matching medications" : "Aucun médicament correspondant")
            XCTAssertFalse(app.buttons["catalog-metformin"].exists)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "medicineSuggestion-")).count, 0)
            XCTAssertTrue(app.buttons["addUnlistedMedicine"].exists)
            XCTAssertFalse(app.buttons["saveMedicine"].isEnabled)

            search.tap()
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
            search.typeText(language == "en" ? "acetaminophen" : "acétaminophène")
            finishTyping(app, language: language)
            XCTAssertTrue(app.buttons["catalog-acetaminophen"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["medicineSearchNoMatches"].exists)
            app.terminate()
        }
    }

    func testBilingualTranspositionSuggestionRequiresProductConfirmation() {
        for language in ["en", "fr-CA"] {
            let app = openSearch(language)
            let search = app.textFields["medicineSearch"]
            search.tap()
            search.typeText("metfomrin")
            finishTyping(app, language: language)
            let suggestion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "medicineSuggestion-")).firstMatch
            XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["medicineSearchNoMatches"].exists)
            suggestion.tap()
            let confirm = app.buttons["confirmMedicine"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["saveMedicine"].isEnabled)
            confirm.tap()
            XCTAssertTrue(app.buttons["saveMedicine"].isEnabled)
            app.terminate()
        }
    }
}
