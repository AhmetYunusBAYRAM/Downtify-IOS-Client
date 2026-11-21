import Foundation

/// Answers whether a catalog row or a server-downloaded file belongs to the
/// user's library. Indexed by file path and by normalized artist + title key so
/// lookups stay O(1) for large libraries.
struct LibraryMembership {
    private let tracksByFile: [String: [LibraryTrack]]
    private let tracksBySongKey: [String: [LibraryTrack]]
    private let trackCountByAlbum: [String: Int]

    init(tracks: [LibraryTrack]) {
        tracksByFile = Dictionary(grouping: tracks, by: \.file)
        tracksBySongKey = tracks.reduce(into: [:]) { index, track in
            let artist = Self.primaryArtist(artists: track.artists, fallback: track.artist)
            let parts = Self.songKeyParts(artist: artist, title: track.title)
            guard !parts.artist.isEmpty, !parts.title.isEmpty else { return }
            index[parts.artist + "|" + parts.title, default: []].append(track)
        }
        trackCountByAlbum = tracks.reduce(into: [:]) { counts, track in
            counts[Self.albumKey(title: track.album,
                                 artist: track.albumArtist.isEmpty ? track.artist : track.albumArtist), default: 0] += 1
        }
    }

    private static func albumKey(title: String, artist: String) -> String {
        let normalize = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return normalize(title) + "\u{1F}" + normalize(artist)
    }

    // MARK: - Song key (port of the server's Python `song_key`)

    private static let sameSongTagRegex = try! NSRegularExpression(
        pattern: #"[(\[](?:(?:feat|ft|with)\b|[^)\]]*remaster)[^)\]]*[)\]]"#, options: [.caseInsensitive])
    private static let featTailRegex = try! NSRegularExpression(
        pattern: #"\s(feat|ft)\.?\s.*$"#, options: [.caseInsensitive])
    private static let remasterTailRegex = try! NSRegularExpression(
        pattern: #"\s-\s[^-]*remaster[^-]*$"#, options: [.caseInsensitive])
    private static let artistSplitRegex = try! NSRegularExpression(pattern: #",|;| & "#)

    /// NFD-normalize, drop combining marks (category Mn), then lowercase.
    private static func foldText(_ text: String) -> String {
        let decomposed = text.decomposedStringWithCanonicalMapping
        let unmarked = String(String.UnicodeScalarView(decomposed.unicodeScalars.filter {
            $0.properties.generalCategory != .nonspacingMark
        }))
        return unmarked.lowercased()
    }

    private static func replacing(_ regex: NSRegularExpression, in text: String, with replacement: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                       withTemplate: replacement)
    }

    private static func cleanKeyPart(_ text: String) -> String {
        var folded = foldText(text)
        folded = replacing(sameSongTagRegex, in: folded, with: " ")
        folded = replacing(featTailRegex, in: folded, with: " ")
        folded = replacing(remasterTailRegex, in: folded, with: " ")
        let alnumOnly = String(String.UnicodeScalarView(folded.unicodeScalars.map { scalar -> Unicode.Scalar in
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber:
                return scalar
            default:
                return " "
            }
        }))
        return alnumOnly.split(separator: " ").joined(separator: " ")
    }

    /// The first artist before any ",", ";" or " & " separator, trimmed.
    private static func firstArtistSegment(_ artist: String) -> String {
        let range = NSRange(artist.startIndex..., in: artist)
        let end: String.Index
        if let match = artistSplitRegex.firstMatch(in: artist, range: range),
           let matchRange = Range(match.range, in: artist) {
            end = matchRange.lowerBound
        } else {
            end = artist.endIndex
        }
        return String(artist[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Catalog/track artist used for keys: first non-empty entry of `artists`, else the fallback artist.
    private static func primaryArtist(artists: [String], fallback: String) -> String {
        if let first = artists.first, !first.isEmpty { return first }
        return fallback
    }

    private static func songKeyParts(artist: String, title: String) -> (artist: String, title: String) {
        (cleanKeyPart(firstArtistSegment(artist)), cleanKeyPart(title))
    }

    /// Normalized "artist|title" key matching the server's rule.
    static func songKey(artist: String, title: String) -> String {
        let parts = songKeyParts(artist: artist, title: title)
        return parts.artist + "|" + parts.title
    }

    // MARK: - Album membership

    /// True when the library holds any track of the album (title + album artist).
    func hasAlbum(title: String, artist: String) -> Bool {
        trackCountByAlbum[Self.albumKey(title: title, artist: artist)] != nil
    }

    /// True when the library holds at least `trackCount` tracks of the album (title + album artist).
    /// An unknown track count is never treated as fully in the library.
    func isAlbumFullyInLibrary(title: String, artist: String, trackCount: Int?) -> Bool {
        guard let trackCount, trackCount > 0,
              let owned = trackCountByAlbum[Self.albumKey(title: title, artist: artist)] else { return false }
        return owned >= trackCount
    }

    // MARK: - Catalog song lookups

    /// Every library track that is the same song as `song`.
    /// Library rows match by file path; other rows match by normalized artist + title.
    func matchingTracks(for song: CatalogSong) -> [LibraryTrack] {
        if song.source == "library" {
            return libraryFileTrack(for: song).map { [$0] } ?? []
        }
        let artist = Self.primaryArtist(artists: song.artists, fallback: song.artist)
        let parts = Self.songKeyParts(artist: artist, title: song.title)
        guard !parts.artist.isEmpty, !parts.title.isEmpty else { return [] }
        return tracksBySongKey[parts.artist + "|" + parts.title] ?? []
    }

    func containsSong(_ song: CatalogSong) -> Bool {
        !matchingTracks(for: song).isEmpty
    }

    /// Library rows resolve by file path; other rows resolve only when exactly one library track matches.
    func track(for song: CatalogSong) -> LibraryTrack? {
        if song.source == "library" {
            return libraryFileTrack(for: song)
        }
        let matches = matchingTracks(for: song)
        return matches.count == 1 ? matches[0] : nil
    }

    private func libraryFileTrack(for song: CatalogSong) -> LibraryTrack? {
        guard song.source == "library", let file = song.file,
              let candidates = tracksByFile[file] else { return nil }
        return song.libraryTrack(in: candidates)
    }

    func track(forServerFilename filename: String) -> LibraryTrack? {
        guard let matches = tracksByFile[filename], matches.count == 1 else { return nil }
        return matches[0]
    }
}
