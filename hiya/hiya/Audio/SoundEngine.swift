import AVFoundation
import Foundation

/// Per-effect `AVAudioPlayer`s, pre-loaded from in-memory WAV data.
///
/// The previous version used `AVAudioEngine` + player nodes + a reverb unit.
/// Two problems killed that approach on real devices:
///
/// 1. **Crashes**: `'player started when in a disconnected state'` thrown by
///    `AVAudioPlayerNode.play()` on first use, even with `engine.isRunning ==
///    true`. The graph-based API has subtle ordering / lifecycle requirements
///    that bit us twice; `AVAudioPlayer` doesn't expose that surface.
/// 2. **Echo**: `AVAudioUnitReverb`'s smallRoom preset at 28 % wet sounded
///    tail-y through the iPhone speaker — read as "weird echo" rather than
///    ambience. The synthesized FM tones already carry their own character.
///
/// Trade-off: the same effect played twice within its own duration
/// self-interrupts (one player per effect). Different effects (save +
/// achievement) still overlap fine because they're separate players.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    /// `@AppStorage` key the Settings toggle writes through. The engine reads
    /// it on every `play()` so flipping the switch takes effect immediately.
    static let enabledDefaultsKey = "hiya.sounds.enabled"

    private var players: [SoundEffect: AVAudioPlayer] = [:]
    private var isStarted = false

    /// True unless the user has explicitly toggled sounds off. Defaults true.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
    }

    private init() {}

    /// Idempotent. Activates an `.ambient` audio session (respects the silent
    /// switch, mixes with other audio) and synthesizes one `AVAudioPlayer`
    /// per effect from an in-memory WAV. Safe to call on every appear.
    func start() {
        guard !isStarted else { return }
        // Skip in unit-test runs — the simulator's audio route can mis-fire
        // and crash the host before the test runner attaches. Tests cover
        // SoundSynth directly anyway.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        isStarted = true

        #if os(iOS) || os(tvOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
        #endif

        for effect in SoundEffect.allCases {
            guard let buffer = SoundSynth.render(spec: effect.spec),
                  let data = SoundSynth.wavData(from: buffer),
                  let player = try? AVAudioPlayer(data: data) else {
                continue
            }
            // ~50% of full volume — synthesized samples are tanh-clipped to
            // [-1, 1], so this is plenty audible on speaker without being
            // shouty in earbuds.
            player.volume = 0.5
            player.prepareToPlay()
            players[effect] = player
        }
    }

    /// Fire-and-forget. Rewinds the player so repeated taps always start at
    /// frame 0 — never queues up a tail. No-op when disabled or the engine
    /// never started.
    func play(_ effect: SoundEffect) {
        guard isStarted, isEnabled, let player = players[effect] else { return }
        player.currentTime = 0
        player.play()
    }
}
