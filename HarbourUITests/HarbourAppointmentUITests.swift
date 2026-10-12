import XCTest

@MainActor final class HarbourAppointmentUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testManualAppointmentRequiresConfirmationAndPersists() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-unlocked", "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launch()
        app.buttons["nav-records"].tap()
        let category = app.buttons["record-category-3"]
        for _ in 0..<3 { if category.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.tap()
        app.buttons["Add record"].tap()
        let title = app.textFields["appointmentTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText("Fictional clinic appointment")
        let save = app.buttons["saveAppointment"]
        XCTAssertFalse(save.isEnabled)
        app.buttons["Done"].tap()
        let confirmation = app.switches["confirmAppointmentDate"]
        confirmation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(confirmation.value as? String, "1")
        let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Appointment draft"; capture.lifetime = .keepAlways; add(capture)
        XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.staticTexts["Fictional clinic appointment"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.buttons["nav-records"].tap(); app.buttons["record-category-3"].tap()
        XCTAssertTrue(app.staticTexts["Fictional clinic appointment"].waitForExistence(timeout: 5))
    }
}

@MainActor final class HarbourMedicationDraftUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testCompactMedicationApprovalAndFrequencyInBothThemes() {
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-unlocked", "--medication-draft-fixture", "-appearance", appearance, "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
            app.launch()
            let approve = app.buttons["approveMedication"]
            XCTAssertTrue(approve.waitForExistence(timeout: 5)); XCTAssertTrue(approve.isEnabled)
            XCTAssertTrue(app.staticTexts["500 mg 2 times daily"].exists)
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2 per day")).firstMatch.exists)
            let capture = XCTAttachment(screenshot: app.screenshot()); capture.name = "Medication approval " + appearance; capture.lifetime = .keepAlways; add(capture)
            approve.tap()
            let frequency = app.buttons["frequency-metformin"]
            for _ in 0..<5 { if frequency.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(frequency.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "2 per day")).firstMatch.exists)
            app.terminate()
        }
    }
}
