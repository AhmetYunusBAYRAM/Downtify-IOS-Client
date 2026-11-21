import Foundation

/// Which song is current, published only when the song or its play state changes.
/// Lists observe this instead of `PlaybackController`, whose position updates would re-render every row.
@MainActor
final class NowPlayingIndicator: ObservableObject {
    @Published private(set) var currentID: PlaybackItem.MediaID?
    /// Lets library-sourced catalog results match the playing library track without scanning the library.
    @Published private(set) var currentLibraryFile: String?
    @Published private(set) var isPlaying = false

    func update(item: PlaybackItem?, phase: PlaybackPhase) {
        let id = item?.mediaID
        let file = item?.libraryTrack?.file
        let playing = item != nil && (phase == .playing || phase == .buffering || phase == .loading)
        if currentID != id { currentID = id }
        if currentLibraryFile != file { currentLibraryFile = file }
        if isPlaying != playing { isPlaying = playing }
    }

    func isCurrent(_ track: LibraryTrack) -> Bool {
        currentID == .library(track.id)
    }

    func isCurrent(_ song: CatalogSong) -> Bool {
        if currentID == .catalog(song.id) { return true }
        guard song.source == "library", let file = song.file, let currentLibraryFile else { return false }
        return file == currentLibraryFile
    }
}
