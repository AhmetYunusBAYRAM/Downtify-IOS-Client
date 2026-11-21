import Combine
import XCTest
@testable import Downtify

@MainActor
final class NowPlayingIndicatorTests: XCTestCase {
    func testLibraryTrackMatchesByIDAndPlayStateFollowsPhase() {
        let indicator = NowPlayingIndicator()
        let first = track("first"), second = track("second")

        indicator.update(item: .library(first), phase: .playing)
        XCTAssertTrue(indicator.isCurrent(first))
        XCTAssertFalse(indicator.isCurrent(second))
        XCTAssertTrue(indicator.isPlaying)

        for phase in [PlaybackPhase.loading, .buffering] {
            indicator.update(item: .library(first), phase: phase)
            XCTAssertTrue(indicator.isPlaying, "\(phase) counts as playing")
        }
        for phase in [PlaybackPhase.paused, .idle, .ended, .failed(.network)] {
            indicator.update(item: .library(first), phase: phase)
            XCTAssertTrue(indicator.isCurrent(first), "\(phase) keeps the current song highlighted")
            XCTAssertFalse(indicator.isPlaying, "\(phase) is not playing")
        }

        indicator.update(item: nil, phase: .playing)
        XCTAssertNil(indicator.currentID)
        XCTAssertNil(indicator.currentLibraryFile)
        XCTAssertFalse(indicator.isPlaying)
    }

    func testCatalogSongMatchesByIDOrLibraryFile() throws {
        let indicator = NowPlayingIndicator()
        let external = try song(id: "ext", source: "youtube", file: nil)
        let libraryCopy = try song(id: "lib", source: "library", file: "first.mp3")
        let otherLibrary = try song(id: "lib2", source: "library", file: "other.mp3")
        let externalSameFile = try song(id: "ext2", source: "youtube", file: "first.mp3")

        indicator.update(item: .catalog(external), phase: .playing)
        XCTAssertTrue(indicator.isCurrent(external))
        XCTAssertFalse(indicator.isCurrent(libraryCopy))
        XCTAssertNil(indicator.currentLibraryFile)

        indicator.update(item: .library(track("first")), phase: .playing)
        XCTAssertTrue(indicator.isCurrent(libraryCopy))
        XCTAssertFalse(indicator.isCurrent(otherLibrary))
        XCTAssertFalse(indicator.isCurrent(externalSameFile), "Only library-sourced results resolve to library files")
        XCTAssertFalse(indicator.isCurrent(external))
    }

    func testRepeatedUpdatesWithSameStateDoNotPublish() {
        let indicator = NowPlayingIndicator()
        var changes = 0
        let subscription = indicator.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        indicator.update(item: .library(track("first")), phase: .playing)
        let afterFirst = changes
        XCTAssertGreaterThan(afterFirst, 0)
        indicator.update(item: .library(track("first")), phase: .playing)
        indicator.update(item: .library(track("first")), phase: .buffering)
        XCTAssertEqual(changes, afterFirst)
    }

    private func track(_ id: String) -> LibraryTrack {
        LibraryTrack(id: id, file: "\(id).mp3", title: id, artist: "Artist", artists: ["Artist"], album: "Album",
                     albumArtist: "Artist", albumID: "album", artistID: "artist", trackNumber: 1, year: "2026",
                     duration: 100, codec: "mp3", bitrate: 128_000, sampleRate: 44_100, channels: 2, size: 100,
                     added: 0, hasCover: false, isExplicit: false, playlists: [])
    }

    private func song(id: String, source: String, file: String?) throws -> CatalogSong {
        let fileJSON = file.map { #","file":"\#($0)""# } ?? ""
        let json = #"{"source":"\#(source)","song_id":"\#(id)","name":"\#(id)","artists":["Artist"],"url":""\#(fileJSON)}"#
        return try JSONDecoder().decode(CatalogSong.self, from: Data(json.utf8))
    }
}
