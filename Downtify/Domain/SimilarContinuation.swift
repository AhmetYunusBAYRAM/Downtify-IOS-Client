import Foundation

/// Accumulated Similar results that grow as the listener nears the end of the list (#72).
/// Pure value type: it decides which seed to use next, drops duplicates, and records when the list ran dry.
struct SimilarFeed: Equatable, Sendable {
    static let pageLimit = 20
    static let rowCap = 200
    static let trailingRows = 5
    static let seedFallbackDepth = 3

    struct Seed: Equatable, Sendable {
        let artist: String
        let track: String
        var key: String { SimilarFeed.seedKey(artist: artist, track: track) }
    }

    private(set) var songs: [CatalogSong] = []
    private(set) var loadingMore = false
    private(set) var hasMore = true
    private(set) var failureMessage: String?
    private var usedSeeds: Set<String> = []
    private var seenIDs: Set<CatalogResultID> = []
    private var seenNames: Set<String> = []

    init(initial: CatalogSimilarResults, querySeed: Seed? = nil) {
        usedSeeds.insert(Self.seedKey(artist: initial.artist, track: initial.track))
        if let querySeed { usedSeeds.insert(querySeed.key) }
        _ = append(initial.tracks)
        hasMore = !songs.isEmpty && songs.count < Self.rowCap
    }

    var canLoadMore: Bool { hasMore && !loadingMore && failureMessage == nil }

    /// True when `song` is one of the last few rows and another page may be fetched.
    func shouldLoadMore(whenShowing song: CatalogSong) -> Bool {
        canLoadMore && songs.suffix(Self.trailingRows).contains { $0.id == song.id }
    }

    /// The last usable row not yet used as a seed, looking back a few rows before giving up.
    func nextSeed() -> Seed? {
        for song in songs.suffix(Self.seedFallbackDepth).reversed() {
            let artist = Self.primaryArtist(song)
            let title = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !artist.isEmpty, !title.isEmpty else { continue }
            let seed = Seed(artist: artist, track: title)
            if !usedSeeds.contains(seed.key) { return seed }
        }
        return nil
    }

    mutating func beginMore() {
        loadingMore = true
        failureMessage = nil
    }

    /// Records a successful page. The seed is marked used only now, so a failed request can be retried.
    @discardableResult
    mutating func finishMore(seed: Seed, tracks: [CatalogSong]) -> Int {
        loadingMore = false
        usedSeeds.insert(seed.key)
        let added = append(tracks)
        if added == 0 || songs.count >= Self.rowCap { hasMore = false }
        return added
    }

    mutating func failMore(message: String) {
        loadingMore = false
        failureMessage = message
    }

    mutating func clearFailure() { failureMessage = nil }

    mutating func exhaust() {
        loadingMore = false
        hasMore = false
    }

    private mutating func append(_ tracks: [CatalogSong]) -> Int {
        var added = 0
        for song in tracks where songs.count < Self.rowCap {
            let name = Self.nameKey(song)
            guard !seenIDs.contains(song.id), !seenNames.contains(name) else { continue }
            seenIDs.insert(song.id)
            seenNames.insert(name)
            songs.append(song)
            added += 1
        }
        return added
    }

    private static func primaryArtist(_ song: CatalogSong) -> String {
        let artist = song.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return artist.isEmpty ? (song.artists.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : artist
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func seedKey(artist: String, track: String) -> String { "\(normalized(artist))\u{1F}\(normalized(track))" }

    private static func nameKey(_ song: CatalogSong) -> String { seedKey(artist: primaryArtist(song), track: song.title) }
}
