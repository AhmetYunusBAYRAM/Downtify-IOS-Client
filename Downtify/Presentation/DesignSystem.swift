import SwiftUI

enum DowntifyAppearance: String, CaseIterable, Identifiable {
    case system, light, dark, oled

    static let storageKey = "downtify.appearance"
    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .oled: "OLED black"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .oled: .dark
        }
    }
}

struct DowntifyPalette {
    var oled = false

    var background: Color {
        oled ? .black : DowntifyStyle.adaptive(light: 0xF2F3F5, dark: 0x141618)
    }

    var surface: Color {
        oled ? Color(uiColor: UIColor(white: 0.09, alpha: 1)) : Color(uiColor: .secondarySystemGroupedBackground)
    }
}

private struct DowntifyPaletteKey: EnvironmentKey {
    static let defaultValue = DowntifyPalette()
}

extension EnvironmentValues {
    var downtifyPalette: DowntifyPalette {
        get { self[DowntifyPaletteKey.self] }
        set { self[DowntifyPaletteKey.self] = newValue }
    }
}

extension View {
    func downtifyAppearance(_ appearance: DowntifyAppearance) -> some View {
        environment(\.downtifyPalette, DowntifyPalette(oled: appearance == .oled))
            .preferredColorScheme(appearance.colorScheme)
            .tint(DowntifyStyle.accent)
    }

    func downtifyControlTarget() -> some View {
        frame(minWidth: DowntifyStyle.minimumControlSize, minHeight: DowntifyStyle.minimumControlSize)
            .contentShape(Rectangle())
    }

    /// Leaves room to scroll the final action clear of the mini player, sized to the dock's measured height.
    /// The dock sits in a safe-area inset outside the tab's `NavigationStack`, which scroll views inside it
    /// do not reliably clear, so every vertically scrolling page in a tab applies this.
    func downtifyScrollEndClearance() -> some View {
        modifier(ScrollEndClearance())
    }
}

private struct ScrollEndClearance: ViewModifier {
    @Environment(\.playbackDockHeight) private var dockHeight

    func body(content: Content) -> some View {
        content.contentMargins(.bottom, DowntifyStyle.scrollEndClearance(dockHeight: dockHeight), for: .scrollContent)
    }
}

private struct PlaybackDockHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Measured height of the playback dock below the current tab; 0 when nothing is playing.
    var playbackDockHeight: CGFloat {
        get { self[PlaybackDockHeightKey.self] }
        set { self[PlaybackDockHeightKey.self] = newValue }
    }
}

/// Shared semantic colors, spacing, and surfaces used throughout the app.
enum DowntifyStyle {
    static let accent = adaptive(light: 0x17623E, dark: 0x72D9A0)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x09160F)
    static let error = adaptive(light: 0xAE252E, dark: 0xFF9B9E)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let minimumControlSize: CGFloat = 44

    /// Bottom content margin that keeps the final row clear of a dock of the given height. Never less than
    /// `Space.scrollEnd`; grows for taller docks such as the stacked accessibility-size layout.
    static func scrollEndClearance(dockHeight: CGFloat) -> CGFloat {
        max(Space.scrollEnd, dockHeight + Space.regular)
    }

    enum Space {
        static let small: CGFloat = 8
        static let regular: CGFloat = 16
        static let large: CGFloat = 24
        static let section: CGFloat = 36
        static let scrollEnd: CGFloat = 96
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                           green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        })
    }
}

struct DowntifyCard<Content: View>: View {
    @Environment(\.downtifyPalette) private var palette
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(DowntifyStyle.Space.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

/// Artwork, metadata, and optional trailing information shared by media lists.
struct DowntifyMediaRow<Artwork: View, Accessory: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let subtitle: String
    var detail: String? = nil
    var accessibilityLineLimit: Int? = nil
    /// Marks the queue's current song: accent title plus the now-playing badge.
    var isCurrent = false
    var isPlaying = false
    @ViewBuilder var artwork: Artwork
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            artwork.accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    metadata
                    accessory
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                metadata
                    .frame(maxWidth: .infinity, alignment: .leading)
                accessory
            }
        }
        .frame(minHeight: DowntifyStyle.minimumControlSize)
        .contentShape(Rectangle())
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isCurrent { NowPlayingBadge(isPlaying: isPlaying) }
                Text(title).font(.body.weight(.semibold))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(DowntifyStyle.accent) : AnyShapeStyle(.primary))
            }
            Text(subtitle).font(.subheadline).foregroundStyle(DowntifyStyle.secondaryText)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(DowntifyStyle.secondaryText)
            }
        }
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? accessibilityLineLimit : 1)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Reads now-playing state inside one row, so a song change re-renders rows rather than whole lists.
struct NowPlayingReader<Content: View>: View {
    @EnvironmentObject private var nowPlaying: NowPlayingIndicator
    @ViewBuilder let content: (NowPlayingIndicator) -> Content

    var body: some View { content(nowPlaying) }
}

/// Speaker glyph shown beside the current song. Animates only while audio is playing and motion is allowed.
struct NowPlayingBadge: View {
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "speaker.wave.2.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(DowntifyStyle.accent)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isPlaying && !reduceMotion)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Announces the current song as selected with a "Now playing" or "Paused" value.
    /// Pass any value the row already announces (such as its duration) as `value` so both are kept.
    func downtifyCurrentRowAccessibility(isCurrent: Bool, isPlaying: Bool, value: String? = nil) -> some View {
        let state = isCurrent ? (isPlaying ? String(localized: "Now playing") : String(localized: "Paused")) : nil
        let combined = [state, value].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return accessibilityAddTraits(isCurrent ? .isSelected : [])
            .accessibilityValue(Text(verbatim: combined))
    }
}

struct DowntifyUnavailableView: View {
    let title: LocalizedStringKey
    let symbol: String
    var message: Text? = nil
    var retry: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            message
        } actions: {
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.bordered)
            }
        }
    }
}
