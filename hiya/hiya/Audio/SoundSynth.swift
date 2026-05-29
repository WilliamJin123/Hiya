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

    /// Five-second seamless drone for the loading-screen ambient bed. Three
    /// sine voices at 60 / 90 / 120 Hz — every voice completes an integer
    /// number of cycles inside the duration (60×5 = 300, 90×5 = 450, 120×5
    /// = 600), so the loop seam lands at zero crossings for all of them and
    /// there's no click on the wraparound. Flat envelope (no attack/decay)
    /// for the same reason — any envelope shape would break the seam.
    static func renderAmbience(durationSec: Double = 5.0) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(durationSec * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }

        // (frequency Hz, amplitude). Low register; volume is dialed in further
        // at the player level so the bed sits well under any action sound.
        let voices: [(Double, Double)] = [
            (60.0,  0.10),
            (90.0,  0.08),
            (120.0, 0.07),
        ]

        let totalFrames = Int(frameCount)
        for i in 0..<totalFrames {
            let t = Double(i) / sampleRate
            var mix: Double = 0
            for (freq, amp) in voices {
                mix += sin(2 * .pi * freq * t) * amp
            }
            samples[i] = Float(tanh(mix))
        }
        return buffer
    }

    /// Wrap a rendered Float32 buffer in 16-bit PCM WAV bytes so it can be
    /// handed to `AVAudioPlayer(data:)` — the simpler, more reliable playback
    /// path. 16-bit PCM (format code 1) is the most broadly-accepted WAV
    /// shape; AVAudioPlayer is rock-solid with it.
    static func wavData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatSamples = buffer.floatChannelData?[0] else { return nil }
        let sampleRate = UInt32(buffer.format.sampleRate)
        let channels = UInt16(buffer.format.channelCount)
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = Int(bitsPerSample / 8)
        let frameCount = Int(buffer.frameLength)
        let dataSize = UInt32(frameCount * Int(channels) * bytesPerSample)

        // Float [-1, 1] → Int16 little-endian.
        var pcm = Data(capacity: Int(dataSize))
        for i in 0..<frameCount {
            let clamped = max(-1.0, min(1.0, floatSamples[i]))
            let int16 = Int16(clamped * Float(Int16.max))
            var le = int16.littleEndian
            Swift.withUnsafeBytes(of: &le) { pcm.append(contentsOf: $0) }
        }

        // Standard RIFF/WAVE header — see http://soundfile.sapp.org/doc/WaveFormat/
        var header = Data()
        header.append(Data("RIFF".utf8))
        header.appendUInt32LE(36 + dataSize)
        header.append(Data("WAVE".utf8))
        header.append(Data("fmt ".utf8))
        header.appendUInt32LE(16)                              // fmt subchunk size
        header.appendUInt16LE(1)                               // 1 == PCM
        header.appendUInt16LE(channels)
        header.appendUInt32LE(sampleRate)
        header.appendUInt32LE(sampleRate * UInt32(channels) * UInt32(bytesPerSample)) // byte rate
        header.appendUInt16LE(channels * UInt16(bytesPerSample))                       // block align
        header.appendUInt16LE(bitsPerSample)
        header.append(Data("data".utf8))
        header.appendUInt32LE(dataSize)

        return header + pcm
    }
}

private extension Data {
    // `Swift.withUnsafeBytes(of:_:)` because the unqualified name binds to
    // `Data`'s own `withUnsafeBytes` instance method when called from a
    // `Data` extension.
    mutating func appendUInt16LE(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
    mutating func appendUInt32LE(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
