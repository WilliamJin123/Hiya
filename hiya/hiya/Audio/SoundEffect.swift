import Foundation

/// Sound moments the app intentionally voices. Each case has a `spec` that
/// `SoundSynth` renders to a PCM buffer once at launch — `SoundEngine` plays
/// the cached buffer on demand, so taps stay cheap.
///
/// **Aesthetic**: tonal but not obviously musical. Frequencies are picked off
/// the equal-tempered grid (250 Hz instead of C4's 261.63) and upper voices
/// sit at non-standard ratios (≈1.47×, ≈1.18×) so the ear hears "pitched
/// sound design" rather than "I recognize that chord". Pure sine, slow
/// attacks (20–80 ms), long exponential tails for the elegant side.
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
    ///
    /// Knobs that drive the "elegant vs. game-y" axis (from most to least
    /// impactful):
    ///   - `attackSec`     — 3-5 ms = percussive click; 20-45 ms = gentle bloom
    ///   - `fmIndex`       — 0 = pure sine (clean / breath); ≥1 = bell / synth
    ///   - chord stacking  — simultaneous tones at chord intervals = richness
    ///   - register        — C4-A4 = warm; above C5 = bright / arcade-y
    ///   - `decaySec`      — 0.05-0.15 s = stab; 0.4-0.7 s = lingering tail
    var spec: SoundSpec {
        switch self {
        case .saveSuccess:
            // 250 + 378 — fundamental + shadow at ≈1.51× (off perfect fifth).
            // Tonal pair, not a recognizable chord.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.85, frequencyHz: 250.0,
                             attackSec: 0.030, decaySec: 0.55, amplitude: 0.18,
                             fmIndex: 0.0, fmRatio: 2),
                    ToneSpec(startSec: 0, durationSec: 0.90, frequencyHz: 378.0,
                             attackSec: 0.030, decaySec: 0.55, amplitude: 0.13,
                             fmIndex: 0.0, fmRatio: 2),
                ],
                totalDurationSec: 1.20
            )
        case .saveFailure:
            // 200 + 236 — narrow interval (≈1.18×), neutral rather than alarmed.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.75, frequencyHz: 200.0,
                             attackSec: 0.035, decaySec: 0.50, amplitude: 0.18,
                             fmIndex: 0.0, fmRatio: 2),
                    ToneSpec(startSec: 0, durationSec: 0.75, frequencyHz: 236.0,
                             attackSec: 0.035, decaySec: 0.50, amplitude: 0.15,
                             fmIndex: 0.0, fmRatio: 2),
                ],
                totalDurationSec: 1.00
            )
        case .achievement:
            // Three voices, staggered entrance, slightly detuned octave-ish
            // span (220 → 331 → 444). Reads as a swell, not an arpeggio.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0.00, durationSec: 1.30, frequencyHz: 220.0,
                             attackSec: 0.080, decaySec: 0.60, amplitude: 0.14,
                             fmIndex: 0.0, fmRatio: 2),
                    ToneSpec(startSec: 0.10, durationSec: 1.20, frequencyHz: 331.0,
                             attackSec: 0.080, decaySec: 0.60, amplitude: 0.13,
                             fmIndex: 0.0, fmRatio: 2),
                    ToneSpec(startSec: 0.22, durationSec: 1.20, frequencyHz: 444.0,
                             attackSec: 0.090, decaySec: 0.65, amplitude: 0.12,
                             fmIndex: 0.0, fmRatio: 2),
                ],
                totalDurationSec: 1.80
            )
        case .modeSwitch:
            // Single 290 Hz tone (slightly off D4). Pure sine, brief.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.40, frequencyHz: 290.0,
                             attackSec: 0.022, decaySec: 0.25, amplitude: 0.14,
                             fmIndex: 0.0, fmRatio: 2),
                ],
                totalDurationSec: 0.50
            )
        case .tab:
            // 340 Hz dot — quietest of all. Slightly different from modeSwitch
            // so the two don't blur together.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.22, frequencyHz: 340.0,
                             attackSec: 0.012, decaySec: 0.16, amplitude: 0.09,
                             fmIndex: 0.0, fmRatio: 2),
                ],
                totalDurationSec: 0.30
            )
        case .sheetOpen:
            // 320 + 470 — ≈1.47× ratio, tonal but neither a fourth nor fifth.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.60, frequencyHz: 320.0,
                             attackSec: 0.045, decaySec: 0.30, amplitude: 0.13,
                             fmIndex: 0.0, fmRatio: 2),
                    ToneSpec(startSec: 0, durationSec: 0.60, frequencyHz: 470.0,
                             attackSec: 0.045, decaySec: 0.30, amplitude: 0.12,
                             fmIndex: 0.0, fmRatio: 2),
                ],
                totalDurationSec: 0.80
            )
        }
    }
}
