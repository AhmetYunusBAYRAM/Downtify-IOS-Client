import Foundation
import XCTest
@testable import Downtify

/// Scripted stand-in for `AppDataReset`: returns queued previews (the last one repeats) and counts calls.
@MainActor
final class ScriptedAppDataReset: AppDataResetting {
    private var previewQueue: [ResetPreview]
    private let outcome: ResetOutcome
    private(set) var previewCalls = 0
    private(set) var runCalls = 0

    init(previews: [ResetPreview], outcome: ResetOutcome) {
        precondition(!previews.isEmpty, "Need at least one scripted preview")
        self.previewQueue = previews
        self.outcome = outcome
    }

    func preview() async -> ResetPreview {
        previewCalls += 1
        return previewQueue.count > 1 ? previewQueue.removeFirst() : previewQueue[0]
    }

    func run() async -> ResetOutcome {
        runCalls += 1
        return outcome
    }
}

@MainActor
final class StorageSettingsModelTests: XCTestCase {
    private func makePreview(pendingActionCount: Int, total: Int64 = 195) -> ResetPreview {
        ResetPreview(
            storage: DeviceStorageReport(
                offlineBytes: 100,
                preloadBytes: 20,
                databaseBytes: 40,
                cachesBytes: 30,
                tmpBytes: 5
            ),
            pendingActionCount: pendingActionCount
        )
    }

    func testConfirmationMessageMentionsUnsentActionCount() async {
        let reset = ScriptedAppDataReset(previews: [makePreview(pendingActionCount: 3)], outcome: .success(freedBytes: 0))
        let model = StorageSettingsModel(reset: reset)

        await model.load()

        XCTAssertTrue(model.confirmationMessage.contains("3 unsent actions"), model.confirmationMessage)
    }

    func testConfirmationMessageOmitsUnsentSentenceWhenNoPendingActions() async {
        let reset = ScriptedAppDataReset(previews: [makePreview(pendingActionCount: 0)], outcome: .success(freedBytes: 0))
        let model = StorageSettingsModel(reset: reset)

        await model.load()

        XCTAssertFalse(model.confirmationMessage.contains("unsent"), model.confirmationMessage)
    }

    func testConfirmationMessageSaysActionCannotBeUndone() async {
        let reset = ScriptedAppDataReset(previews: [makePreview(pendingActionCount: 0)], outcome: .success(freedBytes: 0))
        let model = StorageSettingsModel(reset: reset)

        await model.load()

        XCTAssertTrue(model.confirmationMessage.contains("can't be undone"), model.confirmationMessage)
    }

    func testLoadSetsPreviewFromReset() async {
        let preview = makePreview(pendingActionCount: 2)
        let reset = ScriptedAppDataReset(previews: [preview], outcome: .success(freedBytes: 0))
        let model = StorageSettingsModel(reset: reset)

        await model.load()

        XCTAssertEqual(model.preview, preview)
        XCTAssertEqual(reset.previewCalls, 1)
    }

    func testClearRunsResetOnceRecordsOutcomeRefreshesPreviewAndStopsClearing() async {
        let first = makePreview(pendingActionCount: 0, total: 195)
        let second = makePreview(pendingActionCount: 1, total: 10)
        let outcome = ResetOutcome.success(freedBytes: 185)
        let reset = ScriptedAppDataReset(previews: [first, second], outcome: outcome)
        let model = StorageSettingsModel(reset: reset)
        await model.load()

        await model.clear()

        XCTAssertEqual(reset.runCalls, 1)
        XCTAssertEqual(model.lastOutcome, outcome)
        XCTAssertEqual(model.preview, second)
        XCTAssertEqual(reset.previewCalls, 2)
        XCTAssertFalse(model.isClearing)
    }

    func testRowHelpersGroupStorageCategories() async {
        let reset = ScriptedAppDataReset(previews: [makePreview(pendingActionCount: 0)], outcome: .success(freedBytes: 0))
        let model = StorageSettingsModel(reset: reset)

        await model.load()

        XCTAssertEqual(model.downloadsBytes, 100)
        XCTAssertEqual(model.cachesBytes, 55)
        XCTAssertEqual(model.libraryDataBytes, 40)
        XCTAssertEqual(model.totalBytes, 195)
    }
}
