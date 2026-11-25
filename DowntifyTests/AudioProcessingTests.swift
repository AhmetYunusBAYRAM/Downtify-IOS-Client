import AVFoundation
import XCTest
@testable import Downtify

/// Runs real audio through the code that shapes it during playback: the equalizer's audio tap (offline, with
/// the same `AVAudioMix` the player uses) and the engine's crossfade between two playing `AVPlayer`s.
final class AudioProcessingTests: XCTestCase {
    private var files: [URL] = []

    override func tearDown() {
        files.forEach { try? FileManager.default.removeItem(at: $0) }
        files = []
        super.tearDown()
    }

    // MARK: Equalizer tap

    func testEqualizerTapBoostsTheBandAndLeavesOthersAtThePreamp() async throws {
        var boost = PlaybackEqualizer()
        boost.enabled = true
        boost.gains = [0, 0, 0, 12, 0, 0]  // +12 dB at 1 kHz; the tap lowers everything by 6 dB of headroom.
        let mid = try tone(frequency: 1_000)
        let low = try tone(frequency: 60)

        let midChange = try await level(of: mid, equalizer: boost) - level(of: mid, equalizer: nil)
        let lowChange = try await level(of: low, equalizer: boost) - level(of: low, equalizer: nil)
        XCTAssertEqual(midChange, 12 + boost.preampDB, accuracy: 1, "the boosted band rises by its gain less the headroom")
        XCTAssertEqual(lowChange, boost.preampDB, accuracy: 1, "a distant band only gets the headroom")
    }

    func testEqualizerTapCutsAShelf() async throws {
        var cut = PlaybackEqualizer()
        cut.enabled = true
        cut.gains = [-12, 0, 0, 0, 0, 0]
        let low = try tone(frequency: 40)
        let mid = try tone(frequency: 1_000)
        let lowChange = try await level(of: low, equalizer: cut) - level(of: low, equalizer: nil)
        let midChange = try await level(of: mid, equalizer: cut) - level(of: mid, equalizer: nil)
        XCTAssertLessThan(lowChange, -9, "the low shelf cuts bass")
        XCTAssertEqual(midChange, 0, accuracy: 0.5, "a cut needs no headroom, so mids are untouched")
    }

    func testDisabledOrFlatEqualizerPassesAudioThroughUnchanged() async throws {
        let mid = try tone(frequency: 1_000)
        let original = try await render(mid, equalizer: nil)
        var off = PlaybackEqualizer()
        off.gains = [6, 6, 6, 6, 6, 6]
        let disabled = try await render(mid, equalizer: off)
        var flat = PlaybackEqualizer()
        flat.enabled = true
        let flatOn = try await render(mid, equalizer: flat)
        XCTAssertEqual(original.count, disabled.count)
        XCTAssertEqual(zip(original, disabled).map { abs($0 - $1) }.max() ?? 1, 0, accuracy: 1e-6)
        XCTAssertEqual(zip(original, flatOn).map { abs($0 - $1) }.max() ?? 1, 0, accuracy: 1e-6)
    }

    func testEqualizerChangeTakesEffectWhileAudioIsPlaying() async throws {
        let mid = try tone(frequency: 1_000, seconds: 4)
        let settings = EqualizerSettings()
        var boost = PlaybackEqualizer()
        boost.enabled = true
        boost.gains = [0, 0, 0, 12, 0, 0]
        // Starts flat; the band moves after the first second has been processed, as when a listener drags it.
        let samples = try await render(mid, settings: settings, after: 1) { settings.update(boost) }
        let rate = 44_100
        let before = rmsDB(samples[(rate / 4)..<(rate * 3 / 4)])
        let after = rmsDB(samples[(rate * 3)..<(rate * 7 / 2)])
        XCTAssertEqual(after - before, 12 + boost.preampDB, accuracy: 1)
    }

    func testNormalizationGainAndLimiterStillApplyWithTheEqualizer() async throws {
        let mid = try tone(frequency: 1_000, amplitude: 0.4)
        var boost = PlaybackEqualizer()
        boost.enabled = true
        boost.gains = [0, 0, 0, 12, 0, 0]
        // +6 dB net from the equalizer and 4x gain would reach ~3.2; the limiter holds it at its ceiling.
        let samples = try await render(mid, equalizer: boost, gain: 4)
        let peak = samples.map(abs).max() ?? 0
        XCTAssertEqual(peak, PlaybackLevelMeasurement.peakLimit, accuracy: 0.001)
    }

    // MARK: Engine

    @MainActor
    func testEngineInstallsAndRemovesTheEqualizerTapOnThePlayingItem() async throws {
        let engine = AVPlaybackEngine()
        defer { engine.reset() }
        try await engine.load(stream(for: tone(frequency: 1_000)), at: 0)
        XCTAssertNil(currentItem(of: engine)?.audioMix, "no tap while the equalizer and normalization are off")
        var boost = PlaybackEqualizer()
        boost.enabled = true
        boost.gains = [0, 0, 0, 12, 0, 0]
        engine.setEqualizer(boost)
        try await waitUntil { self.currentItem(of: engine)?.audioMix != nil }
        let tap = (currentItem(of: engine)?.audioMix?.inputParameters.first as? AVAudioMixInputParameters)?.audioTapProcessor
        XCTAssertNotNil(tap)
        boost.enabled = false
        engine.setEqualizer(boost)
        XCTAssertNil(currentItem(of: engine)?.audioMix)
    }

    @MainActor
    func testEngineCrossfadeOverlapsTwoPlayingSongsWithEqualPowerFades() async throws {
        let engine = AVPlaybackEngine()
        defer { engine.cancelCrossfade(); engine.reset() }
        try await engine.load(stream(for: tone(frequency: 440, seconds: 6)), at: 0)
        engine.play()
        let first = try XCTUnwrap(player(of: engine))
        try await waitUntil { first.timeControlStatus == .playing && first.currentTime().seconds > 0.2 }

        engine.beginCrossfade(over: 1.5)
        try await engine.load(stream(for: tone(frequency: 880, seconds: 6)), at: 0)
        engine.play()
        let second = try XCTUnwrap(player(of: engine))
        XCTAssertFalse(first === second, "the next song plays on its own player")
        XCTAssertTrue(outgoing(of: engine) === first, "the previous song keeps playing while it fades")

        try await Task.sleep(for: .milliseconds(700))
        let firstTime = first.currentTime().seconds
        XCTAssertEqual(first.rate, 1, "the fading song is still playing")
        XCTAssertGreaterThan(first.volume, 0.05)
        XCTAssertLessThan(first.volume, 0.95)
        XCTAssertGreaterThan(second.volume, 0.05)
        XCTAssertLessThan(second.volume, 0.95)
        // Equal power: the squared volumes add up to one through the overlap (sampled ~same instant).
        XCTAssertEqual(first.volume * first.volume + second.volume * second.volume, 1, accuracy: 0.15)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThan(first.currentTime().seconds, firstTime, "the fading song advances")

        try await waitUntil(timeout: 3) { self.outgoing(of: engine) == nil }
        XCTAssertNil(first.currentItem, "the faded song is released")
        XCTAssertEqual(second.volume, 1)
        XCTAssertEqual(second.timeControlStatus, .playing)
    }

    @MainActor
    func testPausingDuringACrossfadeStopsTheFadingSongAndRestoresVolume() async throws {
        let engine = AVPlaybackEngine()
        defer { engine.reset() }
        try await engine.load(stream(for: tone(frequency: 440, seconds: 6)), at: 0)
        engine.play()
        let first = try XCTUnwrap(player(of: engine))
        try await waitUntil { first.timeControlStatus == .playing }
        engine.beginCrossfade(over: 3)
        try await engine.load(stream(for: tone(frequency: 880, seconds: 6)), at: 0)
        engine.play()
        try await Task.sleep(for: .milliseconds(300))
        engine.pause()
        XCTAssertNil(outgoing(of: engine))
        XCTAssertEqual(first.rate, 0)
        XCTAssertEqual(player(of: engine)?.volume, 1)
    }

    func testCrossfadeCurvesKeepConstantPower() {
        for step in 0...20 {
            let progress = Double(step) / 20
            let out = CrossfadeCurve.fadeOut(progress), into = CrossfadeCurve.fadeIn(progress)
            XCTAssertEqual(out * out + into * into, 1, accuracy: 1e-5)
        }
        XCTAssertEqual(CrossfadeCurve.fadeOut(0), 1)
        XCTAssertEqual(CrossfadeCurve.fadeIn(0), 0)
        XCTAssertEqual(CrossfadeCurve.fadeOut(1), 0, accuracy: 1e-6)
        XCTAssertEqual(CrossfadeCurve.fadeIn(1), 1)
    }

    // MARK: Helpers

    /// A stereo sine wave written as 32-bit float PCM.
    private func tone(frequency: Double, seconds: Double = 2, amplitude: Float = 0.1) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tone-\(UUID().uuidString).caf")
        files.append(url)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<2 {
            let data = try XCTUnwrap(buffer.floatChannelData?[channel])
            for frame in 0..<Int(frames) {
                data[frame] = amplitude * Float(sin(2 * Double.pi * frequency * Double(frame) / 44_100))
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func level(of url: URL, equalizer: PlaybackEqualizer?) async throws -> Double {
        let samples = try await render(url, equalizer: equalizer)
        // Skip the filters' settling time at the start and any decoder padding at the end.
        return rmsDB(samples[11_025..<(samples.count - 4_410)])
    }

    private func render(_ url: URL, equalizer: PlaybackEqualizer?, gain: Float = 1) async throws -> [Float] {
        let settings = equalizer.map { equalizer -> EqualizerSettings in
            let settings = EqualizerSettings()
            settings.update(equalizer)
            return settings
        }
        return try await render(url, settings: settings, gain: gain)
    }

    /// Reads the file through the playback audio tap, as the player does, and returns the left channel.
    /// `change` runs once `after` seconds of audio have come out of the tap.
    private func render(_ url: URL, settings: EqualizerSettings?, gain: Float = 1, after: Double? = nil,
                        change: (() -> Void)? = nil) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let track = try await XCTUnwrapAsync(await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
        ])
        output.audioMix = try XCTUnwrap(PlaybackAudioTap.audioMix(for: track, gain: gain, equalizer: settings))
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var left: [Float] = []
        var changed = change == nil
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var bytes = [Float](repeating: 0, count: length / MemoryLayout<Float>.stride)
            _ = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            left.append(contentsOf: stride(from: 0, to: bytes.count, by: 2).map { bytes[$0] })
            if !changed, let after, Double(left.count) >= after * 44_100 {
                change?()
                changed = true
            }
        }
        XCTAssertEqual(reader.status, .completed, reader.error.map { "\($0)" } ?? "")
        return left
    }

    private func rmsDB(_ samples: ArraySlice<Float>) -> Double {
        let power = samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(samples.count, 1))
        return 10 * log10(max(power, 1e-20))
    }

    private func stream(for url: URL) throws -> PlaybackStream {
        let length = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
        return PlaybackStream(contentType: "com.apple.coreaudio-format", fileExtension: "caf", length: length,
                              quality: .original, availableQualities: [.original], fileURL: url) { _ in Data() }
    }

    @MainActor private func player(of engine: AVPlaybackEngine) -> AVPlayer? {
        Mirror(reflecting: engine).children.first { $0.label == "player" }?.value as? AVPlayer
    }

    @MainActor private func currentItem(of engine: AVPlaybackEngine) -> AVPlayerItem? { player(of: engine)?.currentItem }

    @MainActor private func outgoing(of engine: AVPlaybackEngine) -> AVPlayer? {
        // `outgoing` is an optional (player, loader) tuple; unwrap it by reflection, as the loader type is private.
        guard let value = Mirror(reflecting: engine).children.first(where: { $0.label == "outgoing" })?.value,
              let pair = Mirror(reflecting: value).children.first?.value else { return nil }
        return Mirror(reflecting: pair).children.first { $0.label == "player" }?.value as? AVPlayer
    }

    @MainActor private func waitUntil(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out waiting for the condition") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
