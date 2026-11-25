import SwiftUI
import UIKit

// MARK: - Artwork tint

/// Picks a background color from cover art that keeps white text readable.
enum ArtworkTint {
    static func color(from image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage, cgImage.width >= 8, cgImage.height >= 8 else { return nil }
        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        // Group colorful pixels into 12 hue buckets and take the heaviest bucket, so a busy cover yields
        // one of its real colors instead of a muddy average. Grey or black covers fall back to the average.
        var buckets = [(weight: Double, red: Double, green: Double, blue: Double)](repeating: (0, 0, 0, 0), count: 12)
        var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[index]) / 255, g = Double(pixels[index + 1]) / 255, b = Double(pixels[index + 2]) / 255
            red += r; green += g; blue += b; total += 1
            let color = UIColor(red: r, green: g, blue: b, alpha: 1)
            var h: CGFloat = 0, sat: CGFloat = 0, value: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &sat, brightness: &value, alpha: &a)
            guard sat > 0.3, value > 0.2 else { continue }
            // Skin tones (orange hues at moderate saturation) are left out so portraits tint by their palette.
            if h < 0.11, sat < 0.62, value > 0.35 { continue }
            // Squared saturation favours vivid colours over skin tones and washed-out backgrounds.
            let weight = Double(sat * sat * value)
            let bucket = min(Int(h * 12), 11)
            buckets[bucket].weight += weight
            buckets[bucket].red += r * weight
            buckets[bucket].green += g * weight
            buckets[bucket].blue += b * weight
        }
        guard total > 0 else { return nil }
        let base: UIColor
        if let best = buckets.max(by: { $0.weight < $1.weight }), best.weight > 0.15 {
            base = UIColor(red: best.red / best.weight, green: best.green / best.weight, blue: best.blue / best.weight, alpha: 1)
        } else {
            base = UIColor(red: red / total, green: green / total, blue: blue / total, alpha: 1)
        }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let adjustedSaturation = saturation < 0.08 ? saturation : min(max(saturation, 0.35), 0.75)
        return UIColor(hue: hue, saturation: adjustedSaturation, brightness: min(max(brightness, 0.34), 0.52), alpha: 1)
    }
}

private struct ArtworkTintModifier: ViewModifier {
    let track: LibraryTrack?
    @Binding var tint: Color?
    @EnvironmentObject private var artwork: ArtworkLoader
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.task(id: track?.id) {
            guard let track else { tint = nil; return }
            if let cached = artwork.cachedTint(for: track) { tint = cached; return }
            let loaded = await artwork.tint(for: track)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { tint = loaded }
        }
    }
}

extension View {
    /// Loads the cover color of `track` into `tint`; nil while loading or when the track has no cover.
    func artworkTint(for track: LibraryTrack?, into tint: Binding<Color?>) -> some View {
        modifier(ArtworkTintModifier(track: track, tint: tint))
    }
}

// MARK: - Controls

/// Rounded filter chip. The selected chip is filled with the brand green.
struct DowntifyChip: View {
    let title: LocalizedStringKey
    var isSelected = false
    let action: () -> Void
    @Environment(\.downtifyPalette) private var palette

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .foregroundStyle(isSelected ? DowntifyStyle.onAccent : Color.primary)
                .background(isSelected ? DowntifyStyle.brand : palette.elevated, in: Capsule())
                .frame(minHeight: DowntifyStyle.minimumControlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Full-width pill button: green with black text when prominent, outlined otherwise.
struct DowntifyPillButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .foregroundStyle(prominent ? DowntifyStyle.onAccent : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background {
                if prominent {
                    Capsule().fill(DowntifyStyle.brand)
                } else {
                    Capsule().strokeBorder(DowntifyStyle.secondaryText, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Large green circular play/pause button used on collection pages.
struct DowntifyPlayButton: View {
    var isPlaying = false
    var size: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(DowntifyStyle.onAccent)
                .offset(x: isPlaying ? 0 : size * 0.03)
                .frame(width: size, height: size)
                .background(DowntifyStyle.brand, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? String(localized: "Pause") : String(localized: "Play"))
    }
}

/// Initial-letter avatar for the signed-in user; opens the profile drawer.
struct ProfileAvatar: View {
    let name: String
    var size: CGFloat = 32

    private var initial: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "D"
    }

    private var hue: Double {
        Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(Color(hue: hue, saturation: 0.5, brightness: 0.9), in: Circle())
            .accessibilityHidden(true)
    }
}

struct DowntifySectionHeader: View {
    let title: LocalizedStringKey
    var trailingTitle: LocalizedStringKey? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailingTitle, let trailingAction {
                Button(trailingTitle, action: trailingAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DowntifyStyle.secondaryText)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Library entries

/// Purple gradient heart used for Liked Songs, matching the familiar streaming-app tile.
struct LikedSongsArtwork: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: max(4, size * 0.04), style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.27, green: 0.04, blue: 0.96), Color(red: 0.56, green: 0.56, blue: 0.9)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct LibraryEntryArtwork: View {
    let entry: LibraryBrowseEntry
    let size: CGFloat
    @Environment(\.downtifyPalette) private var palette

    private var isArtist: Bool { if case .artist = entry.context { true } else { false } }

    var body: some View {
        Group {
            if case .liked = entry.context {
                LikedSongsArtwork(size: size)
            } else if entry.artwork != nil || entry.playlistCover?.isEmpty == false {
                TrackArtwork(track: entry.artwork, size: size, playlistCover: entry.playlistCover)
                    .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(Rectangle()))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.32))
                    .foregroundStyle(DowntifyStyle.secondaryText)
                    .frame(width: size, height: size)
                    .background(palette.elevated, in: isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 4)))
            }
        }
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch entry.context {
        case .artist: "music.mic"
        case .album: "opticaldisc"
        case .playlist: "music.note.list"
        case .liked: "heart.fill"
        }
    }
}

extension LibraryBrowseEntry {
    var isArtist: Bool { if case .artist = context { true } else { false } }

    /// "Album · Artist", "Playlist · Owner", "Artist" — the kind of item and who made it.
    var kindSubtitle: String {
        let songs = count == 1 ? String(localized: "1 song") : String(localized: "\(count) songs")
        switch context {
        case .album: return artist.isEmpty ? String(localized: "Album") : String(localized: "Album · \(artist)")
        case .artist: return String(localized: "Artist")
        case .playlist: return artist.isEmpty ? String(localized: "Playlist · \(songs)") : String(localized: "Playlist · \(artist)")
        case .liked: return String(localized: "Playlist · \(songs)")
        }
    }
}

/// Compact two-column tile for the top of Home.
struct QuickAccessTile: View {
    let entry: LibraryBrowseEntry
    @Environment(\.downtifyPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            LibraryEntryArtwork(entry: entry, size: 56)
            Text(entry.title)
                .font(.footnote.weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 8)
        .frame(height: 56)
        .background(palette.elevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(entry.title), \(entry.kindSubtitle)"))
    }
}

/// Square card for horizontally scrolling shelves; artists get a round image and centered text.
struct ShelfCard: View {
    let entry: LibraryBrowseEntry
    var size: CGFloat = 148

    var body: some View {
        VStack(alignment: entry.isArtist ? .center : .leading, spacing: 6) {
            LibraryEntryArtwork(entry: entry, size: size)
            Text(entry.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(entry.isArtist ? String(localized: "Artist") : (entry.artist.isEmpty ? entry.kindSubtitle : entry.artist))
                .font(.caption)
                .foregroundStyle(DowntifyStyle.secondaryText)
                .lineLimit(2)
        }
        .frame(width: size, alignment: entry.isArtist ? .center : .leading)
        .multilineTextAlignment(entry.isArtist ? .center : .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One row of the Your Library list: artwork, title and "kind · owner".
struct LibraryListRow: View {
    let entry: LibraryBrowseEntry
    var isPinned = false
    var isOnDevice = false

    var body: some View {
        HStack(spacing: 12) {
            LibraryEntryArtwork(entry: entry, size: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if isPinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(DowntifyStyle.accent)
                            .accessibilityLabel("Pinned")
                    }
                    if isOnDevice {
                        Image(systemName: "arrow.down.circle.fill").font(.caption).foregroundStyle(DowntifyStyle.accent)
                            .accessibilityLabel("On this device")
                    }
                    Text(entry.kindSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(DowntifyStyle.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Colored category tile on the Search page.
struct BrowseTile: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            color
            Image(systemName: symbol)
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .rotationEffect(.degrees(22))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 14, y: 8)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .padding(12)
        }
        .frame(height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Remote cover image (https only) with a symbol placeholder; square or round.
struct CatalogCoverImage: View {
    let imageURL: String?
    var size: CGFloat
    var round = false
    var symbol = "music.note"
    @Environment(\.downtifyPalette) private var palette

    private var url: URL? {
        guard let imageURL, let url = URL(string: imageURL), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.3))
                    .foregroundStyle(DowntifyStyle.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.elevated)
            }
        }
        .frame(width: size, height: size)
        .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: max(4, size * 0.04), style: .continuous)))
        .accessibilityHidden(true)
    }
}

/// Card for catalog results that carry a remote cover URL (charts, suggestions, collections).
struct RemoteArtworkCard: View {
    let title: String
    let subtitle: String
    let imageURL: String?
    var round = false
    var symbol = "music.note"
    var size: CGFloat = 140

    var body: some View {
        VStack(alignment: round ? .center : .leading, spacing: 6) {
            CatalogCoverImage(imageURL: imageURL, size: size, round: round, symbol: symbol)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DowntifyStyle.secondaryText)
                    .lineLimit(2)
            }
        }
        .frame(width: size, alignment: round ? .center : .leading)
        .multilineTextAlignment(round ? .center : .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Side drawer

/// Slides in from the leading edge over a dimmed backdrop; tap the backdrop or drag left to close.
struct SideDrawer<Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder var content: Content
    @Environment(\.downtifyPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.84, 360)
            ZStack(alignment: .leading) {
                if isPresented {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { close() }
                        .transition(.opacity)
                        .accessibilityLabel("Close menu")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { close() }
                    content
                        .frame(width: width)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(palette.surface.ignoresSafeArea())
                        .offset(x: min(0, dragOffset))
                        .gesture(DragGesture(minimumDistance: 12)
                            .updating($dragOffset) { value, state, _ in state = value.translation.width }
                            .onEnded { value in if value.translation.width < -width / 4 { close() } })
                        .transition(reduceMotion ? .opacity : .move(edge: .leading))
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { close() }
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: isPresented)
        }
    }

    private func close() { isPresented = false }
}

/// Icon, title and optional trailing detail for drawer and settings menus.
struct DrawerRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    var detail: String? = nil
    var badge: Int = 0
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(role == .destructive ? DowntifyStyle.error : Color.primary)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(role == .destructive ? DowntifyStyle.error : Color.primary)
                Spacer(minLength: 8)
                if badge > 0 {
                    Text(verbatim: "\(badge)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(DowntifyStyle.onAccent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(DowntifyStyle.brand, in: Capsule())
                }
                if let detail {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(DowntifyStyle.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scrubber

/// Thin white timeline with a thumb that grows while dragging. VoiceOver sees a standard slider.
struct DowntifyScrubber: View {
    let value: Double
    let total: Double
    let onChange: (Double) -> Void
    let onEditingChanged: (Bool) -> Void
    @State private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let fraction = total > 0 ? min(max(value / total, 0), 1) : 0
            let thumb: CGFloat = isDragging ? 16 : 12
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.25)).frame(height: 4)
                Capsule().fill(Color.primary).frame(width: proxy.size.width * fraction, height: 4)
                Circle().fill(Color.primary)
                    .frame(width: thumb, height: thumb)
                    .offset(x: proxy.size.width * fraction - thumb / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if !isDragging { isDragging = true; onEditingChanged(true) }
                    let x = min(max(gesture.location.x / max(proxy.size.width, 1), 0), 1)
                    onChange(x * total)
                }
                .onEnded { _ in isDragging = false; onEditingChanged(false) })
        }
        .frame(height: 28)
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .accessibilityRepresentation {
            Slider(value: Binding(get: { min(value, total) }, set: onChange), in: 0...max(total, 1),
                   onEditingChanged: onEditingChanged)
        }
    }
}
