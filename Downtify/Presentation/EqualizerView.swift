import SwiftUI

/// Six-band equalizer with a draggable curve and presets, in the style of familiar streaming apps.
struct EqualizerView: View {
    @ObservedObject var playback: PlaybackController
    var showsDoneButton = false
    @Environment(\.downtifyPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private var equalizer: PlaybackEqualizer { playback.equalizer }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DowntifyStyle.Space.large) {
                Toggle(isOn: Binding(get: { equalizer.enabled }, set: { enabled in
                    var updated = equalizer
                    updated.enabled = enabled
                    playback.setEqualizer(updated)
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Equalizer").font(.headline)
                        Text("Shape the sound to your headphones and taste.")
                            .font(.footnote).foregroundStyle(DowntifyStyle.secondaryText)
                    }
                }
                .tint(DowntifyStyle.brand)
                .accessibilityIdentifier("equalizer.toggle")

                EqualizerGraph(gains: equalizer.gains, enabled: equalizer.enabled) { band, gain in
                    var updated = equalizer
                    updated.enabled = true
                    updated.setGain(gain, at: band)
                    playback.setEqualizer(updated)
                }
                .frame(height: 260)
                .padding(DowntifyStyle.Space.regular)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    Text("Presets").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                        .padding(.bottom, DowntifyStyle.Space.small)
                    ForEach(EqualizerPreset.allCases) { preset in
                        Button {
                            var updated = equalizer
                            updated.enabled = true
                            updated.apply(preset)
                            playback.setEqualizer(updated)
                        } label: {
                            HStack {
                                Text(LocalizedStringKey(preset.name))
                                    .foregroundStyle(equalizer.preset == preset && equalizer.enabled
                                                     ? AnyShapeStyle(DowntifyStyle.accent) : AnyShapeStyle(.primary))
                                Spacer()
                                if equalizer.preset == preset {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(DowntifyStyle.accent)
                                }
                            }
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(equalizer.preset == preset ? .isSelected : [])
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(DowntifyStyle.Space.regular)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .downtifyScrollEndClearance()
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Equalizer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") {
                    var updated = equalizer
                    updated.apply(.flat)
                    playback.setEqualizer(updated)
                }
                .disabled(equalizer.isFlat)
            }
            if showsDoneButton {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// The band curve: drag a point (or anywhere near its column) up or down to change that band.
struct EqualizerGraph: View {
    let gains: [Double]
    let enabled: Bool
    let onChange: (Int, Double) -> Void
    @State private var activeBand: Int?

    private static let labels = ["60Hz", "150Hz", "400Hz", "1kHz", "2.4kHz", "15kHz"]
    private static let spokenLabels = ["60 hertz", "150 hertz", "400 hertz", "1 kilohertz", "2.4 kilohertz", "15 kilohertz"]
    private let maxGain = PlaybackEqualizer.gainRange.upperBound

    var body: some View {
        GeometryReader { proxy in
            let labelHeight: CGFloat = 24
            // Room on the left for the dB scale, so labels never sit under a point.
            let leading: CGFloat = 52, trailing: CGFloat = 20
            let plotHeight = proxy.size.height - labelHeight
            let points = gains.indices.map { band -> CGPoint in
                let x = leading + (proxy.size.width - leading - trailing) * CGFloat(band) / CGFloat(max(gains.count - 1, 1))
                return CGPoint(x: x, y: y(for: gains[band], height: plotHeight))
            }
            let color = enabled ? DowntifyStyle.brand : DowntifyStyle.secondaryText
            ZStack(alignment: .topLeading) {
                ForEach([maxGain, 0, -maxGain], id: \.self) { gain in
                    let lineY = y(for: gain, height: plotHeight)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: lineY))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: lineY))
                    }
                    .stroke(DowntifyStyle.secondaryText.opacity(gain == 0 ? 0.45 : 0.2),
                            style: StrokeStyle(lineWidth: 1, dash: gain == 0 ? [] : [4, 4]))
                    Text(verbatim: gain > 0 ? "+\(Int(gain)) dB" : "\(Int(gain)) dB")
                        .font(.caption2)
                        .foregroundStyle(DowntifyStyle.secondaryText)
                        .position(x: 22, y: lineY + (gain > 0 ? 9 : -9))
                }
                curve(points, closeTo: plotHeight, width: proxy.size.width)
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                curve(points, closeTo: nil, width: proxy.size.width)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                ForEach(points.indices, id: \.self) { band in
                    Circle()
                        .fill(Color.white)
                        .frame(width: activeBand == band ? 22 : 16, height: activeBand == band ? 22 : 16)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .position(points[band])
                    if activeBand == band {
                        Text(verbatim: gainText(gains[band]))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.black.opacity(0.75), in: Capsule())
                            .foregroundStyle(.white)
                            .position(x: points[band].x, y: max(10, points[band].y - 24))
                    }
                    Text(verbatim: Self.labels[band])
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(DowntifyStyle.secondaryText)
                        .position(x: points[band].x, y: plotHeight + labelHeight / 2 + 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let band = activeBand ?? nearestBand(to: value.startLocation.x, points: points)
                    if activeBand == nil { activeBand = band }
                    let clampedY = min(max(value.location.y, 0), plotHeight)
                    onChange(band, gain(for: clampedY, height: plotHeight))
                }
                .onEnded { _ in activeBand = nil })
            .sensoryFeedback(.selection, trigger: activeBand.map { gains[$0] })
        }
        .accessibilityRepresentation {
            VStack {
                ForEach(gains.indices, id: \.self) { band in
                    Slider(value: Binding(get: { gains[band] }, set: { onChange(band, $0) }),
                           in: PlaybackEqualizer.gainRange, step: 0.5) {
                        Text(verbatim: Self.spokenLabels[band])
                    }
                    .accessibilityValue(Text(verbatim: gainText(gains[band])))
                }
            }
        }
    }

    private func y(for gain: Double, height: CGFloat) -> CGFloat {
        let padding: CGFloat = 14
        return height / 2 - CGFloat(gain / maxGain) * (height / 2 - padding)
    }

    private func gain(for y: CGFloat, height: CGFloat) -> Double {
        let padding: CGFloat = 14
        return Double((height / 2 - y) / (height / 2 - padding)) * maxGain
    }

    private func nearestBand(to x: CGFloat, points: [CGPoint]) -> Int {
        points.indices.min { abs(points[$0].x - x) < abs(points[$1].x - x) } ?? 0
    }

    private func gainText(_ gain: Double) -> String {
        let value = gain.formatted(.number.precision(.fractionLength(0...1)))
        return gain > 0 ? "+\(value) dB" : "\(value) dB"
    }

    /// Smooth curve through the points (Catmull-Rom as cubic Béziers), extended flat to both edges.
    private func curve(_ points: [CGPoint], closeTo bottom: CGFloat?, width: CGFloat) -> Path {
        Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: 0, y: first.y))
            path.addLine(to: first)
            for index in 0..<(points.count - 1) {
                let p0 = points[max(index - 1, 0)], p1 = points[index]
                let p2 = points[index + 1], p3 = points[min(index + 2, points.count - 1)]
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                path.addCurve(to: p2, control1: c1, control2: c2)
            }
            path.addLine(to: CGPoint(x: width, y: last.y))
            if let bottom {
                path.addLine(to: CGPoint(x: width, y: bottom))
                path.addLine(to: CGPoint(x: 0, y: bottom))
                path.closeSubpath()
            }
        }
    }
}
