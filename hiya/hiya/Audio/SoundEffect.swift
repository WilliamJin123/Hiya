import Foundation

/// Sound moments the app intentionally voices. Each case has a `spec` that
/// `SoundSynth` renders to a PCM buffer once at launch — `SoundEngine` plays
/// the cached buffer on demand, so taps stay cheap.
///
/// **Aesthetic**: sine carriers with light FM modulation (≤2x index) — soft
/// "bell" timbre, never harsh. Intervals are major / perfect to keep the
/// good-vibes side; short attacks + exponential decays + reverb give the
/// techy / ambient side. Reverb is applied at the engine level, not baked in.
enum SoundEffect: String, Sendable, CaseIterable {
    case saveSuccess
    case saveFailure
    case achievement
    case modeSwitch
    case tab
    case sheetOpen
}

/// One sine + FM tone with its own simple attack-decay envelope. Multiple
/// `ToneSpec`s in a `SoundSpec` can overlap (`startSec` offsets).
struct ToneSpec: Sendable, Equatable {
    let startSec: Double      // offset within the SoundSpec when this tone begins
    let durationSec: Double   // how long the tone is audible
    let frequencyHz: Double
    let attackSec: Double     // linear ramp-in; 0..durationSec
    let decaySec: Double      // exponential decay time constant (τ in `exp(-t/τ)`)
    let amplitude: Double     // 0..1
    /// Sine-FM modulator depth (0 = pure sine). 1–2 gives bell-like overtones.
    let fmIndex: Double
    /// Modulator frequency = `frequencyHz * fmRatio`. Integer ratios stay harmonic.
    let fmRatio: Double

    init(
        startSec: Double = 0,
        durationSec: Double,
        frequencyHz: Double,
        attackSec: Double = 0.005,
        decaySec: Double = 0.18,
        amplitude: Double = 0.4,
        fmIndex: Double = 0,
        fmRatio: Double = 2
    ) {
        self.startSec = startSec
        self.durationSec = durationSec
        self.frequencyHz = frequencyHz
        self.attackSec = attackSec
        self.decaySec = decaySec
        self.amplitude = amplitude
        self.fmIndex = fmIndex
        self.fmRatio = fmRatio
    }
}

/// A complete effect: tone sequence plus the total render duration. The total
/// is usually a bit longer than the last tone's end so the reverb tail has
/// room to breathe before the buffer ends.
struct SoundSpec: Sendable, Equatable {
    let tones: [ToneSpec]
    let totalDurationSec: Double
}

extension SoundEffect {
    /// Tone/envelope blueprint for this effect. Tuned by ear; tweak here to
    /// re-character a moment without touching the engine or call sites.
    var spec: SoundSpec {
        switch self {
        case .saveSuccess:
            // C5 → G5: perfect fifth, clean and open. "Done, on to the next."
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0,    durationSec: 0.14, frequencyHz: 523.25,
                             attackSec: 0.004, decaySec: 0.10, amplitude: 0.42,
                             fmIndex: 1.2, fmRatio: 2),
                    ToneSpec(startSec: 0.07, durationSec: 0.18, frequencyHz: 783.99,
                             attackSec: 0.004, decaySec: 0.12, amplitude: 0.40,
                             fmIndex: 1.0, fmRatio: 2),
                ],
                totalDurationSec: 0.40
            )
        case .saveFailure:
            // Bb4 → G4: descending minor third. Reads as "nope" without buzzing.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0,    durationSec: 0.12, frequencyHz: 466.16,
                             attackSec: 0.005, decaySec: 0.08, amplitude: 0.45,
                             fmIndex: 0.6, fmRatio: 1.5),
                    ToneSpec(startSec: 0.08, durationSec: 0.22, frequencyHz: 392.00,
                             attackSec: 0.005, decaySec: 0.14, amplitude: 0.45,
                             fmIndex: 0.5, fmRatio: 1.5),
                ],
                totalDurationSec: 0.45
            )
        case .achievement:
            // C5 → E5 → G5 → C6: major arpeggio, octave-resolving final note.
            // The celebratory moment when the ring fills to 10.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0.00, durationSec: 0.10, frequencyHz: 523.25,
                             attackSec: 0.004, decaySec: 0.08, amplitude: 0.40,
                             fmIndex: 0.8, fmRatio: 2),
                    ToneSpec(startSec: 0.08, durationSec: 0.10, frequencyHz: 659.25,
                             attackSec: 0.004, decaySec: 0.08, amplitude: 0.42,
                             fmIndex: 0.8, fmRatio: 2),
                    ToneSpec(startSec: 0.16, durationSec: 0.10, frequencyHz: 783.99,
                             attackSec: 0.004, decaySec: 0.08, amplitude: 0.44,
                             fmIndex: 0.8, fmRatio: 2),
                    ToneSpec(startSec: 0.24, durationSec: 0.34, frequencyHz: 1046.50,
                             attackSec: 0.005, decaySec: 0.22, amplitude: 0.50,
                             fmIndex: 1.0, fmRatio: 2),
                ],
                totalDurationSec: 0.85
            )
        case .modeSwitch:
            // Single short F#5 — clean blip; just enough modulation to feel "synth"
            // rather than "system beep".
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.10, frequencyHz: 739.99,
                             attackSec: 0.003, decaySec: 0.07, amplitude: 0.30,
                             fmIndex: 0.5, fmRatio: 2),
                ],
                totalDurationSec: 0.20
            )
        case .tab:
            // Quietest of all — a C5 dot. Background-noise quiet so rapid tab
            // hopping doesn't get annoying.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.06, frequencyHz: 523.25,
                             attackSec: 0.002, decaySec: 0.04, amplitude: 0.22,
                             fmIndex: 0.3, fmRatio: 2),
                ],
                totalDurationSec: 0.15
            )
        case .sheetOpen:
            // F4 → C5: rising perfect fifth, a short upward "lift".
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0,    durationSec: 0.08, frequencyHz: 349.23,
                             attackSec: 0.003, decaySec: 0.06, amplitude: 0.28,
                             fmIndex: 0.7, fmRatio: 1.5),
                    ToneSpec(startSec: 0.05, durationSec: 0.16, frequencyHz: 523.25,
                             attackSec: 0.003, decaySec: 0.11, amplitude: 0.32,
                             fmIndex: 0.7, fmRatio: 1.5),
                ],
                totalDurationSec: 0.32
            )
        }
    }
}
