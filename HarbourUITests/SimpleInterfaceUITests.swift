import XCTest

@MainActor final class SimpleInterfaceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func launch(_ language: String = "en", mode: String = "simple", largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-unlocked",
            "-appearance",
            "Light",
            "-AppleLanguages",
            "(\(language))",
            "-AppleLocale",
            language == "en" ? "en_CA" : "fr_CA"
        ]
        if largeText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        }
        app.launchEnvironment["HARBOUR_INITIAL_INTERFACE"] = mode
        app.launch()

        return app
    }

    private func tapWhenReady(_ element: XCUIElement) {
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: element)],
                timeout: 8
            ),
            .completed
        )
        element.tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0 ..< 6 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func openInterface(in app: XCUIApplication, language: String = "en") {
        tapWhenReady(app.buttons[language == "en" ? "Settings" : "Réglages"])
        tapWhenReady(app.buttons["interfaceSettings"])
        XCTAssertTrue(app.staticTexts["interfaceSharedRecords"].waitForExistence(timeout: 5))
    }

    private func closeInterface(in app: XCUIApplication, language: String = "en") {
        tapWhenReady(app.navigationBars["Interface"].buttons.firstMatch)
        tapWhenReady(app.navigationBars[language == "en" ? "Settings" : "Réglages"].buttons[
            language == "en" ? "Done" : "Terminé"
        ])
    }

    private func switchInterface(to mode: String, in app: XCUIApplication, language: String = "en") {
        openInterface(in: app, language: language)
        let choice = app.buttons["interface-" + mode]
        scrollTo(choice, in: app)
        tapWhenReady(choice)
        XCTAssertTrue(choice.isSelected)
        closeInterface(in: app, language: language)
    }

    func testSimpleHomeHelpAndCaregiverSwitch() {
        let app = launch()
        XCTAssertTrue(app.buttons["simpleTalk"].waitForExistence(timeout: 10))
        for id in ["simpleTalk", "simpleMessage", "simpleRecordVisit", "simpleGuide"] {
            XCTAssertTrue(app.buttons[id].isHittable, id)
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 56, id)
        }
        XCTAssertFalse(app.buttons["nav-records"].exists)
        capture("226-simple-home")
        app.buttons["simpleGuide"].tap()
        XCTAssertTrue(app.staticTexts["Talk naturally"].waitForExistence(timeout: 5))
        capture("227-simple-guide")
        app.buttons["Try a message"].tap()
        XCTAssertTrue(app.textFields["chatInput"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["modelSelector"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["startVoiceConversation"].frame.height, 56)
        capture("228-simple-chat")
        app.buttons["Home"].tap()
        app.buttons["Settings"].tap()
        capture("229-simple-settings")
        app.buttons["interfaceSettings"].tap()
        app.buttons["interface-caregiver"].tap()
        app.navigationBars["Interface"].buttons.firstMatch.tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["nav-records"].waitForExistence(timeout: 5))
        capture("230-caregiver-home")
    }

    func testSimpleLargestTextKeepsPrimaryActionsReachable() {
        for language in ["en", "fr-CA"] {
            let app = launch(language, largeText: true)
            XCTAssertTrue(app.buttons["simpleTalk"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["simpleTalk"].isHittable)
            capture(language == "en" ? "248-simple-largest-text" : "Simple largest text French")
            for id in ["simpleMessage", "simpleRecordVisit", "simpleGuide"] {
                let button = app.buttons[id]
                scrollTo(button, in: app)
                XCTAssertGreaterThanOrEqual(button.frame.height, 56, id)
            }
            app.buttons["simpleGuide"].tap()
            XCTAssertTrue(app.buttons[language == "en" ? "Try a message" : "Essayer un message"]
                .waitForExistence(timeout: 5))
            tapWhenReady(app.navigationBars[language == "en" ? "How to use Harbour" : "Utiliser Harbour"].buttons[
                language == "en" ? "Done" : "Terminé"
            ])
            openInterface(in: app, language: language)
            let caregiver = app.buttons["interface-caregiver"]
            scrollTo(caregiver, in: app)
            XCTAssertGreaterThanOrEqual(caregiver.frame.height, 64)
            caregiver.tap()
            XCTAssertTrue(caregiver.isSelected)
            closeInterface(in: app, language: language)
            for id in ["nav-today", "nav-chat", "nav-records", "nav-visits"] {
                XCTAssertTrue(app.buttons[id].isHittable, id)
            }
            tapWhenReady(app.buttons["nav-records"])
            let appointments = app.buttons["record-category-3"]
            scrollTo(appointments, in: app)
            app.terminate()
        }
    }

    func testFrenchSimpleHome() {
        let app = launch("fr-CA")
        XCTAssertTrue(app.buttons["simpleTalk"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["simpleGuide"].label.contains("Utiliser Harbour"))
        capture("231-simple-french")
        app.buttons["simpleGuide"].tap()
        XCTAssertTrue(app.staticTexts["Parlez naturellement"].waitForExistence(timeout: 5))
        capture("232-simple-guide-french")
    }

    func testUnsentChatDraftSurvivesHomeAndBothModeSwitches() {
        let app = launch()
        tapWhenReady(app.buttons["simpleMessage"])
        let input = app.textFields["chatInput"]
        tapWhenReady(input)
        let draft = "Unsent interface draft " + UUID().uuidString
        input.typeText(draft)
        tapWhenReady(app.buttons["Done"])
        tapWhenReady(app.buttons["Home"])
        tapWhenReady(app.buttons["simpleMessage"])
        XCTAssertEqual(input.value as? String, draft)

        switchInterface(to: "caregiver", in: app)
        tapWhenReady(app.buttons["nav-chat"])
        XCTAssertEqual(input.value as? String, draft)
        switchInterface(to: "simple", in: app)
        tapWhenReady(app.buttons["simpleMessage"])
        XCTAssertEqual(input.value as? String, draft)
    }

    func testModeSelectionPersistsAcrossRelaunchWithoutLaunchSeed() {
        let app = launch()
        switchInterface(to: "caregiver", in: app)
        XCTAssertTrue(app.buttons["nav-records"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "HARBOUR_INITIAL_INTERFACE")
        app.launch()
        XCTAssertTrue(app.buttons["nav-records"].waitForExistence(timeout: 8))
        openInterface(in: app)
        XCTAssertTrue(app.buttons["interface-caregiver"].isSelected)
        tapWhenReady(app.buttons["interface-simple"])
        closeInterface(in: app)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["simpleMessage"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["nav-records"].exists)
        openInterface(in: app)
        XCTAssertTrue(app.buttons["interface-simple"].isSelected)
    }

    func testConfirmedRecordSurvivesModeSwitchesAndRelaunch() {
        let app = launch(mode: "caregiver")
        tapWhenReady(app.buttons["nav-records"])
        let category = app.buttons["record-category-3"]
        scrollTo(category, in: app)
        category.tap()
        tapWhenReady(app.buttons["Add record"])
        let title = "Fictional interface appointment " + String(UUID().uuidString.prefix(8))
        let titleField = app.textFields["appointmentTitle"]
        tapWhenReady(titleField)
        titleField.typeText(title)
        XCTAssertFalse(app.buttons["saveAppointment"].isEnabled)
        tapWhenReady(app.buttons["Cancel"])
        XCTAssertFalse(app.staticTexts[title].exists)

        tapWhenReady(app.buttons["Add record"])
        tapWhenReady(titleField)
        titleField.typeText(title)
        XCTAssertFalse(app.buttons["saveAppointment"].isEnabled)
        tapWhenReady(app.buttons["Done"])
        let confirm = app.switches["confirmAppointmentDate"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(confirm.value as? String, "1")
        tapWhenReady(app.buttons["saveAppointment"])
        scrollTo(app.staticTexts[title], in: app)

        tapWhenReady(app.buttons["nav-today"])
        switchInterface(to: "simple", in: app)
        XCTAssertTrue(app.buttons["simpleMessage"].waitForExistence(timeout: 5))
        switchInterface(to: "caregiver", in: app)
        tapWhenReady(app.buttons["nav-records"])
        scrollTo(app.staticTexts[title], in: app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "HARBOUR_INITIAL_INTERFACE")
        app.launch()
        tapWhenReady(app.buttons["nav-records"])
        scrollTo(category, in: app)
        category.tap()
        scrollTo(app.staticTexts[title], in: app)
    }

    func testInterfaceAccessibilityMetadataInBothLanguages() throws {
        for language in ["en", "fr-CA"] {
            let app = launch(language)
            XCTAssertTrue(app.buttons["simpleTalk"].waitForExistence(timeout: 8))
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
            openInterface(in: app, language: language)
            let notice = app.staticTexts["interfaceSharedRecords"]
            XCTAssertEqual(notice.label, language == "en"
                ? "Both layouts show and edit the same person's health records on this iPhone. Switching layouts does not select another person."
                : "Les deux interfaces affichent et modifient le dossier de santé de la même personne sur cet iPhone. Changer d’interface ne change pas de personne.")
            let simple = app.buttons["interface-simple"]
            let caregiver = app.buttons["interface-caregiver"]
            XCTAssertEqual(simple.label, "Simple")
            XCTAssertEqual(simple.value as? String, language == "en" ? "Chat and voice" : "Clavardage et voix")
            XCTAssertEqual(caregiver.label, language == "en" ? "Caregiver" : "Proche aidant")
            XCTAssertEqual(caregiver.value as? String, language == "en" ? "Records and tools" : "Dossiers et outils")
            XCTAssertTrue(simple.isSelected)
            XCTAssertFalse(caregiver.isSelected)
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
            scrollTo(caregiver, in: app)
            caregiver.tap()
            XCTAssertTrue(caregiver.isSelected)
            XCTAssertFalse(simple.isSelected)
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
            closeInterface(in: app, language: language)
            XCTAssertTrue(app.buttons["nav-records"].waitForExistence(timeout: 5))
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
            app.terminate()
        }
    }
}
