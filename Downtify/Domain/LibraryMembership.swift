import Foundation

/// Answers whether a catalog row or a server-downloaded file belongs to the
/// user's library. Indexed by file path so lookups stay O(1) for large libraries.
struct LibraryMembership {
    private let tracksByFile: [String: [LibraryTrack]]

    init(tracks: [LibraryTrack]) {
        tracksByFile = Dictionary(grouping: tracks, by: \.file)
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
