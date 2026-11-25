import Foundation
import XCTest
@testable import Downtify

final class PlaybackQueueTests: XCTestCase {
    @MainActor
    func testRemoveAllSavedQueuesDropsOnlyQueueSnapshots() throws {
        let suite = "PlaybackQueueTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([1]), forKey: "playback.queue.A")
        defaults.set(Data([2]), forKey: "playback.queue.B")
        defaults.set(Data([3]), forKey: "playback.qualities")
        defaults.set(Data([4]), forKey: "playback.buffering")
        defaults.set(Data([5]), forKey: "playback.normalization")
        defaults.set("install-1", forKey: "playback.installID")

        PlaybackStateStore(defaults: defaults).removeAllSavedQueues()

        XCTAssertNil(defaults.object(forKey: "playback.queue.A"))
        XCTAssertNil(defaults.object(forKey: "playback.queue.B"))
        XCTAssertEqual(defaults.data(forKey: "playback.qualities"), Data([3]))
        XCTAssertEqual(defaults.data(forKey: "playback.buffering"), Data([4]))
        XCTAssertEqual(defaults.data(forKey: "playback.normalization"), Data([5]))
        XCTAssertEqual(defaults.string(forKey: "playback.installID"), "install-1")
    }

    func testLegacyTrackIDQueueEntryDecodesAndRetainsState() throws {
        let occurrence = UUID(uuidString: "A8C8CA9C-2B3D-4D03-A1F4-35367B4990CD")!
        let legacy = #"{"entries":[{"id":"\#(occurrence.uuidString)","trackID":"library-id"}],"shuffledIDs":["\#(occurrence.uuidString)"],"currentID":"\#(occurrence.uuidString)","position":13.5,"repeatMode":"all","listen":null}"#
        let saved = try JSONDecoder().decode(SavedPlaybackQueue.self, from: Data(legacy.utf8))
        XCTAssertEqual(saved.entries.first?.trackID, "library-id")
        XCTAssertNil(saved.entries.first?.catalogSong)

        var queue = PlaybackQueue()
        XCTAssertEqual(queue.restore(saved, tracks: [libraryTrack(id: "library-id", file: "music/song.mp3")]), 13.5)
        XCTAssertEqual(queue.currentID, occurrence)
        XCTAssertEqual(queue.repeatMode, .all)
        XCTAssertEqual(queue.order.first?.track.id, "library-id")
    }

    func testMixedQueuePersistsCatalogPayloadAndRestoresOccurrencesLosslessly() throws {
        let library = libraryTrack(id: "same-id", file: "music/library.mp3")
        let catalog = try catalogSong(#"{"source":"youtube","song_id":"same-id","youtube_id":"video-1","name":"Catalog title","artist":"Catalog artist","artists":["Catalog artist"],"album_name":"Remote album","duration":91.5,"url":"https://catalog.test/watch","extra":{"provider_flag":true}}"#)
        var queue = PlaybackQueue()
        queue.replace([.library(library), .catalog(catalog), .catalog(catalog)], startingAt: 1)
        let selectedID = try XCTUnwrap(queue.currentID)
        queue.setShuffle(true)
        queue.repeatMode = .one

        let encoded = try JSONEncoder().encode(queue.saved(position: 21))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
        XCTAssertEqual(entries[0]["trackID"] as? String, "same-id")
        XCTAssertNil(entries[0]["catalogSong"])
        let storedCatalog = try XCTUnwrap(entries[1]["catalogSong"] as? [String: Any])
        let storedCatalogData = try JSONSerialization.data(withJSONObject: storedCatalog)
        XCTAssertEqual(try JSONDecoder().decode(CatalogSong.self, from: storedCatalogData), catalog)
        XCTAssertNil(entries[1]["trackID"])

        let saved = try JSONDecoder().decode(SavedPlaybackQueue.self, from: encoded)
        var restored = PlaybackQueue()
        XCTAssertEqual(restored.restore(saved, tracks: [library]), 21)
        XCTAssertEqual(restored.currentID, selectedID)
        XCTAssertEqual(restored.repeatMode, .one)
        XCTAssertEqual(restored.entries.map(\.id), queue.entries.map(\.id))
        XCTAssertEqual(restored.order.map(\.id), queue.order.map(\.id))
        XCTAssertEqual(restored.entries[1].item, .catalog(catalog))
        XCTAssertEqual(restored.entries[2].item, .catalog(catalog))
        XCTAssertNotEqual(restored.entries[1].id, restored.entries[2].id)
    }

    func testLibraryCatalogRowsResolveOnlyByUniqueExactFile() throws {
        let row = try catalogSong(#"{"source":"library","name":"Song","file":"Music/song.flac"}"#)
        let matching = libraryTrack(id: "scoped-id", file: "Music/song.flac")
        XCTAssertEqual(PlaybackItem.resolving(row, in: [matching]), .library(matching))
        XCTAssertEqual(PlaybackItem.resolving(row, in: [matching, libraryTrack(id: "other", file: "Music/song.flac")]), .catalog(row))
        XCTAssertEqual(PlaybackItem.resolving(row, in: [libraryTrack(id: "other", file: "Music/elsewhere.flac")]), .catalog(row))

        var queue = PlaybackQueue()
        queue.replace([.catalog(row)], startingAt: 0)
        let saved = queue.saved(position: 7)
        var restored = PlaybackQueue()
        XCTAssertEqual(restored.restore(saved, tracks: [matching]), 7)
        XCTAssertEqual(restored.current?.item, .library(matching))

        var unavailable = PlaybackQueue()
        XCTAssertEqual(unavailable.restore(saved, tracks: []), 0)
        XCTAssertTrue(unavailable.entries.isEmpty)
    }

    func testLibraryOnlyPolicyConvertsLocalRowsPrunesOthersAndKeepsQueueState() throws {
        let first = libraryTrack(id: "first", file: "Music/first.flac")
        let matched = libraryTrack(id: "matched", file: "Music/local.flac")
        let last = libraryTrack(id: "last", file: "Music/last.flac")
        let local = try catalogSong(#"{"source":"library","name":"Local","file":"Music/local.flac"}"#)
        let staleLocal = try catalogSong(#"{"source":"library","name":"Stale","file":"Music/stale.flac"}"#)
        let remote = try catalogSong(#"{"source":"youtube","name":"Remote","youtube_id":"remote-1"}"#)

        var queue = PlaybackQueue()
        queue.replace([.library(first), .catalog(remote), .catalog(local), .catalog(staleLocal), .library(last)], startingAt: 1)
        queue.setShuffle(true)
        queue.repeatMode = .all
        let oldOrderIDs = queue.order.map(\.id)
        let oldCurrentID = try XCTUnwrap(queue.currentID)
        let localID = try XCTUnwrap(queue.entries.first(where: { $0.item.catalogSong == local })?.id)
        let retainedIDs: Set<UUID> = [queue.entries[0].id, localID, queue.entries[4].id]
        let expectedCurrent = try XCTUnwrap(oldOrderIDs.dropFirst().first(where: retainedIDs.contains))

        queue.applyLibraryOnlyPolicy(true, tracks: [matched, first, last])

        XCTAssertEqual(queue.repeatMode, .all)
        XCTAssertNotNil(queue.shuffledIDs)
        XCTAssertEqual(queue.order.map(\.id), oldOrderIDs.filter(retainedIDs.contains))
        XCTAssertEqual(queue.currentID, expectedCurrent)
        XCTAssertNotEqual(queue.currentID, oldCurrentID)
        XCTAssertEqual(queue.entries.map { $0.item.libraryTrack?.id }, ["first", "matched", "last"])
        XCTAssertTrue(queue.entries.allSatisfy { $0.item.catalogSong == nil })
    }

    func testPreloadWindowUsesDistinctMediaAndStopsAfterFiveUpcomingSongs() throws {
        var queue = PlaybackQueue()
        XCTAssertTrue(queue.preloadItems.isEmpty)
        let first = libraryTrack(id: "same-id", file: "original.mp3")
        let updated = libraryTrack(id: "same-id", file: "updated.mp3")
        let catalog = try catalogSong(#"{"source":"youtube","song_id":"same-id","name":"Catalog"}"#)
        queue.replace([.library(first), .library(updated), .catalog(catalog)], startingAt: 0)
        XCTAssertEqual(queue.preloadItems, [.library(first), .catalog(catalog)])

        let extra = (1...6).map { libraryTrack(id: "track-\($0)", file: "song.mp3") }
        queue.append(extra)
        XCTAssertEqual(queue.preloadItems, [.library(first), .catalog(catalog)] + extra.prefix(4).map(PlaybackItem.library))
    }

    func testPreloadWindowUsesShuffledOrderAndRepeatMode() {
        let tracks = (1...4).map { libraryTrack(id: "track-\($0)", file: "song.mp3") }
        var queue = PlaybackQueue()
        queue.replace(tracks, startingAt: 0)
        queue.setShuffle(true)
        let order = queue.order
        queue.select(order[2].id)
        XCTAssertEqual(queue.preloadItems, Array(order[2...]).map(\.item))
        queue.repeatMode = .all
        XCTAssertEqual(queue.preloadItems, (Array(order[2...]) + order.prefix(2)).map(\.item))
        queue.repeatMode = .one
        XCTAssertEqual(queue.preloadItems, [order[2].item])
    }

    private func catalogSong(_ json: String) throws -> CatalogSong {
        try JSONDecoder().decode(CatalogSong.self, from: Data(json.utf8))
    }

    private func ids(_ queue: PlaybackQueue) -> [String] { queue.order.map { $0.item.libraryTrack?.id ?? "?" } }

    private func makeQueue(_ count: Int, current: Int = 0) -> PlaybackQueue {
        var queue = PlaybackQueue()
        queue.replace((1...count).map { libraryTrack(id: "t\($0)", file: "s.mp3") }, startingAt: current)
        return queue
    }

    func testInsertNextPlacesItemsRightAfterCurrentAndKeepsCurrent() {
        var queue = makeQueue(3, current: 1)
        let currentID = queue.currentID
        queue.insertNext([libraryTrack(id: "n1", file: "s.mp3")])
        XCTAssertEqual(ids(queue), ["t1", "t2", "n1", "t3"])
        XCTAssertEqual(queue.currentID, currentID)
        queue.insertNext([libraryTrack(id: "n2", file: "s.mp3")])
        XCTAssertEqual(ids(queue), ["t1", "t2", "n2", "n1", "t3"])
    }

    func testInsertNextIntoEmptyQueueBecomesCurrent() {
        var queue = PlaybackQueue()
        queue.insertNext([libraryTrack(id: "only", file: "s.mp3")])
        XCTAssertEqual(ids(queue), ["only"])
        XCTAssertEqual(queue.current?.item.libraryTrack?.id, "only")
    }

    func testInsertNextAllowsDuplicateTracksWithDistinctOccurrences() {
        var queue = makeQueue(2)
        queue.insertNext([libraryTrack(id: "t2", file: "s.mp3")])
        XCTAssertEqual(ids(queue), ["t1", "t2", "t2"])
        XCTAssertEqual(Set(queue.order.map(\.id)).count, 3)
    }

    func testInsertNextWhileShuffledPlaysNextAndSurvivesUnshuffle() {
        var queue = makeQueue(5, current: 2)
        queue.setShuffle(true)
        let before = queue.order.map(\.id)
        queue.insertNext([libraryTrack(id: "n1", file: "s.mp3")])
        let after = queue.order
        XCTAssertEqual(after[1].item.libraryTrack?.id, "n1")
        XCTAssertEqual(after.first?.id, before.first)
        XCTAssertEqual(queue.upcomingCount, 5)
        queue.setShuffle(false)
        XCTAssertEqual(queue.entries.count, 6)
    }

    func testInsertNextKeepsRepeatMode() {
        var queue = makeQueue(2)
        queue.repeatMode = .one
        queue.insertNext([libraryTrack(id: "n1", file: "s.mp3")])
        XCTAssertEqual(queue.repeatMode, .one)
        XCTAssertEqual(ids(queue), ["t1", "n1", "t2"])
    }

    func testMoveUpcomingReordersWithoutTouchingCurrent() throws {
        var queue = makeQueue(4, current: 1)
        let currentID = queue.currentID
        let last = try XCTUnwrap(queue.order.last?.id)
        XCTAssertTrue(queue.moveUpcoming(last, toUpcomingOffset: 0))
        XCTAssertEqual(ids(queue), ["t1", "t2", "t4", "t3"])
        XCTAssertEqual(queue.currentID, currentID)
        XCTAssertTrue(queue.moveUpcoming(last, toUpcomingOffset: 99))
        XCTAssertEqual(ids(queue), ["t1", "t2", "t3", "t4"])
        XCTAssertFalse(queue.moveUpcoming(last, toUpcomingOffset: 99), "no-op reports false")
    }

    private func placement(from: Int, dragY: CGFloat, rows: Int = 4) -> QueueDragPlacement {
        QueueDragPlacement(midYs: (0..<rows).map { CGFloat($0) * 60 + 30 },
                           rowHeights: Array(repeating: 60, count: rows), from: from, dragY: dragY)
    }

    func testDragPlacementMovingDownShiftsRowsUp() {
        let drag = placement(from: 0, dragY: 100)
        XCTAssertEqual(drag.target, 1)
        XCTAssertEqual((0..<4).map(drag.offset(for:)), [0, -60, 0, 0])
    }

    func testDragPlacementMovingUpShiftsRowsDown() {
        let drag = placement(from: 3, dragY: 40)
        XCTAssertEqual(drag.target, 1)
        XCTAssertEqual((0..<4).map(drag.offset(for:)), [0, 60, 60, 0])
    }

    func testDragPlacementAtOwnMidpointDoesNotMove() {
        let drag = placement(from: 2, dragY: 150)
        XCTAssertEqual(drag.target, 2)
        XCTAssertEqual((0..<4).map(drag.offset(for:)), [0, 0, 0, 0])
    }

    func testDragPlacementClampsBeyondEnds() {
        XCTAssertEqual(placement(from: 2, dragY: -500).target, 0)
        XCTAssertEqual(placement(from: 1, dragY: 5000).target, 3)
        XCTAssertEqual(placement(from: 0, dragY: 90).target, 0, "a finger exactly on a midpoint stays above it")
    }

    func testDragPlacementTreatsUnrenderedRowsAsOutsideTheScreen() {
        let drag = QueueDragPlacement(midYs: [-.infinity, 90, 150, .infinity], rowHeights: [60, 60, 60, 60],
                                      from: 1, dragY: 5000)
        XCTAssertEqual(drag.target, 2, "rows the stack has not rendered are never passed")
    }

    func testDragPlacementIgnoresInvalidInput() {
        let empty = placement(from: 0, dragY: 100, rows: 0)
        XCTAssertEqual(empty.target, 0)
        XCTAssertEqual(empty.offset(for: 0), 0)
        let outOfRange = placement(from: 7, dragY: 100)
        XCTAssertEqual(outOfRange.target, 7)
        XCTAssertEqual((0..<4).map(outOfRange.offset(for:)), [0, 0, 0, 0])
        let mismatched = QueueDragPlacement(midYs: [30, 90], rowHeights: [60], from: 0, dragY: 100)
        XCTAssertEqual(mismatched.target, 0)
    }

    func testMoveUpcomingRejectsCurrentAndPreviousEntries() throws {
        var queue = makeQueue(4, current: 2)
        let currentID = try XCTUnwrap(queue.currentID)
        let previous = queue.order[0].id
        XCTAssertFalse(queue.moveUpcoming(currentID, toUpcomingOffset: 0))
        XCTAssertFalse(queue.moveUpcoming(previous, toUpcomingOffset: 0))
        XCTAssertFalse(queue.moveUpcoming(UUID(), toUpcomingOffset: 0))
        XCTAssertEqual(ids(queue), ["t1", "t2", "t3", "t4"])
    }

    func testMoveUpcomingHandlesDuplicatesAndShuffle() throws {
        var queue = PlaybackQueue()
        let dup = libraryTrack(id: "dup", file: "s.mp3")
        queue.replace([libraryTrack(id: "a", file: "s.mp3"), dup, libraryTrack(id: "b", file: "s.mp3"), dup], startingAt: 0)
        let secondDup = queue.order[3].id
        XCTAssertTrue(queue.moveUpcoming(secondDup, toUpcomingOffset: 0))
        XCTAssertEqual(queue.order[1].id, secondDup)
        queue.setShuffle(true)
        let currentID = queue.currentID
        let tail = try XCTUnwrap(queue.order.last?.id)
        XCTAssertTrue(queue.moveUpcoming(tail, toUpcomingOffset: 0))
        XCTAssertEqual(queue.order[1].id, tail)
        XCTAssertEqual(queue.currentID, currentID)
    }

    private func libraryTrack(id: String, file: String) -> LibraryTrack {
        LibraryTrack(id: id, file: file, title: "Library title", artist: "Library artist", artists: ["Library artist"],
                     album: "Library album", albumArtist: "Library artist", albumID: "album", artistID: "artist",
                     trackNumber: 1, year: "2026", duration: 100, codec: "flac", bitrate: 900_000,
                     sampleRate: 44_100, channels: 2, size: 100, added: 0, hasCover: false,
                     isExplicit: false, playlists: [])
    }
}
