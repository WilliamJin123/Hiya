import Foundation

/// Sound moments the app intentionally voices. Each case has a `spec` that
/// `SoundSynth` renders to a PCM buffer once at launch — `SoundEngine` plays
/// the cached buffer on demand, so taps stay cheap.
///
/// **Aesthetic**: musical chord underneath + pitched sweep on top — Rocket-
/// League-flavored sound design. Real intervals (perfect 5ths, octaves, major
/// triads) make the chords sit pleasantly. Each save/open also has a fast
/// pitched zip (50–120 ms) layered in for "snap" — that's the synthy/game
/// half. Sustained voices use slow attacks (25–80 ms) so nothing barks.
enum SoundEffect: String, Sendable, CaseIterable {
    case saveSuccess
    case saveFailure
    case achievement
    case modeSwitch
    case tab
    case sheetOpen
}

/// Shape of a pitch sweep over the tone's duration. `none` keeps the carrier
/// at `frequencyHz` (the previous, unswept behavior). `linear` and
/// `exponential` interpolate from `frequencyHz * pitchStartRatio` at t=0 to
/// `frequencyHz` at t=durationSec — exponential matches how the ear hears
/// pitch (1 octave = ratio 2, regardless of base frequency).
enum PitchSweepCurve: Sendable, Equatable {
    case none
    case linear
    case exponential
}

/// One sine + FM tone with its own simple attack-decay envelope. Multiple
/// `ToneSpec`s in a `SoundSpec` can overlap (`startSec` offsets).
struct ToneSpec: Sendable, Equatable {
    let startSec: Double      // offset within the SoundSpec when this tone begins
    let durationSec: Double   // how long the tone is audible
    let frequencyHz: Double   // target/end frequency; also the static pitch when curve == .none
    /// Multiplier applied to `frequencyHz` to get the *start* frequency. `1.0`
    /// = no sweep. `2.0` starts one octave up and glides down; `0.5` starts
    /// one octave down and rises. Combined with `pitchCurve`.
    let pitchStartRatio: Double
    let pitchCurve: PitchSweepCurve
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
        pitchStartRatio: Double = 1.0,
        pitchCurve: PitchSweepCurve = .none,
        attackSec: Double = 0.005,
        decaySec: Double = 0.18,
        amplitude: Double = 0.4,
        fmIndex: Double = 0,
        fmRatio: Double = 2
    ) {
        self.startSec = startSec
        self.durationSec = durationSec
        self.frequencyHz = frequencyHz
        self.pitchStartRatio = pitchStartRatio
        self.pitchCurve = pitchCurve
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
    /// Two layers per effect (where it makes sense):
    ///   1. **Sweep voice**  — short pitched zip (`pitchCurve: .exponential`)
    ///      that lands on a chord tone. Adds the Rocket-League snap.
    ///   2. **Chord voices** — sustained tones at real musical intervals
    ///      (perfect 5ths, octaves, triads). Slow attack so they bloom in
    ///      under the zip instead of competing with it.
    ///
    /// Knobs:
    ///   - `pitchStartRatio` — `>1` zips down into the tone; `<1` zips up
    ///   - `attackSec`       — 3-10 ms for the zip; 25-80 ms for chord voices
    ///   - `decaySec`        — short on the zip (0.04-0.10 s), long on chord
    ///                         voices (0.35-0.65 s) for a lingering tail
    var spec: SoundSpec {
        switch self {
        case .saveSuccess:
            // D4 + A4 perfect fifth bloom, with a quick downward zip from D5
            // landing on D4 — the zip gives the "pickup" snap, the chord
            // underneath gives the pleasant resolution.
            return SoundSpec(
                tones: [
                    // Zip: D5 → D4 over 80 ms (one octave down, exponential).
                    ToneSpec(startSec: 0.00, durationSec: 0.10, frequencyHz: 293.66,
                             pitchStartRatio: 2.0, pitchCurve: .exponential,
                             attackSec: 0.003, decaySec: 0.06, amplitude: 0.11),
                    // Chord: D4.
                    ToneSpec(startSec: 0.04, durationSec: 0.85, frequencyHz: 293.66,
                             attackSec: 0.030, decaySec: 0.45, amplitude: 0.15),
                    // Chord: A4 (perfect 5th above).
                    ToneSpec(startSec: 0.05, durationSec: 0.85, frequencyHz: 440.00,
                             attackSec: 0.035, decaySec: 0.45, amplitude: 0.12),
                ],
                totalDurationSec: 1.10
            )
        case .saveFailure:
            // Soft descending minor-third glide (G3 → E3). Single voice,
            // no chord — "didn't land" without sounding alarmed.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.55, frequencyHz: 164.81,
                             pitchStartRatio: 196.0 / 164.81, pitchCurve: .exponential,
                             attackSec: 0.020, decaySec: 0.32, amplitude: 0.17),
                ],
                totalDurationSec: 0.80
            )
        case .achievement:
            // Full C-major triad with octave (C4-E4-G4-C5), staggered entry,
            // led by an upward swept voice that arrives first. Reads as a
            // triumphant swell — RL goal-scored energy without the cheer.
            return SoundSpec(
                tones: [
                    // Lead sweep: A3 → C5 over 180 ms — sets up the chord.
                    ToneSpec(startSec: 0.00, durationSec: 0.22, frequencyHz: 523.25,
                             pitchStartRatio: 220.0 / 523.25, pitchCurve: .exponential,
                             attackSec: 0.005, decaySec: 0.14, amplitude: 0.10),
                    // C4.
                    ToneSpec(startSec: 0.06, durationSec: 1.40, frequencyHz: 261.63,
                             attackSec: 0.050, decaySec: 0.65, amplitude: 0.13),
                    // E4 (major 3rd).
                    ToneSpec(startSec: 0.12, durationSec: 1.35, frequencyHz: 329.63,
                             attackSec: 0.070, decaySec: 0.65, amplitude: 0.12),
                    // G4 (perfect 5th).
                    ToneSpec(startSec: 0.20, durationSec: 1.30, frequencyHz: 392.00,
                             attackSec: 0.075, decaySec: 0.65, amplitude: 0.11),
                    // C5 (octave) — top voice, slightly delayed for sparkle.
                    ToneSpec(startSec: 0.30, durationSec: 1.25, frequencyHz: 523.25,
                             attackSec: 0.080, decaySec: 0.70, amplitude: 0.09),
                ],
                totalDurationSec: 1.80
            )
        case .modeSwitch:
            // Quick upward zip A3 → A4 (octave). RL menu-nav feel — short,
            // pitched, doesn't linger.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.18, frequencyHz: 440.0,
                             pitchStartRatio: 0.5, pitchCurve: .exponential,
                             attackSec: 0.004, decaySec: 0.11, amplitude: 0.13),
                ],
                totalDurationSec: 0.28
            )
        case .tab:
            // Soft pitched click — short downward zip E5 → A4. Quieter than
            // modeSwitch so frequent tab presses don't fatigue.
            return SoundSpec(
                tones: [
                    ToneSpec(startSec: 0, durationSec: 0.10, frequencyHz: 440.0,
                             pitchStartRatio: 659.25 / 440.0, pitchCurve: .exponential,
                             attackSec: 0.003, decaySec: 0.06, amplitude: 0.09),
                ],
                totalDurationSec: 0.18
            )
        case .sheetOpen:
            // Upward whoosh from C4 to G4 (perfect 5th rise) with a sustained
            // G4 underneath — sheet sliding up motion.
            return SoundSpec(
                tones: [
                    // Whoosh: C4 → G4 over 200 ms.
                    ToneSpec(startSec: 0.00, durationSec: 0.24, frequencyHz: 392.00,
                             pitchStartRatio: 261.63 / 392.00, pitchCurve: .exponential,
                             attackSec: 0.008, decaySec: 0.16, amplitude: 0.11),
                    // Sustain: G4 settles in after the whoosh lands.
                    ToneSpec(startSec: 0.06, durationSec: 0.55, frequencyHz: 392.00,
                             attackSec: 0.040, decaySec: 0.30, amplitude: 0.10),
                ],
                totalDurationSec: 0.80
            )
        }
    }
}
