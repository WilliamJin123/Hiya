import AVFoundation
import Testing
@testable import hiya

@MainActor
struct SoundSynthTests {
    @Test func envelope_linearAttack_thenExponentialDecay() {
        // Halfway through attack: 0.5.
        let attackMid = SoundSynth.envelope(t: 0.005, attack: 0.010, decay: 0.20, total: 0.30)
        #expect(abs(attackMid - 0.5) < 0.0001)

        // Just past attack: roughly 1.0 (decay hasn't significantly bitten yet).
        let postAttack = SoundSynth.envelope(t: 0.011, attack: 0.010, decay: 0.20, total: 0.30)
        #expect(postAttack > 0.99 && postAttack <= 1.0)

        // One time-constant past attack end: e^-1 ≈ 0.368.
        let oneTau = SoundSynth.envelope(t: 0.010 + 0.20, attack: 0.010, decay: 0.20, total: 0.40)
        #expect(abs(oneTau - 0.367879) < 0.001)
    }

    @Test func envelope_tailFadesToZero() {
        // The last sample of a SoundSpec must end at zero so the buffer
        // doesn't click on playback.
        let total = 0.20
        let endValue = SoundSynth.envelope(t: total, attack: 0.005, decay: 0.10, total: total)
        #expect(endValue == 0.0)
    }

    @Test func render_bufferLengthMatchesDuration() throws {
        let spec = SoundEffect.tab.spec
        let buffer = try #require(SoundSynth.render(spec: spec))
        let expectedFrames = AVAudioFrameCount(spec.totalDurationSec * SoundSynth.sampleRate)
        #expect(buffer.frameLength == expectedFrames)
        #expect(buffer.format.channelCount == 1)
        #expect(buffer.format.sampleRate == SoundSynth.sampleRate)
    }

    @Test func render_amplitudeWithinClippingBounds() throws {
        // tanh saturation in render() guarantees |sample| < 1 — verify on the
        // loudest effect (achievement's 4-note arpeggio is the densest mix).
        let buffer = try #require(SoundSynth.render(spec: SoundEffect.achievement.spec))
        let samples = try #require(buffer.floatChannelData?[0])
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            peak = max(peak, abs(samples[i]))
        }
        #expect(peak <= 1.0)
        // Sanity: at least *some* signal got rendered.
        #expect(peak > 0.05)
    }

    @Test func render_everyEffectProducesABuffer() {
        // Catches a spec going degenerate (zero duration, no tones, NaN freq).
        for effect in SoundEffect.allCases {
            #expect(SoundSynth.render(spec: effect.spec) != nil,
                    "\(effect) failed to render")
        }
    }

    @Test func sweep_degenerateRatioMatchesUnswept() throws {
        // A swept tone with pitchStartRatio == 1.0 must produce the same audio
        // as the unswept (.none) path — both formulas collapse to f·t. This
        // protects against subtle drift if either branch is changed later.
        let unswept = SoundSpec(tones: [
            ToneSpec(startSec: 0, durationSec: 0.20, frequencyHz: 440.0,
                     attackSec: 0.005, decaySec: 0.10, amplitude: 0.5),
        ], totalDurationSec: 0.20)
        let swept = SoundSpec(tones: [
            ToneSpec(startSec: 0, durationSec: 0.20, frequencyHz: 440.0,
                     pitchStartRatio: 1.0, pitchCurve: .exponential,
                     attackSec: 0.005, decaySec: 0.10, amplitude: 0.5),
        ], totalDurationSec: 0.20)
        let a = try #require(SoundSynth.render(spec: unswept)?.floatChannelData?[0])
        let b = try #require(SoundSynth.render(spec: swept)?.floatChannelData?[0])
        // Sample at a handful of phase-sensitive points across the buffer.
        let length = Int(0.20 * SoundSynth.sampleRate)
        for i in stride(from: 0, to: length, by: 441) {
            #expect(abs(a[i] - b[i]) < 1e-5,
                    "swept f0==f1 should equal unswept at frame \(i): \(a[i]) vs \(b[i])")
        }
    }

    @Test func sweep_producesFiniteSamples() throws {
        // Wide pitch sweeps run through `pow` and `log` — guard against any
        // value producing NaN/Inf, which would corrupt the WAV converter.
        let spec = SoundSpec(tones: [
            // 2-octave downward exponential sweep (D6 → D4).
            ToneSpec(startSec: 0, durationSec: 0.30, frequencyHz: 293.66,
                     pitchStartRatio: 4.0, pitchCurve: .exponential,
                     attackSec: 0.005, decaySec: 0.20, amplitude: 0.6),
            // 2-octave upward linear sweep (A2 → A4).
            ToneSpec(startSec: 0, durationSec: 0.30, frequencyHz: 440.0,
                     pitchStartRatio: 0.25, pitchCurve: .linear,
                     attackSec: 0.005, decaySec: 0.20, amplitude: 0.4),
        ], totalDurationSec: 0.30)
        let buffer = try #require(SoundSynth.render(spec: spec))
        let samples = try #require(buffer.floatChannelData?[0])
        for i in 0..<Int(buffer.frameLength) {
            #expect(samples[i].isFinite, "sample \(i) was not finite: \(samples[i])")
        }
    }

    @Test func renderAmbience_loopsCleanly() throws {
        // The drone has to start AND end at near-zero so the loop seam
        // doesn't click. With 60/90/120 Hz voices over 5 s, every voice
        // completes an integer number of cycles, so both boundary samples
        // should land on the zero crossings.
        let buffer = try #require(SoundSynth.renderAmbience(durationSec: 5.0))
        let samples = try #require(buffer.floatChannelData?[0])
        let last = Int(buffer.frameLength) - 1

        #expect(abs(samples[0]) < 0.01,
                "first sample should be ~0, was \(samples[0])")
        #expect(abs(samples[last]) < 0.05,
                "last sample should be ~0, was \(samples[last])")

        // And the bed should actually be producing signal in the middle —
        // catches a degenerate spec that goes silent.
        let midPeak = (0..<Int(buffer.frameLength))
            .lazy.map { abs(samples[$0]) }.max() ?? 0
        #expect(midPeak > 0.05)
    }

    @Test func wavData_hasRiffHeaderAndCorrectSizes() throws {
        let buffer = try #require(SoundSynth.render(spec: SoundEffect.tab.spec))
        let wav = try #require(SoundSynth.wavData(from: buffer))

        // Sanity: 44-byte header + samples * 2 bytes (Int16).
        let expectedSize = 44 + Int(buffer.frameLength) * 2
        #expect(wav.count == expectedSize)

        // "RIFF" / "WAVE" / "fmt " / "data" markers in the right slots.
        #expect(wav.prefix(4) == Data("RIFF".utf8))
        #expect(wav.subdata(in: 8..<12) == Data("WAVE".utf8))
        #expect(wav.subdata(in: 12..<16) == Data("fmt ".utf8))
        #expect(wav.subdata(in: 36..<40) == Data("data".utf8))

        // AVAudioPlayer round-trip: if our WAV bytes parse, the player builds.
        let player = try AVAudioPlayer(data: wav)
        #expect(player.duration > 0)
    }
}
