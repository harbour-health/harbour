import XCTest

@MainActor final class UnconfirmedMedicineUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a) }

    func testUnconfirmedMedicineCanBeReviewedCancelledAndSaved() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-unlocked", "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launch()
        app.buttons["nav-today"].tap()
        app.buttons["Settings"].tap()
        if !app.buttons["developerSettings"].isHittable {
            app.swipeUp()
        }
        app.buttons["developerSettings"].tap()
        app.buttons["loadDemoData"].tap()
        app.alerts.buttons["Replace with demo data"].tap()
        XCTAssertTrue(app.staticTexts["demoDataLoaded"].waitForExistence(timeout: 5))
        app.navigationBars["Developer"].buttons.firstMatch.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        app.buttons["nav-visits"].tap()
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Demo · Medication review"))
            .firstMatch
        if !row.isHittable {
            app.swipeUp()
        }
        row.tap()
        XCTAssertTrue(app.buttons["reviewUnconfirmedMedicine"].waitForExistence(timeout: 5))
        capture("202-unconfirmed-review-action")
        app.buttons["reviewUnconfirmedMedicine"].tap()
        XCTAssertFalse(app.buttons["saveMedicine"].isEnabled)
        XCTAssertTrue(app.buttons["confirmMedicine"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Camera"].exists)
        capture("203-unconfirmed-review-draft")
        app.navigationBars["Medication"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["reviewUnconfirmedMedicine"].waitForExistence(timeout: 5))
        app.buttons["reviewUnconfirmedMedicine"].tap()
        app.buttons["confirmMedicine"].tap()
        XCTAssertTrue(app.buttons["saveMedicine"].isEnabled)
        app.buttons["saveMedicine"].tap()
        XCTAssertTrue(app.staticTexts["Medication saved"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reviewUnconfirmedMedicine"].exists)
        capture("204-unconfirmed-review-saved")
        app.buttons["nav-records"].tap()
        app.buttons["record-category-1"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "medicine-row-",
            "salbutamol"
        )).firstMatch.exists)
    }
}
