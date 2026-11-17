import Foundation
import XCTest
@testable import Downtify

@MainActor
final class CatalogActionWiringTests: XCTestCase {
    private let title = "One"

    func testFreshCatalogSongShowsAddToLibraryAction() throws {
        let model = ServerDownloadPresentationModel(queue: ServerDownloadQueue(transport: CatalogRouteTransport(routes: [:]))) {
            AsyncStream<DeviceSession?> { $0.finish() }
        }
        let song = try decodeSong()

        XCTAssertEqual(model.actionState(for: song), .idle)
        let presentation = MediaActionPresentation.library(model.actionState(for: song), itemTitle: song.title)
        XCTAssertEqual(presentation.title, "Add to Library")
        XCTAssertEqual(presentation.systemImage, "plus.circle")
        XCTAssertTrue(presentation.isEnabled)
    }

    func testQueuedCatalogSongShowsDisabledQueuedAction() async throws {
        let transport = CatalogRouteTransport(routes: [
            "/api/server/info": #"{"product":"Downtify","api_version":1,"server_id":"server"}"#,
            "/api/download/url": #""job-1""#,
            "/api/queue": "[]",
            "/api/queue/state": #"{"paused":false,"state":"idle","active":0}"#
        ])
        let (updates, continuation) = AsyncStream<DeviceSession?>.makeStream()
        let model = ServerDownloadPresentationModel(queue: ServerDownloadQueue(transport: transport)) { updates }
        model.start()
        continuation.yield(makeSession())
        await waitUntil { model.session != nil }
        let song = try decodeSong()

        await model.request(song: song)

        XCTAssertEqual(model.actionState(for: song), .queued(jobID: "job-1"))
        let presentation = MediaActionPresentation.library(model.actionState(for: song), itemTitle: song.title)
        XCTAssertEqual(presentation.systemImage, "clock.arrow.circlepath")
        XCTAssertFalse(presentation.isEnabled)
        continuation.finish()
    }

    func testCatalogOnlySongHasNoDevicePresentation() throws {
        let state = DeviceSaveState(track: nil, record: nil)
        XCTAssertEqual(state, .unavailable(.notInLibrary))

        let presentation = MediaActionPresentation.device(state, itemTitle: title)
        XCTAssertFalse(presentation.isEnabled)
        XCTAssertNotNil(presentation.explanation)
    }

    func testYouTubeMusicAlbumURLAcceptsOnlyAlbumForms() {
        XCTAssertTrue(ServerDownloadQueue.isYouTubeMusicAlbumURL("https://music.youtube.com/browse/MPREb_abc"))
        XCTAssertTrue(ServerDownloadQueue.isYouTubeMusicAlbumURL("https://music.youtube.com/playlist?list=OLAK5uy_abc"))
        XCTAssertFalse(ServerDownloadQueue.isYouTubeMusicAlbumURL("https://music.youtube.com/channel/UCabc"))
        XCTAssertFalse(ServerDownloadQueue.isYouTubeMusicAlbumURL("https://music.youtube.com/watch?v=abc"))
        XCTAssertFalse(ServerDownloadQueue.isYouTubeMusicAlbumURL("https://open.spotify.com/album/abc"))
        XCTAssertFalse(ServerDownloadQueue.isYouTubeMusicAlbumURL(""))
    }

    private func decodeSong() throws -> CatalogSong {
        try JSONDecoder().decode(CatalogSong.self, from: Data(
            #"{"source":"youtube","song_id":"yt-1","name":"One","artists":["A"],"url":"https://music.youtube.com/watch?v=yt-1"}"#.utf8
        ))
    }

    private func makeSession() -> DeviceSession {
        DeviceSession(baseAddress: "https://example.test", serverID: "server", serverName: "Server", deviceID: "device",
                      username: "listener", role: nil, token: "secret", allowsInsecureHTTP: false)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
    }
}

private final class CatalogRouteTransport: HTTPDataLoading {
    private let routes: [String: String]

    init(routes: [String: String]) { self.routes = routes }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        guard let route = routes.keys.first(where: { path.hasSuffix($0) }), let body = routes[route] else {
            throw APIError.invalidResponse
        }
        let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
