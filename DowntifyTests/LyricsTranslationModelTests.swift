import XCTest
@testable import Downtify

@MainActor
final class LyricsTranslationModelTests: XCTestCase {
    private let english = Locale.Language(identifier: "en")
    private let french = Locale.Language(identifier: "fr")
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "LyricsTranslationModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private let timed = TrackLyrics(synced: "[00:01.00]Bonjour\n[00:02.00]Le monde\n[00:03.00]\n[00:04.00]Bonjour\n[00:04.00]Bonjour", plain: "")
    private let plain = TrackLyrics(synced: "", plain: "Bonjour\nLe monde")

    private func makeModel(source: Locale.Language? = Locale.Language(identifier: "fr")) -> LyricsTranslationModel {
        LyricsTranslationModel(defaults: defaults, detectLanguage: { _ in source })
    }

    private func loadReady(_ model: LyricsTranslationModel, track: String = "t1", lyrics: TrackLyrics? = nil,
                           status: LyricsLanguageStatus = .supported) async {
        model.load(trackID: track, lyrics: lyrics ?? timed, target: english)
        await model.resolveAvailability(using: FakeAvailability(status: status))
    }

    private func translate(_ model: LyricsTranslationModel, _ translator: FakeTranslator) async {
        model.requestTranslation()
        guard let key = model.requestKey else { return }
        await model.run(using: translator, key: key)
    }

    private func timedLines(_ model: LyricsTranslationModel, file: StaticString = #filePath, line: UInt = #line) -> [LyricLine]? {
        guard case .translated(let result) = model.phase, case .timed(let lines) = result.content else {
            XCTFail("\(model.phase)", file: file, line: line)
            return nil
        }
        return lines
    }

    func testTimedWholeSongKeepsTimesOrderRepeatsAndBlankLines() async throws {
        let model = makeModel()
        let translator = FakeTranslator(whole: "Hello\nThe world\nHello\nHello")
        await loadReady(model)
        XCTAssertEqual(model.phase, .ready)
        await translate(model, translator)

        let lines = try XCTUnwrap(timedLines(model))
        XCTAssertEqual(lines.map(\.text), ["Hello", "The world", "", "Hello", "Hello"])
        XCTAssertEqual(lines.map(\.time), timed.lines.map(\.time))
        XCTAssertEqual(translator.wholeCalls, ["Bonjour\nLe monde\nBonjour\nBonjour"])
        XCTAssertTrue(translator.batchCalls.isEmpty)
    }

    func testPlainLyricsStayPlainAndNeverFallBack() async {
        let model = makeModel()
        let translator = FakeTranslator(whole: "Hello\nThe world")
        await loadReady(model, lyrics: plain)
        await translate(model, translator)

        guard case .translated(let result) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertEqual(result.content, .plain("Hello\nThe world"))
        XCTAssertTrue(translator.batchCalls.isEmpty)
    }

    func testMismatchedWholeSongFallsBackToOneBatchMatchedByID() async throws {
        let model = makeModel()
        let translator = FakeTranslator(whole: "Hello The world Hello Hello",
                                        batch: { items in items.reversed().map { .init(id: $0.id, text: "T:\($0.text)") } })
        await loadReady(model)
        await translate(model, translator)

        let lines = try XCTUnwrap(timedLines(model))
        XCTAssertEqual(lines.map(\.text), ["T:Bonjour", "T:Le monde", "", "T:Bonjour", "T:Bonjour"])
        XCTAssertEqual(translator.batchCalls.count, 1)
        XCTAssertEqual(translator.batchCalls[0].map(\.id), ["0", "1", "3", "4"])
        XCTAssertEqual(translator.batchCalls[0].map(\.text), ["Bonjour", "Le monde", "Bonjour", "Bonjour"])
    }

    func testBlankWholeSongSegmentFallsBackToBatch() async {
        let model = makeModel()
        let translator = FakeTranslator(whole: "Hello\n\nHello\nHello")
        await loadReady(model)
        await translate(model, translator)
        XCTAssertEqual(translator.batchCalls.count, 1)
    }

    func testIncompleteDuplicateOrBlankBatchResponsesAreNeverShown() async {
        let cases: [(String, ([LyricsTranslationItem]) -> [LyricsTranslationItem])] = [
            ("missing", { Array($0.dropLast()) }),
            ("duplicate", { $0 + [$0[0]] }),
            ("blank", { items in items.map { .init(id: $0.id, text: $0.id == "1" ? "  " : "x") } }),
        ]
        for (name, transform) in cases {
            let model = makeModel()
            let translator = FakeTranslator(whole: "one line", batch: { transform($0.map { .init(id: $0.id, text: "x") }) })
            await loadReady(model)
            await translate(model, translator)
            XCTAssertEqual(model.phase, .failed(.failed), name)
        }
    }

    func testUnknownBatchIDsAreIgnored() async throws {
        let model = makeModel()
        let translator = FakeTranslator(whole: "x", batch: { $0.map { .init(id: $0.id, text: "y") } + [.init(id: "99", text: "z")] })
        await loadReady(model)
        await translate(model, translator)
        XCTAssertEqual(try XCTUnwrap(timedLines(model)).map(\.text), ["y", "y", "", "y", "y"])
    }

    func testSameLanguageSkipsTranslation() async {
        let model = makeModel(source: Locale.Language(identifier: "en-GB"))
        model.load(trackID: "t", lyrics: timed, target: Locale.Language(identifier: "en-US"))
        XCTAssertEqual(model.phase, .sameLanguage)
        XCTAssertNil(model.availabilityRequest)
    }

    func testDifferentScriptsOfOneLanguageAreNotTheSame() {
        XCTAssertFalse(LyricsTranslationModel.sameLanguage(Locale.Language(identifier: "zh-Hans"), Locale.Language(identifier: "zh-Hant")))
        XCTAssertTrue(LyricsTranslationModel.sameLanguage(Locale.Language(identifier: "pt-BR"), Locale.Language(identifier: "pt-PT")))
    }

    func testUndeterminedSourceStillOffersTranslation() async {
        let model = makeModel(source: nil)
        await loadReady(model)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertNil(model.sourceLanguage)
    }

    func testUnsupportedAvailabilityHidesAction() async {
        let model = makeModel()
        await loadReady(model, status: .unsupported)
        XCTAssertEqual(model.phase, .unsupported)
        model.requestTranslation()
        XCTAssertNil(model.requestKey)
    }

    func testNothingTranslatableIsHidden() {
        let model = makeModel()
        model.load(trackID: "t", lyrics: TrackLyrics(synced: "[00:01.00]\n", plain: ""), target: english)
        XCTAssertEqual(model.phase, .hidden)
        model.load(trackID: "t", lyrics: nil, target: english)
        XCTAssertEqual(model.phase, .hidden)
    }

    func testAvailabilityIsNotResolvedUntilAsked() {
        let model = makeModel()
        model.load(trackID: "t", lyrics: timed, target: english)
        XCTAssertEqual(model.phase, .hidden, "stays hidden until availability resolves, as on iOS 17")
    }

    func testCachedResultIsReusedAndInvalidatedByContentOrTarget() async {
        let model = makeModel()
        let translator = FakeTranslator(whole: "Hello\nThe world\nHello\nHello")
        await loadReady(model)
        await translate(model, translator)
        XCTAssertEqual(translator.wholeCalls.count, 1)

        await loadReady(model, track: "t2")  // same lyrics, same target, preference on
        guard case .translated = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertEqual(translator.wholeCalls.count, 1, "served from cache")

        await loadReady(model, track: "t2", lyrics: TrackLyrics(synced: timed.synced + "\n[00:09.00]Fin", plain: ""))
        XCTAssertEqual(model.phase, .translating, "changed content misses the cache")

        model.load(trackID: "t3", lyrics: timed, target: Locale.Language(identifier: "de"))
        await model.resolveAvailability(using: FakeAvailability(status: .supported))
        XCTAssertEqual(model.phase, .translating, "changed target misses the cache")
    }

    func testCacheEvictsLeastRecentlyUsedBeyondCapacity() async {
        let model = makeModel()
        for index in 0...LyricsTranslationModel.cacheCapacity {
            let lyrics = TrackLyrics(synced: "", plain: "song \(index)")
            await loadReady(model, track: "t\(index)", lyrics: lyrics)
            await translate(model, FakeTranslator(whole: "translated \(index)"))
        }
        let probe = FakeTranslator(whole: "again")
        await loadReady(model, track: "first", lyrics: TrackLyrics(synced: "", plain: "song 0"))
        guard let key = model.requestKey else { return XCTFail("oldest entry should have been evicted: \(model.phase)") }
        await model.run(using: probe, key: key)
        XCTAssertEqual(probe.wholeCalls.count, 1)
    }

    func testFailuresMapToStatesAndPreference() async {
        let model = makeModel()
        await loadReady(model)
        await translate(model, FakeTranslator(error: LyricsTranslationFailure.unsupported))
        XCTAssertEqual(model.phase, .failed(.unsupported))
        XCTAssertTrue(model.isEnabled)

        await translate(model, FakeTranslator(error: URLError(.badServerResponse)))  // Retry
        XCTAssertEqual(model.phase, .failed(.failed))

        await translate(model, FakeTranslator(error: LyricsTranslationFailure.declined))
        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: LyricsTranslationModel.enabledKey))

        await translate(model, FakeTranslator(error: CancellationError()))
        XCTAssertEqual(model.phase, .ready)
        XCTAssertTrue(model.isEnabled, "cancellation keeps the preference")
    }

    func testShowOriginalKeepsOriginalAndTurnsPreferenceOff() async {
        let model = makeModel()
        await loadReady(model)
        await translate(model, FakeTranslator(whole: "Hello\nThe world\nHello\nHello"))
        model.showOriginal()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertNil(model.requestKey)
        XCTAssertFalse(model.isEnabled)
    }

    func testPreferencePersistsAndAutoTranslatesNextTrack() async {
        let model = makeModel()
        await loadReady(model)
        model.requestTranslation()

        let next = makeModel()
        XCTAssertTrue(next.isEnabled)
        await loadReady(next, track: "other")
        XCTAssertEqual(next.phase, .translating)
        XCTAssertNotNil(next.requestKey)
    }

    func testLateResultAfterTrackChangeIsIgnored() async {
        let model = makeModel()
        let translator = FakeTranslator(whole: "Hello\nThe world\nHello\nHello")
        translator.suspendWhole = true
        await loadReady(model)
        model.requestTranslation()
        let key = try! XCTUnwrap(model.requestKey)
        let task = Task { await model.run(using: translator, key: key) }
        await translator.waitUntilSuspended()

        model.load(trackID: "t2", lyrics: plain, target: english)
        translator.resume()
        await task.value

        XCTAssertEqual(model.phase, .hidden)
        XCTAssertNil(model.requestKey)
    }

    func testTrackChangeBetweenWholeSongAndBatchStopsFallback() async {
        let model = makeModel()
        let translator = FakeTranslator(whole: "mismatch")
        translator.suspendWhole = true
        await loadReady(model)
        model.requestTranslation()
        let key = try! XCTUnwrap(model.requestKey)
        let task = Task { await model.run(using: translator, key: key) }
        await translator.waitUntilSuspended()

        model.load(trackID: "t2", lyrics: plain, target: english)
        translator.resume()
        await task.value

        XCTAssertTrue(translator.batchCalls.isEmpty)
        XCTAssertEqual(model.phase, .hidden)
    }

    func testNewerRequestSupersedesOlderOne() async {
        let model = makeModel()
        let slow = FakeTranslator(whole: "OLD\nOLD\nOLD\nOLD")
        slow.suspendWhole = true
        await loadReady(model)
        model.requestTranslation()
        let oldKey = try! XCTUnwrap(model.requestKey)
        let task = Task { await model.run(using: slow, key: oldKey) }
        await slow.waitUntilSuspended()

        model.showOriginal()
        model.requestTranslation()
        let newKey = try! XCTUnwrap(model.requestKey)
        XCTAssertNotEqual(oldKey, newKey)
        await model.run(using: FakeTranslator(whole: "New\nNew\nNew\nNew"), key: newKey)
        slow.resume()
        await task.value

        XCTAssertEqual(timedLines(model)?.first?.text, "New")
    }

    func testCancelledRunNeverAppliesResultAndReturnsToOriginal() async {
        let model = makeModel()
        let translator = FakeTranslator(whole: "Hello\nThe world\nHello\nHello")
        translator.suspendWhole = true
        await loadReady(model)
        model.requestTranslation()
        let key = try! XCTUnwrap(model.requestKey)
        let task = Task { await model.run(using: translator, key: key) }
        await translator.waitUntilSuspended()

        task.cancel()
        translator.resume()
        await task.value

        XCTAssertEqual(model.phase, .ready)
    }

    func testStaleAvailabilityResultIsIgnored() async {
        let model = makeModel()
        model.load(trackID: "a", lyrics: timed, target: english)
        let checker = FakeAvailability(status: .unsupported)
        let other = plain, target = english
        checker.onCheck = { [model] in model.load(trackID: "b", lyrics: other, target: target) }
        await model.resolveAvailability(using: checker)
        XCTAssertEqual(model.phase, .hidden)
        XCTAssertNotNil(model.availabilityRequest, "the newer track still awaits its own check")
    }
}

private final class FakeAvailability: LyricsLanguageAvailabilityChecking {
    let status: LyricsLanguageStatus
    var onCheck: (() -> Void)?
    init(status: LyricsLanguageStatus) { self.status = status }
    func status(sampleText: String, source: Locale.Language?, target: Locale.Language) async -> LyricsLanguageStatus {
        onCheck?()
        return status
    }
}

private final class FakeTranslator: LyricsTranslating {
    var whole: String
    var batch: (([LyricsTranslationItem]) -> [LyricsTranslationItem])?
    var error: Error?
    var suspendWhole = false
    private(set) var wholeCalls: [String] = []
    private(set) var batchCalls: [[LyricsTranslationItem]] = []
    private var continuation: CheckedContinuation<Void, Never>?

    init(whole: String = "", batch: (([LyricsTranslationItem]) -> [LyricsTranslationItem])? = nil, error: Error? = nil) {
        self.whole = whole
        self.batch = batch
        self.error = error
    }

    func translate(_ text: String) async throws -> String {
        wholeCalls.append(text)
        if suspendWhole { await withCheckedContinuation { continuation = $0 } }
        if let error { throw error }
        return whole
    }

    func translate(batch items: [LyricsTranslationItem]) async throws -> [LyricsTranslationItem] {
        batchCalls.append(items)
        if let error { throw error }
        return batch?(items) ?? items
    }

    func waitUntilSuspended() async {
        while continuation == nil { await Task.yield() }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
