import XCTest

@MainActor final class MedicationChatUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) { let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func send(_ text: String, app: XCUIApplication) {
        let field = app.textFields["chatInput"]; XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(text); app.buttons["Send message"].tap()
    }
    func testRealChatDoseCorrectionAndLabelledRemovalAlert() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-unlocked", "-model", "balanced", "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launch(); app.buttons["nav-today"].tap(); app.buttons["Settings"].tap()
        if !app.buttons["developerSettings"].isHittable { app.swipeUp() }
        app.buttons["developerSettings"].tap(); app.buttons["loadDemoData"].tap(); app.alerts.buttons["Replace with demo data"].tap()
        XCTAssertTrue(app.staticTexts["demoDataLoaded"].waitForExistence(timeout: 5))
        app.navigationBars["Developer"].buttons.firstMatch.tap(); app.navigationBars["Settings"].buttons["Done"].tap()
        app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap()
        send("Update my metformin to 400mg", app: app)
        XCTAssertTrue(app.navigationBars["Medication"].waitForExistence(timeout: 300))
        if !app.textFields["medicineInstructions"].exists { app.swipeUp() }
        XCTAssertTrue((app.textFields["medicineInstructions"].value as? String)?.contains("400mg") == true)
        XCTAssertFalse(app.buttons["saveMedicine"].isEnabled)
        capture("205-chat-dose-correction-review")
        app.navigationBars["Medication"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 300))
        app.buttons["New chat"].tap()
        send("Remove metformin from my list", app: app)
        let alert = app.alerts["Remove Metformin from your list?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 300))
        XCTAssertTrue(alert.buttons["Remove"].exists); XCTAssertTrue(alert.buttons["Cancel"].exists)
        capture("206-chat-removal-confirmation")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 300))
        app.buttons["nav-records"].tap()
        if !app.buttons["record-category-1"].exists { app.navigationBars.buttons.firstMatch.tap() }
        app.buttons["record-category-1"].tap()
        XCTAssertTrue(app.buttons["medicine-row-metformin"].exists)
    }
    func testExplicitRemovalAlertHasStablePendingStatus() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-unlocked", "-model", "balanced", "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launch(); app.buttons["nav-today"].tap(); app.buttons["Settings"].tap()
        if !app.buttons["developerSettings"].isHittable { app.swipeUp() }
        app.buttons["developerSettings"].tap(); app.buttons["loadDemoData"].tap(); app.alerts.buttons["Replace with demo data"].tap()
        XCTAssertTrue(app.staticTexts["demoDataLoaded"].waitForExistence(timeout: 5))
        app.navigationBars["Developer"].buttons.firstMatch.tap(); app.navigationBars["Settings"].buttons["Done"].tap()
        app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap()
        send("Remove metformin from my list", app: app)
        let alert = app.alerts["Remove Metformin from your list?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 300))
        XCTAssertTrue(app.staticTexts["chatPendingReview"].exists)
        XCTAssertFalse(app.staticTexts["Thinking…"].exists)
        capture("206-chat-removal-confirmation")
        alert.buttons["Cancel"].tap()
        app.buttons["nav-records"].tap(); app.buttons["record-category-1"].tap()
        XCTAssertTrue(app.buttons["medicine-row-metformin"].exists)
        app.buttons["medicine-row-metformin"].tap()
        XCTAssertTrue(app.navigationBars["Medication"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Camera"].exists)
        capture("207-existing-medication-editor")
        app.navigationBars["Medication"].buttons["Cancel"].tap()
        app.buttons["nav-today"].tap()
        for _ in 0..<5 { if app.buttons["openTimeline"].isHittable { break }; app.swipeUp() }
        app.buttons["openTimeline"].tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 5))
        capture("208-open-timeline")
    }

}
