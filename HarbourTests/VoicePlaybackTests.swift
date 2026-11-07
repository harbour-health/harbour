import XCTest
import Combine
@testable import Harbour

@MainActor final class VoicePlaybackTests: XCTestCase {
    func testPlaybackFeedsVisualizerAndStopClearsIt() async throws {
        try XCTSkipUnless(KokoroAssets.shared.ready, "Local Kokoro assets are required; this test does not download them.")
        let voice = VoiceService()
        let audioLevel = expectation(description: "Playback mixer produces an audible signal")
        let subscription = voice.visualization.$level.filter { $0 > 0.005 }.first().sink { _ in audioLevel.fulfill() }
        defer { subscription.cancel(); voice.stop() }
        voice.speak("This is a fictional voice interface test.")
        await fulfillment(of: [audioLevel], timeout: 45)
        voice.stop()
        XCTAssertEqual(voice.visualization.level, 0)
        XCTAssertFalse(voice.listening)
        XCTAssertFalse(voice.speaking)
        // Queued mixer callbacks from the stopped generation must not revive the orb.
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(voice.visualization.level, 0)
    }
}
