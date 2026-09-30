import XCTest

@MainActor final class HarbourConfirmationTests: XCTestCase {
    func testDeleteCancellationPreservesRecords() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Records"].tap(); app.buttons["Medicines"].tap()
        XCTAssertTrue(app.staticTexts["Warfarin"].firstMatch.exists)
        app.tabBars.buttons["Today"].tap(); app.buttons["Settings"].tap(); app.buttons["Delete all records and chat"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = "27-delete-confirmation"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.alerts.buttons["Cancel"].tap(); app.buttons["Done"].tap()
        app.tabBars.buttons["Records"].tap(); app.buttons["Medicines"].tap()
        XCTAssertTrue(app.staticTexts["Warfarin"].firstMatch.exists)
    }
}

@MainActor final class HarbourUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testMedicineConfirmationAndExport() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Records"].tap(); app.buttons["Medicines"].tap()
        for medicine in ["warfarin", "advil"] {
            app.buttons["Add record"].tap(); app.buttons["catalog-" + medicine].tap()
            XCTAssertFalse(app.buttons["saveMedicine"].isEnabled)
            app.buttons["confirmMedicine"].tap(); XCTAssertTrue(app.buttons["saveMedicine"].isEnabled); app.buttons["saveMedicine"].tap()
        }
        app.buttons["Check interactions"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["interactionSource"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap(); app.tabBars.buttons["Today"].tap(); app.buttons["Settings"].tap()
        app.buttons["Export records"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Native export"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testLocalModelChat() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Chat"].tap(); app.buttons["New chat"].tap()
        let input = app.textFields["chatInput"]
        input.tap(); input.typeText("Can I take Advil and warfarin together?")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["interactionSource"].firstMatch.waitForExistence(timeout: 120))
        input.tap(); input.typeText("Please save my heart rate of 72")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.textFields["readingValue"].waitForExistence(timeout: 45))
        XCTAssertEqual(app.textFields["readingValue"].value as? String, "72")
        app.buttons["saveReading"].tap()
        input.tap(); input.typeText("My knee has been sore since Tuesday")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.textFields["symptomText"].waitForExistence(timeout: 45))
        XCTAssertEqual(app.textFields["symptomText"].value as? String, "My knee has been sore since Tuesday")
        app.buttons["noEmergencySigns"].tap(); app.buttons["saveSymptom"].tap(); app.buttons["saveSymptom"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Symptom saved.")).firstMatch.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Native chat"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testRecordsAndPersistence() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Records"].tap(); app.buttons["Readings"].tap(); app.buttons["Add record"].tap()
        let value = app.textFields["readingValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5)); value.tap(); value.typeText("72")
        app.buttons["saveReading"].tap()
        XCTAssertTrue(app.staticTexts["72"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Symptoms"].tap(); app.buttons["Add record"].tap()
        let symptom = app.textFields["symptomText"]
        XCTAssertTrue(symptom.waitForExistence(timeout: 5)); symptom.tap(); symptom.typeText("Sore knee since Tuesday")
        app.buttons["Done"].tap()
        app.buttons["noEmergencySigns"].tap(); app.buttons["saveSymptom"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Health811"].waitForExistence(timeout: 5)); app.buttons["saveSymptom"].tap()
        XCTAssertTrue(app.staticTexts["Sore knee since Tuesday"].firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["72"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Records"].tap()
        XCTAssertTrue(app.staticTexts["Sore knee since Tuesday"].firstMatch.exists)
    }
    func testChatHintPreservesDraftAndModelSelector() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Chat"].tap()
        let input = app.textFields["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Hello there")
        app.buttons["Choose a topic"].tap(); app.buttons["Medicines"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Clear Medicines topic"].waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Hello there")
        app.buttons["modelSelector"].tap()
        XCTAssertTrue(app.staticTexts["Qwen Small"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["Generation effort"].exists)
    }
    func testScreenshots() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Today"].tap()
        capture(app, "01-today")
        app.tabBars.buttons["Records"].tap(); capture(app, "02-symptoms")
        app.buttons["Medicines"].tap(); capture(app, "03-medicines")
        app.buttons["Readings"].tap(); capture(app, "04-readings")
        app.buttons["Add record"].tap(); capture(app, "05-add-reading"); app.buttons["Cancel"].tap()
        app.buttons["Medicines"].tap(); app.buttons["Add record"].tap(); capture(app, "06-medicine-catalog")
        app.buttons["catalog-advil"].tap(); capture(app, "07-medicine-details"); app.buttons["Cancel"].tap()
        app.buttons["Symptoms"].tap(); app.buttons["Add record"].tap()
        let text = app.textFields["symptomText"]; text.tap(); text.typeText("My knee has been sore since Tuesday")
        app.buttons["Done"].tap(); capture(app, "08-symptom-intake")
        app.buttons["noEmergencySigns"].tap(); app.buttons["saveSymptom"].tap(); app.swipeUp(); capture(app, "09-symptom-review"); app.buttons["Cancel"].tap()
        app.tabBars.buttons["Chat"].tap(); capture(app, "10-chat-conversation")
        app.buttons["New chat"].tap(); capture(app, "11-chat-empty")
        app.buttons["Choose a topic"].tap(); capture(app, "12-topics"); app.buttons["Medicines"].tap()
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        capture(app, "13-chat-topic")
        app.buttons["modelSelector"].tap()
        XCTAssertTrue(app.staticTexts["Qwen Small"].firstMatch.waitForExistence(timeout: 5)); capture(app, "14-models")
        if app.buttons["Download"].exists {
            app.buttons["Download"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 10))
            let progress = app.progressIndicators.firstMatch
            let advancing = NSPredicate { _, _ in progress.exists && (progress.value as? String ?? "0%") != "0%" }
            _ = XCTWaiter.wait(for: [expectation(for: advancing, evaluatedWith: nil)], timeout: 20)
            capture(app, "15-model-download"); app.buttons["Cancel"].firstMatch.tap()
        }
        app.buttons["Done"].tap(); app.tabBars.buttons["Today"].tap(); app.buttons["Settings"].tap(); capture(app, "16-settings")
        app.buttons["Evaluation"].tap(); capture(app, "17-evaluation")
        app.navigationBars["Evaluation"].buttons.firstMatch.tap(); app.buttons["Export records"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5)); capture(app, "18-export")
        app.buttons["Close"].tap(); app.buttons["Done"].tap()
        app.swipeUp(); app.buttons["Appointment note"].tap(); capture(app, "19-appointment-note")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}

@MainActor final class HarbourScreenshotTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testHealthPermissionScreenshot() {
        let app = XCUIApplication(); app.launch(); app.tabBars.buttons["Today"].tap(); app.buttons["Settings"].tap()
        app.buttons["Import from Apple Health"].tap()
        _ = app.buttons["Allow"].waitForExistence(timeout: 10)
        capture(app, "26-health-access")
        app.terminate()
    }
    func testScreenshotDetails() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Records"].tap(); app.buttons["Medicines"].tap()
        app.buttons["Check interactions"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["interactionSource"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "20-interactions"); app.buttons["Done"].tap(); app.tabBars.buttons["Today"].tap()
        app.buttons["addSymptom"].tap()
        let symptom = app.textFields["symptomText"]; symptom.tap(); symptom.typeText("Severe chest pain")
        app.buttons["Done"].tap(); app.buttons["Persistent, severe chest pain"].tap(); app.buttons["saveSymptom"].tap(); app.swipeUp()
        XCTAssertTrue(app.staticTexts["Emergency care"].waitForExistence(timeout: 5)); capture(app, "21-emergency-review"); app.buttons["Cancel"].tap()
        app.tabBars.buttons["Records"].tap(); app.buttons["Symptoms"].tap(); app.staticTexts["Sore knee since Tuesday"].firstMatch.tap()
        capture(app, "22-symptom-detail"); app.navigationBars["Symptom"].buttons.firstMatch.tap()
        app.buttons["Readings"].tap(); app.buttons["Add record"].tap()
        app.buttons["readingKind"].tap(); app.buttons["Blood pressure"].tap()
        let value = app.textFields["readingValue"]; value.tap(); value.typeText("120/80"); app.buttons["Done"].tap()
        capture(app, "23-blood-pressure"); app.buttons["Cancel"].tap()
        app.buttons["Add record"].tap(); app.buttons["readingKind"].tap(); app.buttons["Temperature"].tap()
        value.tap(); value.typeText("36.8"); app.buttons["Done"].tap(); capture(app, "24-temperature"); app.buttons["Cancel"].tap()
        app.buttons["Medicines"].tap(); app.buttons["Add record"].tap()
        let medicine = app.textFields["medicineSearch"]; medicine.tap(); medicine.typeText("Unlisted medicine")
        app.buttons["addUnlistedMedicine"].tap()
        capture(app, "25-manual-medicine"); app.buttons["Cancel"].tap()
        app.tabBars.buttons["Today"].tap(); app.buttons["Settings"].tap(); app.buttons["Import from Apple Health"].tap()
        capture(app, "26-health-access")
        app.terminate(); app.launch(); app.tabBars.buttons["Today"].tap(); app.buttons["Settings"].tap(); app.buttons["Delete all records and chat"].tap()
        XCTAssertTrue(app.buttons["Delete all"].waitForExistence(timeout: 5))
        capture(app, "27-delete-confirmation"); app.terminate(); app.launch()
        app.tabBars.buttons["Chat"].tap(); app.buttons["New chat"].tap(); app.textFields["chatInput"].tap()
        app.textFields["chatInput"].typeText("What can you help me record?")
        XCTAssertTrue(app.buttons["modelSelector"].isHittable); capture(app, "28-chat-keyboard")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
