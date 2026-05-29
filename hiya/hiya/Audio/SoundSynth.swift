import AVFoundation
import Foundation

/// Pure synthesis math: turns a `SoundSpec` into a PCM buffer via sine + FM
/// with an attack/exponential-decay envelope. Free of `AVAudioEngine` state,
/// so the tone/envelope code is unit-testable without an audio session.
enum SoundSynth {
    /// 44.1 kHz mono Float32 — the AVAudioEngine `standardFormat` shape.
    static let sampleRate: Double = 44_100

    /// Render a `SoundSpec` into a mono Float32 buffer ready for
    /// `AVAudioPlayerNode.scheduleBuffer`. Returns nil only if format/buffer
    /// allocation fails (effectively never on real devices).
    static func render(spec: SoundSpec) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(max(1, Int(spec.totalDurationSec * sampleRate)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }

        let totalFrames = Int(frameCount)
        for i in 0..<totalFrames {
            let t = Double(i) / sampleRate
            var mix: Double = 0
            for tone in spec.tones {
                mix += sample(of: tone, atTime: t)
            }
            // tanh saturation keeps overlapping peaks musical and dodges clicks
            // if two tones happen to align constructively at the same sample.
            samples[i] = Float(tanh(mix))
        }
        return buffer
    }

    /// One tone's contribution to the mix at absolute time `t` (seconds from
    /// the start of the SoundSpec). Returns 0 outside the tone's window.
    private static func sample(of tone: ToneSpec, atTime t: Double) -> Double {
        let localT = t - tone.startSec
        guard localT >= 0, localT < tone.durationSec else { return 0 }
        let env = envelope(t: localT,
                           attack: tone.attackSec,
                           decay: tone.decaySec,
                           total: tone.durationSec)
        let twoPi = 2.0 * .pi
        let carrierPhase = twoPi * tone.frequencyHz * localT
        let modFrequency = tone.frequencyHz * tone.fmRatio
        let modPhase = twoPi * modFrequency * localT
        let modulator = sin(modPhase) * tone.fmIndex
        return sin(carrierPhase + modulator) * env * tone.amplitude
    }

    /// Linear attack, exponential decay, plus an 8 ms linear tail fade so the
    /// buffer never ends on a non-zero sample (which would click). Returns 0..1.
    static func envelope(t: Double, attack: Double, decay: Double, total: Double) -> Double {
        if attack > 0, t < attack {
            return t / attack
        }
        let decayT = t - attack
        let value = exp(-decayT / max(0.0001, decay))
        let tailFadeWindow: Double = 0.008
        if t > total - tailFadeWindow {
            let f = (total - t) / tailFadeWindow
            return value * max(0, f)
        }
        return value
    }
}
