import SwiftUI

/// Search surface for the synced library and the server catalog.
struct CatalogSearchView: View {
    @ObservedObject var catalog: CatalogPresentationModel
    @ObservedObject var library: LibraryPresentationModel
    let playback: PlaybackController
    var onDownloadAlbum: (String, [CatalogSong]?) -> Void = { _, _ in }
    var albumDownloadState: (CatalogAlbum, Int?) -> ServerDownloadActionState = { _, _ in .idle }
    var onDownload: (CatalogSong) -> Void = { _ in }
    var downloadState: (CatalogSong) -> ServerDownloadActionState = { _ in .idle }
    var onAddToDevice: (CatalogSong) -> Void = { _ in }
    var deviceState: (CatalogSong) -> DeviceSaveState = { _ in .unavailable(.notInLibrary) }

    private enum SearchCategory: String, CaseIterable {
        case songs, artists, albums
    }

    @State private var category: SearchCategory = .songs
    @State private var query = ""
    @State private var link = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.downtifyPalette) private var palette

    init(catalog: CatalogPresentationModel, library: LibraryPresentationModel,
         playback: PlaybackController,
         onDownloadAlbum: @escaping (String, [CatalogSong]?) -> Void = { _, _ in },
         albumDownloadState: @escaping (CatalogAlbum, Int?) -> ServerDownloadActionState = { _, _ in .idle },
         onDownload: @escaping (CatalogSong) -> Void = { _ in },
         downloadState: @escaping (CatalogSong) -> ServerDownloadActionState = { _ in .idle },
         onAddToDevice: @escaping (CatalogSong) -> Void = { _ in },
         deviceState: @escaping (CatalogSong) -> DeviceSaveState = { _ in .unavailable(.notInLibrary) }) {
        self.catalog = catalog
        self.library = library
        self.playback = playback
        self.onDownloadAlbum = onDownloadAlbum
        self.albumDownloadState = albumDownloadState
        self.onDownload = onDownload
        self.downloadState = downloadState
        self.onAddToDevice = onAddToDevice
        self.deviceState = deviceState
    }

    /// Catalog albums on screen that may need a provider track count to be recognised as owned.
    private var catalogAlbumRows: [CatalogAlbum] {
        var albums: [CatalogAlbum] = []
        switch catalog.searchAlbumsState {
        case .loaded(let value), .partial(let value, _): albums += value
        default: break
        }
        switch catalog.urlResolutionState {
        case .loaded(let value), .partial(let value, _): albums += value.albums
        default: break
        }
        return albums.filter(canRequestAlbumDownload)
    }

    private var albumCountLookupKey: [CatalogResultID] { catalogAlbumRows.map(\.id) + [CatalogResultID(source: "tracks", value: String(library.tracks.count))] }

    private func loadAlbumTrackCounts() {
        let membership = library.membership
        catalog.loadAlbumTrackCounts(for: catalogAlbumRows) {
            membership.hasAlbum(title: $0.title, artist: $0.artist)
        }
    }

    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var localSongs: [LibraryTrack] { LibraryTrackOrdering.matching(library.tracks, query: normalizedQuery) }
    private var localAlbums: [LibraryBrowseEntry] {
        guard !normalizedQuery.isEmpty else { return [] }
        return library.catalog.albumsByID.values.filter {
            $0.title.localizedStandardContains(normalizedQuery) || $0.artist.localizedStandardContains(normalizedQuery)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var localArtists: [LibraryBrowseEntry] {
        guard !normalizedQuery.isEmpty else { return [] }
        return library.catalog.artistsByID.values.filter { $0.title.localizedStandardContains(normalizedQuery) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: category == .songs ? .leading : .center, spacing: 20) {
            Picker("Search category", selection: $category) {
                Text("Songs").tag(SearchCategory.songs)
                Text("Artists").tag(SearchCategory.artists)
                Text("Albums").tag(SearchCategory.albums)
            }
            .pickerStyle(.segmented)

            TextField("Songs, albums, artists", text: $query)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .focused($searchFocused)
                .accessibilityLabel("Search songs, albums, and artists")
                .accessibilityIdentifier("catalog.searchField")

            if !normalizedQuery.isEmpty {
                localResults
                catalogResults
            } else {
                ContentUnavailableView("Search your music", systemImage: "magnifyingglass",
                                       description: Text("Search saved music and available catalog results."))
            }

            if catalog.externalCatalogAvailable {
                linkResolver
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: category == .songs ? .leading : .center)
        .background(palette.background)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { searchFocused = false }
            }
        }
        .task(id: normalizedQuery) {
            guard !normalizedQuery.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            catalog.search(normalizedQuery)
        }
        .onAppear { catalog.start() }
        .task(id: albumCountLookupKey) { loadAlbumTrackCounts() }
    }

    @ViewBuilder private var localResults: some View {
        if category == .songs && !localSongs.isEmpty {
            sectionHeader("In your library")
            ForEach(localSongs) { track in
                NowPlayingReader { nowPlaying in
                    let isCurrent = nowPlaying.isCurrent(track)
                    Button { playback.replaceQueue(localSongs, startingAt: localSongs.firstIndex(of: track) ?? 0) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                currentTitle(track.title, isCurrent: isCurrent, isPlaying: nowPlaying.isPlaying)
                                Text(track.artist).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.fill").frame(minWidth: 44, minHeight: 44)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(track.title)")
                    .downtifyCurrentRowAccessibility(isCurrent: isCurrent, isPlaying: nowPlaying.isPlaying)
                    .padding(.vertical, 4)
                }
            }
        }
        if category == .albums && !localAlbums.isEmpty {
            sectionHeader("Library albums")
            ForEach(localAlbums) { entry in
                NavigationLink(value: entry.context) {
                    Label("\(entry.title) · \(entry.artist)", systemImage: "square.stack")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
        if category == .artists && !localArtists.isEmpty {
            sectionHeader("Library artists")
            ForEach(localArtists) { entry in
                NavigationLink(value: entry.context) {
                    Label(entry.title, systemImage: "person")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private var catalogResults: some View {
        if category == .songs {
            switch catalog.searchSongsState {
            case .loading:
                ProgressView("Searching catalog…")
            case .failed(let message), .unavailable(let message):
                Text(message).foregroundStyle(.secondary)
            case .loaded(let songs), .partial(let songs, _):
                songResults(songs)
            case .empty:
                EmptyView()
            case .idle:
                EmptyView()
            }
        }

        if category == .albums {
            switch catalog.searchAlbumsState {
            case .loaded(let albums), .partial(let albums, _):
                if !albums.isEmpty {
                    sectionHeader("Catalog albums")
                    ForEach(albums) { album in
                        HStack {
                            NavigationLink { albumDetail(album) } label: {
                                Label("\(album.title) · \(album.artist)", systemImage: "square.stack")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }.buttonStyle(.plain)
                            if canRequestAlbumDownload(album), let url = album.url {
                                serverAlbumDownloadButton(url: url, album: album)
                            }
                        }
                    }
                }
            case .loading: ProgressView("Searching catalog…")
            case .failed(let message), .unavailable(let message): Text(message).foregroundStyle(.secondary)
            default: EmptyView()
            }
        }

        if category == .artists {
            switch catalog.searchArtistsState {
            case .loaded(let artists), .partial(let artists, _):
                if !artists.isEmpty {
                    sectionHeader("Catalog artists")
                    ForEach(artists) { artist in
                        NavigationLink { artistDetail(artist) } label: {
                            Label(artist.name, systemImage: "person")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            case .loading: ProgressView("Searching catalog…")
            case .failed(let message), .unavailable(let message): Text(message).foregroundStyle(.secondary)
            default: EmptyView()
            }
        }
    }

    private func albumDetail(_ album: CatalogAlbum) -> AnyView {
        AnyView(ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(album.artist).font(.headline).foregroundStyle(.secondary)
                if finderAlbumID(album) != nil {
                    switch catalog.finderAlbumState {
                    case .loaded(let details), .partial(let details, _):
                        songResults(details.tracks, queueAlbum: true)
                    case .loading, .idle: ProgressView("Loading album…")
                    case .failed(let message), .unavailable(let message): Text(message).foregroundStyle(.secondary)
                    case .empty: Text("No songs found.").foregroundStyle(.secondary)
                    }
                } else if let url = album.url {
                    albumResolutionDetails(url: url)
                } else {
                    Text("Album details are unavailable.").foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .downtifyScrollEndClearance()
        .background(palette.background)
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let id = finderAlbumID(album) { catalog.loadFinderAlbum(id: id) }
            else if let url = album.url { catalog.loadAlbumTracks(url: url) }
        })
    }

    private func artistDetail(_ artist: CatalogArtist) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if finderArtistID(artist) != nil {
                    switch catalog.finderArtistState {
                    case .loaded(let details), .partial(let details, _):
                        if !details.bio.isEmpty { Text(details.bio).font(.subheadline) }
                        if case .loaded(let songs) = catalog.finderArtistSongsState, !songs.isEmpty {
                            songResults(songs)
                        } else {
                            songResults(details.topSongs)
                        }
                    case .loading, .idle: ProgressView("Loading artist…")
                    case .failed(let message), .unavailable(let message): Text(message).foregroundStyle(.secondary)
                    case .empty: Text("Artist details are unavailable.").foregroundStyle(.secondary)
                    }
                    switch catalog.finderArtistAlbumsState {
                    case .loaded(let albums), .partial(let albums, _):
                        if !albums.isEmpty { sectionHeader("Albums") }
                        ForEach(albums) { album in
                            NavigationLink { albumDetail(album) } label: {
                                Label(album.title, systemImage: "square.stack")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                        }
                    case .loading: ProgressView("Loading artist albums…")
                    case .failed(let message), .unavailable(let message): Text(message).foregroundStyle(.secondary)
                    default: EmptyView()
                    }
                } else if artist.url != nil {
                    resolutionDetails
                } else {
                    Text("Artist details are unavailable.").foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .downtifyScrollEndClearance()
        .background(palette.background)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let id = finderArtistID(artist) { catalog.loadFinderArtist(id: id, name: artist.name) }
            else if let url = artist.url { catalog.resolveURL(url) }
        }
    }

    @ViewBuilder private var resolutionDetails: some View {
        switch catalog.urlResolutionState {
        case .loaded(let resolution), .partial(let resolution, _):
            songResults(resolution.tracks)
            if !resolution.albums.isEmpty { sectionHeader("Albums") }
            ForEach(resolution.albums) { album in
                NavigationLink { albumDetail(album) } label: {
                    Label(album.title, systemImage: "square.stack")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        case .loading, .idle: ProgressView("Resolving link…")
        case .failed(let message), .unavailable(let message): Text(message).foregroundStyle(.secondary)
        case .empty: Text("No results found.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func albumResolutionDetails(url: String) -> some View {
        switch catalog.albumTracksState {
        case .loaded(let tracks), .partial(let tracks, _):
            if tracks.isEmpty { Text("No songs found.").foregroundStyle(.secondary) }
            else { songResults(tracks, queueAlbum: true) }
        case .loading, .idle: ProgressView("Loading album tracks…")
        case .failed(let message), .unavailable(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).foregroundStyle(.secondary)
                Button("Retry") { catalog.loadAlbumTracks(url: url) }
            }
        case .empty: Text("No songs found.").foregroundStyle(.secondary)
        }
    }

    private func finderAlbumID(_ album: CatalogAlbum) -> String? {
        let id = album.deezerAlbumID ?? (album.source.lowercased() == "deezer" ? album.albumID : nil)
        return id.flatMap { isDecimalID($0) ? $0 : nil }
    }

    private func finderArtistID(_ artist: CatalogArtist) -> String? {
        let id = artist.deezerID ?? (artist.source.lowercased() == "deezer" ? artist.artistID : nil)
        return id.flatMap { isDecimalID($0) ? $0 : nil }
    }

    private func isDecimalID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy { (48...57).contains($0) }
    }

    @ViewBuilder private func songResults(_ songs: [CatalogSong], queueAlbum: Bool = false) -> some View {
        if !songs.isEmpty {
            sectionHeader("Catalog songs")
            ForEach(songs) { song in
                NowPlayingReader { nowPlaying in
                    let isCurrent = nowPlaying.isCurrent(song)
                    HStack(spacing: 10) {
                        Button {
                            if queueAlbum {
                                let items = songs.map { PlaybackItem.resolving($0, in: library.tracks) }
                                playback.replaceQueue(items, startingAt: songs.firstIndex(of: song) ?? 0)
                                return
                            }
                            if song.source == "library" {
                                guard let track = song.libraryTrack(in: library.tracks) else { return }
                                playback.replaceQueue([.library(track)])
                                return
                            }
                            playback.replaceQueue([PlaybackItem.resolving(song, in: library.tracks)])
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    currentTitle(song.title, isCurrent: isCurrent, isPlaying: nowPlaying.isPlaying)
                                    Text([song.artist, song.albumName].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "play.fill").frame(minWidth: 44, minHeight: 44)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play \(song.title)")
                        .downtifyCurrentRowAccessibility(isCurrent: isCurrent, isPlaying: nowPlaying.isPlaying)
                        .accessibilityIdentifier("catalog.result.\(song.id)")
                        .disabled(song.source == "library" && song.libraryTrack(in: library.tracks) == nil)
                        if song.source != "library", catalog.externalCatalogAvailable {
                            serverDownloadButton(for: song)
                        }
                        deviceButton(for: song)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func currentTitle(_ title: String, isCurrent: Bool, isPlaying: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if isCurrent { NowPlayingBadge(isPlaying: isPlaying) }
            Text(title).font(.body.weight(.semibold))
                .foregroundStyle(isCurrent ? AnyShapeStyle(DowntifyStyle.accent) : AnyShapeStyle(.primary))
        }
    }

    private var linkResolver: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Resolve a link")
            HStack {
                TextField("Paste a music link", text: $link)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Music link to resolve")
                Button("Resolve") { catalog.resolveURL(link.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            switch catalog.urlResolutionState {
            case .loading: ProgressView("Resolving link…")
            case .failed(let message), .unavailable(let message): Text(message).foregroundStyle(.secondary)
            case .loaded(let resolution), .partial(let resolution, _):
                Text(resolution.name).font(.headline)
                Text(resolution.subtitle).font(.subheadline).foregroundStyle(.secondary)
                songResults(resolution.tracks)
                if !resolution.albums.isEmpty {
                    sectionHeader("Albums in this link")
                    ForEach(resolution.albums) { album in
                        HStack {
                            NavigationLink { albumDetail(album) } label: {
                                Label("\(album.title) · \(album.artist)", systemImage: "square.stack")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }.buttonStyle(.plain)
                            if canRequestAlbumDownload(album), let url = album.url {
                                serverAlbumDownloadButton(url: url, album: album)
                            }
                        }
                    }
                }
            default: EmptyView()
            }
        }
        .padding(.top, 8)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader).padding(.top, 8)
    }

    @ViewBuilder private func deviceButton(for song: CatalogSong) -> some View {
        let state = deviceState(song)
        if state != .unavailable(.notInLibrary) {
            MediaActionButton(presentation: .device(state, itemTitle: song.title)) { onAddToDevice(song) }
                .frame(width: 44, height: 44)
        }
    }

    @ViewBuilder private func serverDownloadButton(for song: CatalogSong) -> some View {
        MediaActionButton(presentation: .library(downloadState(song), itemTitle: song.title)) { onDownload(song) }
            .frame(width: 44, height: 44)
    }

    private func canRequestAlbumDownload(_ album: CatalogAlbum) -> Bool {
        guard catalog.externalCatalogAvailable, let url = album.url else { return false }
        return ServerDownloadQueue.isYouTubeMusicAlbumURL(url)
    }

    @ViewBuilder private func serverAlbumDownloadButton(url: String, album: CatalogAlbum) -> some View {
        let resolved = resolvedAlbumTracks(for: url)
        MediaActionButton(presentation: .library(albumDownloadState(album, album.trackCount ?? catalog.albumTrackCounts[album.id] ?? resolved?.count),
                                                 itemTitle: album.title)) {
            onDownloadAlbum(url, resolved)
        }
        .frame(width: 44, height: 44)
    }

    private func resolvedAlbumTracks(for url: String) -> [CatalogSong]? {
        switch catalog.finderAlbumState {
        case .loaded(let details), .partial(let details, _):
            if details.album.url == url { return details.tracks }
        default: break
        }
        switch catalog.urlResolutionState {
        case .loaded(let resolution), .partial(let resolution, _):
            return resolution.albums.count == 1 && resolution.albums.first?.url == url ? resolution.tracks : nil
        default: return nil
        }
    }
}
