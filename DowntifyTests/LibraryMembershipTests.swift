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
