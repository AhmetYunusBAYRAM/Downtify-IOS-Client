import SwiftUI

struct AppShellView: View {
    let name: String
    @ObservedObject var presentation: SessionPresentationCoordinator
    @ObservedObject var library: LibraryPresentationModel
    let playback: PlaybackController
    let serverDownloadQueue: ServerDownloadQueue
    let serverDownloads: ServerDownloadPresentationModel
    @AppStorage(DowntifyAppearance.storageKey) private var appearance = DowntifyAppearance.dark
    @AppStorage("downtify.language") private var language = "system"

    var body: some View {
        Group {
            switch presentation.destination {
            case .loading:
                ProgressView("Checking saved connection…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DowntifyPalette(oled: appearance == .oled).background.ignoresSafeArea())
            case let .connection(error):
                FoundationView(name: name, recoverableError: error, retryAction: presentation.retry,
                               connection: presentation.connectionService, discovery: presentation.serverDiscovery,
                               deviceName: name)
            case let .library(server):
                LibraryHomeView(server: server, library: library, playback: playback, appearance: $appearance,
                                connection: presentation.connectionService, serverDownloadQueue: serverDownloadQueue,
                                serverDownloads: serverDownloads,
                                signOut: { try await presentation.connectionService.signOut() })
            }
        }
        .downtifyAppearance(appearance)
        .environment(\.locale, Locale(identifier: language == "system" ? Locale.current.identifier : language))
        .task { presentation.start(); library.start() }
    }
}

extension LibraryTrack {
    var displayTitle: String { title.isEmpty ? String(localized: "Unknown title") : title }
    var displayArtist: String { artist.isEmpty ? String(localized: "Unknown artist") : artist }
    var accessibleMetadata: String {
        album.isEmpty ? String(localized: "\(displayTitle), \(displayArtist)")
            : String(localized: "\(displayTitle), \(displayArtist), \(album)")
    }
}

private extension PlaybackItem {
    var displayTitle: String { title.isEmpty ? String(localized: "Unknown title") : title }
    var displayArtist: String { artist.isEmpty ? String(localized: "Unknown artist") : artist }
    var accessibleMetadata: String {
        album.isEmpty ? String(localized: "\(displayTitle), \(displayArtist)")
            : String(localized: "\(displayTitle), \(displayArtist), \(album)")
    }
}

private struct PlaybackItemArtwork: View {
    let item: PlaybackItem?
    let size: CGFloat

    var body: some View {
        if let track = item?.libraryTrack {
            TrackArtwork(track: track, size: size)
        } else if let url = item?.catalogSong?.coverURL.flatMap(URL.init(string:)),
                  url.scheme?.lowercased() == "https" {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ArtworkPlaceholder(size: size)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.08, style: .continuous))
        } else {
            ArtworkPlaceholder(size: size)
        }
    }
}

struct TrackRow: View {
    let track: LibraryTrack
    var isCurrent = false
    var isPlaying = false

    var body: some View {
        DowntifyMediaRow(title: track.displayTitle, subtitle: track.displayArtist,
                         detail: track.album.isEmpty ? nil : track.album,
                         isCurrent: isCurrent, isPlaying: isPlaying) {
            TrackArtwork(track: track, size: 56)
        } accessory: {
            Text(durationText(track.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(DowntifyStyle.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Lives at the navigation boundary so playback updates do not invalidate library rows.
struct PlaybackDock: View {
    @ObservedObject var playback: PlaybackController
    /// Passed through to Now Playing's artist and album pages and its Like and Add to Playlist
    /// actions; not observed here.
    let library: LibraryPresentationModel
    let serverDownloads: ServerDownloadPresentationModel
    @Environment(\.downtifyPalette) private var palette
    @State private var showingNowPlaying = false

    var body: some View {
        Group {
            if playback.podcast != nil || playback.queue.current != nil {
                MiniPlayerView(playback: playback) { showingNowPlaying = true }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, DowntifyStyle.Space.regular)
                    .padding(.vertical, DowntifyStyle.Space.small)
                    .frame(maxWidth: .infinity)
                    .background(palette.background)
                    .accessibilityIdentifier("player.dock")
            }
        }
        .sheet(isPresented: $showingNowPlaying) {
            NowPlayingView(playback: playback, library: library, serverDownloads: serverDownloads)
                .presentationDragIndicator(.visible)
        }
    }
}

private struct MiniPlayerView: View {
    @ObservedObject var playback: PlaybackController
    let open: () -> Void
    @Environment(\.downtifyPalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var item: PlaybackItem? { playback.queue.current?.item }
    private var isActive: Bool { playback.phase == .playing || playback.phase == .buffering || playback.phase == .loading }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 4))
        layout {
            if let podcast = playback.podcast {
                Button(action: open) {
                    DowntifyMediaRow(title: podcast.episode.title, subtitle: podcast.show.name, accessibilityLineLimit: 2) {
                        PodcastArtwork(show: podcast.show, size: 44)
                    } accessory: { EmptyView() }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now playing, \(podcast.episode.title), \(podcast.show.name)")
                .accessibilityHint("Open Now Playing")
            } else if let item {
                Button(action: open) {
                    DowntifyMediaRow(title: item.displayTitle, subtitle: item.displayArtist, accessibilityLineLimit: 2) {
                        PlaybackItemArtwork(item: item, size: 44)
                    } accessory: {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now playing, \(item.displayTitle) by \(item.displayArtist)")
                .accessibilityHint("Open Now Playing")
            }
            HStack(spacing: 4) {
                if case .failed = playback.phase {
                    Button { playback.play() } label: {
                        Image(systemName: "arrow.clockwise").downtifyControlTarget()
                    }
                    .accessibilityLabel("Retry playback")
                } else {
                    Button { playback.togglePlayback() } label: {
                        Image(systemName: isActive ? "pause.fill" : "play.fill")
                            .downtifyControlTarget()
                    }
                    .accessibilityLabel(isActive ? String(localized: "Pause") : String(localized: "Play"))
                    .accessibilityIdentifier("player.playPause")
                }
                if playback.podcast == nil {
                    Button { playback.skipNext() } label: {
                        Image(systemName: "forward.end.fill").downtifyControlTarget()
                    }
                    .accessibilityLabel("Next track")
                    .disabled(playback.queue.next(automatic: false) == nil)
                }
            }
            .font(.body.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottom) {
            if let duration = playback.duration, duration.isFinite, duration > 0 {
                ProgressView(value: min(playback.position, duration), total: duration)
                    .padding(.horizontal, 12)
                    .accessibilityHidden(true)
                    .transaction { if reduceMotion { $0.animation = nil } }
            }
        }
    }
}

/// Storage for per-track lyric offsets. Defaults to `.standard`; debug harness injects an isolated suite at the root.
private struct LyricDefaultsKey: EnvironmentKey {
    static let defaultValue: UserDefaults = .standard
}

extension EnvironmentValues {
    var lyricDefaults: UserDefaults {
        get { self[LyricDefaultsKey.self] }
        set { self[LyricDefaultsKey.self] = newValue }
    }
}

private struct NowPlayingView: View {
    @ObservedObject var playback: PlaybackController
    let library: LibraryPresentationModel
    let serverDownloads: ServerDownloadPresentationModel
    @State private var path: [NowPlayingRoute] = []
    @State private var artistChoices: [NowPlayingArtistTarget] = []
    @EnvironmentObject private var collections: LibraryCollectionsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingPlaylistPicker = false
    @State private var confirmation: String?
    @State private var confirmationCount = 0
    @AppStorage("debug.networkOverlay.enabled") private var networkOverlayEnabled = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.downtifyPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var showingQueue = false
    @State private var lyrics: TrackLyrics?
    @State private var lyricsLoading = false
    @State private var lyricsError = false
    @State private var lyricOffset: Double = 0
    @Environment(\.lyricDefaults) private var lyricDefaults

    private var item: PlaybackItem? { playback.queue.current?.item }
    private var track: LibraryTrack? { item?.libraryTrack }
    /// The library track behind the current item, including catalog songs already in the library.
    private var actionTrack: LibraryTrack? {
        if let track { return track }
        guard let song = item?.catalogSong else { return nil }
        return library.membership.track(for: song)
    }
    private var upNext: UpNextSummary? { UpNextSummary(queue: playback.queue) }
    private var activelyPlaying: Bool { playback.phase == .playing || playback.phase == .buffering || playback.phase == .loading }

    private var usesWideLayout: Bool {
        horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .topTrailing) {
            ScrollView {
                let layout = usesWideLayout
                    ? AnyLayout(HStackLayout(alignment: .center, spacing: DowntifyStyle.Space.large))
                    : AnyLayout(VStackLayout(spacing: DowntifyStyle.Space.large))
                layout {
                    Group {
                        if let podcast = playback.podcast {
                            PodcastArtwork(show: podcast.show, size: artworkSize)
                        } else {
                            PlaybackItemArtwork(item: item, size: artworkSize)
                        }
                    }
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("player.artwork")
                    VStack(spacing: DowntifyStyle.Space.regular) {
                        trackMetadata
                        phaseDescription
                            .font(.subheadline)
                            .foregroundStyle(DowntifyStyle.secondaryText)
                            .multilineTextAlignment(.center)
                        timeline
                        transportControls
                        if playback.podcast == nil {
                            actionRow
                            queueControls
                            upNextCard
                            if track != nil { lyricsSection }
                        } else {
                            if playback.podcastProgressSaveFailed {
                                Text("Could not save playback progress to the server.")
                                    .font(.footnote)
                                    .foregroundStyle(DowntifyStyle.error)
                            }
                            if item != nil {
                                Button("Back to music", systemImage: "music.note") { playback.returnToMusic() }
                            }
                        }
                    }
                    .frame(maxWidth: 400)
                }
                .padding(DowntifyStyle.Space.regular)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            if networkOverlayEnabled {
                NetworkDebugOverlayContainer(playback: playback)
            }
            }
            .overlay(alignment: .bottom) { confirmationBanner }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("Now Playing")
            .accessibilityIdentifier("player.full")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: NowPlayingRoute.self) { route in
                Group {
                    switch route {
                    case .artist(let target):
                        NowPlayingArtistPage(target: target, library: library, playback: playback,
                                             serverDownloads: serverDownloads)
                    case .album(let target):
                        NowPlayingAlbumPage(target: target, library: library, playback: playback,
                                            serverDownloads: serverDownloads)
                    }
                }
                .toolbarBackground(palette.background, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .confirmationDialog("Go to artist", isPresented: Binding(get: { !artistChoices.isEmpty },
                                                                     set: { if !$0 { artistChoices = [] } }),
                                titleVisibility: .visible) {
                ForEach(artistChoices, id: \.self) { target in
                    Button(target.name) { path.append(.artist(target)) }
                }
            }
        }
        .sheet(isPresented: $showingQueue) {
            PlaybackQueueSheet(playback: playback)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPlaylistPicker) {
            if let actionTrack {
                AddToPlaylistSheet(track: actionTrack) { title in
                    showConfirmation(String(localized: "Added to \(title)"))
                }
                .presentationDragIndicator(.visible)
                .presentationDetents([.medium, .large])
            }
        }
        .sensoryFeedback(.success, trigger: confirmationCount)
        .task(id: confirmationCount) {
            guard confirmation != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut) { confirmation = nil }
        }
        .task(id: track?.id) { await loadLyrics() }
    }

    @ViewBuilder
    private var trackMetadata: some View {
        if playback.podcast == nil, let item {
            musicMetadata(item)
        } else {
            VStack(spacing: 5) {
                Text(playback.podcast?.episode.title ?? item?.displayTitle ?? String(localized: "Unknown title"))
                    .font(.title2.weight(.bold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .accessibilityAddTraits(.isHeader)
                Text(playback.podcast?.show.name ?? item?.displayArtist ?? String(localized: "Unknown artist"))
                    .font(.title3)
                    .foregroundStyle(DowntifyStyle.secondaryText)
                if let album = playback.podcast?.show.author, !album.isEmpty {
                    Text(album)
                        .font(.subheadline)
                        .foregroundStyle(DowntifyStyle.secondaryText)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }

    /// Title and album open the album page, the artist opens the artist page.
    /// Targets resolve at tap time so this sheet never observes the library.
    private func musicMetadata(_ item: PlaybackItem) -> some View {
        let hasAlbum = !item.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasArtist = !item.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || item.artists.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return VStack(spacing: 5) {
            Button { openAlbum(item) } label: {
                Text(item.displayTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            .disabled(!hasAlbum)
            .accessibilityLabel(item.displayTitle)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(hasAlbum ? String(localized: "Opens the album page") : "")
            .accessibilityIdentifier("player.title")
            Button { openArtist(item) } label: {
                Text(item.displayArtist)
                    .font(.title3)
                    .foregroundStyle(hasArtist ? DowntifyStyle.accent : DowntifyStyle.secondaryText)
            }
            .disabled(!hasArtist)
            .accessibilityLabel("Artist, \(item.displayArtist)")
            .accessibilityHint(hasArtist ? String(localized: "Opens the artist page") : "")
            .accessibilityIdentifier("player.artist")
            if hasAlbum {
                Button { openAlbum(item) } label: {
                    Text(item.album)
                        .font(.subheadline)
                        .foregroundStyle(DowntifyStyle.secondaryText)
                        .underline()
                }
                .accessibilityLabel("Album, \(item.album)")
                .accessibilityHint("Opens the album page")
                .accessibilityIdentifier("player.album")
            }
        }
        .buttonStyle(.plain)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func openAlbum(_ item: PlaybackItem) {
        guard let target = NowPlayingNavigationResolver.albumTarget(for: item, catalog: library.catalog) else { return }
        path.append(.album(target))
    }

    private func openArtist(_ item: PlaybackItem) {
        let targets = NowPlayingNavigationResolver.artistTargets(for: item, catalog: library.catalog)
        if targets.count == 1 {
            path.append(.artist(targets[0]))
        } else if targets.count > 1 {
            artistChoices = targets
        }
    }

    private var transportControls: some View {
        HStack(spacing: DowntifyStyle.Space.regular) {
            if playback.podcast != nil {
                Button { playback.seek(to: playback.position - 15) } label: {
                    Image(systemName: "gobackward.15").font(.title2).downtifyControlTarget()
                }
                .accessibilityLabel("Back 15 seconds")
            } else {
                Button { playback.skipPrevious() } label: {
                    Image(systemName: "backward.end.fill").font(.title2)
                        .downtifyControlTarget()
                }
                .accessibilityLabel("Previous track")
                .disabled(item == nil)
            }
            if case .failed = playback.phase {
                Button { playback.play() } label: {
                    Image(systemName: "arrow.clockwise.circle.fill").font(.system(size: 56))
                        .downtifyControlTarget()
                }
                .accessibilityLabel("Retry playback")
            } else {
                Button { playback.togglePlayback() } label: {
                    Image(systemName: activelyPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56)).downtifyControlTarget()
                }
                .accessibilityLabel(activelyPlaying ? String(localized: "Pause") : String(localized: "Play"))
                .accessibilityIdentifier("player.playPause")
                .disabled(item == nil && playback.podcast == nil)
            }
            if playback.podcast != nil {
                Button { playback.seek(to: playback.position + 30) } label: {
                    Image(systemName: "goforward.30").font(.title2).downtifyControlTarget()
                }
                .accessibilityLabel("Forward 30 seconds")
            } else {
                Button { playback.skipNext() } label: {
                    Image(systemName: "forward.end.fill").font(.title2)
                        .downtifyControlTarget()
                }
                .accessibilityLabel("Next track")
                .accessibilityValue(nextTrackValue)
                .disabled(playback.queue.next(automatic: false) == nil)
            }
        }
        .buttonStyle(.borderless)
    }

    private var nextTrackValue: String {
        guard let title = upNext?.entry.item.displayTitle else { return "" }
        return String(localized: "Next track: \(title)")
    }

    private var queueControls: some View {
        HStack(spacing: DowntifyStyle.Space.regular) {
            Button { playback.setShuffle(playback.queue.shuffledIDs == nil) } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(playback.queue.shuffledIDs == nil ? DowntifyStyle.secondaryText : DowntifyStyle.accent)
                    .downtifyControlTarget()
                    .background {
                        if playback.queue.shuffledIDs != nil {
                            RoundedRectangle(cornerRadius: 10).strokeBorder(DowntifyStyle.accent)
                        }
                    }
            }
            .accessibilityLabel("Shuffle")
            .accessibilityValue(playback.queue.shuffledIDs == nil ? String(localized: "Off") : String(localized: "On"))
            .accessibilityAddTraits(playback.queue.shuffledIDs == nil ? [] : .isSelected)

            Button { playback.setRepeat(nextRepeatMode) } label: {
                Image(systemName: repeatSymbol)
                    .foregroundStyle(playback.queue.repeatMode == .off ? DowntifyStyle.secondaryText : DowntifyStyle.accent)
                    .downtifyControlTarget()
                    .background {
                        if playback.queue.repeatMode != .off {
                            RoundedRectangle(cornerRadius: 10).strokeBorder(DowntifyStyle.accent)
                        }
                    }
            }
            .accessibilityLabel("Repeat")
            .accessibilityValue(repeatDescription)
            .accessibilityHint("Changes repeat mode")
        }
        .buttonStyle(.borderless)
        .font(.title3)
    }

    private var likePresentation: NowPlayingLikePresentation {
        NowPlayingLikePresentation.make(
            itemTitle: item?.displayTitle ?? "", isInLibrary: actionTrack != nil,
            likesAvailable: collections.likedIDs != nil,
            liked: actionTrack.map { collections.effectiveLike($0.id) } ?? false,
            pending: actionTrack.map { collections.hasPendingLike($0.id) } ?? false,
            busy: collections.mutationBusy)
    }

    private var playlistPresentation: NowPlayingPlaylistPresentation {
        NowPlayingPlaylistPresentation.make(
            itemTitle: item?.displayTitle ?? "", isInLibrary: actionTrack != nil,
            supportsEditing: collections.supportsPlaylistEditing,
            editablePlaylistCount: EditablePlaylists.sorted(
                collections.playlists, supportsEditing: collections.supportsPlaylistEditing).count,
            busy: collections.mutationBusy)
    }

    /// Labeled actions so Like, Add to Playlist and the queue are visible without guessing at icons.
    private var actionRow: some View {
        let like = likePresentation
        let playlist = playlistPresentation
        var explanations: [String] = []
        for explanation in [like.explanation, playlist.explanation].compactMap({ $0 }) where !explanations.contains(explanation) {
            explanations.append(explanation)
        }
        return VStack(spacing: DowntifyStyle.Space.small) {
            HStack(alignment: .top, spacing: DowntifyStyle.Space.small) {
                NowPlayingActionButton(title: like.title, systemImage: like.systemImage,
                                       isHighlighted: like.isLiked, showsPending: like.isPending) {
                    guard let actionTrack else { return }
                    Task { await collections.toggleLike(actionTrack) }
                }
                .disabled(!like.isEnabled)
                .accessibilityLabel(Text(verbatim: like.accessibilityLabel))
                .accessibilityValue(like.isPending ? String(localized: "Queued") : "")
                .accessibilityHint(Text(verbatim: like.explanation ?? ""))
                .accessibilityIdentifier("player.like")
                .sensoryFeedback(.selection, trigger: like.isLiked)

                NowPlayingActionButton(title: String(localized: "Add to Playlist"), systemImage: "text.badge.plus") {
                    showingPlaylistPicker = true
                }
                .disabled(!playlist.isEnabled)
                .accessibilityLabel(Text(verbatim: playlist.accessibilityLabel))
                .accessibilityHint(Text(verbatim: playlist.explanation ?? ""))
                .accessibilityIdentifier("player.addToPlaylist")

                NowPlayingActionButton(title: String(localized: "Queue"), systemImage: "list.bullet") {
                    showingQueue = true
                }
                .accessibilityHint("Open queue")
                .accessibilityIdentifier("player.queue")
            }
            if !explanations.isEmpty {
                Text(verbatim: explanations.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(DowntifyStyle.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Shows what plays next; tapping opens the full queue.
    private var upNextCard: some View {
        Button { showingQueue = true } label: {
            HStack(spacing: DowntifyStyle.Space.small) {
                VStack(alignment: .leading, spacing: DowntifyStyle.Space.small) {
                    Text("Up Next")
                        .font(.headline)
                    if let upNext {
                        DowntifyMediaRow(title: upNext.entry.item.displayTitle, subtitle: upNext.entry.item.displayArtist,
                                         accessibilityLineLimit: 2) {
                            PlaybackItemArtwork(item: upNext.entry.item, size: 44)
                        } accessory: { EmptyView() }
                        if upNext.wrapsToStart {
                            Text("Then back to the start")
                                .font(.caption).foregroundStyle(DowntifyStyle.secondaryText)
                        } else if upNext.laterCount > 0 {
                            Text("\(Int(upNext.laterCount)) more in queue")
                                .font(.caption).foregroundStyle(DowntifyStyle.secondaryText)
                        }
                    } else {
                        Text("Nothing up next")
                            .font(.subheadline).foregroundStyle(DowntifyStyle.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DowntifyStyle.secondaryText)
            }
            .padding(DowntifyStyle.Space.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: upNextAccessibilityLabel))
        .accessibilityHint("Open queue")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("player.upNext")
    }

    private var upNextAccessibilityLabel: String {
        guard let entry = upNext?.entry else { return String(localized: "Nothing up next") }
        let title = entry.item.displayTitle
        let artist = entry.item.displayArtist
        return String(localized: "Up Next: \(title) by \(artist)")
    }

    @ViewBuilder
    private var confirmationBanner: some View {
        if let confirmation {
            Label { Text(verbatim: confirmation) } icon: { Image(systemName: "checkmark.circle.fill") }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, DowntifyStyle.Space.regular)
                .padding(.vertical, DowntifyStyle.Space.small)
                .background(palette.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(DowntifyStyle.accent.opacity(0.4)))
                .padding(.bottom, DowntifyStyle.Space.large)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("player.confirmation")
        }
    }

    private func showConfirmation(_ message: String) {
        withAnimation(reduceMotion ? nil : .spring) { confirmation = message }
        confirmationCount += 1
        AccessibilityNotification.Announcement(message).post()
    }

    private var nextRepeatMode: PlaybackRepeat {
        switch playback.queue.repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    private var repeatSymbol: String {
        playback.queue.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private var repeatDescription: String {
        switch playback.queue.repeatMode {
        case .off: "Off"
        case .all: "All"
        case .one: "One"
        }
    }

    private var artworkSize: CGFloat {
        if usesWideLayout { return 200 }
        return dynamicTypeSize.isAccessibilitySize ? 172 : 240
    }

    private var lyricsSection: some View {
        VStack(alignment: .leading, spacing: DowntifyStyle.Space.small) {
            HStack {
                Label("Lyrics", systemImage: "quote.bubble")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if lyrics?.lines.isEmpty == false {
                    HStack(spacing: 4) {
                        Button { setLyricOffset(lyricOffset - 0.5) } label: {
                            Image(systemName: "minus").downtifyControlTarget()
                        }.accessibilityLabel("Lyrics earlier by half a second")
                        Text("\(lyricOffset, format: .number.precision(.fractionLength(1)))s")
                            .font(.caption.monospacedDigit())
                            .accessibilityLabel("Lyrics offset \(lyricOffset, format: .number.precision(.fractionLength(1))) seconds")
                        Button { setLyricOffset(lyricOffset + 0.5) } label: {
                            Image(systemName: "plus").downtifyControlTarget()
                        }.accessibilityLabel("Lyrics later by half a second")
                    }
                    .buttonStyle(.borderless)
                }
            }
            if lyricsLoading {
                ProgressView("Loading lyrics…")
            } else if let lyrics, !lyrics.lines.isEmpty {
                let active = activeLyricIndex(lyrics.lines)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(index == active ? .title3.weight(.bold) : .body)
                            .foregroundStyle(index == active ? DowntifyStyle.accent : DowntifyStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(index == active ? .isSelected : [])
                    }
                }
                .accessibilityElement(children: .contain)
            } else if let lyrics, !lyrics.plain.isEmpty {
                Text(lyrics.plain)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Plain lyrics")
            } else {
                Text(lyricsError ? String(localized: "Lyrics could not be loaded.") : String(localized: "Lyrics are unavailable for this track."))
                    .font(.subheadline)
                    .foregroundStyle(DowntifyStyle.secondaryText)
                if lyricsError {
                    Button("Retry") { Task { await loadLyrics() } }
                }
            }
        }
        .padding(DowntifyStyle.Space.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func loadLyrics() async {
        guard let track else { lyrics = nil; return }
        lyricsLoading = true
        lyricsError = false
        lyricOffset = lyricDefaults.double(forKey: playback.lyricsOffsetKey(trackID: track.id))
        defer { lyricsLoading = false }
        do { lyrics = try await playback.lyrics(for: track.id) }
        catch { if !Task.isCancelled { lyricsError = true; lyrics = nil } }
    }

    private func setLyricOffset(_ value: Double) {
        lyricOffset = min(10, max(-10, value))
        if let track { lyricDefaults.set(lyricOffset, forKey: playback.lyricsOffsetKey(trackID: track.id)) }
    }

    private func activeLyricIndex(_ lines: [LyricLine]) -> Int? {
        lines.lastIndex { $0.time <= playback.position - lyricOffset }
    }

    @ViewBuilder
    private var phaseDescription: some View {
        switch playback.phase {
        case .idle: Text("Ready")
        case .loading: Label(playback.podcast == nil ? String(localized: "Loading track") : String(localized: "Loading episode"), systemImage: "hourglass")
        case .paused: Text("Paused")
        case .playing: Label("Playing", systemImage: "waveform")
        case .buffering: Label("Buffering", systemImage: "waveform")
        case .ended: Text("Finished")
        case .failed(let failure):
            Label(playbackFailureMessage(failure, isPodcast: playback.podcast != nil), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(DowntifyStyle.error)
        }
    }

    private var timeline: some View {
        VStack(spacing: 5) {
            if let duration = playback.duration, duration.isFinite, duration > 0 {
                Slider(value: Binding(get: { min(playback.position, duration) }, set: { playback.seek(to: $0, checkpoint: false) }),
                       in: 0...duration, onEditingChanged: { if !$0 { playback.finishScrubbing() } })
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(spokenDuration(playback.position)) of \(spokenDuration(duration))")
                HStack {
                    Text(durationText(playback.position))
                    Spacer()
                    Text("−\(durationText(max(0, duration - playback.position)))")
                }
                .font(.caption.monospacedDigit()).foregroundStyle(DowntifyStyle.secondaryText)
            } else {
                Text("Duration unavailable")
                    .font(.caption).foregroundStyle(DowntifyStyle.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Slider(value: .constant(0), in: 0...1).disabled(true)
                    .accessibilityLabel("Playback position unavailable")
            }
        }
    }
}

/// Icon over a short label; keeps the 44 pt target and wraps at large Dynamic Type sizes.
private struct NowPlayingActionButton: View {
    let title: String
    let systemImage: String
    var isHighlighted = false
    var showsPending = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(height: 28)
                    .overlay(alignment: .topTrailing) {
                        if showsPending {
                            Image(systemName: "clock.fill")
                                .font(.caption2)
                                .offset(x: 8, y: -6)
                        }
                    }
                Text(verbatim: title)
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isHighlighted ? DowntifyStyle.accent : (isEnabled ? Color.primary : DowntifyStyle.secondaryText))
            .frame(maxWidth: .infinity, minHeight: DowntifyStyle.minimumControlSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

private struct PlaybackQueueSheet: View {
    @ObservedObject var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.downtifyPalette) private var palette

    private var visibleEntries: [PlaybackQueueEntry] {
        guard let currentIndex = playback.queue.currentIndex else { return [] }
        return Array(playback.queue.order.dropFirst(currentIndex))
    }

    private var upcomingEntries: [PlaybackQueueEntry] { Array(visibleEntries.dropFirst()) }

    var body: some View {
        NavigationStack {
            List {
                if visibleEntries.isEmpty {
                    DowntifyUnavailableView(title: "Queue is empty", symbol: "music.note.list")
                        .listRowBackground(palette.surface)
                } else {
                    if let current = visibleEntries.first {
                        QueueEntryRow(entry: current, isCurrent: true, playback: playback)
                            .listRowBackground(palette.surface)
                    }
                    ForEach(upcomingEntries) { entry in
                        QueueEntryRow(entry: entry, isCurrent: false, playback: playback)
                            .listRowBackground(palette.surface)
                    }
                    .onMove(perform: moveEntries)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
            .toolbarBackground(palette.background, for: .navigationBar)
            .navigationTitle("Play Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton().disabled(visibleEntries.count < 2) }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func moveEntries(from source: IndexSet, to destination: Int) {
        let countBeforeDestination = source.filter { $0 < destination }.count
        let finalDestination = max(0, min(upcomingEntries.count - source.count, destination - countBeforeDestination))
        var reordered = upcomingEntries.map(\.id)
        let moved = source.sorted().map { reordered[$0] }
        for index in source.sorted(by: >) { reordered.remove(at: index) }
        reordered.insert(contentsOf: moved, at: finalDestination)
        guard let startIndex = playback.queue.currentIndex else { return }
        // Resolve each target by UUID so duplicate tracks remain distinct.
        for (offset, id) in reordered.enumerated() {
            playback.move(id, to: startIndex + 1 + offset)
        }
    }
}

private struct QueueEntryRow: View {
    let entry: PlaybackQueueEntry
    let isCurrent: Bool
    @ObservedObject var playback: PlaybackController

    var body: some View {
        HStack(spacing: DowntifyStyle.Space.small) {
            Button { playback.select(entry.id) } label: {
                DowntifyMediaRow(title: entry.item.displayTitle, subtitle: entry.item.displayArtist) {
                    PlaybackItemArtwork(item: entry.item, size: 44)
                } accessory: {
                    if isCurrent {
                        Label("Current track", systemImage: "speaker.wave.2.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(DowntifyStyle.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(entry.item.accessibleMetadata))
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            .accessibilityHint(isCurrent ? String(localized: "Current queue entry") : String(localized: "Play this queue entry"))

            Button(role: .destructive) { playback.remove(entry.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(DowntifyStyle.secondaryText)
                    .downtifyControlTarget()
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(entry.item.displayTitle) from queue")
        }
        .padding(.vertical, 3)
    }
}

@MainActor
final class ArtworkLoader: ObservableObject {
    #if DEBUG
    /// Successful image loads; read by the debug state probe only.
    nonisolated(unsafe) static var debugLoadCount = 0
    #endif
    private let connection: ConnectionService
    private let transport: any HTTPDataLoading
    private let cache = NSCache<NSString, UIImage>()
    private var cachedSession: DeviceSession?

    init(connection: ConnectionService, transport: any HTTPDataLoading = ConnectionHTTPTransport()) {
        self.connection = connection
        self.transport = transport
        cache.countLimit = 200
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func removeAll() {
        cache.removeAllObjects()
        cachedSession = nil
    }

    func image(for track: LibraryTrack, size: Int) async -> UIImage? {
        guard track.hasCover, !track.id.isEmpty else { return nil }
        return await image(key: "track:\(track.id):\(size)") { address in
            let url = address.url(for: "/api/v1/tracks").appendingPathComponent(track.id).appendingPathComponent("cover")
            return (url, URLQueryItem(name: "size", value: String(size)))
        }
    }

    /// The largest cover already in memory for this track at any requested size, without a network request.
    func cachedImage(for track: LibraryTrack) -> UIImage? {
        guard track.hasCover, !track.id.isEmpty, cachedSession != nil else { return nil }
        return [600, 150].lazy.compactMap { self.cache.object(forKey: "track:\(track.id):\($0)" as NSString) }.first
    }

    func playlistImage(file: String) async -> UIImage? {
        guard !file.isEmpty else { return nil }
        return await image(key: "playlist:\(file)") { address in
            (address.url(for: "/playlist-cover"), URLQueryItem(name: "file", value: file))
        }
    }

    private func image(key: String, route: (ServerAddress) -> (URL, URLQueryItem)) async -> UIImage? {
        do {
            guard let session = try await connection.restoreSession() else {
                cache.removeAllObjects()
                cachedSession = nil
                return nil
            }
            if cachedSession != session {
                cache.removeAllObjects()
                cachedSession = session
            }
            if let image = cache.object(forKey: key as NSString) { return image }
            let address = try await LibraryAPIClient(transport: transport).verifiedAddress(for: session)
            let (url, query) = route(address)
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            components.queryItems = [query]
            guard let requestURL = components.url else { return nil }
            var request = URLRequest(url: requestURL)
            request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
            request.setValue("image/jpeg", forHTTPHeaderField: "Accept")
            let data = try await APIClient(session: transport, allowsInsecureRequests: session.allowsInsecureHTTP)
                .send(request, to: address)
            guard !Task.isCancelled, try await connection.restoreSession() == session,
                  cachedSession == session, let image = UIImage(data: data) else { return nil }
            cache.setObject(image, forKey: key as NSString, cost: data.count)
            #if DEBUG
            ArtworkLoader.debugLoadCount += 1
            #endif
            return image
        } catch {
            return nil
        }
    }
}

struct TrackArtwork: View {
    let track: LibraryTrack?
    let size: CGFloat
    var playlistCover: String? = nil
    @EnvironmentObject private var artwork: ArtworkLoader
    @State private var image: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct ArtworkRequest: Equatable {
        let track: LibraryTrack?
        let cover: String?
        let size: Int
    }

    private var requestSize: Int { size > 150 ? 600 : 150 }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.08, style: .continuous))
                    .transition(.opacity)
            } else {
                ArtworkPlaceholder(size: size)
                    .transition(.opacity)
            }
        }
        .task(id: ArtworkRequest(track: track, cover: playlistCover, size: requestSize)) {
            image = nil
            var loadedImage: UIImage?
            if let playlistCover, !playlistCover.isEmpty {
                loadedImage = await artwork.playlistImage(file: playlistCover)
            }
            if loadedImage == nil, let track, track.hasCover, !Task.isCancelled {
                loadedImage = await artwork.image(for: track, size: requestSize)
            }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.18)) {
                image = loadedImage
            }
        }
    }
}

private struct ArtworkPlaceholder: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(LinearGradient(colors: [DowntifyStyle.accent.opacity(0.25), DowntifyStyle.accent.opacity(0.08)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "music.note")
                .font(.system(size: size * 0.30, weight: .light))
                .foregroundStyle(DowntifyStyle.accent)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

func playbackFailureMessage(_ failure: PlaybackFailure, isPodcast: Bool = false) -> LocalizedStringKey {
    switch failure {
    case .signedOut: "Sign in to play this track"
    case .differentServer: isPodcast ? "This episode belongs to a different server" : "This track belongs to a different server"
    case .insecureAddress: "The server connection is not secure"
    case .unauthorized: "Your session needs to be refreshed"
    case .network: "Could not reach the server"
    case .invalidStream: "The audio stream is unavailable"
    case .unsupportedFormat: "This audio format is unsupported"
    case .media: isPodcast ? "Could not play this episode" : "Could not play this track"
    case .audioSession: "Audio playback could not start"
    }
}

private func durationText(_ duration: Double) -> String {
    guard duration >= 0, let seconds = Int(exactly: duration.rounded()) else { return "—:—" }
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
}

func spokenDuration(_ duration: Double) -> String {
    guard duration >= 0, let seconds = Int(exactly: duration.rounded()) else {
        return String(localized: "Duration unavailable")
    }
    return Duration.seconds(seconds)
        .formatted(.units(allowed: [.minutes, .seconds], width: .wide, zeroValueUnits: .show(length: 1)))
}

#if DEBUG
private struct LibraryDesignPreviews: PreviewProvider {
    private static let sample = LibraryTrack(
        id: "preview-track", file: "", title: "On the Other Side of the City at Dawn",
        artist: "The Long Distance Orchestra", artists: [], album: "Quiet Streets",
        albumArtist: "", albumID: "", artistID: "", trackNumber: 1, year: "", duration: 223,
        codec: "", bitrate: 0, sampleRate: 0, channels: 0, size: 0, added: 0,
        hasCover: false, isExplicit: false, playlists: []
    )

    static var previews: some View {
        Group {
            NavigationStack {
                ScrollView {
                    DowntifyCard { TrackRow(track: sample) }
                        .padding()
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                }
                .background(DowntifyPalette().background)
                .navigationTitle("Library")
            }
            .downtifyAppearance(.light)
            .environmentObject(ArtworkLoader(connection: ConnectionService()))
            .previewDisplayName("Library row · Light")

            NavigationStack {
                ScrollView {
                    VStack {
                        DowntifyCard { TrackRow(track: sample) }
                        DowntifyUnavailableView(title: "Library unavailable", symbol: "exclamationmark.triangle",
                                                message: Text("The server could not be reached."), retry: {})
                    }
                    .padding()
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .background(Color.black)
                .navigationTitle("Library")
            }
            .downtifyAppearance(.oled)
            .environmentObject(ArtworkLoader(connection: ConnectionService()))
            .dynamicTypeSize(.accessibility3)
            .previewDisplayName("Library error · OLED, Large Type")
        }
    }
}
#endif
