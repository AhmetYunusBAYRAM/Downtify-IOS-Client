import Foundation

struct StorageRoots: Sendable {
    let offlineMedia: URL
    let preload: URL
    let libraryData: [URL]
    let caches: URL
    let tmp: URL

    init(offlineMedia: URL, preload: URL, libraryData: [URL], caches: URL, tmp: URL) {
        self.offlineMedia = offlineMedia
        self.preload = preload
        self.libraryData = libraryData
        self.caches = caches
        self.tmp = tmp
    }

    static var live: StorageRoots {
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.applicationSupportDirectory
        let caches = manager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL.cachesDirectory
        return StorageRoots(
            offlineMedia: support.appending(path: "OfflineMedia", directoryHint: .isDirectory),
            preload: caches.appending(path: "PlaybackPreload", directoryHint: .isDirectory),
            libraryData: [
                support.appending(path: "DowntifyLibrary", directoryHint: .isDirectory),
                support.appending(path: "PlaybackListens", directoryHint: .isDirectory)
            ],
            caches: caches,
            tmp: manager.temporaryDirectory
        )
    }
}

struct DeviceStorageReport: Equatable, Sendable {
    var offlineBytes: Int64
    var preloadBytes: Int64
    var databaseBytes: Int64
    var cachesBytes: Int64
    var tmpBytes: Int64

    var total: Int64 { offlineBytes + preloadBytes + databaseBytes + cachesBytes + tmpBytes }
}

/// Read-only measurement of on-device storage by category. Never deletes anything.
enum StorageInspector {
    static func measure(fileManager: FileManager = .default, roots: StorageRoots = .live) async -> DeviceStorageReport {
        await Task.detached(priority: .utility) {
            DeviceStorageReport(
                offlineBytes: bytes(under: roots.offlineMedia, fileManager: fileManager),
                preloadBytes: bytes(under: roots.preload, fileManager: fileManager),
                databaseBytes: roots.libraryData.reduce(into: Int64(0)) {
                    $0 += bytes(under: $1, fileManager: fileManager)
                },
                cachesBytes: bytes(under: roots.caches, fileManager: fileManager, excluding: roots.preload),
                tmpBytes: bytes(under: roots.tmp, fileManager: fileManager)
            )
        }.value
    }

    /// Sums the logical size of every regular file under `root`, recursively, including hidden files.
    /// A missing root or an unreadable entry contributes 0. Subtrees matching `excluded` are skipped.
    private static func bytes(under root: URL, fileManager: FileManager, excluding excluded: URL? = nil) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let rootValues = try? root.resourceValues(forKeys: Set(keys)) else { return 0 }
        if rootValues.isRegularFile == true {
            return Int64(rootValues.fileSize ?? 0)
        }
        guard rootValues.isDirectory == true,
              let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys,
                                                      options: [], errorHandler: { _, _ in true })
        else { return 0 }

        let excludedPath = excluded.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let excludedPath,
               url.resolvingSymlinksInPath().standardizedFileURL.path == excludedPath {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
