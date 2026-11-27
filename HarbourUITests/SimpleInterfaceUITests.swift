import XCTest

@MainActor final class SimpleInterfaceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func launch(_ language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-unlocked",
            "-appearance",
            "Light",
            "-AppleLanguages",
            "(\(language))",
            "-AppleLocale",
            language == "en" ? "en_CA" : "fr_CA"
        ]
        app.launchEnvironment["HARBOUR_INITIAL_INTERFACE"] = "simple"
        app.launch()

        return app
    }

    func testSimpleHomeHelpAndCaregiverSwitch() {
        let app = launch()
        XCTAssertTrue(app.buttons["simpleTalk"].waitForExistence(timeout: 10))
        for id in ["simpleTalk", "simpleMessage", "simpleRecordVisit", "simpleGuide"] {
            XCTAssertTrue(app.buttons[id].isHittable, id)
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 56, id)
        }
        XCTAssertFalse(app.buttons["nav-records"].exists)
        capture("226-simple-home")
        app.buttons["simpleGuide"].tap()
        XCTAssertTrue(app.staticTexts["Talk naturally"].waitForExistence(timeout: 5))
        capture("227-simple-guide")
        app.buttons["Try a message"].tap()
        XCTAssertTrue(app.textFields["chatInput"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["modelSelector"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["startVoiceConversation"].frame.height, 56)
        capture("228-simple-chat")
        app.buttons["Home"].tap()
        app.buttons["Settings"].tap()
        capture("229-simple-settings")
        app.buttons["interfaceSettings"].tap()
        app.buttons["interface-caregiver"].tap()
        app.navigationBars["Interface"].buttons.firstMatch.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["nav-records"].waitForExistence(timeout: 5))
        capture("230-caregiver-home")
    }

    func testSimpleLargestTextKeepsPrimaryActionsReachable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-unlocked",
            "-appearance",
            "Light",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_CA",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launchEnvironment["HARBOUR_INITIAL_INTERFACE"] = "simple"
        app.launch()
        XCTAssertTrue(app.buttons["simpleTalk"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["simpleTalk"].isHittable)
        capture("248-simple-largest-text")
        for id in ["simpleMessage", "simpleRecordVisit", "simpleGuide"] {
            let button = app.buttons[id]
            for _ in 0 ..< 5 where !button.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(button.isHittable, id)
            XCTAssertGreaterThanOrEqual(button.frame.height, 56, id)
        }
        app.buttons["simpleGuide"].tap()
        XCTAssertTrue(app.buttons["Try a message"].waitForExistence(timeout: 5))
    }

    func testFrenchSimpleHome() {
        let app = launch("fr-CA")
        XCTAssertTrue(app.buttons["simpleTalk"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["simpleGuide"].label.contains("Utiliser Harbour"))
        capture("231-simple-french")
        app.buttons["simpleGuide"].tap()
        XCTAssertTrue(app.staticTexts["Parlez naturellement"].waitForExistence(timeout: 5))
        capture("232-simple-guide-french")
    }
}
