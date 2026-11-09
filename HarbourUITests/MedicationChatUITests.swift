import XCTest

@MainActor final class MedicationChatUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a) }

    private func send(_ text: String, app: XCUIApplication) {
        let field = app.textFields["chatInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        app.buttons["Send message"].tap()
    }

    func testRealChatDoseCorrectionAndLabelledRemovalAlert() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-unlocked",
            "-model",
            "balanced",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_CA"
        ]
        app.launch()
        app.buttons["nav-today"].tap()
        app.buttons["Settings"].tap()
        if !app.buttons["developerSettings"].isHittable {
            app.swipeUp()
        }
        app.buttons["developerSettings"].tap()
        app.buttons["loadDemoData"].tap()
        app.alerts.buttons["Replace with demo data"].tap()
        XCTAssertTrue(app.staticTexts["demoDataLoaded"].waitForExistence(timeout: 5))
        app.navigationBars["Developer"].buttons.firstMatch.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        app.buttons["nav-chat"].tap()
        app.buttons["New chat"].tap()
        send("Update my metformin to 400mg", app: app)
        XCTAssertTrue(app.navigationBars["Medication"].waitForExistence(timeout: 300))
        if !app.textFields["medicineInstructions"].exists {
            app.swipeUp()
        }
        XCTAssertTrue((app.textFields["medicineInstructions"].value as? String)?.contains("400mg") == true)
        XCTAssertFalse(app.buttons["saveMedicine"].isEnabled)
        capture("205-chat-dose-correction-review")
        app.navigationBars["Medication"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 300))
        app.buttons["New chat"].tap()
        send("Remove metformin from my list", app: app)
        let alert = app.alerts["Remove Metformin from your list?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 300))
        XCTAssertTrue(alert.buttons["Remove"].exists)
        XCTAssertTrue(alert.buttons["Cancel"].exists)
        capture("206-chat-removal-confirmation")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForNonExistence(timeout: 300))
        app.buttons["nav-records"].tap()
        if !app.buttons["record-category-1"].exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
        app.buttons["record-category-1"].tap()
        XCTAssertTrue(app.buttons["medicine-row-metformin"].exists)
    }

    func testExplicitRemovalAlertHasStablePendingStatus() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-unlocked",
            "-model",
            "balanced",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_CA"
        ]
        app.launch()
        app.buttons["nav-today"].tap()
        app.buttons["Settings"].tap()
        if !app.buttons["developerSettings"].isHittable {
            app.swipeUp()
        }
        app.buttons["developerSettings"].tap()
        app.buttons["loadDemoData"].tap()
        app.alerts.buttons["Replace with demo data"].tap()
        XCTAssertTrue(app.staticTexts["demoDataLoaded"].waitForExistence(timeout: 5))
        app.navigationBars["Developer"].buttons.firstMatch.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        app.buttons["nav-chat"].tap()
        app.buttons["New chat"].tap()
        send("Remove metformin from my list", app: app)
        let alert = app.alerts["Remove Metformin from your list?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 300))
        XCTAssertTrue(app.staticTexts["chatPendingReview"].exists)
        XCTAssertFalse(app.staticTexts["Thinking…"].exists)
        capture("206-chat-removal-confirmation")
        alert.buttons["Cancel"].tap()
        app.buttons["nav-records"].tap()
        app.buttons["record-category-1"].tap()
        XCTAssertTrue(app.buttons["medicine-row-metformin"].exists)
        app.buttons["medicine-row-metformin"].tap()
        XCTAssertTrue(app.navigationBars["Medication"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Camera"].exists)
        capture("207-existing-medication-editor")
        app.navigationBars["Medication"].buttons["Cancel"].tap()
        app.buttons["nav-today"].tap()
        for _ in 0 ..< 5 {
            if app.buttons["openTimeline"].isHittable {
                break
            }
            app.swipeUp() }
        app.buttons["openTimeline"].tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 5))
        capture("208-open-timeline")
    }

}

@MainActor final class LargeModelUITests: XCTestCase {
    func testOptionalLargeModelSelection() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-unlocked",
            "-model",
            "automatic",
            "-effort",
            "Standard",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_CA"
        ]
        app.launch()
        app.buttons["nav-chat"].tap()
        app.buttons["modelSelector"].tap()
        let choice = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Camille")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        let picker = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        picker.name = "209-optional-7b-model"
        picker.lifetime = .keepAlways
        add(picker)
        app.buttons["Done"].tap()
        XCTAssertEqual(app.buttons["modelSelector"].value as? String, "Camille, Standard")
        let composer = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        composer.name = "210-7b-chat-selector"
        composer.lifetime = .keepAlways
        add(composer)
        // Selecting a model alone does not start a multi-gigabyte download.
        XCTAssertFalse(app.buttons["Cancel download"].exists)
        app.buttons["modelSelector"].tap()
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Automatic")).firstMatch.tap()
        app.buttons["Done"].tap()
        XCTAssertFalse((app.buttons["modelSelector"].value as? String)?.contains("7B") == true)
    }
}

@MainActor final class InterfacePolishUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a) }

    private func launch(_ appearance: String = "Dark") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-unlocked",
            "--verify-drawers",
            "-appearance",
            appearance,
            "-model",
            "balanced",
            "-effort",
            "Standard",
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_CA"
        ]
        app.launch()

        return app
    }

    private func loadDemo(_ app: XCUIApplication) {
        app.buttons["nav-today"].tap()
        app.buttons["Settings"].tap()
        if !app.buttons["developerSettings"].isHittable {
            app.swipeUp()
        }
        app.buttons["developerSettings"].tap()
        app.buttons["loadDemoData"].tap()
        app.alerts.buttons["Replace with demo data"].tap()
        XCTAssertTrue(app.staticTexts["demoDataLoaded"].waitForExistence(timeout: 5))
        app.navigationBars["Developer"].buttons.firstMatch.tap()
        app.buttons["Done"].tap()
        XCTAssertFalse(app.staticTexts["demoDataBadge"].exists)
    }

    func testSwitchContrastDrawerSizesAndInlineVoicePreview() {
        for theme in ["Light", "Dark"] {
            let app = launch(theme)
            app.buttons["nav-today"].tap()
            app.buttons["Settings"].tap()
            let toggle = app.switches["Live Activities"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            if toggle.value as? String != "1" {
                toggle.tap()
            }
            XCTAssertEqual(toggle.value as? String, "1")
            capture(theme == "Light" ? "211-switches-light" : "212-switches-dark")
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            XCTAssertEqual(
                XCTWaiter
                    .wait(
                        for: [expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: toggle)],
                        timeout: 3
                    ),
                .completed
            )
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            let bounds = app.descendants(matching: .any)["drawerBounds"].firstMatch
            let tall = bounds.frame.height
            app.buttons["Appearance"].tap()
            XCTAssertTrue(app.buttons["appearance-light"].waitForExistence(timeout: 5))
            XCTAssertLessThan(bounds.frame.height, tall - 100)
            capture(theme == "Light" ? "213-short-drawer-light" : "214-short-drawer-dark")
            app.navigationBars["Appearance"].buttons.firstMatch.tap()
            XCTAssertGreaterThan(bounds.frame.height, tall - 40)
            app.buttons["voiceSettings"].tap()
            let preview = app.buttons["previewVoice"]
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            let before = preview.frame
            preview.tap()
            XCTAssertEqual(preview.label, "Stop preview")
            XCTAssertEqual(preview.frame.minY, before.minY, accuracy: 2)
            XCTAssertEqual(preview.frame.height, before.height, accuracy: 1)
            capture(theme == "Light" ? "215-inline-voice-light" : "216-inline-voice-dark")
            preview.tap()
            XCTAssertEqual(preview.label, "Preview voice")
            app.terminate()
        }
    }

    func testComposerControlsNamesAndSavedReadingTable() {
        let app = launch()
        loadDemo(app)
        capture("221-home-with-records")
        app.buttons["nav-chat"].tap()
        XCTAssertTrue(app.buttons["startVoiceConversation"].exists)
        XCTAssertTrue(app.buttons["dictateMessage"].exists)
        let chats = app.buttons["Chats"], newChat = app.buttons["New chat"]
        XCTAssertLessThan(newChat.frame.minX - chats.frame.maxX, 16)
        app.buttons["modelSelector"].tap()
        for identifier in ["model-small", "model-balanced", "model-large"] {
            XCTAssertTrue(app.buttons[identifier].exists) }
        capture("217-named-models")
        app.buttons["model-large"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.buttons["modelSelector"].value as? String, "Camille, Standard")
        let field = app.textFields["chatInput"]
        field.tap()
        field.typeText("Show my readings")
        XCTAssertTrue(app.buttons["sendMessage"].exists)
        XCTAssertFalse(app.buttons["startVoiceConversation"].exists)
        app.buttons["New chat"].tap()
        XCTAssertTrue(app.buttons["startVoiceConversation"].exists)
        app.buttons["Chats"].tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Demo · Recent readings")).firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chatReadingsTable"].firstMatch.waitForExistence(timeout: 5))
        capture("218-compact-readings-chat")
        app.buttons["modelSelector"].tap()
        app.buttons["model-automatic"].tap()
        app.buttons["Done"].tap()
        app.buttons["nav-visits"].tap()
        let visit = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Demo · Blood pressure follow-up"))
            .firstMatch
        if !visit.isHittable {
            app.swipeUp()
        }
        visit.tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["Add reminder"].firstMatch.exists)
        capture("219-balanced-visit-follow-up")
    }

    func testLiveBloodPressureRequestUsesSourceBackedTable() {
        let app = launch()
        loadDemo(app)
        app.buttons["nav-chat"].tap()
        app.buttons["New chat"].tap()
        let field = app.textFields["chatInput"]
        field.tap()
        field.typeText("Show my recent blood pressure readings.")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chatReadingsTable"].firstMatch.waitForExistence(timeout: 300))
        if app.buttons["Stop"].exists {
            app.buttons["Stop"].tap()
        }
        capture("220-blood-pressure-chat-table")
    }
}
