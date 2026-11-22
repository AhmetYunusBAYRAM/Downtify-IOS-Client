import XCTest
@testable import Downtify

// MARK: - SimilarFeed (pure)

final class SimilarFeedTests: XCTestCase {
    func testInitialRowsAreDeduplicatedAndSeedIsUsed() throws {
        let feed = SimilarFeed(initial: try results("Air", "Alone", [song("a1", "Alone", "Air"), song("a2", "alone", "AIR"), song("a3", "Other", "Air")]))
        XCTAssertEqual(feed.songs.map(\.title), ["Alone", "Other"])
        XCTAssertTrue(feed.hasMore)
        XCTAssertEqual(feed.nextSeed(), .init(artist: "Air", track: "Other"))
    }

    func testNextSeedSkipsUsedSeedsAndFallsBackThenGivesUp() throws {
        var feed = SimilarFeed(initial: try results("Q", "Q", (1...4).map { song("s\($0)", "T\($0)", "A\($0)") }))
        let first = try XCTUnwrap(feed.nextSeed())
        XCTAssertEqual(first.track, "T4")
        feed.beginMore()
        feed.finishMore(seed: first, tracks: [])
        XCTAssertFalse(feed.hasMore)

        var second = SimilarFeed(initial: try results("Q", "Q", (1...4).map { song("s\($0)", "T\($0)", "A\($0)") }))
        let used = try XCTUnwrap(second.nextSeed())
        second.beginMore()
        second.finishMore(seed: used, tracks: [song("n1", "New", "B")])
        XCTAssertEqual(second.nextSeed()?.track, "New", "the newest unused row seeds next")
        let seed = try XCTUnwrap(second.nextSeed())
        second.beginMore()
        second.finishMore(seed: seed, tracks: [])
        XCTAssertFalse(second.hasMore)
    }

    func testBlankArtistCannotSeed() throws {
        let feed = SimilarFeed(initial: try results("Q", "Q", [song("b2", "Title", "")]))
        XCTAssertNil(feed.nextSeed())
    }

    func testFinishAppendsOnlyNewSongsAndRunsDryWhenNothingNew() throws {
        var feed = SimilarFeed(initial: try results("Q", "Q", [song("1", "One", "A")]))
        let seed = try XCTUnwrap(feed.nextSeed())
        feed.beginMore()
        XCTAssertTrue(feed.loadingMore)
        XCTAssertEqual(feed.finishMore(seed: seed, tracks: [song("1", "One", "A"), song("2", "Two", "B")]), 1)
        XCTAssertEqual(feed.songs.map(\.title), ["One", "Two"])
        XCTAssertTrue(feed.hasMore)
        let next = try XCTUnwrap(feed.nextSeed())
        feed.beginMore()
        XCTAssertEqual(feed.finishMore(seed: next, tracks: [song("2", "Two", "B")]), 0)
        XCTAssertFalse(feed.hasMore)
        XCTAssertFalse(feed.canLoadMore)
    }

    func testFailureKeepsRowsBlocksAutoLoadAndAllowsRetryWithSameSeed() throws {
        var feed = SimilarFeed(initial: try results("Q", "Q", [song("1", "One", "A")]))
        let seed = try XCTUnwrap(feed.nextSeed())
        feed.beginMore()
        feed.failMore(message: "boom")
        XCTAssertEqual(feed.songs.count, 1)
        XCTAssertEqual(feed.failureMessage, "boom")
        XCTAssertFalse(feed.canLoadMore)
        XCTAssertFalse(feed.shouldLoadMore(whenShowing: feed.songs[0]))
        feed.clearFailure()
        XCTAssertEqual(feed.nextSeed(), seed, "a failed seed stays unused")
        XCTAssertTrue(feed.canLoadMore)
    }

    func testTriggerOnlyNearTheEnd() throws {
        let feed = SimilarFeed(initial: try results("Q", "Q", (1...20).map { song("s\($0)", "T\($0)", "A\($0)") }))
        XCTAssertFalse(feed.shouldLoadMore(whenShowing: feed.songs[0]))
        XCTAssertFalse(feed.shouldLoadMore(whenShowing: feed.songs[14]))
        XCTAssertTrue(feed.shouldLoadMore(whenShowing: feed.songs[15]))
        XCTAssertTrue(feed.shouldLoadMore(whenShowing: feed.songs[19]))
    }

    func testRowCapStopsTheList() throws {
        var feed = SimilarFeed(initial: try results("Q", "Q", (1...190).map { song("s\($0)", "T\($0)", "A\($0)") }))
        let seed = try XCTUnwrap(feed.nextSeed())
        feed.beginMore()
        feed.finishMore(seed: seed, tracks: (1000...1030).map { song("n\($0)", "N\($0)", "B\($0)") })
        XCTAssertEqual(feed.songs.count, SimilarFeed.rowCap)
        XCTAssertFalse(feed.hasMore)
    }

    func testEmptyInitialResultHasNothingMore() throws {
        XCTAssertFalse(SimilarFeed(initial: try results("Q", "Q", [])).hasMore)
    }
}

// MARK: - CatalogPresentationModel integration

@MainActor
final class SimilarContinuationModelTests: XCTestCase {
    private func makeModel(_ api: ScriptedSimilarAPI) async -> (CatalogPresentationModel, AsyncStream<DeviceSession?>.Continuation) {
        let (updates, continuation) = AsyncStream<DeviceSession?>.makeStream()
        let model = CatalogPresentationModel(api: api, sessionUpdates: { updates })
        model.start()
        continuation.yield(session)
        await waitUntil { model.policyState == .ready }
        return (model, continuation)
    }

    private let session = DeviceSession(baseAddress: "https://example.test", serverID: "server", serverName: "Server", deviceID: "device",
                                        username: "listener", role: nil, token: "secret", allowsInsecureHTTP: false)

    func testExtendsOnceNearEndAndNeverRepeatsASeed() async throws {
        let api = ScriptedSimilarAPI { artist, track in
            switch track {
            case "T20": return (21...40).map { song("s\($0)", "T\($0)", "A\($0)") }
            case "T40": return (41...45).map { song("s\($0)", "T\($0)", "A\($0)") }
            default: return (1...20).map { song("s\($0)", "T\($0)", "A\($0)") }
            }
        }
        let (model, _) = await makeModel(api)
        model.loadSimilar(artist: "Seed", track: "Song")
        await waitUntil { model.similarFeed != nil }
        let initial = try XCTUnwrap(model.similarFeed).songs
        XCTAssertEqual(initial.count, 20)

        model.similarRowAppeared(initial[0])
        XCTAssertEqual(api.calls.count, 1, "rows far from the end do not trigger")

        model.similarRowAppeared(initial[19])
        model.similarRowAppeared(initial[18])   // concurrent trigger while loading
        await waitUntil { model.similarFeed?.songs.count == 40 }
        XCTAssertEqual(api.calls.map(\.track), ["Song", "T20"])

        let all = try XCTUnwrap(model.similarFeed).songs
        model.similarRowAppeared(all[39])
        await waitUntil { model.similarFeed?.songs.count == 45 }
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(api.calls.map(\.track), ["Song", "T20", "T40"])

        // The last page added fewer than a full page but something new, so another seed is allowed, then dry-up.
        let end = try XCTUnwrap(model.similarFeed).songs
        model.similarRowAppeared(end[44])
        await waitUntil { model.similarFeed?.hasMore == false }
        XCTAssertEqual(model.similarFeed?.songs.count, 45)
        let callCount = api.calls.count
        model.similarRowAppeared(end[44])
        XCTAssertEqual(api.calls.count, callCount, "no more requests once the list ran dry")
    }

    func testFailedExtensionKeepsRowsAndRetryRecovers() async throws {
        let failOnce = Once()
        let api = ScriptedSimilarAPI { _, track in
            if track == "T20", failOnce.take() { throw APIError.httpStatus(500, retryAfter: nil) }
            return track == "T20" ? (21...25).map { song("s\($0)", "T\($0)", "A\($0)") } : (1...20).map { song("s\($0)", "T\($0)", "A\($0)") }
        }
        let (model, _) = await makeModel(api)
        model.loadSimilar(artist: "Seed", track: "Song")
        await waitUntil { model.similarFeed != nil }
        let last = try XCTUnwrap(model.similarFeed?.songs.last)
        model.similarRowAppeared(last)
        await waitUntil { model.similarFeed?.failureMessage != nil }
        XCTAssertEqual(model.similarFeed?.songs.count, 20)
        let attempts = api.calls.count
        model.similarRowAppeared(last)
        XCTAssertEqual(api.calls.count, attempts, "no automatic retry while the error is showing")

        model.retrySimilarMore()
        await waitUntil { model.similarFeed?.songs.count == 25 }
        XCTAssertNil(model.similarFeed?.failureMessage)
        XCTAssertEqual(api.calls.map(\.track), ["Song", "T20", "T20"])
    }

    func testNewSearchDiscardsLateExtensionResponse() async throws {
        let api = ScriptedSimilarAPI { _, track in
            switch track {
            case "T20":
                try await Task.sleep(for: .milliseconds(300))
                return (100...110).map { song("late\($0)", "Late\($0)", "L") }
            case "Fresh": return (200...204).map { song("f\($0)", "F\($0)", "FA") }
            default: return (1...20).map { song("s\($0)", "T\($0)", "A\($0)") }
            }
        }
        let (model, _) = await makeModel(api)
        model.loadSimilar(artist: "Seed", track: "Song")
        await waitUntil { model.similarFeed != nil }
        model.similarRowAppeared(try XCTUnwrap(model.similarFeed?.songs.last))
        await waitUntil { api.calls.count == 2 }

        model.loadSimilar(artist: "New", track: "Fresh")
        await waitUntil { model.similarFeed?.songs.first?.title == "F200" }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(model.similarFeed?.songs.map(\.title), ["F200", "F201", "F202", "F203", "F204"])
        XCTAssertEqual(model.similarFeed?.loadingMore, false)
    }

    func testSessionChangeClearsFeed() async throws {
        let api = ScriptedSimilarAPI { _, _ in (1...3).map { song("s\($0)", "T\($0)", "A") } }
        let (model, continuation) = await makeModel(api)
        model.loadSimilar(artist: "Seed", track: "Song")
        await waitUntil { model.similarFeed != nil }
        continuation.yield(nil)
        await waitUntil { model.session == nil }
        model.loadSimilar(artist: "Seed", track: "Song")
        XCTAssertNil(model.similarFeed)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }
}

// MARK: - Helpers

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

private func song(_ id: String, _ title: String, _ artist: String) -> CatalogSong {
    let json = #"{"source":"youtube","song_id":"\#(id)","name":"\#(title)","artist":"\#(artist)","artists":["\#(artist)"],"album_name":"Album","duration":200,"url":"https://youtube.test/\#(id)"}"#
    return try! JSONDecoder().decode(CatalogSong.self, from: Data(json.utf8))
}

private func results(_ artist: String, _ track: String, _ songs: [CatalogSong]) throws -> CatalogSimilarResults {
    CatalogSimilarResults(artist: artist, track: track, source: "youtube", tracks: songs)
}

/// Serves `similar` from a script and records every request; all other routes are unavailable.
private final class ScriptedSimilarAPI: CatalogServing, @unchecked Sendable {
    struct Call: Equatable { let artist: String; let track: String }
    typealias Script = @Sendable (String, String) async throws -> [CatalogSong]
    private let script: Script
    private let lock = NSLock()
    private var recorded: [Call] = []

    init(_ script: @escaping Script) { self.script = script }

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return recorded }

    func similar(artist: String, track: String, limit: Int, session: DeviceSession) async throws -> CatalogSimilarResults {
        lock.lock(); recorded.append(Call(artist: artist, track: track)); lock.unlock()
        return CatalogSimilarResults(artist: artist, track: track, source: "youtube", tracks: try await script(artist, track))
    }

    func serverInfo(session: DeviceSession) async throws -> MobileAPIV1.ServerInfoDTO {
        let json = #"{"product":"Downtify","api_version":1,"server_id":"\#(session.serverID)","capabilities":{"discover":true}}"#
        return try JSONDecoder().decode(MobileAPIV1.ServerInfoDTO.self, from: Data(json.utf8))
    }

    private var unavailable: Error { CatalogAPIError.featureUnavailable }
    func searchSongs(query: String, session: DeviceSession) async throws -> [CatalogSong] { throw unavailable }
    func searchAlbums(query: String, limit: Int, session: DeviceSession) async throws -> [CatalogAlbum] { throw unavailable }
    func searchArtists(query: String, session: DeviceSession) async throws -> [CatalogArtist] { throw unavailable }
    func search(query: String, albumLimit: Int, session: DeviceSession) async throws -> CatalogSearchResults { throw unavailable }
    func resolve(url: String, session: DeviceSession) async throws -> URLResolution { throw unavailable }
    func preview(artist: String, title: String, duration: Double?, session: DeviceSession) async throws -> URL? { throw unavailable }
    func finderSearch(query: String, limit: Int, session: DeviceSession) async throws -> CatalogSearchResults { throw unavailable }
    func finderArtist(id: String, language: String, session: DeviceSession) async throws -> CatalogFinderArtist { throw unavailable }
    func finderArtistSongs(id: String, name: String, session: DeviceSession) async throws -> CatalogSearchResults { throw unavailable }
    func finderArtistAlbums(id: String, session: DeviceSession) async throws -> [CatalogAlbum] { throw unavailable }
    func finderAlbumTrackCounts(ids: [String], session: DeviceSession) async throws -> [String: Int] { throw unavailable }
    func finderAlbum(id: String, session: DeviceSession) async throws -> CatalogFinderAlbum { throw unavailable }
    func charts(limit: Int, session: DeviceSession) async throws -> CatalogCharts { throw unavailable }
    func discover(library: [CatalogLibraryArtist], session: DeviceSession) async throws -> CatalogDiscoverResults { throw unavailable }
    func deezerCollections(library: [CatalogLibraryArtist], albums: [CatalogLibraryAlbum], playlistNames: [String], session: DeviceSession) async throws -> CatalogCollectionsResults { throw unavailable }
    func spotifyCollections(library: [CatalogLibraryArtist], albums: [CatalogLibraryAlbum], playlistIDs: [String], shown: [String], session: DeviceSession) async throws -> CatalogCollectionsResults { throw unavailable }
    func blockedArtists(session: DeviceSession) async throws -> [CatalogBlockedArtist] { throw unavailable }
    func blockArtist(name: String, session: DeviceSession) async throws -> CatalogBlockedArtist { throw unavailable }
    func unblockArtist(name: String, session: DeviceSession) async throws { throw unavailable }
}
