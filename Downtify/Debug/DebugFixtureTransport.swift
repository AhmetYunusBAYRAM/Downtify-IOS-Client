#if DEBUG
import Foundation

/// Fixture JSON API for `fixture` mode. Serves only JSON routes; media comes from `DebugPlaybackStreamResolver`.
/// Faults are scripted per named route through `DebugHarnessConfiguration.faults`.
final class DebugFixtureTransport: HTTPDataLoading, @unchecked Sendable {
    static let serverID = "fixture-server"
    static let token = "fixture-token"

    private let faults: [DebugRoute: DebugFaultKind]
    /// Mutable fixture state for likes and the one editable playlist; guarded by `lock`.
    private let lock = NSLock()
    private var likedIDs: [String] = []
    private var playlistTrackIDs: [String] = []

    private let trackCount: Int

    init(faults: [DebugRoute: DebugFaultKind], trackCount: Int = 2) {
        self.trackCount = trackCount
        self.faults = faults
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let path = url.path
        let route = Self.route(for: path)
        if let route, let fault = faults[route] {
            switch fault {
            case .timeout: throw URLError(.timedOut)
            case .offline: throw URLError(.notConnectedToInternet)
            case .http500: return respond(url, 500, #"{"detail":"injected fault"}"#)
            case .unauthorized: return respond(url, 401, #"{"detail":"injected fault"}"#)
            }
        }
        let method = request.httpMethod ?? "GET"
        if method == "GET", path.hasPrefix("/api/v1/tracks/"), path.hasSuffix("/cover"), let png = Data(base64Encoded: Self.coverPNGBase64) {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
            return (png, response)
        }
        let response = try await respondTo(method: method, path: path, url: url, body: request.httpBody)
        if let http = response.1 as? HTTPURLResponse {
            DebugLog.logger.info("fixture \(method, privacy: .public) \(path, privacy: .public) -> \(http.statusCode, privacy: .public)")
        }
        return response
    }

    private func respondTo(method: String, path: String, url: URL, body: Data?) async throws -> (Data, URLResponse) {
        switch (method, path) {
        case ("GET", "/api/server/info"):
            return respond(url, 200, Self.serverInfo)
        case ("POST", "/api/auth/token"), ("POST", "/api/auth/pair"):
            return respond(url, 200, Self.authResponse)
        case ("GET", "/api/auth/status"):
            return respond(url, 200, #"{"via":"device","signed_in":true}"#)
        case ("GET", "/api/v1/library"):
            return respond(url, 200, Self.libraryPage(trackCount: trackCount), headers: ["ETag": "\"fixture-1\""])
        case ("GET", "/api/v1/playlists"):
            return respond(url, 200, playlistsJSON())
        case ("GET", "/api/v1/likes"):
            return respond(url, 200, json(["track_ids": withLock { likedIDs }]))
        case ("PUT", "/api/v1/likes"):
            guard let change = decode(body), let id = change["track_id"] as? String,
                  let liked = change["liked"] as? Bool else { return respond(url, 400, #"{"detail":"bad request"}"#) }
            withLock {
                likedIDs.removeAll { $0 == id }
                if liked { likedIDs.append(id) }
            }
            return respond(url, 200, "{}")
        case ("POST", "/api/v1/playlists/tracks"):
            guard let edit = decode(body), edit["name"] as? String == Self.playlistName else {
                return respond(url, 404, #"{"detail":"not found"}"#)
            }
            let add = edit["add"] as? [String] ?? []
            let allowDuplicates = edit["allow_duplicates"] as? Bool ?? false
            let (ids, added, already) = withLock { () -> ([String], Int, [String]) in
                var added = 0
                var already: [String] = []
                for id in add {
                    if playlistTrackIDs.contains(id) && !allowDuplicates { already.append(id); continue }
                    playlistTrackIDs.append(id)
                    added += 1
                }
                return (playlistTrackIDs, added, already)
            }
            return respond(url, 200, json(["name": Self.playlistName, "manual": true, "count": ids.count,
                                           "track_ids": ids, "added": added, "already": already]))
        case ("GET", "/api/songs/search"):
            return respond(url, 200, "[\(Self.catalogSong)]")
        default:
            return respond(url, 404, #"{"detail":"not found"}"#)
        }
    }

    static let playlistName = "Fixture Mix"

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func decode(_ body: Data?) -> [String: Any]? {
        body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    private func json(_ object: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: object)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private func playlistsJSON() -> String {
        let ids = withLock { playlistTrackIDs }
        let playlist: [String: Any] = ["name": Self.playlistName, "track_ids": ids, "favorite": false, "mine": true,
                                       "manual": true, "can_edit_tracks": true, "owner": "fixture"]
        return (try? JSONSerialization.data(withJSONObject: [playlist])).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    }

    static func route(for path: String) -> DebugRoute? {
        if path == "/api/server/info" { return .serverInfo }
        if path.hasPrefix("/api/auth/") { return .auth }
        if path.hasPrefix("/api/v1/library") { return .library }
        if path.hasPrefix("/api/songs") || path.hasPrefix("/api/albums") || path.hasPrefix("/api/artists")
            || path.hasPrefix("/api/url") || path.hasPrefix("/api/finder") { return .catalog }
        if path.hasPrefix("/api/v1/tracks/") && path.hasSuffix("/stream") { return .stream }
        return nil
    }

    private func respond(_ url: URL, _ status: Int, _ body: String, headers: [String: String] = [:]) -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"].merging(headers) { $1 })!
        return (Data(body.utf8), response)
    }

    /// 1x1 transparent PNG used as the fixture cover for every track.
    static let coverPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="

    static let serverInfo = #"{"product":"Downtify","api_version":1,"server_id":"fixture-server","server_name":"Fixture","capabilities":{"password_sign_in":true,"signed_urls":false,"podcasts":false,"discover":false,"lyrics":false,"playlist_editing":true}}"#

    static let authResponse = #"{"token":"fixture-token","device":{"id":"fixture-device"},"server":{"server_id":"fixture-server","name":"Fixture"},"user":{"username":"fixture","role":"admin"}}"#

    /// Library page with `trackCount` generated tracks `fixture-track-1...n` (title "Fixture One", "Fixture Two", ...).
    static func libraryPage(trackCount: Int) -> String {
        let names = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve"]
        let tracks = (1...max(1, min(trackCount, names.count))).map { n in
            #"{"id":"fixture-track-\#(n)","file":"track\#(n).wav","title":"Fixture \#(names[n - 1])","artist":"Fixture Artist","artists":["Fixture Artist"],"album":"Fixture Album","album_artist":"Fixture Artist","album_id":"fixture-album","artist_id":"fixture-artist","track_number":\#(n),"year":"2026","duration":30,"codec":"wav","bitrate":64000,"sample_rate":8000,"channels":1,"size":240044,"added":\#(n),"has_cover":true,"explicit":false,"playlists":[]}"#
        }
        return #"{"cursor":1,"full":true,"deleted":[],"tracks":["# + tracks.joined(separator: ",") + #"]}"#
    }
    static let libraryPage = libraryPage(trackCount: 2)

    static let catalogSong = #"{"source":"youtube","song_id":"fixture-song-1","name":"Fixture Catalog Song","artist":"Fixture Artist","artists":["Fixture Artist"],"album_name":"Fixture Album","duration":30,"url":"https://youtube.test/watch?v=fixture-song-1"}"#
}
#endif
