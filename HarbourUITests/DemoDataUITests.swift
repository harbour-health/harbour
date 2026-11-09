import XCTest

@MainActor final class DemoDataUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testDemoReplacementConfirmationAndVisitSummary() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-unlocked", "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launch(); app.buttons["nav-today"].tap(); app.buttons["Settings"].tap()
        if !app.buttons["developerSettings"].isHittable { app.swipeUp() }
        app.buttons["developerSettings"].tap()
        capture("169-developer-settings")
        app.buttons["loadDemoData"].tap()
        XCTAssertTrue(app.alerts["Replace all local data?"].waitForExistence(timeout: 5))
        capture("170-demo-replacement-confirmation")
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["loadDemoData"].exists)
        app.buttons["loadDemoData"].tap(); app.alerts.buttons["Replace with demo data"].tap()
        XCTAssertTrue(app.staticTexts["demoDataLoaded"].waitForExistence(timeout: 5))
        app.navigationBars["Developer"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["demoDataBadge"].waitForExistence(timeout: 5))
        capture("171-demo-today")
        app.buttons["nav-visits"].tap()
        let visit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Demo · Blood pressure follow-up")).firstMatch
        if !visit.isHittable { app.swipeUp() }
        visit.tap()
        XCTAssertTrue(app.buttons["reviewVisitMedicines"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo visit · preset transcript, no audio"].exists)
        capture("172-demo-visit-summary")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["demoDataBadge"].waitForExistence(timeout: 5))
    }
    func testFrenchDemoSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-unlocked", "-AppleLanguages", "(fr-CA)", "-AppleLocale", "fr_CA"]
        app.launch(); app.buttons["nav-today"].tap(); app.buttons["Réglages"].tap()
        if !app.buttons["developerSettings"].isHittable { app.swipeUp() }
        app.buttons["developerSettings"].tap(); app.buttons["loadDemoData"].tap()
        XCTAssertTrue(app.alerts["Remplacer toutes les données locales?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Remplacer par les données de démo"].tap()
        XCTAssertTrue(app.staticTexts["demoDataLoaded"].waitForExistence(timeout: 5))
        capture("173-developer-french")
        app.navigationBars["Développement"].buttons.firstMatch.tap(); app.navigationBars["Réglages"].buttons["Terminé"].tap()
        XCTAssertTrue(app.staticTexts["demoDataBadge"].waitForExistence(timeout: 5))
    }
}
