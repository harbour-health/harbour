import XCTest
import UIKit

@MainActor final class AppearanceAndLockVisualTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAppearanceSelectionMovesBetweenRowsImmediately() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-unlocked", "-AppleLanguages", "(en)", "-AppleLocale", "en_CA"]
        app.launch()

        app.buttons["nav-today"].tap()
        app.buttons["Settings"].tap()
        app.buttons["Appearance"].tap()

        let system = app.buttons["appearance-system"]
        let light = app.buttons["appearance-light"]
        let dark = app.buttons["appearance-dark"]
        let original = system.isSelected ? system : light.isSelected ? light : dark
        XCTAssertTrue(original.isSelected)

        dark.tap()
        XCTAssertTrue(dark.isSelected)
        XCTAssertFalse(system.isSelected)
        XCTAssertFalse(light.isSelected)

        light.tap()
        XCTAssertTrue(light.isSelected)
        XCTAssertFalse(dark.isSelected)

        original.tap()
        XCTAssertTrue(original.isSelected)
        XCTAssertEqual([system, light, dark].filter { $0.isSelected }.count, 1)
    }

    func testBiometricUnlockButtonOnDarkAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-biometric-lock",
            "-appearance", "Dark",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_CA"
        ]
        app.launch()

        let unlock = app.buttons["biometricUnlockButton"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(unlock.label.contains("Face ID"), unlock.label)

        let capture = app.screenshot()
        let bitmap = try XCTUnwrap(capture.image.cgImage)
        let scale = CGFloat(bitmap.width) / app.frame.width
        let frame = unlock.frame
        // Sample the label region, away from the icon and rounded button edges.
        let label = CGRect(x: (frame.minX + frame.width * 0.35) * scale, y: (frame.minY + frame.height * 0.25) * scale, width: frame.width * 0.55 * scale, height: frame.height * 0.5 * scale)
        let crop = try XCTUnwrap(bitmap.cropping(to: label))
        var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(crop.width), height: CGFloat(crop.height)))
        }
        let dark = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] < 80 && pixels[$0 + 1] < 80 && pixels[$0 + 2] < 80 }.count
        let light = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 120 && pixels[$0 + 1] > 120 && pixels[$0 + 2] > 120 }.count
        XCTAssertGreaterThan(dark, 20, "Dark unlock label must be visible on the light button fill")
        XCTAssertGreaterThan(light, 200, "Expected a contrasting light button fill")
        let screenshot = XCTAttachment(screenshot: capture)
        screenshot.name = "Dark Face ID unlock"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
