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
}
