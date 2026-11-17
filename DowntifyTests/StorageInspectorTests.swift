import Foundation
import XCTest
@testable import Downtify

final class StorageInspectorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appending(path: "StorageInspectorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        try super.tearDownWithError()
    }

    func testMeasuresKnownBytesPerCategory() async throws {
        try write(1000, "AppSupport/OfflineMedia/a.mp3")
        try write(500, "AppSupport/OfflineMedia/nested/b.mp3")
        try write(700, "Caches/PlaybackPreload/p.mp3")
        try write(300, "AppSupport/DowntifyLibrary/library.sqlite")
        try write(200, "AppSupport/PlaybackListens/listens.sqlite")
        try write(400, "Caches/other.bin")
        try write(50, "Caches/.x")
        try write(60, "tmp/scratch.tmp")

        let report = await StorageInspector.measure(roots: try roots())

        XCTAssertEqual(report.offlineBytes, 1500)
        XCTAssertEqual(report.preloadBytes, 700)
        XCTAssertEqual(report.databaseBytes, 500)
        XCTAssertEqual(report.cachesBytes, 450)
        XCTAssertEqual(report.tmpBytes, 60)
        XCTAssertEqual(report.total, 3210)
    }

    func testMissingDirectoriesMeasureZero() async {
        let missing = root.appending(path: "does-not-exist", directoryHint: .isDirectory)
        let roots = StorageRoots(
            offlineMedia: missing.appending(path: "OfflineMedia", directoryHint: .isDirectory),
            preload: missing.appending(path: "Caches/PlaybackPreload", directoryHint: .isDirectory),
            libraryData: [
                missing.appending(path: "DowntifyLibrary", directoryHint: .isDirectory),
                missing.appending(path: "PlaybackListens", directoryHint: .isDirectory)
            ],
            caches: missing.appending(path: "Caches", directoryHint: .isDirectory),
            tmp: missing.appending(path: "tmp", directoryHint: .isDirectory)
        )

        let report = await StorageInspector.measure(roots: roots)

        XCTAssertEqual(report, DeviceStorageReport(offlineBytes: 0, preloadBytes: 0, databaseBytes: 0,
                                                   cachesBytes: 0, tmpBytes: 0))
        XCTAssertEqual(report.total, 0)
    }

    func testTotalEqualsSumOfCategories() async throws {
        try write(1234, "AppSupport/OfflineMedia/track.mp3")
        try write(321, "Caches/PlaybackPreload/preload.mp3")
        try write(77, "AppSupport/DowntifyLibrary/library.sqlite")
        try write(18, "Caches/image.png")
        try write(9, "tmp/leftover")

        let report = await StorageInspector.measure(roots: try roots())

        XCTAssertEqual(report.offlineBytes, 1234)
        XCTAssertEqual(report.preloadBytes, 321)
        XCTAssertEqual(report.databaseBytes, 77)
        XCTAssertEqual(report.cachesBytes, 18)
        XCTAssertEqual(report.tmpBytes, 9)
        XCTAssertEqual(report.total, report.offlineBytes + report.preloadBytes + report.databaseBytes
                       + report.cachesBytes + report.tmpBytes)
        XCTAssertEqual(report.total, 1659)
    }

    func testEmptyDirectoriesMeasureZero() async throws {
        let roots = try roots()
        for directory in [roots.offlineMedia, roots.preload, roots.caches, roots.tmp] + roots.libraryData {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let report = await StorageInspector.measure(roots: roots)

        XCTAssertEqual(report, DeviceStorageReport(offlineBytes: 0, preloadBytes: 0, databaseBytes: 0,
                                                   cachesBytes: 0, tmpBytes: 0))
        XCTAssertEqual(report.total, 0)
    }

    // MARK: - Helpers

    /// Builds roots in the app's layout: preload lives inside caches.
    private func roots() throws -> StorageRoots {
        StorageRoots(
            offlineMedia: root.appending(path: "AppSupport/OfflineMedia", directoryHint: .isDirectory),
            preload: root.appending(path: "Caches/PlaybackPreload", directoryHint: .isDirectory),
            libraryData: [
                root.appending(path: "AppSupport/DowntifyLibrary", directoryHint: .isDirectory),
                root.appending(path: "AppSupport/PlaybackListens", directoryHint: .isDirectory)
            ],
            caches: root.appending(path: "Caches", directoryHint: .isDirectory),
            tmp: root.appending(path: "tmp", directoryHint: .isDirectory)
        )
    }

    private func write(_ count: Int, _ relativePath: String) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(count: count).write(to: url)
    }
}
