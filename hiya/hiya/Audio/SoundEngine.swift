import AVFoundation
import Foundation

/// Single audio engine for the app. `AVAudioEngine` → two round-robin
/// `AVAudioPlayerNode`s → `AVAudioUnitReverb` → main mixer. The reverb is
/// what gives the tiny percussive synth hits their "ambient" character without
/// bundling impulse responses; two players let a save sound and the immediate
/// achievement chime overlap instead of cutting each other off.
///
/// Buffers are pre-rendered once on `start()`; `play()` is fire-and-forget.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    /// `@AppStorage` key the Settings toggle writes through. The engine reads
    /// it on every `play()` so flipping the switch takes effect immediately
    /// without re-plumbing anything.
    static let enabledDefaultsKey = "hiya.sounds.enabled"

    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    /// Two players in round-robin so a quick succession (e.g. save → achievement)
    /// overlaps musically instead of one cutting the other.
    private let players: [AVAudioPlayerNode] = (0..<2).map { _ in AVAudioPlayerNode() }
    private var nextPlayerIndex = 0
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var isStarted = false

    /// True unless the user has explicitly toggled sounds off. Defaults true.
    var isEnabled: Bool {
        // Treat "no value yet" as enabled — the default-on intent.
        UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
    }

    private init() {}

    /// Idempotent: safe to call from `.task {}` on every view appearance — only
    /// the first call wires the graph, renders buffers, and starts the engine.
    func start() {
        guard !isStarted else { return }
        // Skip in unit-test runs — the simulator's audio route can crash the
        // host app at `AVAudioEngine.start()`, which makes the test runner
        // bail before it can connect. Tests cover SoundSynth directly anyway.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        isStarted = true

        // Activate the audio session BEFORE wiring nodes. Connecting nodes
        // before the session is active can leave players in a disconnected
        // state that throws `'player started when in a disconnected state'`
        // on the first play() call.
        // .ambient: mixes with other apps' audio (Spotify, podcasts) and
        // respects the silent switch — the polite choice for a journaling app.
        // Guarded for iOS/tvOS/watchOS; AVAudioSession isn't on macOS, and we
        // don't want this file to break a hypothetical future Catalyst target.
        #if os(iOS) || os(tvOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
        #endif

        engine.attach(reverb)
        for player in players { engine.attach(player) }

        // SmallRoom + ~28% wet keeps the tail short and present — feels
        // "in the room" rather than cathedral-y. Tune here to re-character.
        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = 28

        let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.sampleRate, channels: 1)
        for player in players {
            engine.connect(player, to: reverb, format: format)
        }
        engine.connect(reverb, to: engine.mainMixerNode, format: format)

        for effect in SoundEffect.allCases {
            buffers[effect] = SoundSynth.render(spec: effect.spec)
        }

        do {
            try engine.start()
        } catch {
            // Engine failed to spin up (rare; silent simulator / no output route).
            // Reset so a future start() can retry, and play() will no-op silently.
            isStarted = false
        }
        // Note: do NOT call `player.play()` here. Pre-playing before any
        // buffer is scheduled is what triggers the "disconnected state"
        // crash on some iOS versions. Each play(_:) starts its player
        // lazily on first use; `engine.isRunning` is the gate.
    }

    /// Fire-and-forget. Cheap; safe to call from any tap. No-op when sounds
    /// are disabled, the engine never started, or the engine got torn down
    /// by an interruption (incoming call, route change).
    func play(_ effect: SoundEffect) {
        guard isStarted, isEnabled, let buffer = buffers[effect] else { return }
        guard engine.isRunning else { return }
        let player = players[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        // Lazily kick the player on first use — and on every use, since
        // `.interrupts` doesn't auto-resume a stopped player. `isPlaying`
        // means "the player has been told to play and isn't stopped"; it
        // stays true between scheduled buffers.
        if !player.isPlaying {
            player.play()
        }
    }
}
