import XCTest

@MainActor private func selectRecords(_ app: XCUIApplication, _ name: String) {
    if app.navigationBars[name].exists { return }
    for _ in 0..<3 {
        if app.navigationBars["Records"].exists { break }
        app.navigationBars.buttons.firstMatch.tap()
    }
    let index = ["Symptoms": 0, "Medicines": 1, "Readings": 2][name]!
    app.buttons["record-category-\(index)"].tap()
    XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
}

@MainActor private func openSymptomCapture(_ app: XCUIApplication) {
    app.buttons["nav-records"].tap(); selectRecords(app, "Symptoms"); app.buttons["Add record"].tap()
}
@MainActor private func openInteractions(_ app: XCUIApplication) {
    app.buttons["nav-records"].tap(); selectRecords(app, "Medicines"); app.buttons["Check interactions"].tap()
}
@MainActor private func openPreparation(_ app: XCUIApplication) {
    app.buttons["nav-visits"].tap(); app.buttons["prepareAppointment"].tap()
}

@MainActor final class HarbourConfirmationTests: XCTestCase {
    func testDeleteCancellationPreservesRecords() {
        let app = XCUIApplication(); app.launch()
        app.buttons["nav-records"].tap(); selectRecords(app, "Medicines")
        XCTAssertTrue(app.staticTexts["Warfarin"].firstMatch.exists)
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Delete all records and chat"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = "27-delete-confirmation"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.alerts.buttons["Cancel"].tap(); app.buttons["Done"].tap()
        app.buttons["nav-records"].tap(); selectRecords(app, "Medicines")
        XCTAssertTrue(app.staticTexts["Warfarin"].firstMatch.exists)
    }
}

@MainActor final class HarbourUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testMedicineConfirmationAndExport() {
        let app = XCUIApplication(); app.launch()
        app.buttons["nav-records"].tap(); selectRecords(app, "Medicines")
        for medicine in ["warfarin", "advil"] {
            app.buttons["Add record"].tap(); app.buttons["catalog-" + medicine].tap()
            XCTAssertFalse(app.buttons["saveMedicine"].isEnabled)
            app.buttons["confirmMedicine"].tap(); XCTAssertTrue(app.buttons["saveMedicine"].isEnabled); app.buttons["saveMedicine"].tap()
        }
        openInteractions(app)
        XCTAssertTrue(app.descendants(matching: .any)["interactionSource"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap(); app.buttons["nav-today"].tap(); app.buttons["Settings"].tap()
        app.buttons["Export records"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Native export"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testLocalModelChat() {
        let app = XCUIApplication(); app.launch()
        app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap()
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
        app.buttons["nav-records"].tap(); selectRecords(app, "Readings"); app.buttons["Add record"].tap()
        let value = app.textFields["readingValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5)); value.tap(); value.typeText("72")
        app.buttons["saveReading"].tap()
        XCTAssertTrue(app.staticTexts["72"].firstMatch.waitForExistence(timeout: 5))
        selectRecords(app, "Symptoms"); app.buttons["Add record"].tap()
        let symptom = app.textFields["symptomText"]
        XCTAssertTrue(symptom.waitForExistence(timeout: 5)); symptom.tap(); symptom.typeText("Sore knee since Tuesday")
        app.buttons["Done"].tap()
        app.buttons["noEmergencySigns"].tap(); app.buttons["saveSymptom"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Health811"].waitForExistence(timeout: 5)); app.buttons["saveSymptom"].tap()
        XCTAssertTrue(app.staticTexts["Sore knee since Tuesday"].firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.buttons["nav-today"].tap()
        XCTAssertTrue(app.staticTexts["72"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["nav-records"].tap(); selectRecords(app, "Symptoms")
        XCTAssertTrue(app.staticTexts["Sore knee since Tuesday"].firstMatch.exists)
    }
    func testChatHintPreservesDraftAndModelSelector() {
        let app = XCUIApplication(); app.launch()
        app.buttons["nav-chat"].tap()
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
        app.buttons["nav-today"].tap()
        capture(app, "01-today")
        app.buttons["nav-records"].tap(); capture(app, "64-records"); selectRecords(app, "Symptoms"); capture(app, "02-symptoms")
        selectRecords(app, "Medicines"); capture(app, "03-medicines")
        selectRecords(app, "Readings"); capture(app, "04-readings")
        app.buttons["Add record"].tap(); capture(app, "05-add-reading"); app.buttons["Cancel"].tap()
        selectRecords(app, "Medicines"); app.buttons["Add record"].tap(); capture(app, "06-medicine-catalog")
        app.buttons["catalog-advil"].tap(); capture(app, "07-medicine-details"); app.buttons["Cancel"].tap()
        selectRecords(app, "Symptoms"); app.buttons["Add record"].tap()
        let text = app.textFields["symptomText"]; text.tap(); text.typeText("My knee has been sore since Tuesday")
        app.buttons["Done"].tap(); capture(app, "08-symptom-intake")
        app.buttons["noEmergencySigns"].tap(); app.buttons["saveSymptom"].tap(); app.swipeUp(); capture(app, "09-symptom-review"); app.buttons["Cancel"].tap()
        app.buttons["nav-chat"].tap(); capture(app, "10-chat-conversation")
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
        app.buttons["Done"].tap(); app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); capture(app, "16-settings")
        app.buttons["Evaluation"].tap(); capture(app, "17-evaluation")
        app.navigationBars["Evaluation"].buttons.firstMatch.tap(); app.buttons["Export records"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5)); capture(app, "18-export")
        app.buttons["Close"].tap(); app.buttons["Done"].tap()
        app.swipeUp(); openPreparation(app); capture(app, "19-appointment-note")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}

@MainActor final class HarbourScreenshotTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testHealthPermissionScreenshot() {
        let app = XCUIApplication(); app.launch(); app.buttons["nav-today"].tap(); app.buttons["Settings"].tap()
        app.buttons["Import from Apple Health"].tap()
        _ = app.buttons["Allow"].waitForExistence(timeout: 10)
        capture(app, "26-health-access")
        app.terminate()
    }
    func testScreenshotDetails() {
        let app = XCUIApplication(); app.launch()
        app.buttons["nav-records"].tap(); selectRecords(app, "Medicines")
        openInteractions(app)
        XCTAssertTrue(app.descendants(matching: .any)["interactionSource"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "20-interactions"); app.buttons["Done"].tap(); app.buttons["nav-today"].tap()
        openSymptomCapture(app)
        let symptom = app.textFields["symptomText"]; symptom.tap(); symptom.typeText("Severe chest pain")
        app.buttons["Done"].tap(); app.buttons["Persistent, severe chest pain"].tap(); app.buttons["saveSymptom"].tap(); app.swipeUp()
        XCTAssertTrue(app.staticTexts["Emergency care"].waitForExistence(timeout: 5)); capture(app, "21-emergency-review"); app.buttons["Cancel"].tap()
        app.buttons["nav-records"].tap(); selectRecords(app, "Symptoms"); app.staticTexts["Sore knee since Tuesday"].firstMatch.tap()
        capture(app, "22-symptom-detail"); app.navigationBars["Symptom"].buttons.firstMatch.tap()
        selectRecords(app, "Readings"); app.buttons["Add record"].tap()
        app.buttons["readingKind"].tap(); app.buttons["Blood pressure"].tap()
        let value = app.textFields["readingValue"]; value.tap(); value.typeText("120/80"); app.buttons["Done"].tap()
        capture(app, "23-blood-pressure"); app.buttons["Cancel"].tap()
        app.buttons["Add record"].tap(); app.buttons["readingKind"].tap(); app.buttons["Temperature"].tap()
        value.tap(); value.typeText("36.8"); app.buttons["Done"].tap(); capture(app, "24-temperature"); app.buttons["Cancel"].tap()
        selectRecords(app, "Medicines"); app.buttons["Add record"].tap()
        let medicine = app.textFields["medicineSearch"]; medicine.tap(); medicine.typeText("Unlisted medicine")
        app.buttons["addUnlistedMedicine"].tap()
        capture(app, "25-manual-medicine"); app.buttons["Cancel"].tap()
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Import from Apple Health"].tap()
        capture(app, "26-health-access")
        app.terminate(); app.launch(); app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Delete all records and chat"].tap()
        XCTAssertTrue(app.buttons["Delete all"].waitForExistence(timeout: 5))
        capture(app, "27-delete-confirmation"); app.terminate(); app.launch()
        app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap(); app.textFields["chatInput"].tap()
        app.textFields["chatInput"].typeText("What can you help me record?")
        XCTAssertTrue(app.buttons["modelSelector"].isHittable); capture(app, "28-chat-keyboard")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}


@MainActor final class HarbourRichResultsTests: XCTestCase {
    private func appearance(_ app: XCUIApplication, _ choice: String) {
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Appearance"].tap(); app.buttons["appearance-" + choice.lowercased()].tap()
        app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testRichToolResults() {
        let app = XCUIApplication(); app.launch()
        for dark in [false, true] {
            appearance(app, dark ? "Dark" : "Light")
            app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap()
            let input = app.textFields["chatInput"]
            input.tap(); input.typeText("Show my medicines"); app.buttons["Send message"].tap()
            XCTAssertTrue(app.staticTexts["Your medicines"].waitForExistence(timeout: 120)); XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 60)); capture(dark ? "45-chat-medicines-dark" : "44-chat-medicines")
            app.buttons["New chat"].tap(); input.tap(); input.typeText("Show my recent readings"); app.buttons["Send message"].tap()
            XCTAssertTrue(app.staticTexts["Recent readings"].waitForExistence(timeout: 60)); XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 60)); capture(dark ? "47-chat-readings-dark" : "46-chat-readings")
            app.buttons["New chat"].tap(); input.tap(); input.typeText("Can I take Advil and warfarin together?"); app.buttons["Send message"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["interactionSource"].firstMatch.waitForExistence(timeout: 60)); XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 60)); capture(dark ? "42-chat-result-dark" : "10-chat-conversation")
        }
        appearance(app, "System")
    }
}

@MainActor final class HarbourAppearanceTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func appearance(_ app: XCUIApplication, _ choice: String) {
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Appearance"].tap()
        app.buttons["appearance-" + choice.lowercased()].tap()
        XCTAssertTrue(app.buttons["appearance-" + choice.lowercased()].isSelected)
        app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testScreensAndAppearancePersistence() {
        let app = XCUIApplication(); app.launch()
        for dark in [false, true] {
            appearance(app, dark ? "Dark" : "Light")
            app.terminate(); app.launch()
            app.buttons["Settings"].tap(); app.buttons["Appearance"].tap()
            XCTAssertTrue(app.buttons[dark ? "appearance-dark" : "appearance-light"].isSelected)
            capture(dark ? "41-appearance-dark" : "40-appearance-light")
            app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
            capture(dark ? "31-today-dark" : "01-today")
            app.buttons["nav-records"].tap(); capture(dark ? "65-records-dark" : "64-records"); selectRecords(app, "Symptoms"); capture(dark ? "33-symptoms-dark" : "02-symptoms")
            selectRecords(app, "Medicines"); capture(dark ? "34-medicines-dark" : "03-medicines")
            selectRecords(app, "Readings"); capture(dark ? "35-readings-dark" : "04-readings")
            app.buttons["Add record"].tap(); capture(dark ? "48-add-reading-dark" : "05-add-reading"); app.buttons["Cancel"].tap()
            selectRecords(app, "Medicines"); app.buttons["Add record"].tap(); capture(dark ? "49-catalog-dark" : "06-medicine-catalog")
            app.buttons["catalog-advil"].tap(); capture(dark ? "50-confirm-medicine-dark" : "07-medicine-details"); app.buttons["Cancel"].tap()
            selectRecords(app, "Symptoms"); app.buttons["Add record"].tap()
            let text = app.textFields["symptomText"]; text.tap(); text.typeText("My knee has been sore since Tuesday"); app.buttons["Done"].tap()
            capture(dark ? "51-symptom-entry-dark" : "08-symptom-intake")
            app.buttons["noEmergencySigns"].tap(); app.buttons["saveSymptom"].tap(); app.swipeUp()
            XCTAssertTrue(app.staticTexts["Health811"].exists)
            capture(dark ? "52-symptom-review-dark" : "09-symptom-review"); app.buttons["Cancel"].tap()
            app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap(); capture(dark ? "32-chat-dark" : "11-chat-empty")
            let input = app.textFields["chatInput"]; input.tap(); input.typeText("Hello there")
            app.buttons["Choose a topic"].tap(); capture(dark ? "36-topics-dark" : "12-topics"); app.buttons["Medicines"].tap()
            XCTAssertEqual(input.value as? String, "Hello there")
            XCTAssertTrue(app.buttons["Clear Medicines topic"].exists)
            app.buttons["Done"].tap(); capture(dark ? "53-selected-topic-dark" : "13-chat-topic")
            app.buttons["modelSelector"].tap(); XCTAssertTrue(app.sliders["Generation effort"].exists)
            capture(dark ? "37-models-dark" : "14-models"); app.buttons["Done"].tap()
            app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); capture(dark ? "38-settings-dark" : "16-settings")
            if !dark {
                app.buttons["Evaluation"].tap(); capture("17-evaluation"); app.navigationBars["Evaluation"].buttons.firstMatch.tap()
                app.buttons["Export records"].tap(); XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5)); capture("18-export"); app.buttons["Close"].tap()
                app.buttons["Delete all records and chat"].tap(); capture("27-delete-confirmation"); app.alerts.buttons["Cancel"].tap()
            }
            app.buttons["Done"].tap(); app.swipeUp(); openPreparation(app); capture(dark ? "39-note-dark" : "19-appointment-note"); app.buttons["Done"].tap()
        }
        appearance(app, "System")
    }

}

@MainActor final class HarbourDetailRefreshTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testEntryAndReviewScreens() {
        let app = XCUIApplication(); app.launch()
        app.buttons["Settings"].tap(); app.buttons["Appearance"].tap(); app.buttons["appearance-light"].tap()
        app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
        app.buttons["nav-records"].tap(); selectRecords(app, "Medicines"); openInteractions(app)
        XCTAssertTrue(app.descendants(matching: .any)["interactionSource"].firstMatch.waitForExistence(timeout: 5)); capture("20-interactions"); app.buttons["Done"].tap()
        app.buttons["nav-today"].tap(); openSymptomCapture(app)
        let symptom = app.textFields["symptomText"]; symptom.tap(); symptom.typeText("Severe chest pain"); app.buttons["Done"].tap()
        app.buttons["Persistent, severe chest pain"].tap(); app.buttons["saveSymptom"].tap(); app.swipeUp()
        XCTAssertTrue(app.staticTexts["Emergency care"].exists); capture("21-emergency-review"); app.buttons["Cancel"].tap()
        app.buttons["nav-records"].tap(); selectRecords(app, "Symptoms"); app.staticTexts["Sore knee since Tuesday"].firstMatch.tap()
        capture("22-symptom-detail"); app.navigationBars["Symptom"].buttons.firstMatch.tap()
        selectRecords(app, "Readings"); app.buttons["Add record"].tap(); app.buttons["readingKind"].tap(); app.buttons["Blood pressure"].tap()
        let value = app.textFields["readingValue"]; value.tap(); value.typeText("120/80"); app.buttons["Done"].tap(); capture("23-blood-pressure"); app.buttons["Cancel"].tap()
        app.buttons["Add record"].tap(); app.buttons["readingKind"].tap(); app.buttons["Temperature"].tap()
        value.tap(); value.typeText("36.8"); app.buttons["Done"].tap(); capture("24-temperature"); app.buttons["Cancel"].tap()
        selectRecords(app, "Medicines"); app.buttons["Add record"].tap()
        let medicine = app.textFields["medicineSearch"]; medicine.tap(); medicine.typeText("Unlisted medicine"); app.buttons["addUnlistedMedicine"].tap()
        capture("25-manual-medicine"); app.buttons["Cancel"].tap()
        app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap(); app.textFields["chatInput"].tap(); app.textFields["chatInput"].typeText("What can you help me record?")
        XCTAssertTrue(app.buttons["modelSelector"].isHittable); capture("28-chat-keyboard")
    }
}


@MainActor final class HarbourNavigationTests: XCTestCase {
    func testDashboardNavigationAndSystemAppearance() {
        let app = XCUIApplication(); app.launch()
        app.buttons["openMedicines"].tap()
        XCTAssertTrue(app.staticTexts["Warfarin"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Medicines"].exists)
        app.buttons["Add record"].tap()
        XCTAssertTrue(app.buttons["catalog-advil"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap()
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Appearance"].tap(); app.buttons["appearance-system"].tap()
        XCTAssertTrue(app.buttons["appearance-system"].isSelected)
        app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
        app.buttons["nav-chat"].tap(); app.buttons["modelSelector"].tap()
        let slider = app.sliders["Generation effort"]; XCTAssertTrue(slider.exists)
        slider.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(slider.value as? String, "Extended")
        slider.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertEqual(slider.value as? String, "Standard")
        let models = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); models.name = "37-models-dark"; models.lifetime = .keepAlways; add(models)
        app.buttons["Done"].tap(); app.buttons["nav-today"].tap()
        app.terminate(); app.launch()
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "43-system-dark"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

@MainActor final class HarbourLockTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func enter(_ app: XCUIApplication, _ pin: String) {
        XCTAssertTrue(app.descendants(matching: .any)["pinSlots"].firstMatch.waitForExistence(timeout: 5))
        for digit in pin { app.buttons["pin-key-\(digit)"].tap() }
    }
    func testPINLifecycleAndThrottle() {
        let app = XCUIApplication(); app.launch()
        app.buttons["Settings"].tap(); app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "App lock")).firstMatch.tap()
        capture("54-app-lock-settings")
        app.buttons["lock-option-pin"].tap(); enter(app, "5826")
        XCTAssertTrue(app.staticTexts["Confirm PIN"].waitForExistence(timeout: 5)); enter(app, "5820")
        XCTAssertTrue(app.staticTexts["Those PINs don’t match."].waitForExistence(timeout: 5)); capture("61-pin-mismatch")
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
        enter(app, "5826"); XCTAssertTrue(app.staticTexts["Confirm PIN"].waitForExistence(timeout: 5))
        enter(app, "582"); capture("55-pin-setup"); app.buttons["pin-key-6"].tap()
        XCTAssertTrue(app.buttons["lockNow"].waitForExistence(timeout: 5)); app.buttons["lockNow"].tap()
        XCTAssertTrue(app.staticTexts["Enter PIN"].waitForExistence(timeout: 5)); capture("56-pin-lock")
        XCTAssertFalse(app.buttons["nav-records"].exists); XCTAssertFalse(app.secureTextFields.firstMatch.exists)
        enter(app, "1111"); XCTAssertTrue(app.staticTexts["Incorrect PIN. Try again."].waitForExistence(timeout: 5))
        // Delete removes the last digit without submitting a guess.
        enter(app, "58"); app.buttons["pin-delete"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["pinSlots"].firstMatch.value as? String, "1 of 4 digits entered")
        enter(app, "826"); XCTAssertTrue(app.buttons["nav-today"].waitForExistence(timeout: 5))
        openSymptomCapture(app); XCTAssertTrue(app.textFields["symptomText"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.staticTexts["Enter PIN"].waitForExistence(timeout: 5)); XCTAssertFalse(app.textFields["symptomText"].exists)
        for attempt in 0..<5 {
            enter(app, "1111")
            XCTAssertTrue(app.staticTexts[attempt == 4 ? "Too many attempts. Please wait before trying again." : "Incorrect PIN. Try again."].waitForExistence(timeout: 5))
        }
        capture("57-pin-retry-delay"); XCTAssertFalse(app.buttons["pin-key-5"].isEnabled)
        app.terminate(); app.launch(); XCTAssertFalse(app.buttons["pin-key-5"].isEnabled)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["pin-key-5"])
        waitForExpectations(timeout: 35)
        enter(app, "5826"); XCTAssertTrue(app.buttons["nav-today"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap(); app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "App lock")).firstMatch.tap(); app.buttons["lock-option-off"].tap()
        XCTAssertTrue(app.staticTexts["Current PIN"].waitForExistence(timeout: 5)); capture("59-current-pin")
        enter(app, "1111"); XCTAssertTrue(app.staticTexts["Incorrect PIN. Try again."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current PIN"].exists)
        enter(app, "5826"); XCTAssertTrue(app.buttons["lock-option-off"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["lock-option-off"].isSelected)
        app.terminate(); app.launch(); XCTAssertTrue(app.buttons["nav-today"].waitForExistence(timeout: 5))
    }
}

@MainActor final class HarbourFreshScreensTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    // Run on a fresh, disposable simulator so downloads and permissions need no reset.
    func testDownloadPermissionsAndImportScreens() {
        let app = XCUIApplication(); app.launch()
        app.buttons["Settings"].tap(); app.buttons["Appearance"].tap(); app.buttons["appearance-light"].tap()
        app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Models"].tap()
        XCTAssertTrue(app.buttons["Download"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Download"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        let advancing = app.staticTexts.containing(NSPredicate(format: "label MATCHES %@", "[1-9][0-9]*%"))
        XCTAssertTrue(advancing.firstMatch.waitForExistence(timeout: 30)); capture("15-model-download")
        app.buttons["Cancel"].tap(); XCTAssertTrue(app.buttons["Download"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars["Models"].buttons.firstMatch.tap()
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "App lock")).firstMatch.tap()
        app.buttons["lock-option-biometrics"].tap()
        XCTAssertTrue(app.staticTexts["lockSettingsError"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lock-option-off"].isSelected); capture("62-face-id-unavailable")
        app.navigationBars["App lock"].buttons.firstMatch.tap()
        app.buttons["Import from Apple Health"].tap()
        XCTAssertTrue(app.buttons["Allow"].waitForExistence(timeout: 10)); capture("30-health-permission")
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() } else { app.buttons["Don’t Allow"].tap() }
        if app.alerts["Health Access"].waitForExistence(timeout: 3) { capture("63-health-access-reminder"); app.alerts["Health Access"].buttons["OK"].tap() }
        let healthStatus = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "No readings available.", "Couldn’t access Apple Health."))
        XCTAssertTrue(healthStatus.firstMatch.waitForExistence(timeout: 10)); capture("26-health-access")
        app.buttons["Import records"].tap(); XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5)); capture("60-import-records")
        app.buttons["Cancel"].tap()
    }
}

@MainActor final class HarbourEvaluationScreenTests: XCTestCase {
    func testEvaluationResultsScreenshot() {
        let app = XCUIApplication(); app.launch(); app.buttons["Settings"].tap(); app.buttons["Evaluation"].tap()
        let all = app.switches["Test all effort settings"]
        for _ in 0..<5 { if all.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(all.isHittable); all.tap(); app.buttons["Evaluate selected model"].tap()
        XCTAssertTrue(app.buttons["Stop evaluation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Evaluate selected model"].waitForExistence(timeout: 150))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "29-evaluation-results"; shot.lifetime = .keepAlways; add(shot)
    }
}

@MainActor final class HarbourDashboardTests: XCTestCase {
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    func testDashboardAndGeneratedTitle() {
        let app = XCUIApplication(); app.launch()
        app.buttons["Settings"].tap(); app.buttons["Appearance"].tap(); app.buttons["appearance-light"].tap(); app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
        let medicine = app.buttons["openMedicines"], symptoms = app.buttons["addSymptom"]
        XCTAssertEqual(medicine.frame.height, symptoms.frame.height, accuracy: 1)
        XCTAssertEqual(medicine.frame.width, symptoms.frame.width, accuracy: 1)
        // Decorative overlay bounds include the cropped artwork; visible headings retain the margins.
        XCTAssertGreaterThanOrEqual(app.staticTexts["Medicines"].firstMatch.frame.minX, 32)
        XCTAssertLessThanOrEqual(app.staticTexts["Symptoms"].firstMatch.frame.maxX, app.frame.width - 32)
        XCTAssertTrue(app.otherElements["readingSummary"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        capture("01-today")
        app.buttons["Settings"].tap(); app.buttons["Appearance"].tap(); app.buttons["appearance-dark"].tap(); app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap(); capture("31-today-dark")
        app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap()
        XCTAssertEqual(app.staticTexts["chatTitle"].label, "New chat"); capture("32-chat-dark")
        XCTAssertLessThanOrEqual(app.buttons["modelSelector"].frame.maxY, app.buttons["nav-chat"].frame.minY)
        XCTAssertTrue(app.buttons["modelSelector"].isHittable)
        // The AX text view covers its two lines; the containing draft area reserves extra space.
        XCTAssertGreaterThanOrEqual(app.textFields["chatInput"].frame.height, 46)
        XCTAssertGreaterThanOrEqual(app.buttons["modelSelector"].frame.maxY - app.textFields["chatInput"].frame.minY, 130)
        let input = app.textFields["chatInput"]; input.tap(); input.typeText("Could you show me the medicines I recorded?"); app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["Your medicines"].waitForExistence(timeout: 120))
        XCTAssertTrue(app.buttons["Send message"].waitForExistence(timeout: 60))
        let title = app.staticTexts["chatTitle"].label
        XCTAssertFalse(title.isEmpty); XCTAssertNotEqual(title, "New chat"); XCTAssertNotEqual(title, "Could you show me the medicines")
        capture("58-generated-chat-title")
        app.terminate(); app.launch(); app.buttons["nav-chat"].tap(); XCTAssertEqual(app.staticTexts["chatTitle"].label, title)
        app.buttons["New chat"].tap(); XCTAssertEqual(app.staticTexts["chatTitle"].label, "New chat")
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Appearance"].tap(); app.buttons["appearance-light"].tap(); app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
        app.buttons["nav-chat"].tap(); capture("11-chat-empty")
    }
}

@MainActor final class HarbourFloatingDockTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testSupplementaryCapturePages() {
        let app = XCUIApplication(); app.launch(); app.buttons["Settings"].tap()
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "App lock")).firstMatch.tap()
        app.buttons["lock-option-biometrics"].tap()
        XCTAssertTrue(app.staticTexts["lockSettingsError"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lock-option-off"].isSelected)
        var shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "62-face-id-unavailable"; shot.lifetime = .keepAlways; add(shot)
        app.navigationBars["App lock"].buttons.firstMatch.tap()
        app.buttons["Import records"].tap(); XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "60-import-records"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Cancel"].tap(); app.buttons["Done"].tap()
    }

    func testScrollableContentAndKeyboardClearance() {
        let app = XCUIApplication(); app.launch()
        app.buttons["Settings"].tap(); app.buttons["Appearance"].tap(); app.buttons["appearance-light"].tap()
        app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        let note = app.buttons["Timeline"]
        for _ in 0..<4 {
            if note.isHittable && note.frame.maxY < app.buttons["nav-today"].frame.minY { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(note.isHittable)
        XCTAssertLessThan(note.frame.maxY, app.buttons["nav-today"].frame.minY)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "66-floating-navigation"; attachment.lifetime = .keepAlways; add(attachment)
        note.tap(); XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 5)); app.navigationBars["Timeline"].buttons.firstMatch.tap()
        app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap()
        XCTAssertLessThanOrEqual(app.buttons["modelSelector"].frame.maxY, app.buttons["nav-chat"].frame.minY)
        app.textFields["chatInput"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["nav-chat"].exists)
        XCTAssertTrue(app.buttons["modelSelector"].isHittable)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["nav-chat"].waitForExistence(timeout: 5))
        app.buttons["nav-records"].tap(); selectRecords(app, "Readings")
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertTrue(app.buttons["Add record"].isHittable)
        app.buttons["Add record"].tap(); XCTAssertTrue(app.textFields["readingValue"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap()
    }
}

@MainActor final class HarbourVisitTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    func testVisitNotesLocalSummaryAndConfirmedMedicineChanges() {
        let app = XCUIApplication(); app.launch()
        app.buttons["nav-visits"].tap(); capture("67-visits")
        app.buttons["recordVisit"].tap(); capture("68-visit-recorder")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["addVisitNotes"].tap()
        XCTAssertTrue(app.textViews["visitTranscriptInput"].waitForExistence(timeout: 5))
        let title = app.textFields["visitTitleInput"]
        title.tap(); title.press(forDuration: 1.2)
        if app.menuItems["Select All"].exists { app.menuItems["Select All"].tap() }
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40) + "Medication review")
        let transcript = app.textViews["visitTranscriptInput"]
        transcript.tap(); transcript.typeText("Start metformin 500 mg twice daily. Book blood work in two weeks.")
        app.buttons["Done"].tap(); app.buttons["saveVisitTranscript"].tap()
        capture("69-visit-notes")
        app.buttons["summariseVisit"].tap()
        XCTAssertTrue(app.buttons["reviewVisitMedicines"].waitForExistence(timeout: 120), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Book blood work in two weeks."].exists)
        capture("70-visit-summary")
        app.buttons["reviewVisitMedicines"].tap()
        XCTAssertFalse(app.buttons["saveVisitMedicines"].isEnabled)
        app.buttons["visit-change-metformin"].tap()
        XCTAssertFalse(app.buttons["saveVisitMedicines"].isEnabled)
        app.buttons["confirmVisitMedicines"].tap(); capture("71-visit-medicine-review")
        app.buttons["Cancel"].tap(); app.buttons["reviewVisitMedicines"].tap()
        XCTAssertFalse(app.buttons["saveVisitMedicines"].isEnabled)
        app.buttons["visit-change-metformin"].tap(); app.buttons["confirmVisitMedicines"].tap(); app.buttons["saveVisitMedicines"].tap()
        XCTAssertTrue(app.staticTexts["Medicine changes saved"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.buttons["nav-visits"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Medication review")).firstMatch.waitForExistence(timeout: 5))
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Medication review")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Medicine changes saved"].exists)
        app.buttons["Transcript"].tap(); capture("72-visit-transcript")
        XCTAssertTrue(app.staticTexts["savedVisitTranscript"].exists)
        app.buttons["Visit options"].tap(); app.buttons["Share notes"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5))
    }
    func testRecorderPauseResumeAndAudioPersistence() {
        let app = XCUIApplication(); app.launch()
        app.buttons["nav-visits"].tap(); app.buttons["recordVisit"].tap()
        addUIInterruptionMonitor(withDescription: "Microphone and speech") { alert in
            for name in ["Allow", "OK", "Allow While Using App"] { if alert.buttons[name].exists { alert.buttons[name].tap(); return true } }
            return false
        }
        app.buttons["visitRecordingControl"].tap()
        for _ in 0..<4 {
            if app.buttons["Pause recording"].exists { break }
            if app.alerts.firstMatch.exists { for name in ["Allow", "OK"] { if app.alerts.buttons[name].exists { app.alerts.buttons[name].tap() } } }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertTrue(app.buttons["Pause recording"].waitForExistence(timeout: 30), app.debugDescription)
        capture("73-visit-recording")
        app.buttons["Pause recording"].tap(); XCTAssertTrue(app.buttons["Resume recording"].waitForExistence(timeout: 5)); capture("74-visit-paused")
        app.buttons["Resume recording"].tap(); XCTAssertTrue(app.buttons["Pause recording"].waitForExistence(timeout: 5))
        app.buttons["nav-chat"].tap(); XCTAssertFalse(app.buttons["Voice options"].isEnabled)
        app.buttons["nav-visits"].tap(); XCTAssertTrue(app.buttons["Pause recording"].waitForExistence(timeout: 5))
        app.buttons["finishVisitRecording"].tap()
        XCTAssertTrue(app.buttons["Play visit audio"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["Play visit audio"].tap(); XCTAssertTrue(app.buttons["Pause visit audio"].waitForExistence(timeout: 5)); capture("75-visit-audio")
        app.buttons["Pause visit audio"].tap()
        app.terminate(); app.launch(); app.buttons["nav-visits"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Doctor visit")).firstMatch.waitForExistence(timeout: 5))
    }
    func testZUpdatedMainScreensAndDarkVisits() {
        let app = XCUIApplication(); app.launch()
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Appearance"].tap(); app.buttons["appearance-light"].tap()
        app.navigationBars.buttons.firstMatch.tap(); app.buttons["Done"].tap(); capture("01-today")
        app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap(); capture("11-chat-empty")
        app.buttons["nav-records"].tap(); capture("64-records")
        app.buttons["nav-visits"].tap(); capture("67-visits")
        app.buttons["addVisitNotes"].tap(); XCTAssertTrue(app.textViews["visitTranscriptInput"].waitForExistence(timeout: 5)); capture("87-new-visit-notes"); app.buttons["Cancel"].tap()
        app.buttons["recordVisit"].tap(); capture("68-visit-recorder"); app.navigationBars["Recorder"].buttons.firstMatch.tap()
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); capture("16-settings")
        app.buttons["Appearance"].tap(); app.buttons["appearance-dark"].tap(); app.navigationBars.buttons.firstMatch.tap(); capture("38-settings-dark"); app.buttons["Done"].tap()
        capture("31-today-dark"); app.buttons["nav-chat"].tap(); capture("32-chat-dark"); app.buttons["nav-records"].tap(); capture("65-records-dark")
        app.buttons["nav-visits"].tap(); capture("76-visits-dark")
        app.buttons["addVisitNotes"].tap(); XCTAssertTrue(app.textViews["visitTranscriptInput"].waitForExistence(timeout: 5)); capture("88-new-visit-notes-dark"); app.buttons["Cancel"].tap()
        app.buttons["recordVisit"].tap(); capture("77-visit-recorder-dark")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Medication review")).firstMatch.tap(); capture("78-visit-summary-dark")
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Appearance"].tap(); app.buttons["appearance-light"].tap()
    }
}

@MainActor final class HarbourDrawerTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func drawer(_ app: XCUIApplication, shorterThan maximum: CGFloat = 800) {
        let panel = app.descendants(matching: .any)["drawerBounds"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), app.debugDescription)
        let fits = NSPredicate { _, _ in
            let frame = panel.frame
            return frame.height > 100 && frame.height < maximum && frame.minX > 0 && frame.maxX < app.frame.width && frame.maxY < app.frame.height - 5
        }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: fits, evaluatedWith: nil)], timeout: 5), .completed, app.debugDescription)
    }
    func testCompactDrawersNavigationKeyboardAndThemes() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--verify-drawers"]; app.launch()
        for dark in [false, true] {
            app.buttons["nav-today"].tap(); app.buttons["Settings"].tap()
            app.buttons["Appearance"].tap(); app.buttons[dark ? "appearance-dark" : "appearance-light"].tap()
            drawer(app, shorterThan: 400); capture(dark ? "41-appearance-dark" : "40-appearance-light")
            app.navigationBars["Appearance"].buttons.firstMatch.tap()
            drawer(app, shorterThan: 750); capture(dark ? "38-settings-dark" : "16-settings")
            app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "App lock")).firstMatch.tap()
            drawer(app, shorterThan: 500); capture("54-app-lock-settings")
            app.buttons["lock-option-pin"].tap()
            XCTAssertTrue(app.staticTexts["Choose a PIN"].waitForExistence(timeout: 5))
            drawer(app, shorterThan: 650); capture(dark ? "80-pin-drawer-dark" : "55-pin-setup")
            app.buttons["pin-key-5"].tap(); app.buttons["pin-key-8"].tap()
            XCTAssertEqual(app.descendants(matching: .any)["pinSlots"].firstMatch.value as? String, "2 of 4 digits entered")
            app.buttons["Cancel"].tap(); app.navigationBars["App lock"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
            app.buttons["nav-records"].tap(); selectRecords(app, "Readings"); app.buttons["Add record"].tap()
            drawer(app, shorterThan: 400); capture(dark ? "48-add-reading-dark" : "05-add-reading")
            let value = app.textFields["readingValue"]; value.tap(); value.typeText("73")
            XCTAssertTrue(app.buttons["saveReading"].isHittable); drawer(app)
            capture(dark ? "82-reading-keyboard-dark" : "81-reading-keyboard")
            app.buttons["saveReading"].tap()
            XCTAssertTrue(app.staticTexts["73"].firstMatch.waitForExistence(timeout: 5))
            selectRecords(app, "Medicines"); app.buttons["Add record"].tap(); drawer(app)
            capture(dark ? "49-catalog-dark" : "06-medicine-catalog")
            app.buttons["catalog-advil"].tap(); drawer(app)
            XCTAssertFalse(app.buttons["saveMedicine"].isEnabled)
            capture(dark ? "50-confirm-medicine-dark" : "07-medicine-details"); app.buttons["Cancel"].tap()
            app.buttons["nav-chat"].tap(); app.buttons["Choose a topic"].tap()
            drawer(app, shorterThan: 430); capture(dark ? "36-topics-dark" : "12-topics")
            app.buttons["Medicines"].tap(); XCTAssertTrue(app.buttons["Clear Medicines topic"].exists)
            app.buttons["modelSelector"].tap(); drawer(app)
            capture(dark ? "37-models-dark" : "14-models"); app.buttons["Done"].tap()
        }
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Appearance"].tap()
        app.buttons["appearance-light"].tap(); app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
    }
}

@MainActor final class HarbourDrawerDetailTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    func testLongDrawersAndLandscape() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--verify-drawers"]; app.launch()
        app.buttons["nav-today"].tap(); openSymptomCapture(app)
        let symptom = app.textFields["symptomText"]; symptom.tap(); symptom.typeText("Sore knee since Tuesday")
        app.buttons["Done"].tap(); capture("08-symptom-intake")
        app.buttons["noEmergencySigns"].tap(); app.buttons["saveSymptom"].tap(); app.swipeUp()
        XCTAssertTrue(app.staticTexts["Health811"].waitForExistence(timeout: 5)); capture("09-symptom-review")
        app.buttons["Cancel"].tap(); app.swipeUp(); openInteractions(app)
        XCTAssertTrue(app.otherElements["floatingDrawer"].waitForExistence(timeout: 5)); capture("20-interactions")
        app.buttons["Done"].tap(); openPreparation(app); capture("19-appointment-note"); app.buttons["Done"].tap()
        app.buttons["nav-visits"].tap(); app.buttons["addVisitNotes"].tap()
        XCTAssertTrue(app.textViews["visitTranscriptInput"].waitForExistence(timeout: 5)); capture("83-visit-notes-drawer")
        app.buttons["Cancel"].tap(); app.buttons["nav-records"].tap(); selectRecords(app, "Readings")
        app.buttons["Add record"].tap()
        let value = app.textFields["readingValue"]; value.tap(); value.typeText("74"); app.buttons["Done"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.textFields["readingValue"].waitForExistence(timeout: 5))
        let panel = app.descendants(matching: .any)["drawerBounds"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        capture("79-reading-landscape")
        XCTAssertLessThan(panel.frame.maxY, app.frame.height - 5)
        XCTAssertEqual(value.value as? String, "74")
        XCTAssertTrue(app.buttons["saveReading"].isHittable); app.buttons["saveReading"].tap()
        XCTAssertTrue(app.staticTexts["74"].firstMatch.waitForExistence(timeout: 5))
    }
}

@MainActor final class HarbourDrawerAccessibilityTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testLargestTextReadingAndTopic() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--verify-drawers"]; app.launch()
        app.buttons["nav-today"].tap(); app.swipeDown(); app.swipeDown()
        let summary = app.descendants(matching: .any)["readingSummary"].firstMatch
        XCTAssertTrue(summary.exists); XCTAssertLessThanOrEqual(summary.frame.maxX, app.frame.width)
        let dashboard = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); dashboard.name = "116-today-large-text"; dashboard.lifetime = .keepAlways; add(dashboard)
        app.buttons["nav-records"].tap(); app.swipeUp(); selectRecords(app, "Readings"); app.buttons["Add record"].tap()
        let value = app.textFields["readingValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5)); XCTAssertGreaterThan(value.frame.height, 30)
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = "84-drawer-large-text"; item.lifetime = .keepAlways; add(item)
        value.tap(); value.typeText("75"); XCTAssertTrue(app.buttons["saveReading"].isHittable); app.buttons["saveReading"].tap()
        XCTAssertTrue(app.staticTexts["75"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["nav-chat"].tap(); app.buttons["Choose a topic"].tap(); app.buttons["Readings"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Clear Readings topic"].waitForExistence(timeout: 5))
    }
}

@MainActor final class HarbourRemainingDrawerScreens: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    func testRemainingDrawers() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launch()
        for dark in [false, true] {
            app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Appearance"].tap()
            app.buttons[dark ? "appearance-dark" : "appearance-light"].tap(); app.navigationBars["Appearance"].buttons.firstMatch.tap(); capture(dark ? "38-settings-dark" : "16-settings")
            app.buttons["Evaluation"].tap(); capture(dark ? "86-evaluation-drawer-dark" : "17-evaluation")
            app.navigationBars["Evaluation"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
            if dark {
                app.swipeDown(); app.swipeDown()
                openSymptomCapture(app); app.textFields["symptomText"].tap(); app.textFields["symptomText"].typeText("Sore knee since Tuesday")
                app.buttons["Done"].tap(); capture("51-symptom-entry-dark")
                app.buttons["noEmergencySigns"].tap(); app.buttons["saveSymptom"].tap(); app.swipeUp(); capture("52-symptom-review-dark"); app.buttons["Cancel"].tap()
            }
            app.swipeUp(); openInteractions(app); capture(dark ? "85-interactions-drawer-dark" : "20-interactions"); app.buttons["Done"].tap()
            openPreparation(app); capture(dark ? "39-note-dark" : "19-appointment-note"); app.buttons["Done"].tap()
        }
        app.buttons["Settings"].tap(); app.buttons["Appearance"].tap(); app.buttons["appearance-light"].tap()
        app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
    }
}

@MainActor final class HarbourStreamlineTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    private func appearance(_ app: XCUIApplication, dark: Bool) {
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Appearance"].tap()
        app.buttons[dark ? "appearance-dark" : "appearance-light"].tap()
        app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
    }
    func testMainActionsDraftRetentionAndVisitCreation() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launch()
        for dark in [false, true] {
            appearance(app, dark: dark)
            app.swipeDown(); app.swipeDown(); capture(dark ? "31-today-dark" : "01-today")
            for destination in ["today", "chat", "records", "visits"] {
                app.buttons["nav-" + destination].tap()
                if destination == "records", !app.navigationBars["Records"].exists { app.navigationBars.buttons.firstMatch.tap() }
                XCTAssertTrue(app.buttons["Settings"].isHittable)
                XCTAssertGreaterThan(app.buttons["Settings"].frame.midX, app.frame.width * 0.7)
                app.buttons["Settings"].tap(); XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
                app.buttons["Done"].tap()
                XCTAssertTrue(app.buttons["nav-" + destination].isSelected)
            }
            app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap(); capture(dark ? "32-chat-dark" : "11-chat-empty")
            let input = app.textFields["chatInput"]; input.tap(); input.typeText("Help me organise my notes")
            app.buttons["Done"].tap(); app.buttons["Settings"].tap(); app.buttons["Models"].tap()
            XCTAssertTrue(app.sliders["Generation effort"].waitForExistence(timeout: 5))
            app.navigationBars["Models"].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Settings"].exists); app.buttons["Done"].tap()
            XCTAssertEqual(input.value as? String, "Help me organise my notes")
            app.buttons["modelSelector"].tap(); XCTAssertTrue(app.buttons["Done"].isHittable); app.buttons["Done"].tap()
            XCTAssertEqual(input.value as? String, "Help me organise my notes")
            app.buttons["nav-records"].tap(); capture(dark ? "65-records-dark" : "64-records")
            selectRecords(app, "Medicines")
            XCTAssertFalse(app.buttons["Settings"].exists)
            XCTAssertTrue(app.buttons["Add record"].isHittable); capture(dark ? "34-medicines-dark" : "03-medicines")
            app.navigationBars["Medicines"].buttons.firstMatch.tap()
            app.buttons["nav-visits"].tap(); capture(dark ? "76-visits-dark" : "67-visits")
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "visit-row-"))
            let count = rows.count
            app.buttons["addVisitNotes"].tap()
            XCTAssertTrue(app.textViews["visitTranscriptInput"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["saveVisitTranscript"].isEnabled)
            capture(dark ? "88-new-visit-notes-dark" : "87-new-visit-notes")
            app.buttons["Cancel"].tap(); XCTAssertTrue(app.buttons["addVisitNotes"].waitForExistence(timeout: 5))
            XCTAssertEqual(rows.count, count)
            app.buttons["recordVisit"].tap(); capture(dark ? "77-visit-recorder-dark" : "68-visit-recorder")
            XCTAssertFalse(app.buttons["Settings"].exists); XCTAssertFalse(app.buttons["addVisitNotes"].exists)
            app.navigationBars["Recorder"].buttons.firstMatch.tap()
            app.buttons["nav-today"].tap(); app.swipeUp()
            openPreparation(app); capture(dark ? "39-note-dark" : "19-appointment-note")
            XCTAssertTrue(app.textFields["appointmentQuestion"].exists)
            XCTAssertGreaterThan(app.buttons["Done"].frame.midX, app.frame.width * 0.7)
            app.swipeUp(); app.buttons["Copy note"].tap()
            app.buttons["Done"].tap()
        }
        app.buttons["nav-visits"].tap(); app.buttons["addVisitNotes"].tap()
        let transcript = app.textViews["visitTranscriptInput"]
        transcript.tap(); transcript.typeText("Discussed sleep habits and bringing a medicine list to the next visit.")
        app.buttons["Done"].tap(); app.buttons["saveVisitTranscript"].tap()
        XCTAssertTrue(app.buttons["summariseVisit"].waitForExistence(timeout: 5))
        app.buttons["Transcript"].tap()
        XCTAssertEqual(app.staticTexts["savedVisitTranscript"].label, "Discussed sleep habits and bringing a medicine list to the next visit.")
        app.terminate(); app.launch(); app.buttons["nav-visits"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "visit-row-")).firstMatch.tap()
        app.buttons["Transcript"].tap()
        XCTAssertEqual(app.staticTexts["savedVisitTranscript"].label, "Discussed sleep habits and bringing a medicine list to the next visit.")
        appearance(app, dark: false)
    }
}

@MainActor final class HarbourCompactLayoutTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
    func testComposerAndFloatingReadingOnSmallPhone() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.launchArguments = ["--verify-drawers"]; app.launch()
        app.buttons["nav-chat"].tap(); app.buttons["modelSelector"].tap()
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Qwen Balanced")).firstMatch.tap()
        app.sliders["Generation effort"].adjust(toNormalizedSliderPosition: 1)
        app.buttons["Done"].tap()
        let input = app.textFields["chatInput"]; input.tap(); input.typeText("Help me prepare for my appointment")
        let selector = app.buttons["modelSelector"], microphone = app.buttons["Voice options"], send = app.buttons["Send message"]
        XCTAssertTrue(selector.isHittable); XCTAssertTrue(microphone.isHittable); XCTAssertTrue(send.isHittable)
        XCTAssertTrue(send.isEnabled)
        XCTAssertLessThanOrEqual(selector.frame.maxX, microphone.frame.minX + 1)
        XCTAssertLessThanOrEqual(microphone.frame.maxX, send.frame.minX + 1)
        XCTAssertLessThan(send.frame.maxX, app.frame.width)
        XCTAssertGreaterThanOrEqual(app.buttons["Choose a topic"].frame.width, 44)
        app.buttons["Done"].tap(); capture("89-chat-small-phone")
        app.buttons["nav-records"].tap(); selectRecords(app, "Readings"); app.buttons["Add record"].tap()
        let value = app.textFields["readingValue"]; value.tap(); value.typeText("74"); app.buttons["Done"].tap()
        let panel = app.descendants(matching: .any)["drawerBounds"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5)); XCTAssertLessThan(panel.frame.maxY, app.frame.height - 5)
        XCTAssertTrue(app.buttons["saveReading"].isHittable); capture("90-reading-small-phone")
        app.buttons["saveReading"].tap(); XCTAssertTrue(app.staticTexts["74"].waitForExistence(timeout: 5))
    }
}

@MainActor final class HarbourCareFeatureTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) { Thread.sleep(forTimeInterval: 0.6); let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<6 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func appearance(_ app: XCUIApplication, dark: Bool) {
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Appearance"].tap(); app.buttons[dark ? "appearance-dark" : "appearance-light"].tap(); app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
    }
    func testCareFlowsAndScreenshots() {
        let app = XCUIApplication(); app.launchArguments = ["--qa-label-fixture"]; app.launch(); appearance(app, dark: false)
        app.buttons["nav-records"].tap(); selectRecords(app, "Medicines"); app.buttons["Add record"].tap()
        XCTAssertTrue(app.buttons["qaReadLabel"].waitForExistence(timeout: 5)); capture("112-label-entry"); app.buttons["qaReadLabel"].tap()
        XCTAssertTrue(app.buttons["Use Metformin"].waitForExistence(timeout: 20)); capture("91-label-scan")
        XCTAssertFalse(app.buttons["saveMedicine"].isEnabled)
        let addTime = app.buttons["addDoseTime"]; reveal(app, addTime); addTime.tap(); let firstTime = app.descendants(matching: .any)["doseTime-0"].firstMatch; reveal(app, firstTime); XCTAssertTrue(firstTime.exists); capture("92-medicine-schedule")
        let confirmed = app.buttons["confirmMedicine"]; reveal(app, confirmed); confirmed.tap(); app.buttons["saveMedicine"].tap()
        XCTAssertTrue(app.navigationBars["Medicines"].waitForExistence(timeout: 5))
        app.buttons["nav-today"].tap(); let addReminder = app.buttons["Add reminder"]; reveal(app, addReminder); addReminder.tap()
        let title = app.textFields["reminderTitle"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Book blood work")
        app.buttons["Done"].tap(); app.buttons["confirmReminderDate"].tap(); capture("93-reminder")
        XCTAssertTrue(app.buttons["saveReminder"].isEnabled); app.buttons["saveReminder"].tap()
        XCTAssertTrue(app.staticTexts["Book blood work"].firstMatch.waitForExistence(timeout: 5))
        let dose = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dose-metformin-")).firstMatch
        reveal(app, dose); dose.tap(); XCTAssertTrue(app.buttons["doseStatus-Taken"].waitForExistence(timeout: 5)); capture("94-dose-log")
        app.buttons["saveDose"].tap(); XCTAssertTrue(app.staticTexts["Taken"].firstMatch.waitForExistence(timeout: 5))
        let timeline = app.buttons["Timeline"]; reveal(app, timeline); capture("95-agenda"); timeline.tap(); capture("96-timeline")
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Metformin"); capture("97-timeline-search")
        app.navigationBars["Timeline"].buttons.firstMatch.tap(); app.buttons["nav-visits"].tap(); app.buttons["prepareAppointment"].tap()
        let question = app.textFields["appointmentQuestion"]; XCTAssertTrue(question.waitForExistence(timeout: 5)); question.tap(); question.typeText("Should I repeat my blood test?")
        app.buttons["Save question"].tap(); capture("98-appointment-preparation")
        app.buttons["Done"].tap(); app.terminate(); app.launch(); app.buttons["nav-visits"].tap(); app.buttons["prepareAppointment"].tap()
        XCTAssertTrue(app.buttons["Should I repeat my blood test?"].exists); app.buttons["Done"].tap()
        appearance(app, dark: true)
        reveal(app, app.buttons["Timeline"]); capture("99-agenda-dark")
        app.buttons["Timeline"].tap(); capture("100-timeline-dark"); app.navigationBars["Timeline"].buttons.firstMatch.tap()
        app.buttons["nav-visits"].tap(); app.buttons["prepareAppointment"].tap(); capture("101-preparation-dark"); app.buttons["Done"].tap()
        app.buttons["nav-records"].tap(); selectRecords(app, "Medicines"); app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Metformin")).firstMatch.tap()
        reveal(app, app.buttons["addDoseTime"]); capture("102-schedule-dark"); app.buttons["Cancel"].tap()
        app.buttons["nav-today"].tap(); reveal(app, dose); dose.tap(); app.buttons["doseStatus-Remind later"].tap(); capture("103-dose-later-dark"); app.buttons["Cancel"].tap()
        app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap(); app.buttons["Voice options"].tap(); capture("104-voice-options"); app.tap()
        appearance(app, dark: false); app.swipeDown(); app.swipeDown(); capture("01-today")
        app.buttons["nav-chat"].tap(); capture("11-chat-empty"); app.buttons["nav-records"].tap(); selectRecords(app, "Medicines"); capture("03-medicines")
        app.navigationBars["Medicines"].buttons.firstMatch.tap(); capture("64-records"); app.buttons["nav-visits"].tap(); capture("67-visits")
    }
    func testAgentCareToolsAndConfirmation() {
        let app = XCUIApplication(); app.launchArguments = ["--qa-label-fixture"]; app.launch()
        app.buttons["nav-records"].tap(); selectRecords(app, "Medicines"); app.buttons["Add record"].tap()
        reveal(app, app.buttons["catalog-metformin"]); app.buttons["catalog-metformin"].tap()
        reveal(app, app.buttons["addDoseTime"]); app.buttons["addDoseTime"].tap(); reveal(app, app.buttons["confirmMedicine"]); app.buttons["confirmMedicine"].tap(); app.buttons["saveMedicine"].tap()
        app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap()
        let input = app.textFields["chatInput"]
        func send(_ text: String) { input.tap(); input.typeText(text); app.buttons["Send message"].tap() }
        send("Remind me to book blood work")
        XCTAssertTrue(app.textFields["reminderTitle"].waitForExistence(timeout: 120)); XCTAssertFalse(app.buttons["saveReminder"].isEnabled); capture("105-chat-reminder-review"); app.buttons["confirmReminderDate"].tap(); app.buttons["saveReminder"].tap()
        send("Show my reminders")
        XCTAssertTrue(app.staticTexts["Reminders"].firstMatch.waitForExistence(timeout: 90)); capture("106-chat-reminders")
        send("Schedule Metformin at 8 am and 8 pm")
        XCTAssertTrue(app.buttons["saveMedicine"].waitForExistence(timeout: 90)); reveal(app, app.buttons["addDoseTime"]); capture("107-chat-schedule-review"); app.buttons["Cancel"].tap()
        send("I took Metformin")
        XCTAssertTrue(app.buttons["doseStatus-Taken"].waitForExistence(timeout: 90)); capture("108-chat-dose-review"); app.buttons["Cancel"].tap()
        send("Search my history for Metformin")
        XCTAssertTrue(app.staticTexts["Health history"].firstMatch.waitForExistence(timeout: 90)); capture("109-chat-history")
        send("Save question for my doctor: Should I repeat my blood test?")
        XCTAssertTrue(app.textFields["appointmentQuestion"].waitForExistence(timeout: 90)); XCTAssertEqual(app.textFields["appointmentQuestion"].value as? String, "Should I repeat my blood test?"); capture("110-chat-question-review"); app.buttons["Done"].tap()
        send("Scan a medicine label")
        XCTAssertTrue(app.buttons["Label photo"].waitForExistence(timeout: 90)); capture("111-chat-label-scan"); app.buttons["Cancel"].tap()
    }
    func testZCareLayoutScreenshots() {
        let app = XCUIApplication(); app.launch(); appearance(app, dark: true)
        app.swipeDown(); app.swipeDown(); capture("31-today-dark")
        app.buttons["nav-chat"].tap(); app.buttons["New chat"].tap(); capture("32-chat-dark")
        app.buttons["nav-records"].tap(); selectRecords(app, "Medicines"); capture("34-medicines-dark")
        app.navigationBars["Medicines"].buttons.firstMatch.tap(); capture("65-records-dark")
        app.buttons["nav-visits"].tap(); capture("76-visits-dark")
        appearance(app, dark: false)
        app.buttons["nav-chat"].tap(); let draft = app.textFields["chatInput"]; draft.tap(); draft.typeText("What should I ask at my next appointment?"); capture("28-chat-keyboard")
        app.buttons["Done"].tap(); app.buttons["New chat"].tap()
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); capture("16-settings"); app.buttons["Done"].tap()
    }

}

@MainActor final class HarbourStableMainScreensTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testStableLightMainScreens() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launch()
        for dark in [true, false] {
            app.buttons["nav-today"].tap(); app.buttons["Settings"].tap(); app.buttons["Appearance"].tap(); app.buttons[dark ? "appearance-dark" : "appearance-light"].tap()
            app.navigationBars["Appearance"].buttons.firstMatch.tap(); app.buttons["Done"].tap()
            let pages = dark ? [("today", "31-today-dark"), ("chat", "32-chat-dark"), ("records", "65-records-dark"), ("visits", "76-visits-dark")] : [("today", "01-today"), ("chat", "11-chat-empty"), ("records", "64-records"), ("visits", "67-visits")]
            for (destination, name) in pages {
                app.buttons["nav-" + destination].tap()
                if destination == "chat" {
                    app.buttons["New chat"].tap()
                    let last = app.buttons["starter-readings"]
                    XCTAssertTrue(last.isHittable); XCTAssertLessThan(last.frame.maxY, app.textFields["chatInput"].frame.minY - 8)
                }
                if destination == "today" { app.swipeDown(); app.swipeDown() }
                for tab in ["today", "chat", "records", "visits"] { XCTAssertTrue(app.buttons["nav-" + tab].isHittable) }
                Thread.sleep(forTimeInterval: 2)
                let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
            }
        }
    }
}

@MainActor final class HarbourPermissionFeatureTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) { Thread.sleep(forTimeInterval: 0.6); let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func acceptPermission(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<5 {
            if app.alerts["Voice input"].exists { return }
            let alert = springboard.alerts.firstMatch
            if alert.exists {
                if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap() }
                else if alert.buttons["OK"].exists { alert.buttons["OK"].tap() }
                else { return }
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
    }
    func testNotificationPermissionAndVoiceAvailability() {
        let app = XCUIApplication(); app.launch(); app.buttons["nav-today"].tap()
        let add = app.buttons["Add reminder"]
        for _ in 0..<5 { if add.isHittable { break }; app.swipeUp() }; add.tap()
        let title = app.textFields["reminderTitle"]; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Reminder notification test"); app.buttons["Done"].tap()
        app.buttons["confirmReminderDate"].tap()
        let notify = app.switches["Notify me"]; notify.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(notify.value as? String, "1"); capture("115-notification-setting")
        app.buttons["saveReminder"].tap(); acceptPermission(app)
        XCTAssertTrue(app.buttons["Add reminder"].waitForExistence(timeout: 10))
        app.buttons["nav-chat"].tap(); app.buttons["Voice options"].tap(); capture("104-voice-options"); app.buttons["Voice conversation"].tap(); acceptPermission(app)
        if app.buttons["Resume voice"].exists && !app.alerts.firstMatch.exists { app.buttons["Resume voice"].tap(); acceptPermission(app) }
        if app.alerts["Voice input"].exists { capture("114-voice-input-error"); app.alerts["Voice input"].buttons["OK"].tap() }
        else { XCTAssertTrue(app.buttons["End voice"].waitForExistence(timeout: 5)); capture("113-voice-mode"); app.buttons["End voice"].tap() }
        XCTAssertTrue(app.buttons["Voice options"].exists)
        app.buttons["nav-today"].tap()
    }
}

@MainActor final class HarbourFrenchScreensTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<6 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    private func openRecords(_ app: XCUIApplication, category: Int? = nil) {
        app.buttons["nav-records"].tap()
        for _ in 0..<3 {
            if app.buttons["record-category-0"].exists { break }
            app.navigationBars.firstMatch.buttons.firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["record-category-0"].waitForExistence(timeout: 5))
        if let category { app.buttons["record-category-\(category)"].tap() }
    }

    private func appearance(_ app: XCUIApplication, dark: Bool) {
        app.buttons["nav-today"].tap(); app.buttons["Réglages"].tap(); app.buttons["Apparence"].tap()
        app.buttons[dark ? "appearance-dark" : "appearance-light"].tap()
        app.navigationBars["Apparence"].buttons.firstMatch.tap(); app.buttons["Terminé"].tap()
    }

    func testFrenchMainScreensAndDraftWorkflows() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(fr-CA)", "-AppleLocale", "fr_CA"]
        app.launch()
        XCTAssertTrue(app.buttons["nav-today"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.buttons["nav-today"].label, "Aujourd’hui")
        XCTAssertEqual(app.buttons["nav-chat"].label, "Conversation")
        XCTAssertEqual(app.buttons["nav-records"].label, "Dossier")
        XCTAssertEqual(app.buttons["nav-visits"].label, "Consultations")

        app.buttons["nav-chat"].tap(); app.buttons["Nouvelle conversation"].tap(); app.buttons["nav-today"].tap()

        for dark in [false, true] {
            appearance(app, dark: dark)
            let pages = dark
                ? [("today", "121-french-today-dark"), ("chat", "122-french-chat-dark"), ("records", "123-french-records-dark"), ("visits", "124-french-visits-dark")]
                : [("today", "117-french-today"), ("chat", "118-french-chat"), ("records", "119-french-records"), ("visits", "120-french-visits")]
            for (destination, name) in pages {
                if destination == "records" { openRecords(app) }
                else { app.buttons["nav-" + destination].tap() }
                if destination == "today" { app.swipeDown(); app.swipeDown() }
                if destination == "chat" {
                    let last = app.buttons["starter-readings"]
                    XCTAssertTrue(last.isHittable)
                    XCTAssertLessThan(last.frame.maxY, app.textFields["chatInput"].frame.minY - 8)
                }
                for tab in ["today", "chat", "records", "visits"] { XCTAssertTrue(app.buttons["nav-" + tab].isHittable) }
                capture(name)
            }
        }
        appearance(app, dark: false)

        app.buttons["Réglages"].tap()
        XCTAssertTrue(app.navigationBars["Réglages"].waitForExistence(timeout: 5)); capture("125-french-settings")
        app.buttons["Apparence"].tap()
        XCTAssertEqual(app.buttons["appearance-system"].label, "Système")
        XCTAssertEqual(app.buttons["appearance-light"].label, "Clair")
        XCTAssertEqual(app.buttons["appearance-dark"].label, "Sombre"); capture("126-french-appearance")
        app.navigationBars["Apparence"].buttons.firstMatch.tap(); app.buttons["appLockSettings"].tap()
        app.buttons["lock-option-pin"].tap()
        let slots = app.descendants(matching: .any)["pinSlots"].firstMatch
        XCTAssertTrue(slots.waitForExistence(timeout: 5)); XCTAssertEqual(slots.label, "NIP")
        app.buttons["pin-key-1"].tap()
        XCTAssertTrue((slots.value as? String ?? "").contains("Chiffres saisis : 1 sur")); capture("127-french-pin-draft")
        app.buttons["Annuler"].tap()
        XCTAssertTrue(app.buttons["lock-option-pin"].waitForExistence(timeout: 5))
        app.navigationBars["Verrouillage de l’app"].buttons.firstMatch.tap(); app.buttons["Terminé"].tap()

        openRecords(app, category: 1); app.buttons["Ajouter une entrée"].tap()
        let search = app.textFields["medicineSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("acétaminophène")
        XCTAssertTrue(app.buttons["catalog-acetaminophen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["addUnlistedMedicine"].exists)
        app.buttons["Terminé"].tap(); capture("128-french-medicine-search"); app.buttons["Annuler"].tap()

        openRecords(app, category: 2); app.buttons["Ajouter une entrée"].tap()
        app.buttons["readingKind"].tap(); app.buttons["Température"].tap()
        let value = app.textFields["readingValue"]; value.tap(); value.typeText("36,8"); app.buttons["Terminé"].tap()
        XCTAssertEqual(value.value as? String, "36,8"); XCTAssertTrue(app.buttons["saveReading"].isEnabled)
        capture("129-french-reading-comma"); app.buttons["Annuler"].tap()

        openRecords(app, category: 0); app.buttons["Ajouter une entrée"].tap()
        let symptom = app.textFields["symptomText"]
        symptom.tap(); symptom.typeText("Exemple fictif : douleur au genou depuis mardi."); app.buttons["Terminé"].tap()
        XCTAssertTrue(app.staticTexts["Que se passe-t-il?"].exists); capture("130-french-symptom-draft")
        let redFlag = app.buttons["Persistent, severe chest pain"]; reveal(app, redFlag); redFlag.tap()
        app.buttons["saveSymptom"].tap()
        let emergency = app.staticTexts["Soins d’urgence"]; reveal(app, emergency)
        XCTAssertTrue(emergency.exists); capture("131-french-emergency-review"); app.buttons["Annuler"].tap()

        app.buttons["nav-chat"].tap(); app.buttons["Choisir un sujet"].tap()
        XCTAssertTrue(app.staticTexts["Sujet"].waitForExistence(timeout: 5)); capture("132-french-topics")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Médicaments")).firstMatch.tap()
        app.buttons["modelSelector"].tap()
        XCTAssertTrue(app.navigationBars["Modèles"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.sliders["Generation effort"].label, "Effort de génération")
        capture("133-french-models"); app.buttons["Terminé"].tap()
        let draft = app.textFields["chatInput"]
        draft.tap(); draft.typeText("Exemple fictif : quelles questions devrais-je poser pendant ma prochaine consultation?")
        let selector = app.buttons["modelSelector"], voice = app.buttons["Options vocales"], send = app.buttons["Envoyer le message"]
        XCTAssertTrue(selector.isHittable); XCTAssertTrue(voice.isHittable); XCTAssertTrue(send.isHittable)
        XCTAssertLessThanOrEqual(selector.frame.maxX, voice.frame.minX + 1)
        XCTAssertLessThanOrEqual(voice.frame.maxX, send.frame.minX + 1)
        XCTAssertLessThanOrEqual(send.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(app.buttons["Choisir un sujet"].frame.width, 44)
        capture("137-french-chat-controls")
        draft.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (draft.value as? String ?? "").count))
        app.buttons["Terminé"].tap()

        app.buttons["nav-visits"].tap(); app.buttons["addVisitNotes"].tap()
        XCTAssertEqual(app.textFields["visitTitleInput"].placeholderValue, "Titre de la consultation")
        let transcript = app.textViews["visitTranscriptInput"]
        transcript.tap(); transcript.typeText("Exemple fictif : discuter du sommeil et de la liste des médicaments."); app.buttons["Terminé"].tap()
        capture("134-french-visit-notes-draft"); app.buttons["Annuler"].tap()

        app.buttons["nav-today"].tap()
        let reminderButton = app.buttons["Ajouter un rappel"]; reveal(app, reminderButton); reminderButton.tap()
        let reminder = app.textFields["reminderTitle"]; reminder.tap(); reminder.typeText("Exemple fictif : préparer une liste de questions")
        app.buttons["Terminé"].tap(); XCTAssertFalse(app.buttons["saveReminder"].isEnabled)
        app.buttons["confirmReminderDate"].tap(); XCTAssertTrue(app.buttons["saveReminder"].isEnabled)
        capture("135-french-reminder-draft"); app.buttons["Annuler"].tap()

        app.buttons["nav-visits"].tap(); app.buttons["prepareAppointment"].tap()
        let question = app.textFields["appointmentQuestion"]
        XCTAssertTrue(question.waitForExistence(timeout: 5)); XCTAssertEqual(question.placeholderValue, "Question pour votre médecin")
        let note = app.staticTexts["appointmentNoteContent"]
        reveal(app, note); XCTAssertTrue(note.label.contains("Préoccupation")); XCTAssertTrue(note.label.contains("Médicaments consignés"))
        capture("136-french-preparation-draft"); app.buttons["Terminé"].tap()
        app.buttons["nav-today"].tap()
    }
}

@MainActor final class HarbourFrenchModelTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 2)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<6 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    private func recordLabels(_ app: XCUIApplication) -> [String] {
        app.buttons["nav-records"].tap()
        for _ in 0..<3 {
            if app.buttons["record-category-0"].exists { break }
            app.navigationBars.firstMatch.buttons.firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["record-category-0"].waitForExistence(timeout: 5))
        return (0...2).map { app.buttons["record-category-\($0)"].label }
    }

    private func send(_ input: String, app: XCUIApplication) {
        let field = app.textFields["chatInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(input)
        XCTAssertTrue(app.buttons["Envoyer le message"].isEnabled); app.buttons["Envoyer le message"].tap()
    }

    func testCachedSmallModelRoutesFrenchRequestsAndNamesTheConversation() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(fr-CA)", "-AppleLocale", "fr_CA"]
        app.launch()
        XCTAssertTrue(app.buttons["nav-chat"].waitForExistence(timeout: 10))
        let before = recordLabels(app)
        app.buttons["nav-chat"].tap(); app.buttons["modelSelector"].tap()

        // Refuse to start inference if Small has not already passed native download verification.
        func smallIsCached() -> Bool {
            app.cells.containing(.staticText, identifier: "Qwen Petit").allElementsBoundByIndex.contains { $0.buttons["Retirer"].exists }
        }
        for _ in 0..<3 { if smallIsCached() { break }; app.swipeUp() }
        XCTAssertTrue(smallIsCached(), "Qwen Small must already be cached; this test does not start a download.")
        let small = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Qwen Petit")).firstMatch
        for _ in 0..<3 { if small.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(small.isHittable); small.tap()
        let effort = app.sliders["Generation effort"]; reveal(app, effort); effort.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertEqual(effort.value as? String, "Standard"); app.buttons["Terminé"].tap()
        XCTAssertEqual(app.buttons["modelSelector"].value as? String, "Qwen Petit, Standard")
        app.buttons["Nouvelle conversation"].tap()
        XCTAssertEqual(app.staticTexts["chatTitle"].label, "Nouvelle conversation")

        let medicines = "Montre-moi les médicaments que j’ai déjà enregistrés."
        send(medicines, app: app)
        XCTAssertTrue(app.staticTexts["Vos médicaments"].waitForExistence(timeout: 120), app.debugDescription)
        // Send returns only after the separate title generation has finished.
        XCTAssertTrue(app.buttons["Envoyer le message"].waitForExistence(timeout: 90))
        let title = app.staticTexts["chatTitle"].label
        let fallback = medicines.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ")
        XCTAssertFalse(title.isEmpty); XCTAssertNotEqual(title, "Nouvelle conversation"); XCTAssertNotEqual(title, fallback)
        XCTAssertNotNil(title.range(of: "(?i)médic|medic|liste|consign|enregistr", options: .regularExpression), title)
        XCTAssertNil(title.range(of: "(?i)\\b(medicine|medicines|medication|medications|recorded|saved|show|list)\\b", options: .regularExpression), title)
        capture("138-french-model-medicines-title")

        send("Montre mes relevés de fréquence cardiaque.", app: app)
        XCTAssertTrue(app.staticTexts["Relevés récents"].waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertTrue(app.buttons["Envoyer le message"].waitForExistence(timeout: 60))
        XCTAssertEqual(app.staticTexts["chatTitle"].label, title); capture("139-french-model-readings")

        let symptom = "Exemple fictif : j’ai une douleur au genou depuis mardi."
        send(symptom, app: app)
        let symptomField = app.textFields["symptomText"]
        XCTAssertTrue(symptomField.waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertEqual(symptomField.value as? String, symptom)
        XCTAssertFalse(app.buttons["saveSymptom"].isEnabled)
        reveal(app, app.buttons["noEmergencySigns"]); app.buttons["noEmergencySigns"].tap()
        XCTAssertTrue(app.buttons["saveSymptom"].isEnabled); app.buttons["saveSymptom"].tap()
        let guidance = app.staticTexts["Santé811"]; reveal(app, guidance); XCTAssertTrue(guidance.exists)
        XCTAssertEqual(app.buttons["saveSymptom"].label, "Enregistrer")
        capture("140-french-model-symptom-review"); app.buttons["Annuler"].tap()
        XCTAssertTrue(app.staticTexts["Vérifiez les détails du symptôme et les signes d’urgence avant d’enregistrer."].exists)

        let reminder = "Exemple fictif : rappelle-moi de réserver une prise de sang."
        send(reminder, app: app)
        let reminderField = app.textFields["reminderTitle"]
        XCTAssertTrue(reminderField.waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertEqual(reminderField.value as? String, reminder)
        XCTAssertFalse(app.buttons["saveReminder"].isEnabled)
        app.buttons["confirmReminderDate"].tap(); XCTAssertTrue(app.buttons["saveReminder"].isEnabled)
        capture("141-french-model-reminder-review"); app.buttons["Annuler"].tap()
        XCTAssertTrue(app.staticTexts["Vérifiez le rappel et choisissez sa date."].exists)
        XCTAssertEqual(recordLabels(app), before)
        app.buttons["nav-chat"].tap(); XCTAssertEqual(app.staticTexts["chatTitle"].label, title)
    }
}
