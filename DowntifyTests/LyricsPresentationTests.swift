import XCTest
@testable import Downtify

final class LyricsPresentationTests: XCTestCase {
    private let both = TrackLyrics(synced: "[00:02.00]One\n[00:08.00]Two\n[00:14.00]Three", plain: "One\nTwo\nThree")
    private let syncedOnly = TrackLyrics(synced: "[00:02.00]One", plain: "")
    private let plainOnly = TrackLyrics(synced: "", plain: "Just words")
    private let untagged = TrackLyrics(synced: "no timestamps here", plain: "")

    func testAvailabilityAndModeChoice() {
        XCTAssertTrue(LyricsPresentation.offersModeChoice(both))
        XCTAssertFalse(LyricsPresentation.offersModeChoice(syncedOnly))
        XCTAssertFalse(LyricsPresentation.offersModeChoice(plainOnly))
        XCTAssertFalse(LyricsPresentation.offersModeChoice(untagged))
        XCTAssertFalse(LyricsPresentation.offersModeChoice(nil))
    }

    func testEffectiveModeFollowsRequestOnlyWhenBothFormatsExist() {
        XCTAssertEqual(LyricsPresentation.effectiveMode(both, requested: .synced), .synced)
        XCTAssertEqual(LyricsPresentation.effectiveMode(both, requested: .static), .static)
        XCTAssertEqual(LyricsPresentation.effectiveMode(syncedOnly, requested: .static), .synced)
        XCTAssertEqual(LyricsPresentation.effectiveMode(plainOnly, requested: .synced), .static)
        XCTAssertNil(LyricsPresentation.effectiveMode(untagged, requested: .synced))
        XCTAssertNil(LyricsPresentation.effectiveMode(nil, requested: .synced))
        XCTAssertNil(LyricsPresentation.effectiveMode(TrackLyrics(synced: "", plain: "  \n"), requested: .static))
    }

    func testSeekTargetSelectsTheTappedLineForEveryOffset() {
        let lines = both.lines
        for offset in [-10.0, -0.5, 0, 0.1, 0.5, 3.3, 10] {
            for (index, line) in lines.enumerated() {
                let target = LyricsPresentation.seekTarget(for: line, offset: offset, duration: 600)
                if line.time + offset < 0 { XCTAssertEqual(target, 0) ; continue }
                XCTAssertEqual(LyricsPresentation.activeIndex(lines, position: target, offset: offset), index,
                               "offset \(offset) line \(index)")
            }
        }
    }

    func testDuplicateTimestampsAreSeparateRows() {
        let lyrics = TrackLyrics(synced: "[00:04.00][00:08.00]Chorus\n[00:06.00]Verse", plain: "")
        XCTAssertEqual(lyrics.lines.map(\.text), ["Chorus", "Verse", "Chorus"])
        XCTAssertEqual(LyricsPresentation.activeIndex(lyrics.lines, position: 5, offset: 0), 0)
        XCTAssertEqual(LyricsPresentation.activeIndex(lyrics.lines, position: 9, offset: 0), 2)
    }

    func testSeekTargetIsClamped() {
        let line = LyricLine(time: 20, text: "Late")
        XCTAssertEqual(LyricsPresentation.seekTarget(for: line, offset: 10, duration: 25), 25)
        XCTAssertEqual(LyricsPresentation.seekTarget(for: line, offset: 10, duration: nil), 30)
        XCTAssertEqual(LyricsPresentation.seekTarget(for: LyricLine(time: 1, text: ""), offset: -5, duration: 25), 0)
        XCTAssertEqual(LyricsPresentation.seekTarget(for: line, offset: 0, duration: 0), 20)
    }

    func testActiveIndexBeforeFirstLineIsNil() {
        XCTAssertNil(LyricsPresentation.activeIndex(both.lines, position: 1, offset: 0))
        XCTAssertEqual(LyricsPresentation.activeIndex(both.lines, position: 2, offset: 0), 0)
        XCTAssertNil(LyricsPresentation.activeIndex(both.lines, position: 2.4, offset: 1))
    }

    func testOffsetClampAndAccessibilityTime() {
        XCTAssertEqual(LyricsPresentation.clampedOffset(12), 10)
        XCTAssertEqual(LyricsPresentation.clampedOffset(-12), -10)
        XCTAssertEqual(LyricsPresentation.accessibilityTime(75.9), "1:15")
        XCTAssertEqual(LyricsPresentation.accessibilityTime(-3), "0:00")
    }

    func testResetRemovesOnlyThisTracksSavedOffset() throws {
        let suite = "lyrics-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1.5, forKey: "lyrics.offset.a")
        defaults.set(-2.0, forKey: "lyrics.offset.b")
        XCTAssertEqual(LyricsPresentation.savedOffset(in: defaults, key: "lyrics.offset.a"), 1.5)
        LyricsPresentation.resetOffset(in: defaults, key: "lyrics.offset.a")
        XCTAssertNil(defaults.object(forKey: "lyrics.offset.a"))
        XCTAssertEqual(LyricsPresentation.savedOffset(in: defaults, key: "lyrics.offset.a"), 0)
        XCTAssertEqual(defaults.double(forKey: "lyrics.offset.b"), -2.0)
    }
}
