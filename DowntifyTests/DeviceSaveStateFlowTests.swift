import Foundation
import XCTest
@testable import Downtify

@MainActor
final class DeviceSaveStateFlowTests: XCTestCase {
    func testAddToDeviceStateMovesFromNotSavedToPendingThenSaved() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let libraryTrack = makeTrack()
        let membership = LibraryMembership(tracks: [libraryTrack])
        let track = try XCTUnwrap(membership.track(forServerFilename: libraryTrack.file))

        let downloads = OfflineDownloads(directory: directory, api: HangingPreparation())
        downloads.setSession(session())
        XCTAssertNil(downloads.currentDownloads.first)
        XCTAssertEqual(DeviceSaveState(track: track, record: nil), .notSaved)

        let id = try downloads.enqueue(track)
        let queued = try XCTUnwrap(downloads.currentDownloads.first { $0.id == id })
        XCTAssertEqual(DeviceSaveState(track: track, record: queued), .pending)

        // Same completion path as testRecoverCompletedFileAndPlayWithoutServerThenDelete: a record whose
        // verified file is already on disk is recovered as ready on reattach.
        let completedDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: completedDirectory) }
        let transfer = record(state: .transferring, bytes: 5)
        try seed([transfer], in: completedDirectory)
        let file = completedDirectory.appending(path: "\(transfer.id.uuidString).mp3")
        try Data(repeating: 1, count: 8).write(to: file)

        let completed = OfflineDownloads(directory: completedDirectory)
        completed.setSession(session())
        completed.reattach([], previouslyPending: [transfer.id])
        let saved = try XCTUnwrap(completed.currentDownloads.first)
        XCTAssertEqual(saved.state, .ready)
        XCTAssertEqual(DeviceSaveState(track: track, record: saved), .saved)
    }

    func testInFlightTransferReportsFractionFromReceivedBytes() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transfer = record(state: .transferring, bytes: 2)
        try seed([transfer], in: directory)

        let downloads = OfflineDownloads(directory: directory)
        downloads.setSession(session())
        let current = try XCTUnwrap(downloads.currentDownloads.first)
        XCTAssertEqual(DeviceSaveState(track: makeTrack(), record: current), .transferring(fraction: 0.25))
    }

    func testCatalogOnlySongResolvesToNotInLibraryDeviceState() throws {
        let membership = LibraryMembership(tracks: [makeTrack(file: "Music/Roads.flac")])
        let song = try decodeSong(#"{"source":"youtube","song_id":"yt-1","name":"Roads","file":"Music/Roads.flac"}"#)

        let resolved = membership.track(for: song)
        XCTAssertNil(resolved)
        XCTAssertEqual(DeviceSaveState(track: resolved, record: nil), .unavailable(.notInLibrary))
    }

    func testServerFilenameResolvesOnlyAfterMembershipRebuildIncludesFile() {
        var tracks = [makeTrack(id: "other", file: "Other/Song.flac")]
        XCTAssertNil(LibraryMembership(tracks: tracks).track(forServerFilename: "Artist/Album/Song.flac"))

        tracks.append(makeTrack(id: "song", file: "Artist/Album/Song.flac"))
        XCTAssertEqual(LibraryMembership(tracks: tracks).track(forServerFilename: "Artist/Album/Song.flac")?.id, "song")
    }

    func testYouTubeRowMatchingExactlyOneOwnedTrackResolvesToDevice() throws {
        let song = try decodeSong(#"{"source":"youtube","song_id":"yt-2","name":"Song","artists":["Artist"]}"#)
        let one = LibraryMembership(tracks: [makeTrack(id: "a", file: "A/Song.flac")])
        let resolved = one.track(for: song)
        XCTAssertEqual(resolved?.id, "a")
        XCTAssertNotEqual(DeviceSaveState(track: resolved, record: nil), .unavailable(.notInLibrary))

        let two = LibraryMembership(tracks: [makeTrack(id: "a", file: "A/Song.flac"), makeTrack(id: "b", file: "B/Song.flac")])
        XCTAssertTrue(two.containsSong(song))
        XCTAssertEqual(DeviceSaveState(track: two.track(for: song), record: nil), .unavailable(.notInLibrary))
    }

    private func decodeSong(_ json: String) throws -> CatalogSong {
        try JSONDecoder().decode(CatalogSong.self, from: Data(json.utf8))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func seed(_ downloads: [OfflineDownload], in directory: URL) throws {
        try JSONEncoder().encode(downloads).write(to: directory.appending(path: "downloads.json"))
    }

    private var media: OfflineMedia {
        OfflineMedia(length: 8, mime: "audio/mpeg", type: "public.mp3",
                     fileExtension: "mp3", etag: "\"version\"", quality: .original)
    }

    private func session() -> DeviceSession {
        DeviceSession(baseAddress: "https://music.local/proxy", serverID: "server", serverName: "Music",
                      deviceID: "device", username: "user", role: nil, token: "test-token", allowsInsecureHTTP: false)
    }

    private func makeTrack(id: String = "song", file: String = "Artist/Album/Song.flac") -> LibraryTrack {
        LibraryTrack(id: id, file: file, title: "Song", artist: "Artist", artists: ["Artist"], album: "Album",
                     albumArtist: "Artist", albumID: "album", artistID: "artist", trackNumber: 1, year: "2026",
                     duration: 60, codec: "flac", bitrate: 900_000, sampleRate: 44_100, channels: 2,
                     size: 8, added: 1, hasCover: false, isExplicit: false, playlists: [])
    }

    private func record(state: OfflineDownload.State, bytes: Int64) -> OfflineDownload {
        OfflineDownload(id: UUID(), track: makeTrack(), scope: .init(session()), requestedQuality: .original,
                        state: state, media: media, receivedBytes: bytes)
    }
}

private struct HangingPreparation: OfflineDownloadPreparing {
    func prepare(track: LibraryTrack, quality: PlaybackQuality, session: DeviceSession,
                 wifiOnly: Bool) async throws -> OfflineDownloadSource {
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }
}
