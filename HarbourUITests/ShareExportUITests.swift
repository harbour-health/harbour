import XCTest

@MainActor final class ShareExportUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testClosingExportReturnsToSettingsWithoutRepresenting() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-unlocked"]
        app.launch()
        app.buttons["nav-today"].tap()
        app.buttons["Settings"].tap()
        for _ in 0 ..< 2 {
            let export = app.buttons["Export records"]
            XCTAssertTrue(export.waitForExistence(timeout: 5))
            export.tap()
            let share = app.otherElements["ActivityListView"]
            XCTAssertTrue(share.waitForExistence(timeout: 10))
            let close = app.buttons["Close"]
            XCTAssertTrue(close.waitForExistence(timeout: 30))
            close.tap()
            XCTAssertTrue(share.waitForNonExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(app.buttons["Delete all records and chat"].waitForExistence(timeout: 5), app.debugDescription)
        }
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["nav-today"].waitForExistence(timeout: 5))
    }
}
