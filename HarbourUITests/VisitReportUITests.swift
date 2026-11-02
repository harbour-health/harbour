import XCTest

@MainActor final class VisitReportUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testReportPreviewAndSharing() {
        let app = XCUIApplication()
        app.launchArguments = ["--app-store-screenshots", "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launch()
        app.buttons["nav-visits"].tap()
        app.buttons["openVisitReport"].tap()
        XCTAssertTrue(app.navigationBars["Doctor visit report"].waitForExistence(timeout: 5))
        app.buttons["reportAllTime"].tap()
        capture(app, "Report - options")
        app.swipeUp()
        let generate = app.buttons["previewVisitReport"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()
        XCTAssertTrue(app.navigationBars["Report preview"].waitForExistence(timeout: 90), app.debugDescription)
        capture(app, "Report - PDF preview")
        app.buttons["shareVisitReport"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, "Report - sharing")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testFrenchReportPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["--app-store-screenshots", "-AppleLanguages", "(fr-CA)", "-AppleLocale", "fr_CA"]
        app.launch()
        app.buttons["nav-visits"].tap(); app.buttons["openVisitReport"].tap()
        XCTAssertTrue(app.buttons["reportAllTime"].waitForExistence(timeout: 5))
        app.buttons["reportAllTime"].tap(); app.swipeUp(); app.buttons["previewVisitReport"].tap()
        XCTAssertTrue(app.navigationBars["Aperçu du rapport"].waitForExistence(timeout: 90), app.debugDescription)
        capture(app, "Rapport - aperçu PDF")
    }
}
