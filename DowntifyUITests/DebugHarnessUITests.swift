import XCTest

final class DebugHarnessUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Scenario 1: fixture end-to-end. Library loads, playback starts, player visible with artwork.
    func testFixtureLibraryPlaybackEndToEnd() throws {
        let app = DowntifyUITestSupport.launch()
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 30) {
            $0.sessionActive && $0.libraryTrackCount == 2
        }, "library did not load in fixture mode; last state: \(String(describing: DowntifyUITestSupport.state(of: app)))")

        DowntifyUITestSupport.openLibrarySongs(app)
        let row = DowntifyUITestSupport.element(app, "library.trackRow.fixture-track-1")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()

        let playing = DowntifyUITestSupport.waitForState(app, timeout: 30) { $0.playbackPhase == "playing" }
        XCTAssertNotNil(playing, "playback never reached playing")
        XCTAssertEqual(playing?.currentTrackID, "fixture-track-1")
        XCTAssertEqual(playing?.playerVisible, true)
        XCTAssertTrue(DowntifyUITestSupport.element(app, "player.dock").waitForExistence(timeout: 10))
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 15) { $0.artworkLoaded })
    }

    /// Scenario 2: controlled failure. A stream fault must surface as a failed phase with an error code.
    func testInjectedStreamFaultReportsFailure() throws {
        let app = DowntifyUITestSupport.launch(faults: ["stream=http500"])
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 30) {
            $0.sessionActive && $0.libraryTrackCount == 2
        })

        DowntifyUITestSupport.openLibrarySongs(app)
        DowntifyUITestSupport.element(app, "library.trackRow.fixture-track-1").tap()

        let failed = DowntifyUITestSupport.waitForState(app, timeout: 30) { $0.playbackPhase == "failed" }
        XCTAssertNotNil(failed, "stream fault did not produce a failed phase")
        XCTAssertNotNil(failed?.lastErrorCode)
    }

    /// Scenario 3 (optional): real staging server, read-only. Skipped unless the runner provides a server.
    func testRealStagingLibraryLoadsReadOnly() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["DOWNTIFY_TEST_SERVER"] == nil,
                      "No staging server configured for the test runner; scenario not run.")
        let app = DowntifyUITestSupport.launch(staging: true)
        let state = DowntifyUITestSupport.waitForState(app, timeout: 60) { $0.sessionActive }
        XCTAssertNotNil(state, "staging session did not become active")
        XCTAssertNotEqual(state?.playbackPhase, "failed")
    }
}
