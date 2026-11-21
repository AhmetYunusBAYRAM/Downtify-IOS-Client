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

    /// Issue #46: the current song row is highlighted, moves to a newly played song, and survives pause.
    func testCurrentSongHighlightFollowsQueue() throws {
        let app = DowntifyUITestSupport.launch()
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 30) {
            $0.sessionActive && $0.libraryTrackCount == 2
        })
        DowntifyUITestSupport.openLibrarySongs(app)
        let first = DowntifyUITestSupport.element(app, "library.trackRow.fixture-track-1")
        let second = DowntifyUITestSupport.element(app, "library.trackRow.fixture-track-2")
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertFalse(value(of: first).contains("Now playing"))
        first.tap()

        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 30) { $0.playbackPhase == "playing" })
        XCTAssertTrue(waitForValue(of: first, toContain: "Now playing"), "first row value: \(value(of: first))")
        XCTAssertTrue(first.isSelected)
        XCTAssertFalse(second.isSelected)

        second.tap()
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 30) {
            $0.currentTrackID == "fixture-track-2" && $0.playbackPhase == "playing"
        }, "after selecting the second song: \(String(describing: DowntifyUITestSupport.state(of: app)))")
        XCTAssertTrue(waitForValue(of: second, toContain: "Now playing"), "second row value: \(value(of: second))")
        XCTAssertTrue(second.isSelected)
        XCTAssertFalse(first.isSelected)
        XCTAssertFalse(value(of: first).contains("Now playing"))

        let pause = app.buttons["Pause"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 15) { $0.playbackPhase == "paused" })
        XCTAssertTrue(waitForValue(of: second, toContain: "Paused"), "paused row value: \(value(of: second))")
        XCTAssertTrue(second.isSelected, "A paused song stays highlighted")
    }

    private func value(of element: XCUIElement) -> String { element.value as? String ?? "" }

    private func waitForValue(of element: XCUIElement, toContain text: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if value(of: element).contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return false
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
