import Foundation

/// How the lyrics section shows a track's lyrics (#71).
enum LyricsDisplayMode: String, Equatable, Sendable {
    case synced, `static`
}

/// Pure presentation rules for the Now Playing lyrics section: which formats exist, which mode applies,
/// which line is active and where tapping a line seeks to.
enum LyricsPresentation {
    static let offsetStep: Double = 0.5
    static let offsetLimit: Double = 10

    /// Tolerance so a seek to `time + offset` always selects the tapped line despite floating-point rounding.
    private static let epsilon = 1e-6

    static func hasSynced(_ lyrics: TrackLyrics?) -> Bool { lyrics?.lines.isEmpty == false }

    static func hasStatic(_ lyrics: TrackLyrics?) -> Bool {
        guard let lyrics else { return false }
        return !lyrics.plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The synced/static selector is useful only when both formats exist.
    static func offersModeChoice(_ lyrics: TrackLyrics?) -> Bool { hasSynced(lyrics) && hasStatic(lyrics) }

    /// Resolves the displayed mode from the listener's choice and what the track has.
    /// Returns nil when the track has no usable lyrics.
    static func effectiveMode(_ lyrics: TrackLyrics?, requested: LyricsDisplayMode) -> LyricsDisplayMode? {
        switch (hasSynced(lyrics), hasStatic(lyrics)) {
        case (true, true): requested
        case (true, false): .synced
        case (false, true): .static
        case (false, false): nil
        }
    }

    static func clampedOffset(_ value: Double) -> Double { min(offsetLimit, max(-offsetLimit, value)) }

    static func activeIndex(_ lines: [LyricLine], position: TimeInterval, offset: Double) -> Int? {
        lines.lastIndex { $0.time <= position - offset + epsilon }
    }

    /// Playback position that makes `line` the active line under the current offset.
    static func seekTarget(for line: LyricLine, offset: Double, duration: TimeInterval?) -> TimeInterval {
        let target = max(0, line.time + offset)
        guard let duration, duration.isFinite, duration > 0 else { return target }
        return min(target, duration)
    }

    static func accessibilityTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Reads the saved timing offset for one track (0 when none is saved).
    static func savedOffset(in defaults: UserDefaults, key: String) -> Double {
        clampedOffset(defaults.double(forKey: key))
    }

    /// Resetting removes the saved key instead of storing 0, so only this track's adjustment is affected.
    static func resetOffset(in defaults: UserDefaults, key: String) {
        defaults.removeObject(forKey: key)
    }
}
