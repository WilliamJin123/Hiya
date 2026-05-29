import Foundation

/// Sound moments the app intentionally voices. Each case has a `spec` that
/// `SoundSynth` renders to a PCM buffer once at launch — `SoundEngine` plays
/// the cached buffer on demand, so taps stay cheap.
///
/// **Aesthetic**: soft sine chords with slow attacks and long exponential
/// tails. Almost no FM (the previous bell-FM voiced too "game-y"); the chord
/// stack supplies richness instead. Lower fundamentals (C4–A4 register) for
/// warmth. Intervals stay major / perfect for good vibes.
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
            // C4 + E4 + G4 — major triad, soft bloom + long tail. "Settled."
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.80, frequencyHz: 261.63,   // C4
                             attackSec: 0.025, decaySec: 0.55, amplitude: 0.16,
                             fmIndex: 0.1, fmRatio: 3),
                    ToneSpec(startSec: 0, durationSec: 0.80, frequencyHz: 329.63,   // E4
                             attackSec: 0.025, decaySec: 0.55, amplitude: 0.14,
                             fmIndex: 0.1, fmRatio: 3),
                    ToneSpec(startSec: 0, durationSec: 0.90, frequencyHz: 392.00,   // G4
                             attackSec: 0.025, decaySec: 0.60, amplitude: 0.13,
                             fmIndex: 0.1, fmRatio: 3),
                ],
                totalDurationSec: 1.20
            )
        case .saveFailure:
            // A3 + C4 — low minor third. Reads as "didn't work" without alarm.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.70, frequencyHz: 220.00,   // A3
                             attackSec: 0.030, decaySec: 0.50, amplitude: 0.18,
                             fmIndex: 0.0, fmRatio: 2),
                    ToneSpec(startSec: 0, durationSec: 0.70, frequencyHz: 261.63,   // C4
                             attackSec: 0.030, decaySec: 0.50, amplitude: 0.16,
                             fmIndex: 0.0, fmRatio: 2),
                ],
                totalDurationSec: 1.00
            )
        case .achievement:
            // Slow blooming arpeggio — C4 → E4 → G4 → C5. Each note overlaps
            // the previous, so the ending is a full C-major chord with the
            // octave. Long elegant tail; deliberately not a stinger.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0.00, durationSec: 1.00, frequencyHz: 261.63,
                             attackSec: 0.025, decaySec: 0.55, amplitude: 0.13,
                             fmIndex: 0.1, fmRatio: 3),
                    ToneSpec(startSec: 0.15, durationSec: 0.95, frequencyHz: 329.63,
                             attackSec: 0.025, decaySec: 0.55, amplitude: 0.13,
                             fmIndex: 0.1, fmRatio: 3),
                    ToneSpec(startSec: 0.30, durationSec: 0.90, frequencyHz: 392.00,
                             attackSec: 0.025, decaySec: 0.55, amplitude: 0.13,
                             fmIndex: 0.1, fmRatio: 3),
                    ToneSpec(startSec: 0.45, durationSec: 0.95, frequencyHz: 523.25,
                             attackSec: 0.030, decaySec: 0.65, amplitude: 0.16,
                             fmIndex: 0.1, fmRatio: 3),
                ],
                totalDurationSec: 1.50
            )
        case .modeSwitch:
            // Single warm D4 — felt-mallet-on-bell vibe. Pure sine, no FM.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.35, frequencyHz: 293.66,   // D4
                             attackSec: 0.018, decaySec: 0.22, amplitude: 0.14,
                             fmIndex: 0.0, fmRatio: 2),
                ],
                totalDurationSec: 0.45
            )
        case .tab:
            // Background-noise level. F4 dot, brief and unobtrusive.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.20, frequencyHz: 349.23,   // F4
                             attackSec: 0.012, decaySec: 0.15, amplitude: 0.09,
                             fmIndex: 0.0, fmRatio: 2),
                ],
                totalDurationSec: 0.28
            )
        case .sheetOpen:
            // E4 + A4 — perfect fourth, gentle bloom with a slight upward feel.
            // Long-ish attack (40 ms) so it never reads as a click.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.55, frequencyHz: 329.63,   // E4
                             attackSec: 0.040, decaySec: 0.30, amplitude: 0.13,
                             fmIndex: 0.0, fmRatio: 2),
                    ToneSpec(startSec: 0, durationSec: 0.55, frequencyHz: 440.00,   // A4
                             attackSec: 0.040, decaySec: 0.30, amplitude: 0.12,
                             fmIndex: 0.0, fmRatio: 2),
                ],
                totalDurationSec: 0.75
            )
        }
    }
}
