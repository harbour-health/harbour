import XCTest

/// Clean footage from real native controls and local inference; no presenter UI inside the phone.
@MainActor final class PresentationWalkthroughUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func capture(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        print("WALKTHROUGH_CHAPTER \(name) \(Date().timeIntervalSince1970)")
        let app = XCUIApplication()
        var regions: [String: [String: Double]] = [:]
        for id in ["simpleTalk", "simpleMessage", "simpleRecordVisit", "chatInput", "chatReadingsTable", "reviewVisitMedicines", "confirmVisitMedicines", "saveVisitMedicines", "confirmMedicine", "medicineInstructions", "saveMedicine"] {
            let element = app.descendants(matching: .any)[id].firstMatch
            if element.exists {
                let r = element.frame
                if r.intersects(app.frame) {
                    regions[id] = ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
                }
            }
        }
        let payload: [String: Any] = ["chapter": name, "screen": ["width": app.frame.width, "height": app.frame.height], "regions": regions]
        if let bytes = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), let text = String(data: bytes, encoding: .utf8) { print("WALKTHROUGH_REGIONS " + text) }
    }
    private func interface(_ mode: String, app: XCUIApplication) {
        app.buttons["Settings"].tap(); app.buttons["interfaceSettings"].tap(); app.buttons["interface-" + mode].tap()
        app.navigationBars["Interface"].buttons.firstMatch.tap(); app.navigationBars["Settings"].buttons["Done"].tap()
    }
    func testGuidedWalkthrough() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-unlocked", "-model", "small", "-appearance", "Light", "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launchCaregiver()
        app.buttons["nav-today"].tap(); app.buttons["Settings"].tap()
        if !app.buttons["developerSettings"].isHittable { app.swipeUp() }
        app.buttons["developerSettings"].tap(); app.buttons["loadDemoData"].tap()
        app.alerts.buttons["Replace with demo data"].tap()
        XCTAssertTrue(app.staticTexts["demoDataLoaded"].waitForExistence(timeout: 5))
        app.navigationBars["Developer"].buttons.firstMatch.tap(); app.buttons["interfaceSettings"].tap()
        app.buttons["interface-simple"].tap(); app.navigationBars["Interface"].buttons.firstMatch.tap(); app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["simpleMessage"].waitForExistence(timeout: 5))
        capture("233-guided-simple-home")
        app.buttons["simpleMessage"].tap()
        let input = app.textFields["chatInput"]; input.tap(); input.typeText("Show my recent blood pressure readings")
        capture("236-guided-real-request"); app.buttons["Send message"].tap()
        print("WALKTHROUGH_INFERENCE_START \(Date().timeIntervalSince1970)")
        XCTAssertTrue(app.descendants(matching: .any)["chatReadingsTable"].firstMatch.waitForExistence(timeout: 360))
        print("WALKTHROUGH_INFERENCE_END \(Date().timeIntervalSince1970)")
        capture("237-guided-readings")
        app.buttons["Home"].tap(); interface("caregiver", app: app)
        app.buttons["nav-records"].tap(); capture("240-guided-caregiver-records")
        app.buttons["record-category-1"].tap(); capture("242-guided-medicines")
        app.buttons["Add record"].tap()
        let search = app.textFields["medicineSearch"]; search.tap(); search.typeText("hydroclorothiazide")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        XCTAssertTrue(app.staticTexts["Similar names"].waitForExistence(timeout: 5)); capture("243-guided-phonetic-suggestions")
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","medicineSuggestion-")).firstMatch.tap()
        XCTAssertTrue(app.buttons["confirmMedicine"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveMedicine"].isEnabled); capture("244-guided-medicine-confirmation")
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        app.buttons["nav-visits"].tap()
        let visit = app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Demo · Blood pressure follow-up")).firstMatch
        if !visit.isHittable { app.swipeUp() }; visit.tap()
        XCTAssertTrue(app.buttons["reviewVisitMedicines"].waitForExistence(timeout: 5)); capture("245-guided-visit-summary")
        app.swipeUp(); capture("246-guided-visit-followups"); app.swipeDown()
        app.buttons["reviewVisitMedicines"].tap()
        XCTAssertTrue(app.buttons["saveVisitMedicines"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveVisitMedicines"].isEnabled); capture("247-guided-visit-review")
        app.navigationBars["Medication changes"].buttons["Cancel"].tap()
    }
}
