import Foundation

@MainActor
protocol AppDataResetting {
    func preview() async -> ResetPreview
    func run() async -> ResetOutcome
}

extension AppDataReset: AppDataResetting {}

@MainActor
final class StorageSettingsModel: ObservableObject {
    @Published private(set) var preview: ResetPreview?
    @Published private(set) var isClearing = false
    @Published private(set) var lastOutcome: ResetOutcome?
    private let reset: any AppDataResetting

    init(reset: any AppDataResetting) { self.reset = reset }

    func load() async { preview = await reset.preview() }

    func clear() async {
        guard !isClearing else { return }
        isClearing = true
        lastOutcome = await reset.run()
        await load()
        isClearing = false
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var downloadsBytes: Int64? { preview?.storage.offlineBytes }
    var cachesBytes: Int64? {
        preview.map { $0.storage.preloadBytes + $0.storage.cachesBytes + $0.storage.tmpBytes }
    }
    var libraryDataBytes: Int64? { preview?.storage.databaseBytes }
    var totalBytes: Int64? { preview?.storage.total }

    var confirmationMessage: String {
        let size = Self.formatted(preview?.storage.total ?? 0)
        var message = String(localized: "This removes songs added to this device, caches and local library data, freeing about \(size). You stay signed in.")
        if let count = preview?.pendingActionCount, count > 0 {
            message += " " + String(localized: "\(count) unsent actions (likes and playlist favorites) will be lost.")
        }
        return message + " " + String(localized: "This can't be undone.")
    }
}
