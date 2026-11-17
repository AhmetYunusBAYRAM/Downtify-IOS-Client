import Foundation

struct ResetPreview: Equatable {
    let storage: DeviceStorageReport
    let pendingActionCount: Int
}

enum ResetOutcome: Equatable {
    case success(freedBytes: Int64)
    case partial(failedSteps: [String])
}

@MainActor
protocol ResettableLibrarySync {
    /// Stops background syncing and waits for in-flight work to finish.
    func pause() async
    /// Restarts syncing (if it was running before `pause`) and performs a full refresh from the server.
    func resume(refresh: Bool) async
}

@MainActor
protocol ResettablePlayback {
    func stopAndClear()
}

@MainActor
protocol ResettableOfflineDownloads {
    func removeAll() async throws
}

/// A store that can wipe its on-device data. Named `resetAll` to avoid clashing with each type's own `removeAll`.
protocol ResettableStore {
    var resetName: String { get }
    func resetAll() async throws
}

@MainActor
protocol PendingActionCounting {
    var queuedPendingActionCount: Int { get }
}

@MainActor
protocol ResettablePendingActions: PendingActionCounting {
    /// Reloads in-memory pending actions from the (now empty) database.
    func reloadAfterReset() async throws
}

/// Clears all on-device app data except the login session, then lets the app resync from the server.
@MainActor
final class AppDataReset {
    private let sync: any ResettableLibrarySync
    private let playback: any ResettablePlayback
    private let offline: any ResettableOfflineDownloads
    private let preloadCache: any ResettableStore
    private let blockCache: any ResettableStore
    private let artwork: any ResettableStore
    private let database: any ResettableStore
    private let pendingActions: any ResettablePendingActions
    private let listenOutbox: any ResettableStore
    private let savedQueues: any ResettableStore
    private let networkFailures: any ResettableStore
    private let defaults: UserDefaults
    private let roots: StorageRoots
    private let fileManager: FileManager
    private let urlCache: URLCache
    private var running = false

    static let defaultsPrefixes = ["playback.queue.", "lyrics.offset.", "pending-actions.discard."]
    static let defaultsKeys = ["debug.networkOverlay.recentFailures"]

    init(sync: any ResettableLibrarySync, playback: any ResettablePlayback, offline: any ResettableOfflineDownloads,
         preloadCache: any ResettableStore, blockCache: any ResettableStore, artwork: any ResettableStore,
         database: any ResettableStore, pendingActions: any ResettablePendingActions,
         listenOutbox: any ResettableStore, savedQueues: any ResettableStore, networkFailures: any ResettableStore,
         defaults: UserDefaults = .standard, roots: StorageRoots = .live,
         fileManager: FileManager = .default, urlCache: URLCache = .shared) {
        self.sync = sync
        self.playback = playback
        self.offline = offline
        self.preloadCache = preloadCache
        self.blockCache = blockCache
        self.artwork = artwork
        self.database = database
        self.pendingActions = pendingActions
        self.listenOutbox = listenOutbox
        self.savedQueues = savedQueues
        self.networkFailures = networkFailures
        self.defaults = defaults
        self.roots = roots
        self.fileManager = fileManager
        self.urlCache = urlCache
    }

    func preview() async -> ResetPreview {
        let storage = await StorageInspector.measure(fileManager: fileManager, roots: roots)
        return ResetPreview(storage: storage, pendingActionCount: pendingActions.queuedPendingActionCount)
    }

    func run() async -> ResetOutcome {
        guard !running else { return .partial(failedSteps: ["alreadyRunning"]) }
        running = true
        defer { running = false }
        var failed: [String] = []
        func step(_ name: String, _ work: () async throws -> Void) async {
            do { try await work() } catch { failed.append(name) }
        }

        let before = await StorageInspector.measure(fileManager: fileManager, roots: roots)
        await sync.pause()
        playback.stopAndClear()
        await step("offlineDownloads") { try await offline.removeAll() }
        for store in [preloadCache, blockCache, artwork] {
            await step(store.resetName) { try await store.resetAll() }
        }
        await step(database.resetName) { try await database.resetAll() }
        await step("pendingActions") { try await pendingActions.reloadAfterReset() }
        for store in [listenOutbox, savedQueues, networkFailures] {
            await step(store.resetName) { try await store.resetAll() }
        }
        await step("userDefaults") { clearDefaults() }
        await step("temporaryFiles") { try clearTemporaryDirectory() }
        urlCache.removeAllCachedResponses()
        let after = await StorageInspector.measure(fileManager: fileManager, roots: roots)
        await sync.resume(refresh: true)

        if failed.isEmpty { return .success(freedBytes: max(0, before.total - after.total)) }
        return .partial(failedSteps: failed)
    }

    private func clearDefaults() {
        for key in defaults.dictionaryRepresentation().keys
        where Self.defaultsPrefixes.contains(where: key.hasPrefix) || Self.defaultsKeys.contains(key) {
            defaults.removeObject(forKey: key)
        }
    }

    private func clearTemporaryDirectory() throws {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(at: roots.tmp, includingPropertiesForKeys: nil, options: [])
        } catch CocoaError.fileReadNoSuchFile {
            return
        }
        var firstError: Error?
        for entry in entries {
            do { try fileManager.removeItem(at: entry) } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }
}

// MARK: - Conformances for the real types

/// Adapts the sync coordinator and presentation model to the reset coordinator.
@MainActor
struct LibrarySyncReset: ResettableLibrarySync {
    let coordinator: LibrarySyncCoordinator
    let presentation: LibraryPresentationModel
    private let wasActive = Box()

    init(coordinator: LibrarySyncCoordinator, presentation: LibraryPresentationModel) {
        self.coordinator = coordinator
        self.presentation = presentation
    }

    @MainActor final class Box { var value = false }

    func pause() async {
        wasActive.value = await coordinator.suspendAndWait()
    }

    func resume(refresh: Bool) async {
        if refresh { await presentation.refresh() }
        if wasActive.value { coordinator.setActive(true) }
        wasActive.value = false
    }
}

extension PlaybackController: ResettablePlayback {}
extension OfflineDownloads: ResettableOfflineDownloads {}

extension LibraryCollectionsModel: ResettablePendingActions {
    var queuedPendingActionCount: Int { pendingActions.filter { $0.status == .queued }.count }
    func reloadAfterReset() async throws { try await reloadPendingActions() }
}

extension PlaybackCache: ResettableStore {
    nonisolated var resetName: String { "blockCache" }
    func resetAll() async throws { await removeAll() }
}

extension PlaybackPreloadCache: ResettableStore {
    nonisolated var resetName: String { "preloadCache" }
    func resetAll() async throws { await removeAll() }
}

extension ArtworkLoader: @MainActor ResettableStore {
    var resetName: String { "artwork" }
    func resetAll() async throws { removeAll() }
}

extension LibraryDatabase: ResettableStore {
    nonisolated var resetName: String { "libraryDatabase" }
    func resetAll() async throws { try await removeAll() }
}

extension PlaybackListenOutbox: ResettableStore {
    var resetName: String { "listenOutbox" }
    func resetAll() async throws { try removeAll() }
}

extension PlaybackStateStore: ResettableStore {
    var resetName: String { "savedQueues" }
    func resetAll() async throws { removeAllSavedQueues() }
}

extension NetworkOperationCoordinator: ResettableStore {
    nonisolated var resetName: String { "recentFailures" }
    func resetAll() async throws { clearRecentFailures() }
}
