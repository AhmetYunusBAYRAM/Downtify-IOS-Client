import XCTest
@testable import Downtify

final class LibraryMembershipTests: XCTestCase {
    func testLibrarySongWithUniqueFileMatchReturnsItsTrack() throws {
        let matching = makeLibraryTrack(id: "track-1", file: "Music/Roads.flac")
        let membership = LibraryMembership(tracks: [matching, makeLibraryTrack(id: "track-2", file: "Music/Other.flac")])
        let song = try decodeSong(#"{"source":"library","song_id":"lib-1","name":"Roads","file":"Music/Roads.flac"}"#)

        XCTAssertEqual(membership.track(for: song), matching)
    }

    func testLibrarySongWhoseFileMatchesTwoTracksReturnsNil() throws {
        let membership = LibraryMembership(tracks: [
            makeLibraryTrack(id: "track-1", file: "Music/Roads.flac"),
            makeLibraryTrack(id: "track-2", file: "Music/Roads.flac")
        ])
        let song = try decodeSong(#"{"source":"library","song_id":"lib-1","name":"Roads","file":"Music/Roads.flac"}"#)

        XCTAssertNil(membership.track(for: song))
    }

    func testNonLibrarySongWithMatchingFileReturnsNil() throws {
        let membership = LibraryMembership(tracks: [makeLibraryTrack(id: "track-1", file: "Music/Roads.flac")])
        let song = try decodeSong(#"{"source":"youtube","song_id":"yt-1","name":"Roads","file":"Music/Roads.flac"}"#)

        XCTAssertNil(membership.track(for: song))
    }

    func testServerFilenameLookupRequiresExactFileMatch() {
        let matching = makeLibraryTrack(id: "track-1", file: "Music/Roads.flac", title: "Roads")
        let membership = LibraryMembership(tracks: [matching])

        XCTAssertEqual(membership.track(forServerFilename: "Music/Roads.flac"), matching)
    }

    func testServerFilenameLookupNeverMatchesByTitle() {
        let membership = LibraryMembership(tracks: [
            makeLibraryTrack(id: "track-1", file: "Music/Other/Roads.flac", title: "Roads")
        ])

        XCTAssertNil(membership.track(forServerFilename: "Music/Roads.flac"))
    }

    func testServerFilenameLookupWithDuplicateFilesReturnsNil() {
        let membership = LibraryMembership(tracks: [
            makeLibraryTrack(id: "track-1", file: "Music/Roads.flac"),
            makeLibraryTrack(id: "track-2", file: "Music/Roads.flac")
        ])

        XCTAssertNil(membership.track(forServerFilename: "Music/Roads.flac"))
    }

    func testServerFilenameLookupInEmptyLibraryReturnsNil() {
        XCTAssertNil(LibraryMembership(tracks: []).track(forServerFilename: "Music/Roads.flac"))
    }

    func testSongKeyIgnoresRemasterAndFeatureTags() {
        XCTAssertEqual(LibraryMembership.songKey(artist: "Radiohead", title: "Karma Police"),
                       LibraryMembership.songKey(artist: "Radiohead", title: "Karma Police - Remastered 2017"))
        XCTAssertEqual(LibraryMembership.songKey(artist: "A", title: "Song (feat. X)"),
                       LibraryMembership.songKey(artist: "A", title: "Song"))
        XCTAssertEqual(LibraryMembership.songKey(artist: "A", title: "Song (Remastered 2011)"),
                       LibraryMembership.songKey(artist: "A", title: "Song"))
    }

    func testSongKeyFoldsAccentsAndCase() {
        XCTAssertEqual(LibraryMembership.songKey(artist: "Beyoncé", title: "Halo"),
                       LibraryMembership.songKey(artist: "BEYONCE", title: "HALO"))
    }

    func testSongKeyUsesOnlyPrimaryArtist() {
        XCTAssertEqual(LibraryMembership.songKey(artist: "A & B", title: "Song"),
                       LibraryMembership.songKey(artist: "A", title: "Song"))
        XCTAssertEqual(LibraryMembership.songKey(artist: "A, B", title: "Song"),
                       LibraryMembership.songKey(artist: "A", title: "Song"))
    }

    func testSongKeyKeepsLiveTagDistinct() {
        XCTAssertNotEqual(LibraryMembership.songKey(artist: "A", title: "Song (Live)"),
                          LibraryMembership.songKey(artist: "A", title: "Song"))
    }

    func testContainsSongMatchesCatalogRowByKeyAcrossAlbums() throws {
        let owned = makeLibraryTrack(id: "track-1", file: "Music/Roads.flac", title: "Roads")
        let membership = LibraryMembership(tracks: [owned])
        let song = try decodeSong(#"{"source":"youtube","song_id":"yt-1","name":"Roads (Remastered 2009)","artist":"Portishead"}"#)

        XCTAssertTrue(membership.containsSong(song))
        XCTAssertEqual(membership.track(for: song), owned)
    }

    func testContainsSongIsFalseForEmptyTitle() throws {
        let membership = LibraryMembership(tracks: [makeLibraryTrack(id: "track-1", file: "Music/Roads.flac", title: "Roads")])
        let song = try decodeSong(#"{"source":"youtube","song_id":"yt-1","name":"   ","artist":"Portishead"}"#)

        XCTAssertFalse(membership.containsSong(song))
        XCTAssertTrue(membership.matchingTracks(for: song).isEmpty)
    }

    func testContainsSongIsTrueForLibraryRowMatchedByFile() throws {
        let membership = LibraryMembership(tracks: [makeLibraryTrack(id: "track-1", file: "Music/Roads.flac")])
        let song = try decodeSong(#"{"source":"library","song_id":"lib-1","name":"Roads","file":"Music/Roads.flac"}"#)

        XCTAssertTrue(membership.containsSong(song))
    }

    func testNonLibrarySongWithSingleKeyMatchReturnsItsTrack() throws {
        let owned = makeLibraryTrack(id: "track-1", file: "Music/Roads.flac", title: "Roads")
        let membership = LibraryMembership(tracks: [owned])
        let song = try decodeSong(#"{"source":"deezer","song_id":"dz-1","name":"Roads","artist":"Portishead"}"#)

        XCTAssertEqual(membership.track(for: song), owned)
    }

    func testNonLibrarySongWithTwoKeyMatchesReturnsNil() throws {
        let membership = LibraryMembership(tracks: [
            makeLibraryTrack(id: "track-1", file: "Music/Roads.flac", title: "Roads"),
            makeLibraryTrack(id: "track-2", file: "Music/Roads Live.flac", title: "Roads (Remastered)")
        ])
        let song = try decodeSong(#"{"source":"deezer","song_id":"dz-1","name":"Roads","artist":"Portishead"}"#)

        XCTAssertEqual(membership.matchingTracks(for: song).count, 2)
        XCTAssertNil(membership.track(for: song))
    }

    private func decodeSong(_ json: String) throws -> CatalogSong {
        try JSONDecoder().decode(CatalogSong.self, from: Data(json.utf8))
    }

    private func makeLibraryTrack(id: String, file: String, title: String = "Roads") -> LibraryTrack {
        LibraryTrack(id: id, file: file, title: title, artist: "Portishead", artists: ["Portishead"], album: "Dummy",
                     albumArtist: "Portishead", albumID: "album", artistID: "artist", trackNumber: 1, year: "1994",
                     duration: 305, codec: "flac", bitrate: 900_000, sampleRate: 44_100, channels: 2,
                     size: 1_024, added: 1, hasCover: false, isExplicit: false, playlists: [])
    }
}
