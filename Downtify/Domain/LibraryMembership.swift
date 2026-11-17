import Foundation

/// Answers whether a catalog row or a server-downloaded file belongs to the
/// user's library. Indexed by file path so lookups stay O(1) for large libraries.
struct LibraryMembership {
    private let tracksByFile: [String: [LibraryTrack]]
    private let trackCountByAlbum: [String: Int]

    init(tracks: [LibraryTrack]) {
        tracksByFile = Dictionary(grouping: tracks, by: \.file)
        trackCountByAlbum = tracks.reduce(into: [:]) { counts, track in
            counts[Self.albumKey(title: track.album,
                                 artist: track.albumArtist.isEmpty ? track.artist : track.albumArtist), default: 0] += 1
        }
    }

    private static func albumKey(title: String, artist: String) -> String {
        let normalize = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return normalize(title) + "\u{1F}" + normalize(artist)
    }

    /// True when the library holds at least `trackCount` tracks of the album (title + album artist).
    /// An unknown track count is never treated as fully in the library.
    func isAlbumFullyInLibrary(title: String, artist: String, trackCount: Int?) -> Bool {
        guard let trackCount, trackCount > 0,
              let owned = trackCountByAlbum[Self.albumKey(title: title, artist: artist)] else { return false }
        return owned >= trackCount
    }

    func track(for song: CatalogSong) -> LibraryTrack? {
        guard song.source == "library", let file = song.file,
              let candidates = tracksByFile[file] else { return nil }
        return song.libraryTrack(in: candidates)
    }

    func track(forServerFilename filename: String) -> LibraryTrack? {
        guard let matches = tracksByFile[filename], matches.count == 1 else { return nil }
        return matches[0]
    }
}
