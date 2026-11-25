import XCTest

/// Issue #72: the Similar list extends as the listener nears its end.
final class SimilarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func row(_ app: XCUIApplication, page: Int, _ index: Int) -> XCUIElement {
        DowntifyUITestSupport.element(app, "similar.row.similar-p\(page)-\(index)")
    }

    /// Opens Discover > Similar and runs a search from the fixture seed.
    private func search(_ app: XCUIApplication, artist: String = "Radiohead", track: String = "Karma Police") {
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 30) { $0.sessionActive && $0.libraryTrackCount == 2 })
        DowntifyUITestSupport.element(app, "tab.discover").tap()
        let similar = app.segmentedControls.buttons["Similar"].firstMatch
        XCTAssertTrue(similar.waitForExistence(timeout: 15), "Similar section missing")
        similar.tap()
        let artistField = app.textFields["Similar artist"].firstMatch
        XCTAssertTrue(artistField.waitForExistence(timeout: 10))
        artistField.tap()
        artistField.typeText(artist)
        let trackField = app.textFields["Similar track"].firstMatch
        trackField.tap()
        trackField.typeText(track)
        let done = app.buttons["Done"].firstMatch
        if done.exists { done.tap() }
        app.buttons["Find similar tracks"].firstMatch.tap()
        XCTAssertTrue(row(app, page: 1, 1).waitForExistence(timeout: 15), "first page never loaded")
    }

    private func scrollDown(_ app: XCUIApplication, until condition: () -> Bool, maxSwipes: Int = 30) {
        for _ in 0..<maxSwipes where !condition() { app.swipeUp() }
    }

    func testNextPageLoadsOnlyNearTheEndWithoutDuplicates() throws {
        let app = DowntifyUITestSupport.launch(fixtureSimilar: "3")
        search(app)
        XCTAssertFalse(row(app, page: 2, 1).exists, "no extension before the listener scrolls")
        XCTAssertFalse(DowntifyUITestSupport.element(app, "similar.loadingMore").exists)

        scrollDown(app, until: { self.row(app, page: 2, 1).exists })
        XCTAssertTrue(row(app, page: 2, 1).waitForExistence(timeout: 15), "page 2 never appended")
        // Every appended row is unique: ids are page-specific, so counting by prefix is enough.
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'similar.row.'"))
        let ids = (0..<rows.count).map { rows.element(boundBy: $0).identifier }
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate row identifiers")
    }

    func testListRunsDryAfterTheLastPage() throws {
        let app = DowntifyUITestSupport.launch(fixtureSimilar: "2")
        search(app)
        let end = DowntifyUITestSupport.element(app, "similar.end")
        scrollDown(app, until: { end.exists }, maxSwipes: 60)
        XCTAssertTrue(end.waitForExistence(timeout: 20), "end marker never shown")
        XCTAssertTrue(row(app, page: 2, 1).exists || row(app, page: 2, 20).exists)
        XCTAssertFalse(DowntifyUITestSupport.element(app, "similar.loadingMore").exists)
    }

    func testFailedExtensionKeepsRowsAndRetryRecovers() throws {
        let app = DowntifyUITestSupport.launch(fixtureSimilar: "3,failpage=2")
        search(app)
        let retry = DowntifyUITestSupport.element(app, "similar.retry")
        scrollDown(app, until: { retry.exists })
        XCTAssertTrue(retry.waitForExistence(timeout: 20), "retry control never shown")
        XCTAssertTrue(row(app, page: 1, 20).exists, "existing rows are preserved after a failure")
        XCTAssertFalse(row(app, page: 2, 1).exists)

        retry.tap()
        XCTAssertTrue(row(app, page: 2, 1).waitForExistence(timeout: 15), "retry did not append page 2")
        XCTAssertFalse(retry.exists)
    }

    func testNewSearchReplacesExtendedList() throws {
        let app = DowntifyUITestSupport.launch(fixtureSimilar: "3")
        search(app)
        scrollDown(app, until: { self.row(app, page: 2, 1).exists })
        XCTAssertTrue(row(app, page: 2, 1).waitForExistence(timeout: 15))
        for _ in 0..<30 where !app.buttons["Find similar tracks"].isHittable { app.swipeDown() }
        let button = app.buttons["Find similar tracks"].firstMatch
        XCTAssertTrue(button.isHittable)
        button.tap()
        XCTAssertTrue(row(app, page: 1, 1).waitForExistence(timeout: 15))
        XCTAssertFalse(row(app, page: 2, 1).exists, "a new search starts from a fresh list")
    }

    func testExtensionDoesNotInterruptPlayback() throws {
        let app = DowntifyUITestSupport.launch(fixtureSimilar: "3")
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 30) { $0.sessionActive && $0.libraryTrackCount == 2 })
        DowntifyUITestSupport.openLibrarySongs(app)
        let track = DowntifyUITestSupport.element(app, "library.trackRow.fixture-track-1")
        XCTAssertTrue(track.waitForExistence(timeout: 15))
        track.tap()
        XCTAssertNotNil(DowntifyUITestSupport.waitForState(app, timeout: 30) { $0.playbackPhase == "playing" })

        search(app)
        scrollDown(app, until: { self.row(app, page: 2, 1).exists })
        XCTAssertTrue(row(app, page: 2, 1).waitForExistence(timeout: 15))
        let state = DowntifyUITestSupport.state(of: app)
        XCTAssertEqual(state?.currentTrackID, "fixture-track-1")
        XCTAssertNotEqual(state?.playbackPhase, "failed")
    }
}
