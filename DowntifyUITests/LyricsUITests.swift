import XCTest

/// Issue #71: tap-to-seek, synced/static display modes and timing reset in the Now Playing lyrics section.
final class LyricsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Helpers

    /// Launches with fixture lyrics, plays the given track and opens the full player.
    private func openPlayer(lyrics: String, trackID: String = "fixture-track-1", app existing: XCUIApplication? = nil) -> XCUIApplication {
        let app = existing ?? DowntifyUITestSupport.launch(fixtureLyrics: lyrics)
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 30) {
            $0.sessionActive && $0.libraryTrackCount == 2
        }, "library did not load")
        playTrack(app, trackID)
        return app
    }

    private func playTrack(_ app: XCUIApplication, _ trackID: String) {
        DowntifyUITestSupport.openLibrarySongs(app)
        let row = DowntifyUITestSupport.element(app, "library.trackRow.\(trackID)")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 30) {
            $0.playbackPhase == "playing" && $0.currentTrackID == trackID
        })
        let dock = DowntifyUITestSupport.element(app, "player.dock")
        XCTAssertTrue(dock.waitForExistence(timeout: 10))
        dock.tap()
        XCTAssertTrue(DowntifyUITestSupport.element(app, "player.full").waitForExistence(timeout: 10))
    }

    private func pause(_ app: XCUIApplication) {
        // The full player's button carries this identifier; the dock behind the sheet is "player.dock".
        let pause = DowntifyUITestSupport.element(app, "player.playPause")
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        XCTAssertEqual(pause.label, "Pause")
        pause.tap()
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 15) { $0.playbackPhase == "paused" })
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<10 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) not reachable", file: file, line: line)
    }

    private func line(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        DowntifyUITestSupport.element(app, "lyrics.line.\(index)")
    }

    private func waitForPosition(_ app: XCUIApplication, near target: Double, tolerance: Double = 0.75, timeout: TimeInterval = 10) -> Bool {
        DowntifyUITestSupport.waitForState(app, timeout: timeout) {
            guard let position = $0.position else { return false }
            return abs(position - target) <= tolerance
        } != nil
    }

    private func offsetLabel(_ app: XCUIApplication) -> String {
        // Regions with a decimal comma read "0,5"; compare digits the same way everywhere.
        DowntifyUITestSupport.element(app, "lyrics.offsetValue").label.replacingOccurrences(of: ",", with: ".")
    }

    // MARK: Seek

    func testTappingTimedLineSeeksAndHighlightsWhilePaused() throws {
        let app = openPlayer(lyrics: "both")
        pause(app)
        let third = line(app, 2)
        reveal(third, in: app)
        XCTAssertTrue(third.label.hasPrefix("Seek to Third line at 0:14"), "label: \(third.label)")

        third.tap()
        XCTAssertTrue(waitForPosition(app, near: 14), "position after tapping line 3: \(String(describing: DowntifyUITestSupport.state(of: app)?.position))")
        XCTAssertTrue(third.isSelected, "tapped line should be highlighted immediately")
        XCTAssertFalse(line(app, 0).isSelected)
        XCTAssertEqual(DowntifyUITestSupport.state(of: app)?.playbackPhase, "paused", "seeking must not resume playback")

        let first = line(app, 0)
        reveal(first, in: app)
        first.tap()
        XCTAssertTrue(waitForPosition(app, near: 2))
        XCTAssertTrue(first.isSelected)
        XCTAssertFalse(third.isSelected)
    }

    func testTappingTimedLineWhilePlayingKeepsPlaying() throws {
        let app = openPlayer(lyrics: "synced")
        let fourth = line(app, 3)
        reveal(fourth, in: app)
        fourth.tap()
        let state = DowntifyUITestSupport.waitForState(app, timeout: 10) { ($0.position ?? 0) >= 19.5 }
        XCTAssertNotNil(state, "position never reached the fourth line")
        XCTAssertEqual(state?.playbackPhase, "playing")
    }

    // MARK: Display modes

    func testModePickerSwitchesBetweenSyncedAndStatic() throws {
        let app = openPlayer(lyrics: "both")
        let picker = DowntifyUITestSupport.element(app, "lyrics.modePicker")
        reveal(picker, in: app)
        XCTAssertTrue(line(app, 0).exists)
        XCTAssertFalse(DowntifyUITestSupport.element(app, "lyrics.plain").exists)

        picker.buttons["Static"].tap()
        let plain = DowntifyUITestSupport.element(app, "lyrics.plain")
        XCTAssertTrue(plain.waitForExistence(timeout: 5))
        XCTAssertFalse(line(app, 0).exists, "timed rows are hidden in static mode")
        XCTAssertFalse(DowntifyUITestSupport.element(app, "lyrics.resetOffset").exists, "timing controls are hidden in static mode")

        picker.buttons["Synced"].tap()
        XCTAssertTrue(line(app, 0).waitForExistence(timeout: 5))
        XCTAssertTrue(DowntifyUITestSupport.element(app, "lyrics.resetOffset").exists)
    }

    func testSingleFormatShowsNoPicker() throws {
        let synced = openPlayer(lyrics: "synced")
        reveal(line(synced, 0), in: synced)
        XCTAssertFalse(DowntifyUITestSupport.element(synced, "lyrics.modePicker").exists)
        synced.terminate()

        let plain = openPlayer(lyrics: "plain")
        let text = DowntifyUITestSupport.element(plain, "lyrics.plain")
        reveal(text, in: plain)
        XCTAssertFalse(DowntifyUITestSupport.element(plain, "lyrics.modePicker").exists)
        XCTAssertFalse(line(plain, 0).exists)
        XCTAssertFalse(DowntifyUITestSupport.element(plain, "lyrics.resetOffset").exists)
    }

    // MARK: Timing reset

    func testResetClearsOnlyTheCurrentTracksOffset() throws {
        let app = openPlayer(lyrics: "both", trackID: "fixture-track-2")
        let later = app.buttons["Lyrics later by half a second"].firstMatch
        reveal(later, in: app)
        later.tap()
        XCTAssertTrue(offsetLabel(app).contains("0.5"), offsetLabel(app))
        app.buttons["Done"].firstMatch.tap()

        playTrack(app, "fixture-track-1")
        let later1 = app.buttons["Lyrics later by half a second"].firstMatch
        reveal(later1, in: app)
        XCTAssertTrue(offsetLabel(app).contains("0.0"), "offsets are per track: \(offsetLabel(app))")
        let reset = DowntifyUITestSupport.element(app, "lyrics.resetOffset")
        XCTAssertFalse(reset.isEnabled, "reset is disabled while there is nothing to reset")
        later1.tap()
        later1.tap()
        XCTAssertTrue(offsetLabel(app).contains("1.0"), offsetLabel(app))
        XCTAssertTrue(reset.isEnabled)

        reset.tap()
        XCTAssertTrue(offsetLabel(app).contains("0.0"), offsetLabel(app))
        XCTAssertFalse(reset.isEnabled)
        app.buttons["Done"].firstMatch.tap()

        playTrack(app, "fixture-track-2")
        reveal(app.buttons["Lyrics later by half a second"].firstMatch, in: app)
        XCTAssertTrue(offsetLabel(app).contains("0.5"), "resetting one track must not clear another: \(offsetLabel(app))")
    }

    func testResetMovesHighlightImmediately() throws {
        let app = openPlayer(lyrics: "both")
        pause(app)
        let later = app.buttons["Lyrics later by half a second"].firstMatch
        reveal(later, in: app)
        let second = line(app, 1)
        second.tap()
        XCTAssertTrue(waitForPosition(app, near: 8))
        XCTAssertTrue(second.isSelected)
        // Shifting lyrics later makes the same playback position fall on an earlier line.
        for _ in 0..<4 { later.tap() }
        XCTAssertTrue(line(app, 0).isSelected, "a 2 s later offset moves the highlight back to the first line")
        DowntifyUITestSupport.element(app, "lyrics.resetOffset").tap()
        XCTAssertTrue(second.isSelected, "reset restores the highlight right away")
    }

    // MARK: Track changes, missing and error states

    func testLyricsReloadWhenTrackChanges() throws {
        let app = openPlayer(lyrics: "both")
        reveal(line(app, 0), in: app)
        app.buttons["Done"].firstMatch.tap()
        playTrack(app, "fixture-track-2")
        let picker = DowntifyUITestSupport.element(app, "lyrics.modePicker")
        reveal(picker, in: app)
        XCTAssertTrue(line(app, 0).exists, "mode resets to synced for a new track")
    }

    func testMissingLyricsShowUnavailableMessage() throws {
        let app = openPlayer(lyrics: "none")
        let message = app.staticTexts["Lyrics are unavailable for this track."]
        for _ in 0..<10 where !message.exists { app.swipeUp() }
        XCTAssertTrue(message.exists)
        XCTAssertFalse(line(app, 0).exists)
    }

    func testLyricsErrorOffersRetry() throws {
        let app = openPlayer(lyrics: "error")
        let message = app.staticTexts["Lyrics could not be loaded."]
        for _ in 0..<10 where !message.exists { app.swipeUp() }
        XCTAssertTrue(message.exists)
        XCTAssertTrue(app.buttons["Retry"].firstMatch.exists)
    }

    // MARK: Real staging server

    /// Optional: plays "Karma Police" from the configured staging library and checks real timed lyrics seek.
    /// Read-only; skipped unless the runner provides a staging server (see docs/SIMULATOR_AUTOMATION.md).
    func testKarmaPoliceTimedLyricsSeekOnStaging() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["DOWNTIFY_TEST_SERVER"] == nil,
                      "No staging server configured for the test runner; scenario not run.")
        let app = DowntifyUITestSupport.launch(staging: true)
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 90) { $0.sessionActive && $0.libraryTrackCount > 0 },
                        "staging library did not load")
        DowntifyUITestSupport.openLibrarySongs(app)
        let filter = app.searchFields.firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 15))
        filter.tap()
        filter.typeText("Karma Police")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Karma Police'")).firstMatch
        try XCTSkipUnless(row.waitForExistence(timeout: 20), "Karma Police is not in the staging library")
        row.tap()
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 60) { $0.playbackPhase == "playing" })
        let dock = DowntifyUITestSupport.element(app, "player.dock")
        XCTAssertTrue(dock.waitForExistence(timeout: 10))
        dock.tap()
        pause(app)

        let first = line(app, 0)
        for _ in 0..<10 where !first.exists { app.swipeUp() }
        try XCTSkipUnless(first.exists, "Staging server has no timed lyrics for Karma Police")
        // Pick a line well into the song and seek to the time shown in its label ("Seek to <text> at m:ss").
        var index = 5
        while index > 0 && !line(app, index).exists { index -= 1 }
        let target = line(app, index)
        reveal(target, in: app)
        let label = target.label
        let stamp = try XCTUnwrap(label.components(separatedBy: " at ").last, "label: \(label)")
        let parts = stamp.split(separator: ":").compactMap { Double($0) }
        XCTAssertEqual(parts.count, 2, "label: \(label)")
        let seconds = parts[0] * 60 + parts[1]
        target.tap()
        XCTAssertTrue(waitForPosition(app, near: seconds, tolerance: 1.5), "seek target \(seconds) s from \(label)")
        XCTAssertTrue(target.isSelected)
    }
}
