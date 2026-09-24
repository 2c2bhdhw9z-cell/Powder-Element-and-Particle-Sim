import AVFoundation
import CrucibleCore
import Observation

/// Plays the lab's sounds.
///
/// The sounds themselves — the waveforms, the sweeps, the envelopes, how often each may repeat — are
/// in the engine, where they are tested. This is only the machinery: an audio session, a handful of
/// players, and the decision about which thread does the arithmetic.
///
/// ## Three decisions worth stating
///
/// **The session is "ambient".** That means the phone's silent switch really does silence it, and
/// music someone already had playing keeps playing. Both are the right way round for a toy: nobody
/// wants a sandbox to stop their podcast, and a physics lab that ignores the mute switch is a
/// physics lab that gets deleted.
///
/// **Nothing starts until the first sound.** Activating an audio session has a visible cost — it can
/// duck other audio and it wakes hardware — so a session that is never used should never be
/// started. This matches the web version, which creates its audio context lazily for the same
/// reason.
///
/// **The samples are computed off the main thread.** An explosion is about twenty thousand samples,
/// each needing a sine, a cosine and a power for the sweeping filter, which measures in the
/// milliseconds. On the main thread that is a dropped frame every time something explodes — the
/// simulation's entire budget at 120Hz is eight milliseconds. The few milliseconds of delay this
/// adds before the sound starts is imperceptible; a stutter in the picture is not.
@MainActor
@Observable
final class LabAudio {
    /// Whether sound is wanted at all. The dock has a speaker button for this.
    var isEnabled = true {
        didSet {
            guard !isEnabled else { return }
            // Stopped rather than left running silently, so nothing holds the audio session open.
            stop()
        }
    }

    /// Master volume, nought to one. The reference implementation's default.
    var volume: Double = 0.4

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var isStarted = false

    /// Used for the pitch jitter and the explosion's noise.
    ///
    /// Deliberately its own, never the simulation's. A sound effect that drew from the physics'
    /// random numbers would change how the sand falls — and differently depending on whether the
    /// volume happened to be turned up, which is about the worst kind of bug to be told about.
    private var jitterSeed: UInt32 = 0x5EED

    private var throttle = SoundThrottle()

    /// How many sounds can overlap.
    ///
    /// Eight is generous for this: the throttle already stops any one sound repeating quickly, so
    /// this only has to cover different sounds landing together — an explosion over a fire crackle
    /// over a chime.
    private static let voiceCount = 8

    /// One format throughout, rather than following the hardware's.
    ///
    /// The engine resamples to whatever the speaker wants. Fixing it here means the synthesis does
    /// not have to care what device it is on, and the sounds are identical on all of them.
    private static let sampleRate = 44_100.0

    // MARK: Playing

    /// Plays a sound, if it is allowed to.
    ///
    /// Silently does nothing when sound is off or the same sound played too recently. That is the
    /// normal case rather than an error — the simulation asks for a fire crackle from every flame on
    /// every tick, which is hundreds a second.
    func play(_ sound: LabSound, intensity: Double = 1) {
        guard isEnabled, volume > 0 else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let permitted = throttle.allows(sound, at: now)
        guard permitted else { return }

        guard start() else { return }

        // A fresh generator per sound, seeded from a counter, so nothing mutable crosses to the
        // background task.
        jitterSeed = jitterSeed &* 1_664_525 &+ 1_013_904_223
        let seed = jitterSeed
        let volume = self.volume

        Task.detached(priority: .userInitiated) {
            var random = Mulberry32(seed: seed)
            let samples = SoundSynthesis.render(
                sound,
                intensity: intensity,
                volume: volume,
                sampleRate: Self.sampleRate,
                random: &random
            )
            guard !samples.isEmpty else { return }
            await MainActor.run { [weak self] in
                self?.schedule(samples)
            }
        }
    }

    /// Convenience for the set-piece events, which report the sound they want as part of their
    /// definition rather than playing it themselves.
    func play(_ cue: PowderEventSound?, intensity: Double) {
        switch cue {
        case .meteor: play(.meteor)
        case .explosion: play(.explosion, intensity: intensity)
        case nil: break
        }
    }

    private func schedule(_ samples: [Float]) {
        guard isStarted, !players.isEmpty else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(samples.count)
              )
        else { return }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else { return }
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }

        // Round-robin rather than looking for an idle player. Finding one means asking each whether
        // it is playing, and the answer can change between asking and using it; cycling is simpler
        // and the worst case is cutting off a sound that is already fading out.
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    // MARK: Lifetime

    /// Starts the session and the engine, the first time anything needs them.
    ///
    /// - Returns: whether sound can be played. Failing here is not worth surfacing — the simulation
    ///   is the point and it runs perfectly well in silence.
    @discardableResult
    private func start() -> Bool {
        if isStarted { return true }

        do {
            let session = AVAudioSession.sharedInstance()
            // Ambient: the silent switch works, and other audio is left alone.
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            return false
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else {
            return false
        }

        for _ in 0 ..< Self.voiceCount {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }

        do {
            try engine.start()
        } catch {
            // Tidied up rather than left half-built, so a later attempt starts from a clean state
            // instead of attaching a second set of players to a dead engine.
            for player in players { engine.detach(player) }
            players.removeAll()
            return false
        }

        isStarted = true
        return true
    }

    /// Shuts everything down and releases the audio session.
    func stop() {
        guard isStarted else { return }
        for player in players {
            player.stop()
            engine.detach(player)
        }
        players.removeAll()
        engine.stop()
        isStarted = false
        nextPlayer = 0
        // Let go of the session, so the app stops appearing in the now-playing machinery and stops
        // holding any audio hardware awake.
        try? AVAudioSession.sharedInstance().setActive(false)
        // Cleared so that turning sound back on plays immediately rather than waiting out an
        // interval measured from before it was switched off.
        throttle.reset()
    }
}
