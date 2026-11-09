import XCTest

@MainActor final class VoiceConversationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func capture(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    func testFullScreenVoiceKeepsConversationOnExit() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--app-store-screenshots",
            "--voice-conversation-fixture",
            "--voice-ui-state",
            "listening",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_CA"
        ]
        app.launch()
        app.buttons["nav-chat"].tap()
        app.buttons["startVoiceConversation"].tap()
        XCTAssertTrue(app.buttons["endVoiceConversation"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nav-chat"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.textFields["chatInput"].isHittable)
        XCTAssertFalse(app.staticTexts["Fictional voice screen test: prepare for my visit."].isHittable)
        capture("164-voice-conversation-light")
        app.buttons["endVoiceConversation"].tap()
        XCTAssertTrue(app.buttons["nav-chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["chatInput"].isHittable)
        XCTAssertTrue(app.staticTexts["Fictional voice screen test: prepare for my visit."].isHittable)
        XCTAssertTrue(app.staticTexts["Fictional voice screen test: we can prepare your questions."].isHittable)
        capture("165-voice-conversation-history")
    }

    func testLargeTextVoiceControlsRemainReachable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--app-store-screenshots",
            "--voice-conversation-fixture",
            "--voice-ui-state",
            "paused",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_CA",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        app.buttons["nav-chat"].tap()
        app.buttons["startVoiceConversation"].tap()
        XCTAssertTrue(app.buttons["endVoiceConversation"].waitForExistence(timeout: 5))
        if !app.buttons["endVoiceConversation"].isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["endVoiceConversation"].isHittable)
        capture("168-voice-conversation-large-text")
        app.buttons["endVoiceConversation"].tap()
        XCTAssertTrue(app.buttons["nav-chat"].waitForExistence(timeout: 5))
    }

    func testVoicePresentationFrenchDarkAndLandscape() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--app-store-screenshots",
            "--voice-conversation-fixture",
            "--voice-ui-state",
            "speaking",
            "-AppleLanguages",
            "(fr-CA)",
            "-AppleLocale",
            "fr_CA"
        ]
        app.launch()
        app.buttons["Réglages"].tap()
        // Use stable identifiers for appearance and navigation in either language.
        app.buttons["Apparence"].tap()
        app.buttons["appearance-dark"].tap()
        app.navigationBars["Apparence"].buttons.firstMatch.tap()
        app.buttons["Terminé"].tap()
        app.buttons["nav-chat"].tap()
        app.buttons["startVoiceConversation"].tap()
        XCTAssertTrue(app.buttons["endVoiceConversation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["nav-chat"].exists)
        capture("166-voice-conversation-french-dark")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["endVoiceConversation"].isHittable)
        capture("167-voice-conversation-landscape")
        XCUIDevice.shared.orientation = .portrait
        app.buttons["endVoiceConversation"].tap()
        XCTAssertTrue(app.buttons["nav-chat"].waitForExistence(timeout: 5))
    }
}
