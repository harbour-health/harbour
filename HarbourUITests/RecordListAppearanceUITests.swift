import XCTest

@MainActor final class RecordListAppearanceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ number: Int, _ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "\(number)-\(name)"; image.lifetime = .keepAlways; add(image)
    }
    func testPopulatedListsInBothAppearances() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-unlocked", "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launch(); app.buttons["nav-today"].tap(); app.buttons["Settings"].tap()
        if !app.buttons["developerSettings"].isHittable { app.swipeUp() }
        app.buttons["developerSettings"].tap(); app.buttons["loadDemoData"].tap()
        app.alerts.buttons["Replace with demo data"].tap()
        XCTAssertTrue(app.staticTexts["demoDataLoaded"].waitForExistence(timeout: 5))
        app.navigationBars["Developer"].buttons.firstMatch.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        for (themeIndex, theme) in ["light", "dark"].enumerated() {
            let first = themeIndex == 0 ? 174 : 181
            app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Appearance"].tap()
            app.buttons["appearance-" + theme].tap()
            app.navigationBars["Appearance"].buttons.firstMatch.tap()
            app.navigationBars["Settings"].buttons["Done"].tap()
            app.buttons["nav-records"].tap()
            for (index, title) in ["Symptoms", "Medications", "Readings", "Appointments"].enumerated() {
                app.buttons["record-category-\(index)"].tap()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
                capture(first + index, "flat-" + title.lowercased() + "-" + theme)
                if index == 0 {
                    app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Sore right knee after a walk")).firstMatch.tap()
                    XCTAssertTrue(app.navigationBars["Symptom"].waitForExistence(timeout: 5))
                    capture(first + 6, "flat-symptom-detail-" + theme)
                    app.navigationBars["Symptom"].buttons.firstMatch.tap()
                }
                if index == 1 {
                    app.buttons["medicine-row-amlodipine"].tap()
                    XCTAssertTrue(app.navigationBars["Medication"].waitForExistence(timeout: 5))
                    app.navigationBars["Medication"].buttons["Cancel"].tap()
                }
                app.navigationBars[title].buttons.firstMatch.tap()
            }
            app.buttons["nav-visits"].tap(); app.buttons["prepareAppointment"].tap()
            XCTAssertTrue(app.textFields["appointmentQuestion"].waitForExistence(timeout: 5))
            capture(first + 4, "flat-preparation-" + theme)
            app.navigationBars["Appointment preparation"].buttons["Done"].tap()
            app.buttons["nav-chat"].tap(); app.buttons["Chats"].tap()
            XCTAssertTrue(app.navigationBars["Chats"].waitForExistence(timeout: 5))
            capture(first + 5, "flat-chat-history-" + theme)
            app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Demo · Recent readings")).firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Here are the readings saved in this fictional demo."].waitForExistence(timeout: 5))
            app.buttons["New chat"].tap()
        }
    }
}
