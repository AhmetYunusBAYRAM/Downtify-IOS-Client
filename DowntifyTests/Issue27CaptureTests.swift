import Foundation
import XCTest
@testable import Downtify

/// Issue 27 investigation: documents EXACTLY what the client sends for every "Add to Library" entry point.
/// These tests assert CURRENT behavior; they do not claim it is correct. Fixtures are shaped like the server's
/// catalog search results (YouTube Music, Deezer, Spotify, text-search pseudo rows).
@MainActor
final class Issue27CaptureTests: XCTestCase {

    // MARK: Fixtures

    private static let ytSong = #"{"source":"youtube","song_id":"dQw4w9WgXcQ","youtube_id":"dQw4w9WgXcQ","name":"Roads","artists":["Portishead"],"album_name":"Dummy","duration":305,"url":"https://music.youtube.com/watch?v=dQw4w9WgXcQ"}"#
    private static let deezerSong = #"{"source":"deezer","song_id":"3135556","name":"Roads","artists":["Portishead"],"album_name":"Dummy","duration":305,"url":"https://www.deezer.com/track/3135556","deezer_artist_id":"42","deezer_album_id":"13","preview_url":"https://cdns-preview.test/3135556.mp3"}"#
    private static let spotifySong = #"{"source":"spotify","song_id":"4uLU6hMCjMI75M1A2tKUQC","name":"Roads","artists":["Portishead"],"album_name":"Dummy","duration":305,"url":"https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC","cover_url":"https://i.scdn.test/dummy.jpg"}"#
    private static let textSearchSong = #"{"source":"text_search","song_id":"search-abc","name":"Roads","artists":["Portishead"],"duration":0,"url":"downtify-search:search-abc","download_by_metadata":true}"#

    private static let ytAlbumURL = "https://music.youtube.com/browse/MPREb_AbC123xyz"
    private static let ytAlbumPlaylistURL = "https://music.youtube.com/playlist?list=OLAK5uy_kDummy123"
    private static let deezerAlbumURL = "https://www.deezer.com/album/13"
    private static let spotifyAlbumURL = "https://open.spotify.com/album/6ye6l4WNg1uZ3QhK7wNTT6"

    private var infoBody: String {
        #"{"product":"Downtify","api_version":1,"server_id":"server","capabilities":{"discover":true}}"#
    }

    // MARK: Harness

    private func makeSession() -> DeviceSession {
        DeviceSession(baseAddress: "https://example.test", serverID: "server", serverName: "Server", deviceID: "device",
                      username: "listener", role: nil, token: "secret", allowsInsecureHTTP: false)
    }

    private func song(_ json: String) throws -> CatalogSong {
        try JSONDecoder().decode(CatalogSong.self, from: Data(json.utf8))
    }

    private func makeModel(_ transport: RecordingTransport) async -> (ServerDownloadPresentationModel, AsyncStream<DeviceSession?>.Continuation) {
        let (updates, continuation) = AsyncStream<DeviceSession?>.makeStream()
        let model = ServerDownloadPresentationModel(queue: ServerDownloadQueue(transport: transport)) { updates }
        model.start()
        continuation.yield(makeSession())
        let deadline = ContinuousClock.now + .seconds(2)
        while model.session == nil, ContinuousClock.now < deadline { await Task.yield() }
        return (model, continuation)
    }

    private func routes(extra: [String: String] = [:]) -> [String: String] {
        var base: [String: String] = [
            "/api/server/info": infoBody,
            "/api/download/url": #""job-1""#,
            "/api/download/batch": #"{"job_ids":["j1","j2","j3","j4"],"count":4}"#,
            "/api/download/album": #"{}"#,
            "/api/queue/state": #"{"paused":false,"state":"idle","active":0}"#,
            "/api/queue": "[]"
        ]
        base.merge(extra) { $1 }
        return base
    }

    /// Download-related requests only (drops server/info probes and queue refreshes).
    private func downloads(_ transport: RecordingTransport) -> [Captured] {
        transport.captured.filter { $0.path.contains("/api/download/") }
    }

    private func only(_ transport: RecordingTransport, file: StaticString = #filePath, line: UInt = #line) throws -> Captured {
        let d = downloads(transport)
        XCTAssertEqual(d.count, 1, "expected exactly one download request", file: file, line: line)
        return try XCTUnwrap(d.first, file: file, line: line)
    }

    // MARK: a/b. Song rows (Search song row, Discover song row) -> serverDownloads.request(song:)
    // CatalogSearchView `onDownload` and CatalogDiscoverView `onDownload` are wired to the same closure
    // (LibraryHomeView.swift:1473 and :1506), so one request path serves both; fixtures differ per source.

    func testSearchSongRow_YouTubeMusic_sendsWatchURLAndFullRowBody() async throws {
        let t = RecordingTransport(routes: routes())
        let (model, c) = await makeModel(t)
        await model.request(song: try song(Self.ytSong))
        let r = try only(t)
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.path, "/api/download/url")
        XCTAssertEqual(r.query, ["url": "https://music.youtube.com/watch?v=dQw4w9WgXcQ"])
        XCTAssertEqual(r.json["source"] as? String, "youtube")
        XCTAssertEqual(r.json["youtube_id"] as? String, "dQw4w9WgXcQ")
        XCTAssertEqual(r.json["name"] as? String, "Roads")
        XCTAssertEqual(r.json["album_name"] as? String, "Dummy")
        t.log("search-row/youtube", r)
        c.finish()
    }

    func testSearchSongRow_Deezer_sendsDeezerTrackURLNoYouTubeID() async throws {
        let t = RecordingTransport(routes: routes())
        let (model, c) = await makeModel(t)
        await model.request(song: try song(Self.deezerSong))
        let r = try only(t)
        XCTAssertEqual(r.query, ["url": "https://www.deezer.com/track/3135556"])
        XCTAssertEqual(r.json["source"] as? String, "deezer")
        XCTAssertEqual(r.json["song_id"] as? String, "3135556")
        XCTAssertNil(r.json["youtube_id"], "client sends no YouTube ID; server must match the Deezer track to a YouTube source itself")
        XCTAssertEqual(r.json["deezer_album_id"] as? String, "13")
        XCTAssertEqual(r.json["duration"] as? Double, 305)
        t.log("search-row/deezer", r)
        c.finish()
    }

    func testSearchSongRow_Spotify_sendsSpotifyTrackURLNoYouTubeID() async throws {
        let t = RecordingTransport(routes: routes())
        let (model, c) = await makeModel(t)
        await model.request(song: try song(Self.spotifySong))
        let r = try only(t)
        XCTAssertEqual(r.query, ["url": "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"])
        XCTAssertEqual(r.json["source"] as? String, "spotify")
        XCTAssertNil(r.json["youtube_id"])
        t.log("search-row/spotify", r)
        c.finish()
    }

    func testSearchSongRow_TextSearchPseudoURL_sendsDownloadByMetadataFlag() async throws {
        let t = RecordingTransport(routes: routes())
        let (model, c) = await makeModel(t)
        await model.request(song: try song(Self.textSearchSong))
        let r = try only(t)
        XCTAssertEqual(r.query, ["url": "downtify-search:search-abc"])
        XCTAssertEqual(r.json["download_by_metadata"] as? Bool, true)
        XCTAssertEqual(r.json["name"] as? String, "Roads")
        XCTAssertEqual(r.json["artists"] as? [String], ["Portishead"])
        t.log("search-row/text_search", r)
        c.finish()
    }

    func testDiscoverSongRow_chartsShapedDeezerRow_usesSameRequestPathAsSearchRow() async throws {
        // Discover rows come from /api/charts, /api/similar, finder artist songs: same CatalogSong, same closure.
        let chartRow = #"{"source":"deezer","song_id":"916424","name":"Roads (Remastered)","artists":["Portishead","Guest"],"album_name":"Dummy (Deluxe)","duration":303,"url":"https://www.deezer.com/track/916424","deezer_artist_id":"42","deezer_album_id":"14"}"#
        let t = RecordingTransport(routes: routes())
        let (model, c) = await makeModel(t)
        await model.request(song: try song(chartRow))
        let r = try only(t)
        XCTAssertEqual(r.path, "/api/download/url")
        XCTAssertEqual(r.query, ["url": "https://www.deezer.com/track/916424"])
        XCTAssertEqual(r.json["name"] as? String, "Roads (Remastered)")
        XCTAssertEqual(r.json["artists"] as? [String], ["Portishead", "Guest"])
        t.log("discover-row/deezer", r)
        c.finish()
    }

    // MARK: c/d/e. Album actions -> requestAlbum(url:expected:)

    func testSearchAlbumRow_YouTubeMusicBrowseURL_sendsOnlyAlbumURLQueryNoBody() async throws {
        let t = RecordingTransport(routes: routes(extra: ["/api/download/album": #"{"yt-1":"j1"}"#]))
        let (model, c) = await makeModel(t)
        // CatalogSearchView passes `resolvedAlbumTracks` (nil unless album details were opened) as `expected`.
        await model.requestAlbum(url: Self.ytAlbumURL, expected: nil)
        let r = try only(t)
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.path, "/api/download/album")
        XCTAssertEqual(r.query, ["url": Self.ytAlbumURL])
        XCTAssertNil(r.body, "album request carries no body: no track list, no artist, no album id")
        t.log("search-album-row/ytm-browse", r)
        c.finish()
    }

    func testAlbumsInThisLink_sendsSameAlbumURLRequestAsSearchAlbumRow() async throws {
        // "Albums in this link" uses the same serverAlbumDownloadButton -> onDownloadAlbum(url, resolved).
        // `resolved` is the link's whole track list ONLY when the link resolves to exactly one album.
        let t = RecordingTransport(routes: routes(extra: ["/api/download/album": #"{"dQw4w9WgXcQ":"j1"}"#]))
        let (model, c) = await makeModel(t)
        let expected = [try song(Self.ytSong)]
        await model.requestAlbum(url: Self.ytAlbumPlaylistURL, expected: expected)
        let r = try only(t)
        XCTAssertEqual(r.path, "/api/download/album")
        XCTAssertEqual(r.query, ["url": Self.ytAlbumPlaylistURL])
        XCTAssertNil(r.body)
        XCTAssertEqual(model.actionState(forAlbumURL: Self.ytAlbumPlaylistURL), .accepted)
        t.log("albums-in-this-link/ytm-playlist", r)
        c.finish()
    }

    func testDownloadsScreenAlbumAction_sendsSameAlbumURLRequest() async throws {
        // DownloadsView.swift:246 calls requestAlbum(url:) with no expected list.
        let t = RecordingTransport(routes: routes())
        let (model, c) = await makeModel(t)
        await model.requestAlbum(url: Self.ytAlbumURL)
        let r = try only(t)
        XCTAssertEqual(r.query, ["url": Self.ytAlbumURL])
        XCTAssertNil(r.body)
        XCTAssertEqual(model.actionState(forAlbumURL: Self.ytAlbumURL), .outcomeUnknown)
        t.log("downloads-album/ytm-browse", r)
        c.finish()
    }

    func testDeezerAndSpotifyAlbumURLsNeverReachTheAlbumEndpoint() async throws {
        // The album button is only rendered when isYouTubeMusicAlbumURL(url) (CatalogSearchView.swift:448,
        // CatalogDiscoverView.swift:~365, DownloadsView.swift:238); the queue also refuses anything else.
        XCTAssertFalse(ServerDownloadQueue.isYouTubeMusicAlbumURL(Self.deezerAlbumURL))
        XCTAssertFalse(ServerDownloadQueue.isYouTubeMusicAlbumURL(Self.spotifyAlbumURL))
        let t = RecordingTransport(routes: routes())
        let (model, c) = await makeModel(t)
        await model.requestAlbum(url: Self.deezerAlbumURL)
        await model.requestAlbum(url: Self.spotifyAlbumURL)
        XCTAssertTrue(downloads(t).isEmpty, "Deezer/Spotify album rows send nothing: no Add-to-Library button exists for them")
        c.finish()
    }

    // MARK: f. Artist album "Add Missing Songs to Library" (ArtistCatalogAlbumView, LibraryHomeView.swift:~1093)
    // Flow in the view: ArtistCatalogAlbumsView lists albums via searchAlbums(query: <artist name>, limit: 50)
    // filtered to album.artist == artist. Opening ONE album loads `songs` from finderAlbum(id) (Deezer id) or
    // resolve(url) -- keyed by that album only -- and the button batches `songs.filter(canRequest)`.

    func testArtistAlbumAddMissing_batchContainsOnlyTheOpenedAlbumsTracks() async throws {
        let albumsJSON = #"[{"name":"Dummy","artist":"Portishead","source":"deezer","deezer_album_id":"13","deezer_artist_id":"42","url":"https://www.deezer.com/album/13"},{"name":"Third","artist":"Portishead","source":"youtube","album_id":"MPREb_Third","url":"https://music.youtube.com/browse/MPREb_Third"},{"name":"Dummy Tribute","artist":"Someone Else","source":"deezer","deezer_album_id":"99","url":"https://www.deezer.com/album/99"}]"#
        let dummyTracks = #"[{"source":"deezer","song_id":"d1","name":"Mysterons","artists":["Portishead"],"album_name":"Dummy","url":"https://www.deezer.com/track/d1","deezer_album_id":"13"},{"source":"deezer","song_id":"d2","name":"Sour Times","artists":["Portishead"],"album_name":"Dummy","url":"https://www.deezer.com/track/d2","deezer_album_id":"13"}]"#
        let thirdTracks = #"[{"source":"youtube","song_id":"t1","youtube_id":"t1","name":"Silence","artists":["Portishead"],"album_name":"Third","url":"https://music.youtube.com/watch?v=t1"}]"#
        let finderAlbum = #"{"name":"Dummy","artist":"Portishead","source":"deezer","deezer_album_id":"13","url":"https://www.deezer.com/album/13","tracks":\#(dummyTracks)}"#
        let resolution = #"{"kind":"album","name":"Third","subtitle":"Portishead","tracks":\#(thirdTracks),"albums":[]}"#

        let t = RecordingTransport(routes: routes(extra: [
            "/api/albums/search": albumsJSON,
            "/api/finder/album": finderAlbum,
            "/api/url/resolve": resolution
        ]))
        let api = CatalogAPI(transport: t)
        let session = makeSession()

        // Step 1 (ArtistCatalogAlbumsView): search albums by artist NAME, keep exact-name matches.
        let found = try await api.searchAlbums(query: "Portishead", limit: 50, session: session)
        let albums = found.filter { $0.artist.localizedCaseInsensitiveCompare("Portishead") == .orderedSame }
        XCTAssertEqual(albums.map(\.title), ["Dummy", "Third"])
        let search = try XCTUnwrap(t.captured.first { $0.path == "/api/albums/search" })
        XCTAssertEqual(search.query["query"], "Portishead")
        XCTAssertEqual(search.query["limit"], "50")

        // Step 2 (ArtistCatalogAlbumView .task) for album "Dummy": finder album by Deezer ID.
        let dummy = try XCTUnwrap(albums.first { $0.title == "Dummy" })
        let id = try XCTUnwrap(dummy.deezerAlbumID)
        let dummySongs = try await api.finderAlbum(id: id, session: session).tracks
        XCTAssertEqual(t.captured.last?.path, "/api/finder/album")
        XCTAssertEqual(t.captured.last?.query, ["album_id": "13"])

        // Step 3: the "Add Missing Songs" button batches exactly `songs` (nothing from the other album).
        let (model, c) = await makeModel(t)
        await model.requestBatch(songs: dummySongs)
        let r = try only(t)
        XCTAssertEqual(r.path, "/api/download/batch")
        XCTAssertTrue(r.query.isEmpty)
        let sent = try XCTUnwrap(r.json["songs"] as? [[String: Any]])
        XCTAssertEqual(sent.compactMap { $0["song_id"] as? String }, ["d1", "d2"])
        XCTAssertFalse(sent.contains { ($0["song_id"] as? String) == "t1" }, "other album's track must not be in the batch")
        XCTAssertNil(r.json["playlist_url"])
        XCTAssertEqual(r.json["generate_m3u"] as? Bool, false)
        t.log("artist-album-add-missing/deezer-album", r)

        // Same for the album without a Deezer ID: resolve(url) of that album's URL.
        let third = try XCTUnwrap(albums.first { $0.title == "Third" })
        let thirdSongs = try await api.resolve(url: try XCTUnwrap(third.url), session: session).tracks
        XCTAssertEqual(t.captured.last?.path, "/api/url/resolve")
        XCTAssertEqual(t.captured.last?.query, ["url": "https://music.youtube.com/browse/MPREb_Third"])
        await model.requestBatch(songs: thirdSongs)
        let r2 = try XCTUnwrap(downloads(t).last)
        let sent2 = try XCTUnwrap(r2.json["songs"] as? [[String: Any]])
        XCTAssertEqual(sent2.compactMap { $0["song_id"] as? String }, ["t1"])
        t.log("artist-album-add-missing/url-album", r2)
        c.finish()
    }

    func testArtistAlbumAddMissing_clientSendsWholeRowsAndNoAlbumIdentity() async throws {
        // The batch has no album/artist field; each song row is the full provider payload, so a server
        // that resolves each row by title/artist (e.g. text_search) sees nothing that ties it to this album
        // beyond `album_name` inside the row.
        let tracks = try [song(Self.deezerSong), song(Self.textSearchSong)]
        let t = RecordingTransport(routes: routes())
        let (model, c) = await makeModel(t)
        await model.requestBatch(songs: tracks)
        let r = try only(t)
        XCTAssertEqual(Set(r.json.keys), ["songs", "generate_m3u"])
        c.finish()
    }
}

// MARK: - Recording transport

private struct Captured {
    let method: String
    let path: String
    let query: [String: String]
    let body: Data?
    var json: [String: Any] { body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:] }
}

private final class RecordingTransport: HTTPDataLoading, @unchecked Sendable {
    private let routes: [String: String]
    private let lock = NSLock()
    private var all: [Captured] = []

    init(routes: [String: String]) { self.routes = routes }

    var captured: [Captured] { lock.withLock { all } }

    func log(_ label: String, _ r: Captured) {
        let body = r.body.flatMap { String(data: $0, encoding: .utf8) } ?? "<none>"
        print("ISSUE27-CAPTURE [\(label)] \(r.method) \(r.path) query=\(r.query) body=\(body)")
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = try XCTUnwrap(request.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var query: [String: String] = [:]
        for item in items { query[item.name] = item.value ?? "" }
        lock.withLock {
            all.append(Captured(method: request.httpMethod ?? "GET", path: url.path, query: query, body: request.httpBody))
        }
        guard let key = routes.keys.sorted(by: { $0.count > $1.count }).first(where: { url.path.hasSuffix($0) }),
              let body = routes[key] else { throw APIError.invalidResponse }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
