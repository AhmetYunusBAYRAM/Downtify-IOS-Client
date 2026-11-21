import AVFoundation
import Foundation
import MediaPlayer
import Network
import UIKit

enum PlaybackAudioEvent {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case outputDisconnected
    case mediaServicesReset
}

@MainActor
protocol PlaybackAudioSession: AnyObject {
    var onEvent: ((PlaybackAudioEvent) -> Void)? { get set }
    func activate() throws
    func deactivate()
}

@MainActor
final class SystemPlaybackAudioSession: PlaybackAudioSession {
    var onEvent: ((PlaybackAudioEvent) -> Void)?
    private let session: AVAudioSession
    private let notifications: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var active = false

    init(session: AVAudioSession = .sharedInstance(), notifications: NotificationCenter = .default) {
        self.session = session
        self.notifications = notifications
        observe(AVAudioSession.interruptionNotification) { [weak self] info in
            guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self?.active = false
                self?.onEvent?(.interruptionBegan)
            } else {
                let rawOptions = info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let resume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                self?.onEvent?(.interruptionEnded(shouldResume: resume))
            }
        }
        observe(AVAudioSession.routeChangeNotification) { [weak self] info in
            let rawReason = info?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if rawReason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                self?.onEvent?(.outputDisconnected)
            }
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            self?.active = false
            self?.onEvent?(.mediaServicesReset)
        }
    }

    deinit { observers.forEach(notifications.removeObserver) }

    func activate() throws {
        guard !active else { return }
        // The playback category supplies Bluetooth A2DP and AirPlay routes through the system.
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        active = true
    }

    func deactivate() {
        guard active else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            active = false
        } catch {
            // A subsequent pause can retry deactivating this session.
        }
    }

    private func observe(_ name: Notification.Name, action: @escaping @MainActor ([AnyHashable: Any]?) -> Void) {
        observers.append(notifications.addObserver(forName: name, object: session, queue: .main) { notification in
            MainActor.assumeIsolated { action(notification.userInfo) }
        })
    }
}

enum PlaybackRemoteCommand {
    case play, pause, toggle, next, previous
    case seek(TimeInterval)
}

struct PlaybackMetadata {
    let item: PlaybackItem?
    var track: LibraryTrack? { item?.libraryTrack }
    var podcast: PodcastSelection? = nil
    var title: String { podcast?.episode.title ?? item?.title ?? "" }
    var artist: String { podcast?.show.author ?? item?.artist ?? "" }
    var album: String { podcast?.show.name ?? item?.album ?? "" }
    let position: TimeInterval
    let duration: TimeInterval?
    let isPlaying: Bool
    let wantsPlayback: Bool
    let queueIndex: Int
    let queueCount: Int
    let canSkipNext: Bool
    let canSkipPrevious: Bool

}

@MainActor
protocol PlaybackRemoteControlling: AnyObject {
    var onCommand: ((PlaybackRemoteCommand) -> Void)? { get set }
    func publish(_ metadata: PlaybackMetadata?)
}

/// Where the lock screen artwork for the current item comes from.
enum NowPlayingArtworkSource: Equatable {
    /// A library track's cover, served by the paired server.
    case track(LibraryTrack)
    /// A catalog song's or podcast's https cover on a third-party host.
    case remote(URL)

    init?(_ metadata: PlaybackMetadata) {
        if let podcast = metadata.podcast {
            guard let url = Self.httpsURL(podcast.show.artworkURL) else { return nil }
            self = .remote(url)
        } else if let track = metadata.track {
            guard track.hasCover, !track.id.isEmpty else { return nil }
            self = .track(track)
        } else if let url = Self.httpsURL(metadata.item?.catalogSong?.coverURL) {
            self = .remote(url)
        } else {
            return nil
        }
    }

    private static func httpsURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
}

@MainActor
protocol NowPlayingArtworkProviding: AnyObject {
    /// Artwork already in memory or on disk, without touching the network (so it still shows offline).
    func cachedArtwork(for source: NowPlayingArtworkSource) -> UIImage?
    /// Full-size artwork; may fetch. Returns nil on any failure.
    func artwork(for source: NowPlayingArtworkSource) async -> UIImage?
}

/// Loads lock screen artwork once per item: a cached image shows at once, the full-size load then replaces it,
/// and a load that finishes after the item changed is dropped.
@MainActor
final class NowPlayingArtworkCoordinator {
    private let provider: (any NowPlayingArtworkProviding)?
    private(set) var source: NowPlayingArtworkSource?
    private(set) var image: UIImage?
    private var task: Task<Void, Never>?
    /// Called when a load finishes for the current item after `update` returned.
    var onLoad: ((UIImage) -> Void)?

    init(provider: (any NowPlayingArtworkProviding)?) {
        self.provider = provider
    }

    deinit { task?.cancel() }

    /// Returns the image to publish for this metadata, starting a load when the item changed.
    func update(for metadata: PlaybackMetadata?) -> UIImage? {
        let next = metadata.flatMap(NowPlayingArtworkSource.init)
        guard next != source else { return image }
        task?.cancel()
        task = nil
        source = next
        image = nil
        guard let next, let provider else { return nil }
        image = provider.cachedArtwork(for: next)
        task = Task { [weak self] in
            let loaded = await provider.artwork(for: next)
            guard !Task.isCancelled, let self, self.source == next, let loaded else { return }
            self.image = loaded
            self.onLoad?(loaded)
        }
        return image
    }
}

/// Lock screen artwork from the app's own caches: the server's library covers through `ArtworkLoader`,
/// catalog and podcast covers through the shared URL cache that `AsyncImage` fills.
@MainActor
final class AppNowPlayingArtworkProvider: NowPlayingArtworkProviding {
    private static let size = 600
    private let artwork: ArtworkLoader
    private let session: URLSession

    init(artwork: ArtworkLoader, session: URLSession = .shared) {
        self.artwork = artwork
        self.session = session
    }

    func cachedArtwork(for source: NowPlayingArtworkSource) -> UIImage? {
        switch source {
        case .track(let track):
            return artwork.cachedImage(for: track)
        case .remote(let url):
            return session.configuration.urlCache?.cachedResponse(for: Self.request(url))
                .flatMap { UIImage(data: $0.data) }
        }
    }

    func artwork(for source: NowPlayingArtworkSource) async -> UIImage? {
        switch source {
        case .track(let track):
            return await artwork.image(for: track, size: Self.size)
        case .remote(let url):
            // Third-party host: never attach the server token.
            guard let (data, response) = try? await session.data(for: Self.request(url)),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { return nil }
            return UIImage(data: data)
        }
    }

    private static func request(_ url: URL) -> URLRequest {
        URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
    }
}

@MainActor
final class SystemPlaybackRemoteControls: PlaybackRemoteControlling {
    var onCommand: ((PlaybackRemoteCommand) -> Void)?
    private let commands: MPRemoteCommandCenter
    private let nowPlaying: MPNowPlayingInfoCenter
    private var targets: [(MPRemoteCommand, Any)] = []
    private let artwork: NowPlayingArtworkCoordinator
    private var publishedArtwork: (image: UIImage, artwork: MPMediaItemArtwork)?

    init(commands: MPRemoteCommandCenter = .shared(), nowPlaying: MPNowPlayingInfoCenter = .default(),
         artworkProvider: (any NowPlayingArtworkProviding)? = nil) {
        self.commands = commands
        self.nowPlaying = nowPlaying
        artwork = NowPlayingArtworkCoordinator(provider: artworkProvider)
        artwork.onLoad = { [weak self] image in self?.applyArtwork(image) }
        register(commands.playCommand) { _ in .play }
        register(commands.pauseCommand) { _ in .pause }
        register(commands.togglePlayPauseCommand) { _ in .toggle }
        register(commands.nextTrackCommand) { _ in .next }
        register(commands.previousTrackCommand) { _ in .previous }
        register(commands.changePlaybackPositionCommand) {
            ($0 as? MPChangePlaybackPositionCommandEvent).map { .seek($0.positionTime) }
        }
        publish(nil)
    }

    deinit { targets.forEach { $0.0.removeTarget($0.1) } }

    func publish(_ metadata: PlaybackMetadata?) {
        commands.playCommand.isEnabled = metadata.map { !$0.wantsPlayback } ?? false
        commands.pauseCommand.isEnabled = metadata?.wantsPlayback ?? false
        commands.togglePlayPauseCommand.isEnabled = metadata != nil
        commands.nextTrackCommand.isEnabled = metadata?.canSkipNext ?? false
        commands.previousTrackCommand.isEnabled = metadata?.canSkipPrevious ?? false
        commands.changePlaybackPositionCommand.isEnabled = metadata?.duration != nil
        let image = artwork.update(for: metadata)
        guard let metadata else {
            publishedArtwork = nil
            nowPlaying.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata.title,
            MPMediaItemPropertyArtist: metadata.artist,
            MPMediaItemPropertyAlbumTitle: metadata.album,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: metadata.position,
            MPNowPlayingInfoPropertyPlaybackRate: metadata.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: metadata.queueIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: metadata.queueCount
        ]
        info[MPMediaItemPropertyPlaybackDuration] = metadata.duration
        info[MPMediaItemPropertyArtwork] = image.map(mediaArtwork)
        nowPlaying.nowPlayingInfo = info
    }

    /// Adds artwork that finished loading after the last publish, keeping the rest of the info.
    private func applyArtwork(_ image: UIImage) {
        guard var info = nowPlaying.nowPlayingInfo else { return }
        info[MPMediaItemPropertyArtwork] = mediaArtwork(image)
        nowPlaying.nowPlayingInfo = info
    }

    /// Reuses one `MPMediaItemArtwork` per image; publish runs on every position update.
    private func mediaArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        if let publishedArtwork, publishedArtwork.image === image { return publishedArtwork.artwork }
        let artwork = Self.makeArtwork(image)
        publishedArtwork = (image, artwork)
        return artwork
    }

    /// Nonisolated so the request handler, which MediaPlayer calls off the main thread, isn't main-actor isolated.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func register(_ command: MPRemoteCommand, map: @escaping (MPRemoteCommandEvent) -> PlaybackRemoteCommand?) {
        let target = command.addTarget { [weak self] event in
            guard let action = map(event) else { return .commandFailed }
            Task { @MainActor in self?.onCommand?(action) }
            return .success
        }
        targets.append((command, target))
    }
}

@MainActor
protocol PlaybackNetworkMonitoring: AnyObject {
    func start(_ update: @escaping @MainActor (PlaybackNetwork) -> Void)
}

@MainActor
final class SystemPlaybackNetworkMonitor: PlaybackNetworkMonitoring {
    private let monitor = NWPathMonitor()

    deinit { monitor.cancel() }

    func start(_ update: @escaping @MainActor (PlaybackNetwork) -> Void) {
        monitor.pathUpdateHandler = { path in
            let network: PlaybackNetwork
            if path.status != .satisfied {
                network = .unavailable
            } else {
                network = path.usesInterfaceType(.cellular) ? .cellular : .wifiOrWired
            }
            Task { @MainActor in update(network) }
        }
        monitor.start(queue: DispatchQueue(label: "app.downtify.playback-network"))
    }
}
