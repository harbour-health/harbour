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
        app.switches["confirmAppointmentDate"].tap()
        XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.staticTexts["Fictional clinic appointment"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.buttons["nav-records"].tap(); app.buttons["record-category-3"].tap()
        XCTAssertTrue(app.staticTexts["Fictional clinic appointment"].waitForExistence(timeout: 5))
    }
}
