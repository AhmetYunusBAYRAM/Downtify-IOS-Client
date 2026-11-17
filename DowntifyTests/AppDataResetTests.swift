import Foundation
import XCTest
@testable import Downtify

/// Ordered record of every fake call, shared by all fakes in one test.
final class CallLog: @unchecked Sendable {
    private(set) var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }
}

enum FakeFailure: Error {
    case injected
}

@MainActor
final class SyncFake: ResettableLibrarySync {
    private let log: CallLog
    var pauseNanoseconds: UInt64 = 0

    init(log: CallLog) {
        self.log = log
    }

    func pause() async {
        log.append("sync.pause")
        if pauseNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: pauseNanoseconds)
        }
    }

    func resume(refresh: Bool) async {
        log.append("sync.resume(refresh: \(refresh))")
    }
}

@MainActor
final class PlaybackFake: ResettablePlayback {
    private let log: CallLog

    init(log: CallLog) {
        self.log = log
    }

    func stopAndClear() {
        log.append("playback.stopAndClear")
    }
}

@MainActor
final class OfflineFake: ResettableOfflineDownloads {
    private let log: CallLog
    var shouldThrow = false

    init(log: CallLog) {
        self.log = log
    }

    func removeAll() async throws {
        log.append("offline.removeAll")
        if shouldThrow { throw FakeFailure.injected }
    }
}

final class StoreFake: ResettableStore {
    let resetName: String
    private let log: CallLog
    var shouldThrow = false

    init(_ resetName: String, log: CallLog) {
        self.resetName = resetName
        self.log = log
    }

    func resetAll() async throws {
        log.append("store.\(resetName)")
        if shouldThrow { throw FakeFailure.injected }
    }
}

@MainActor
final class PendingActionsFake: ResettablePendingActions {
    private let log: CallLog
    var queuedPendingActionCount: Int
    var shouldThrow = false

    init(queued: Int, log: CallLog) {
        self.queuedPendingActionCount = queued
        self.log = log
    }

    func reloadAfterReset() async throws {
        log.append("pendingActions.reload")
        if shouldThrow { throw FakeFailure.injected }
    }
}

@MainActor
final class AppDataResetTests: XCTestCase {
    private var base: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var roots: StorageRoots!
    private var log: CallLog!
    private var sync: SyncFake!
    private var playback: PlaybackFake!
    private var offline: OfflineFake!
    private var preload: StoreFake!
    private var block: StoreFake!
    private var artwork: StoreFake!
    private var database: StoreFake!
    private var pending: PendingActionsFake!
    private var outbox: StoreFake!
    private var queues: StoreFake!
    private var failures: StoreFake!
    private var reset: AppDataReset!

    private let expectedOrder = [
        "sync.pause",
        "playback.stopAndClear",
        "offline.removeAll",
        "store.preloadCache",
        "store.blockCache",
        "store.artwork",
        "store.libraryDatabase",
        "pendingActions.reload",
        "store.listenOutbox",
        "store.savedQueues",
        "store.recentFailures",
        "sync.resume(refresh: true)"
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        base = FileManager.default.temporaryDirectory
            .appending(path: "AppDataResetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        suiteName = "AppDataResetTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        roots = StorageRoots(
            offlineMedia: base.appending(path: "AppSupport/OfflineMedia", directoryHint: .isDirectory),
            preload: base.appending(path: "Caches/PlaybackPreload", directoryHint: .isDirectory),
            libraryData: [
                base.appending(path: "AppSupport/DowntifyLibrary", directoryHint: .isDirectory),
                base.appending(path: "AppSupport/PlaybackListens", directoryHint: .isDirectory)
            ],
            caches: base.appending(path: "Caches", directoryHint: .isDirectory),
            tmp: base.appending(path: "tmp", directoryHint: .isDirectory)
        )
        for directory in [roots.offlineMedia, roots.preload, roots.caches, roots.tmp] + roots.libraryData {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        log = CallLog()
        sync = SyncFake(log: log)
        playback = PlaybackFake(log: log)
        offline = OfflineFake(log: log)
        preload = StoreFake("preloadCache", log: log)
        block = StoreFake("blockCache", log: log)
        artwork = StoreFake("artwork", log: log)
        database = StoreFake("libraryDatabase", log: log)
        pending = PendingActionsFake(queued: 0, log: log)
        outbox = StoreFake("listenOutbox", log: log)
        queues = StoreFake("savedQueues", log: log)
        failures = StoreFake("recentFailures", log: log)

        reset = AppDataReset(
            sync: sync, playback: playback, offline: offline,
            preloadCache: preload, blockCache: block, artwork: artwork,
            database: database, pendingActions: pending,
            listenOutbox: outbox, savedQueues: queues, networkFailures: failures,
            defaults: defaults, roots: roots, fileManager: .default,
            urlCache: URLCache(memoryCapacity: 0, diskCapacity: 0, directory: nil)
        )
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: base)
        defaults = nil
        roots = nil
        reset = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func write(_ count: Int, to relativePath: String) throws {
        let url = base.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: count).write(to: url)
    }

    // MARK: - Tests

    func testRunPausesFirstAndResumesLastInExpectedOrder() async {
        let outcome = await reset.run()

        XCTAssertEqual(outcome, .success(freedBytes: 0))
        XCTAssertEqual(log.entries, expectedOrder)
    }

    func testRunClearsResettableDefaultsAndKeepsSettings() async {
        defaults.set("queue", forKey: "playback.queue.A")
        defaults.set(12.5, forKey: "lyrics.offset.s.u.t")
        defaults.set(true, forKey: "pending-actions.discard.x")
        defaults.set("failures", forKey: "debug.networkOverlay.recentFailures")
        defaults.set("dark", forKey: "downtify.appearance")
        defaults.set("en", forKey: "downtify.language")
        defaults.set("title", forKey: "library.sort")
        defaults.set("high", forKey: "playback.qualities")
        defaults.set("install-1", forKey: "playback.installID")
        defaults.set(true, forKey: "debug.networkOverlay.enabled")

        _ = await reset.run()

        XCTAssertNil(defaults.object(forKey: "playback.queue.A"))
        XCTAssertNil(defaults.object(forKey: "lyrics.offset.s.u.t"))
        XCTAssertNil(defaults.object(forKey: "pending-actions.discard.x"))
        XCTAssertNil(defaults.object(forKey: "debug.networkOverlay.recentFailures"))
        XCTAssertEqual(defaults.string(forKey: "downtify.appearance"), "dark")
        XCTAssertEqual(defaults.string(forKey: "downtify.language"), "en")
        XCTAssertEqual(defaults.string(forKey: "library.sort"), "title")
        XCTAssertEqual(defaults.string(forKey: "playback.qualities"), "high")
        XCTAssertEqual(defaults.string(forKey: "playback.installID"), "install-1")
        XCTAssertTrue(defaults.bool(forKey: "debug.networkOverlay.enabled"))
    }

    func testRunRemovesTemporaryFilesButKeepsDirectory() async throws {
        try write(100, to: "tmp/scratch.tmp")
        try write(50, to: "tmp/nested/inner.bin")

        let outcome = await reset.run()

        XCTAssertEqual(outcome, .success(freedBytes: 150))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: roots.tmp.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: roots.tmp.path)
        XCTAssertEqual(remaining, [])
    }

    func testPreviewReportsPendingCountAndStorageBytes() async throws {
        pending.queuedPendingActionCount = 3
        try write(1000, to: "AppSupport/OfflineMedia/a.mp3")
        try write(34, to: "tmp/scratch.tmp")

        let preview = await reset.preview()

        XCTAssertEqual(preview.pendingActionCount, 3)
        XCTAssertEqual(preview.storage.offlineBytes, 1000)
        XCTAssertEqual(preview.storage.tmpBytes, 34)
        XCTAssertEqual(preview.storage.total, 1034)
    }

    func testLibraryDatabaseFailureIsIsolated() async {
        database.shouldThrow = true
        defaults.set("queue", forKey: "playback.queue.A")

        let outcome = await reset.run()

        XCTAssertEqual(outcome, .partial(failedSteps: ["libraryDatabase"]))
        XCTAssertEqual(log.entries, expectedOrder)
        XCTAssertNil(defaults.object(forKey: "playback.queue.A"))
    }

    func testOfflineRemoveAllRunsBeforeCachesAndDatabase() async {
        let outcome = await reset.run()

        XCTAssertEqual(outcome, .success(freedBytes: 0))
        let offlineIndex = try? XCTUnwrap(log.entries.firstIndex(of: "offline.removeAll"))
        let firstStoreIndex = log.entries.firstIndex { $0.hasPrefix("store.") }
        XCTAssertNotNil(offlineIndex)
        XCTAssertNotNil(firstStoreIndex)
        if let offlineIndex, let firstStoreIndex {
            XCTAssertLessThan(offlineIndex, firstStoreIndex)
        }
    }

    func testResumeRunsEvenWhenOfflineRemoveAllThrows() async {
        offline.shouldThrow = true

        let outcome = await reset.run()

        XCTAssertEqual(outcome, .partial(failedSteps: ["offlineDownloads"]))
        XCTAssertEqual(log.entries.first, "sync.pause")
        XCTAssertEqual(log.entries.last, "sync.resume(refresh: true)")
        XCTAssertEqual(log.entries, expectedOrder)
    }

    func testRunIsIdempotent() async {
        let first = await reset.run()
        let second = await reset.run()

        XCTAssertEqual(first, .success(freedBytes: 0))
        guard case .success(let freedBytes) = second else {
            return XCTFail("Expected second run to succeed, got \(second)")
        }
        XCTAssertGreaterThanOrEqual(freedBytes, 0)
    }

    func testConcurrentRunReturnsAlreadyRunning() async {
        sync.pauseNanoseconds = 50_000_000

        async let first = reset.run()
        async let second = reset.run()
        let outcomes = [await first, await second]

        let alreadyRunning = outcomes.filter { $0 == .partial(failedSteps: ["alreadyRunning"]) }
        XCTAssertEqual(alreadyRunning.count, 1)
        XCTAssertEqual(outcomes.count - alreadyRunning.count, 1)
        XCTAssertEqual(log.entries.filter { $0 == "sync.pause" }.count, 1)
    }

    func testLoginSessionDefaultsAreNotTouched() async {
        // AppDataReset has no session or Keychain dependency, so the login session cannot be cleared here.
        defaults.set("keep-me", forKey: "session.marker")

        _ = await reset.run()

        XCTAssertEqual(defaults.string(forKey: "session.marker"), "keep-me")
    }
}
