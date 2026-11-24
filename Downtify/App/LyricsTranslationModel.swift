import Foundation
import NaturalLanguage

/// Why a translation did not produce lyrics. Thrown by `LyricsTranslating` adapters and mapped by the model.
enum LyricsTranslationFailure: Error, Equatable, Sendable {
    case unsupported
    case declined
    case cancelled
    case failed
}

enum LyricsLanguageStatus: Equatable, Sendable {
    case installed, supported, unsupported
}

struct LyricsTranslationItem: Equatable, Sendable {
    let id: String
    let text: String
}

/// Boundary around Apple's `TranslationSession` so tests never depend on downloaded languages or Apple UI.
protocol LyricsTranslating {
    func translate(_ text: String) async throws -> String
    func translate(batch: [LyricsTranslationItem]) async throws -> [LyricsTranslationItem]
}

protocol LyricsLanguageAvailabilityChecking {
    func status(sampleText: String, source: Locale.Language?, target: Locale.Language) async -> LyricsLanguageStatus
}

struct TranslatedLyrics: Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case timed([LyricLine])
        case plain(String)
    }
    let content: Content
    let sourceLanguage: Locale.Language?
}

/// Presentation state for translated lyrics. The original `TrackLyrics` stay with the view in every phase.
@MainActor
final class LyricsTranslationModel: ObservableObject {
    enum Phase: Equatable {
        /// No lyrics, nothing translatable, or availability not resolved yet (always the case before iOS 18).
        case hidden
        case sameLanguage
        case unsupported
        case ready
        case translating
        case translated(TranslatedLyrics)
        case failed(LyricsTranslationFailure)
    }

    struct RequestKey: Equatable, Sendable {
        let trackID: String
        let fingerprint: String
        let target: String
        let generation: Int
    }

    static let enabledKey = "lyrics.translation.enabled"
    static let cacheCapacity = 16

    @Published private(set) var phase: Phase = .hidden
    /// Set when `resolveAvailability` should run; the view keys its availability task on this.
    @Published private(set) var availabilityRequest: Int?
    /// Set when a translation should run; the view keys its `translationTask` configuration on this.
    @Published private(set) var requestKey: RequestKey?
    @Published private(set) var sourceLanguage: Locale.Language?
    @Published private(set) var target: Locale.Language?
    @Published private(set) var isEnabled: Bool

    private var defaults: UserDefaults
    private let detectLanguage: (String) -> Locale.Language?
    private var trackID: String?
    private var lyrics: TrackLyrics?
    private var generation = 0
    private var cache: [String: TranslatedLyrics] = [:]
    private var cacheOrder: [String] = []

    init(defaults: UserDefaults = .standard,
         detectLanguage: @escaping (String) -> Locale.Language? = LyricsTranslationModel.detectDominantLanguage) {
        self.defaults = defaults
        self.detectLanguage = detectLanguage
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    // MARK: - Inputs

    /// Points the model at the view's injected defaults (the debug harness uses an isolated suite).
    func configure(defaults: UserDefaults) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    /// Replaces the current track and lyrics. Pass `lyrics: nil` to clear. Invalidates all in-flight work.
    func load(trackID: String?, lyrics: TrackLyrics?, target: Locale.Language?) {
        generation += 1
        requestKey = nil
        availabilityRequest = nil
        sourceLanguage = nil
        self.trackID = trackID
        self.lyrics = lyrics
        self.target = target
        phase = .hidden
        guard trackID != nil, let target, let lyrics, let sample = Self.sampleText(for: lyrics) else { return }
        let source = detectLanguage(sample)
        sourceLanguage = source
        if let source, Self.sameLanguage(source, target) {
            phase = .sameLanguage
            return
        }
        availabilityRequest = generation
    }

    func resolveAvailability(using checker: any LyricsLanguageAvailabilityChecking) async {
        guard let token = availabilityRequest, token == generation,
              let lyrics, let target, let sample = Self.sampleText(for: lyrics) else { return }
        let status = await checker.status(sampleText: sample, source: sourceLanguage, target: target)
        guard token == generation, !Task.isCancelled else { return }
        availabilityRequest = nil
        switch status {
        case .unsupported:
            phase = .unsupported
        case .installed, .supported:
            phase = .ready
            if isEnabled { begin() }
        }
    }

    /// The Translate button and Retry. Remembers the choice for later tracks.
    func requestTranslation() {
        guard canRequest else { return }
        setPreference(true)
        begin()
    }

    private var canRequest: Bool {
        switch phase {
        case .ready, .failed: true
        default: false
        }
    }

    /// The "Show original" toggle. Keeps the original on screen until translation is requested again.
    func showOriginal() {
        setPreference(false)
        guard phase != .hidden, phase != .sameLanguage, phase != .unsupported else { return }
        generation += 1
        requestKey = nil
        phase = .ready
    }

    /// Runs one translation. Results are applied only if `key` is still the current request.
    func run(using translator: any LyricsTranslating, key: RequestKey) async {
        guard isCurrent(key), let lyrics else { return }
        phase = .translating
        do {
            let result = try await translate(lyrics, using: translator, key: key)
            guard isCurrent(key) else { return settleIfCancelled(key) }
            store(result, for: key)
            phase = .translated(result)
        } catch {
            guard isCurrent(key) else { return settleIfCancelled(key) }
            switch Self.failure(for: error) {
            case .declined:
                setPreference(false)
                phase = .ready
            case .cancelled:
                phase = .ready
            case let failure:
                phase = .failed(failure)
            }
        }
    }

    // MARK: - Internals

    private func begin() {
        guard let trackID, let lyrics, let target else { return }
        let key = RequestKey(trackID: trackID, fingerprint: Self.fingerprint(lyrics),
                             target: target.minimalIdentifier, generation: generation + 1)
        if let cached = cachedResult(for: key) {
            generation += 1
            requestKey = nil
            phase = .translated(cached)
            return
        }
        generation += 1
        requestKey = key
        phase = .translating
    }

    private func isCurrent(_ key: RequestKey) -> Bool {
        !Task.isCancelled && isLatest(key)
    }

    private func isLatest(_ key: RequestKey) -> Bool {
        key.generation == generation && requestKey == key && isEnabled
    }

    /// A cancelled run that is still the latest request returns to the original lyrics; stale runs change nothing.
    private func settleIfCancelled(_ key: RequestKey) {
        if Task.isCancelled, isLatest(key) { phase = .ready }
    }

    private func setPreference(_ value: Bool) {
        isEnabled = value
        defaults.set(value, forKey: Self.enabledKey)
    }

    private func translate(_ lyrics: TrackLyrics, using translator: any LyricsTranslating,
                           key: RequestKey) async throws -> TranslatedLyrics {
        let lines = lyrics.lines
        guard !lines.isEmpty else {
            let text = try await translator.translate(lyrics.plain)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LyricsTranslationFailure.failed }
            return TranslatedLyrics(content: .plain(text), sourceLanguage: sourceLanguage)
        }
        let indices = lines.indices.filter { !lines[$0].text.isEmpty }
        guard !indices.isEmpty else { throw LyricsTranslationFailure.failed }

        // Whole-song pass gives the best context; it is trusted only when it splits back into the same lines.
        let passage = indices.map { lines[$0].text }.joined(separator: "\n")
        let whole = try await translator.translate(passage)
        guard isCurrent(key) else { throw CancellationError() }
        let segments = Self.segments(of: whole)
        if segments.count == indices.count {
            return rebuild(lines, indices: indices, texts: segments)
        }

        // Otherwise translate each line on its own, matched back by id, so timing always lines up.
        let requests = indices.map { LyricsTranslationItem(id: String($0), text: lines[$0].text) }
        let responses = try await translator.translate(batch: requests)
        guard isCurrent(key) else { throw CancellationError() }
        var byID: [String: String] = [:]
        for item in responses {
            guard byID[item.id] == nil else { throw LyricsTranslationFailure.failed }
            byID[item.id] = item.text
        }
        var texts: [String] = []
        for request in requests {
            guard let text = byID[request.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw LyricsTranslationFailure.failed
            }
            texts.append(text)
        }
        return rebuild(lines, indices: indices, texts: texts)
    }

    private func rebuild(_ lines: [LyricLine], indices: [Int], texts: [String]) -> TranslatedLyrics {
        var translated = lines
        for (position, index) in indices.enumerated() {
            translated[index] = LyricLine(time: lines[index].time, text: texts[position])
        }
        return TranslatedLyrics(content: .timed(translated), sourceLanguage: sourceLanguage)
    }

    private func cachedResult(for key: RequestKey) -> TranslatedLyrics? {
        let id = Self.cacheID(key)
        guard let value = cache[id] else { return nil }
        cacheOrder.removeAll { $0 == id }
        cacheOrder.append(id)
        return value
    }

    private func store(_ value: TranslatedLyrics, for key: RequestKey) {
        let id = Self.cacheID(key)
        cache[id] = value
        cacheOrder.removeAll { $0 == id }
        cacheOrder.append(id)
        while cacheOrder.count > Self.cacheCapacity {
            cache[cacheOrder.removeFirst()] = nil
        }
    }

    // MARK: - Helpers

    private static func cacheID(_ key: RequestKey) -> String { "\(key.target)\u{0}\(key.fingerprint)" }

    private static func fingerprint(_ lyrics: TrackLyrics) -> String { "\(lyrics.synced)\u{0}\(lyrics.plain)" }

    /// Text used for language detection and availability, or nil when there is nothing to translate.
    private static func sampleText(for lyrics: TrackLyrics) -> String? {
        let lines = lyrics.lines
        let text = lines.isEmpty ? lyrics.plain : lines.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private static func segments(of text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func sameLanguage(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        guard let codeA = a.languageCode, let codeB = b.languageCode, codeA == codeB else { return false }
        if let scriptA = a.script, let scriptB = b.script { return scriptA == scriptB }
        return true
    }

    private static func failure(for error: Error) -> LyricsTranslationFailure {
        if let failure = error as? LyricsTranslationFailure { return failure }
        if error is CancellationError { return .cancelled }
        return .failed
    }

    nonisolated static func detectDominantLanguage(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .undetermined,
              (recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0) >= 0.5 else { return nil }
        return Locale.Language(identifier: language.rawValue)
    }
}
