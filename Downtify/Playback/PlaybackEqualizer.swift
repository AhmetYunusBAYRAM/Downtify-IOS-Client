import AVFoundation
import Foundation
import os

/// Six-band equalizer settings, persisted per device. Gains are in decibels.
struct PlaybackEqualizer: Codable, Equatable, Sendable {
    static let frequencies: [Double] = [60, 150, 400, 1_000, 2_400, 15_000]
    static let gainRange: ClosedRange<Double> = -12...12

    var enabled = false
    var gains: [Double] = Array(repeating: 0, count: PlaybackEqualizer.frequencies.count)
    /// The preset the gains came from; nil once the listener moves a band by hand.
    var preset: EqualizerPreset? = .flat

    mutating func setGain(_ gain: Double, at band: Int) {
        guard gains.indices.contains(band) else { return }
        gains[band] = min(max((gain * 2).rounded() / 2, Self.gainRange.lowerBound), Self.gainRange.upperBound)
        preset = EqualizerPreset.matching(gains)
    }

    mutating func apply(_ preset: EqualizerPreset) {
        gains = preset.gains
        self.preset = preset
    }

    /// Headroom in decibels so boosted bands do not clip before the limiter.
    var preampDB: Double { -max(0, gains.max() ?? 0) * 0.5 }

    var isFlat: Bool { gains.allSatisfy { $0 == 0 } }
}

enum EqualizerPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case flat, acoustic, bassBooster, bassReducer, classical, dance, deep, electronic, hipHop, jazz, loudness,
         piano, pop, rnb, rock, smallSpeakers, spokenWord, trebleBooster, trebleReducer, vocalBooster

    var id: Self { self }

    /// Gains for 60 Hz, 150 Hz, 400 Hz, 1 kHz, 2.4 kHz and 15 kHz.
    var gains: [Double] {
        switch self {
        case .flat: [0, 0, 0, 0, 0, 0]
        case .acoustic: [3, 2, 1, 1.5, 2.5, 2]
        case .bassBooster: [6, 4.5, 2, 0, 0, 0]
        case .bassReducer: [-6, -4, -2, 0, 0, 0]
        case .classical: [3, 2, 0, 0, -1, 3]
        case .dance: [4, 5, 1.5, 0, 1.5, 3]
        case .deep: [4, 2.5, 1, -1, -2.5, -4]
        case .electronic: [4.5, 3, 0, -1, 2, 4.5]
        case .hipHop: [5, 3.5, 0, 1, -1, 2]
        case .jazz: [3, 2, -1, 1, 2.5, 3]
        case .loudness: [5, 3, 0, 0, -1, 4.5]
        case .piano: [1, 0.5, 0, 2, 3, 1.5]
        case .pop: [-1, 1.5, 3, 2, 0, -1]
        case .rnb: [3, 6, 2, -1.5, 2, 3]
        case .rock: [4.5, 3, -1, -1.5, 2, 4]
        case .smallSpeakers: [5, 4, 2, 0, -1, -2]
        case .spokenWord: [-3, -1, 2, 3.5, 3, -1]
        case .trebleBooster: [0, 0, 0, 1.5, 4, 6]
        case .trebleReducer: [0, 0, 0, -1.5, -4, -6]
        case .vocalBooster: [-2, -1, 2, 4, 3, 0]
        }
    }

    /// English name; also the localization key.
    var name: String {
        switch self {
        case .flat: "Flat"
        case .acoustic: "Acoustic"
        case .bassBooster: "Bass Booster"
        case .bassReducer: "Bass Reducer"
        case .classical: "Classical"
        case .dance: "Dance"
        case .deep: "Deep"
        case .electronic: "Electronic"
        case .hipHop: "Hip-Hop"
        case .jazz: "Jazz"
        case .loudness: "Loudness"
        case .piano: "Piano"
        case .pop: "Pop"
        case .rnb: "R&B"
        case .rock: "Rock"
        case .smallSpeakers: "Small Speakers"
        case .spokenWord: "Spoken Word"
        case .trebleBooster: "Treble Booster"
        case .trebleReducer: "Treble Reducer"
        case .vocalBooster: "Vocal Booster"
        }
    }

    static func matching(_ gains: [Double]) -> EqualizerPreset? {
        allCases.first { $0.gains == gains }
    }
}

/// One second-order filter section, normalized so a0 is 1 (Robert Bristow-Johnson's cookbook formulas).
struct BiquadCoefficients: Equatable {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0

    static let identity = BiquadCoefficients()

    enum Shape { case lowShelf, peaking, highShelf }

    init() {}

    init(shape: Shape, frequency: Double, gainDB: Double, q: Double = 0.9, sampleRate: Double) {
        guard gainDB != 0, sampleRate > 0 else { self = .identity; return }
        let f = min(frequency, sampleRate * 0.45)
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * f / sampleRate
        let cosw = cos(w0), sinw = sin(w0)
        var b0, b1, b2, a0, a1, a2: Double
        switch shape {
        case .peaking:
            let alpha = sinw / (2 * q)
            b0 = 1 + alpha * a; b1 = -2 * cosw; b2 = 1 - alpha * a
            a0 = 1 + alpha / a; a1 = -2 * cosw; a2 = 1 - alpha / a
        case .lowShelf, .highShelf:
            let alpha = sinw / 2 * sqrt(2)
            let root = 2 * sqrt(a) * alpha
            if shape == .lowShelf {
                b0 = a * ((a + 1) - (a - 1) * cosw + root)
                b1 = 2 * a * ((a - 1) - (a + 1) * cosw)
                b2 = a * ((a + 1) - (a - 1) * cosw - root)
                a0 = (a + 1) + (a - 1) * cosw + root
                a1 = -2 * ((a - 1) + (a + 1) * cosw)
                a2 = (a + 1) + (a - 1) * cosw - root
            } else {
                b0 = a * ((a + 1) + (a - 1) * cosw + root)
                b1 = -2 * a * ((a - 1) + (a + 1) * cosw)
                b2 = a * ((a + 1) + (a - 1) * cosw - root)
                a0 = (a + 1) - (a - 1) * cosw + root
                a1 = 2 * ((a - 1) - (a + 1) * cosw)
                a2 = (a + 1) - (a - 1) * cosw - root
            }
        }
        self.b0 = b0 / a0; self.b1 = b1 / a0; self.b2 = b2 / a0; self.a1 = a1 / a0; self.a2 = a2 / a0
    }

    /// Gain in decibels at `frequency`, used by tests to check the curve.
    func magnitudeDB(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        func complex(_ c0: Double, _ c1: Double, _ c2: Double) -> (Double, Double) {
            (c0 + c1 * cos(-w) + c2 * cos(-2 * w), c1 * sin(-w) + c2 * sin(-2 * w))
        }
        let num = complex(b0, b1, b2), den = complex(1, a1, a2)
        let magnitude = sqrt(num.0 * num.0 + num.1 * num.1) / sqrt(den.0 * den.0 + den.1 * den.1)
        return 20 * log10(magnitude)
    }
}

/// Settings shared between the main thread and every audio tap currently playing.
final class EqualizerSettings: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: (version: 0, equalizer: PlaybackEqualizer()))

    func update(_ equalizer: PlaybackEqualizer) {
        lock.withLock { state in
            guard state.equalizer != equalizer else { return }
            state.version += 1
            state.equalizer = equalizer
        }
    }

    func snapshot() -> (version: Int, equalizer: PlaybackEqualizer) { lock.withLock { $0 } }
}

/// Filter state for one audio stream. Used only on that stream's render thread; after the first buffer it
/// does not allocate.
final class EqualizerFilterBank {
    private let sampleRate: Double
    private var sections: [BiquadCoefficients] = []
    private var active: [Int] = []
    private var preamp: Float = 1
    /// Two delay values per section per channel (transposed direct form II), channel after channel.
    private var state: [Double] = []
    private var version = -1

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    func configure(_ equalizer: PlaybackEqualizer, version: Int) {
        guard version != self.version else { return }
        self.version = version
        let count = PlaybackEqualizer.frequencies.count
        sections = PlaybackEqualizer.frequencies.enumerated().map { band, frequency in
            let shape: BiquadCoefficients.Shape = band == 0 ? .lowShelf : band == count - 1 ? .highShelf : .peaking
            let gain = equalizer.gains.indices.contains(band) ? equalizer.gains[band] : 0
            return BiquadCoefficients(shape: shape, frequency: frequency, gainDB: gain, sampleRate: sampleRate)
        }
        active = sections.indices.filter { sections[$0] != .identity }
        preamp = Float(pow(10, equalizer.preampDB / 20))
    }

    /// Filters interleaved samples in place; `firstChannel` numbers channels across separate buffers.
    func process(_ samples: UnsafeMutableBufferPointer<Float>, channels: Int, firstChannel: Int) {
        guard channels > 0, !sections.isEmpty else { return }
        let stride = sections.count * 2
        let needed = (firstChannel + channels) * stride
        if state.count < needed { state.append(contentsOf: repeatElement(0, count: needed - state.count)) }
        let frames = samples.count / channels
        let preamp = self.preamp
        state.withUnsafeMutableBufferPointer { delays in
            sections.withUnsafeBufferPointer { coefficients in
                active.withUnsafeBufferPointer { active in
                    for channel in 0..<channels {
                        let base = (firstChannel + channel) * stride
                        for frame in 0..<frames {
                            let index = frame * channels + channel
                            var x = Double(samples[index] * preamp)
                            for section in active {
                                let c = coefficients[section]
                                let z = base + section * 2
                                let y = c.b0 * x + delays[z]
                                delays[z] = c.b1 * x - c.a1 * y + delays[z + 1]
                                delays[z + 1] = c.b2 * x - c.a2 * y
                                x = y
                            }
                            samples[index] = x.isFinite ? Float(x) : 0
                        }
                    }
                }
            }
        }
    }
}

/// Audio tap that applies the equalizer, then the normalization gain and peak limiter.
final class PlaybackAudioTap {
    let gain: Float
    let equalizer: EqualizerSettings?
    var supportsFormat = false
    var filters: EqualizerFilterBank?

    init(gain: Float, equalizer: EqualizerSettings?) {
        self.gain = gain
        self.equalizer = equalizer
    }

    static func audioMix(for track: AVAssetTrack, gain: Float, equalizer: EqualizerSettings?) -> AVAudioMix? {
        guard let tap = create(gain: gain, equalizer: equalizer) else { return nil }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    static func create(gain: Float, equalizer: EqualizerSettings?) -> MTAudioProcessingTap? {
        let state = Unmanaged.passRetained(PlaybackAudioTap(gain: gain, equalizer: equalizer))
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: state.toOpaque(),
            init: { _, info, storage in storage.pointee = info },
            finalize: { tap in Unmanaged<PlaybackAudioTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
            prepare: { tap, _, format in
                let state = Unmanaged<PlaybackAudioTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                let format = format.pointee
                state.supportsFormat = format.mFormatID == kAudioFormatLinearPCM && format.mBitsPerChannel == 32
                    && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
                    && format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0
                state.filters = state.equalizer == nil ? nil : EqualizerFilterBank(sampleRate: format.mSampleRate)
            },
            unprepare: { tap in
                let state = Unmanaged<PlaybackAudioTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                state.filters = nil
            },
            process: { tap, count, _, buffers, countOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(tap, count, buffers, flagsOut, nil, countOut)
                guard status == noErr, countOut.pointee > 0 else { countOut.pointee = 0; return }
                let state = Unmanaged<PlaybackAudioTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                guard state.supportsFormat else { return }
                var filters: EqualizerFilterBank?
                if let settings = state.equalizer, let bank = state.filters {
                    let snapshot = settings.snapshot()
                    if snapshot.equalizer.enabled, !snapshot.equalizer.isFlat {
                        bank.configure(snapshot.equalizer, version: snapshot.version)
                        filters = bank
                    }
                }
                var channel = 0
                for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
                    guard let data = buffer.mData else { continue }
                    let channels = Int(buffer.mNumberChannels)
                    let capacity = Int(buffer.mDataByteSize) / MemoryLayout<Float>.stride
                    let samples = UnsafeMutableBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                                                             count: min(capacity, countOut.pointee * channels))
                    filters?.process(samples, channels: channels, firstChannel: channel)
                    PlaybackLevelMeasurement.process(samples, gain: state.gain)
                    channel += channels
                }
            }
        )
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr else {
            state.release()
            return nil
        }
        return tap
    }
}
