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
/// Who is using the phone's one shared audio session.
///
/// The app's sounds and the microphone both need it, in different modes, and each used to set it up for
/// itself. So listening to music switched the session under the sounds — which then went silent for good,
/// since they believed they were still running — and the first sound after listening started switched it
/// back to play-only and quietly stopped the microphone. Each now says whether it is using the session, and
/// neither changes it out from under the other.
@MainActor
enum AudioSessionUsers {
    static var microphone = false
    static var speaker = false
}

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

    /// Whether the world's own sound plays: water, fire, glass, electricity and things landing, mixed by what the
    /// world is doing. See `Soundscape.swift` in the engine. Only while ``isEnabled`` too.
    var soundscapeEnabled = true {
        didSet {
            if !soundscapeEnabled { soundscape.set(.silence, volume: volume) }
        }
    }

    /// Whether the world should bother listening for the soundscape at all.
    var wantsSoundscape: Bool { isEnabled && soundscapeEnabled && volume > 0 }

    /// The soundscape's synthesiser, handed to the audio thread. See `SoundscapeVoice`.
    private let soundscape = SoundscapeVoice(sampleRate: LabAudio.sampleRate)
    private var soundscapeNode: AVAudioSourceNode?

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
    ///
    /// Outside the actor, because the synthesis runs on a background task and a constant needs no
    /// protection — there is nothing to race against a number that never changes.
    nonisolated static let sampleRate = 44_100.0

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

    /// Tells the soundscape how loud each of its beds should now be. Called a few times a second by the powder world.
    ///
    /// Silence does not start anything: a session is only opened once there is something to hear.
    func setSoundscape(_ levels: SoundscapeLevels) {
        guard wantsSoundscape else { return }
        if levels.isSilent, !isStarted { return }
        guard start() else { return }
        if !engine.isRunning { try? engine.start() }
        // Quieter than the one-shot sounds: this is a room's sound, under everything else, not an event.
        soundscape.set(levels, volume: volume * 0.8)
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
        // The system stops the engine on its own — a phone call, headphones plugged in or out, the
        // microphone changing the session's mode — and nothing here was told. Every sound after that went
        // nowhere until the Sound switch was turned off and on again. Started again here instead.
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
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
            // Ambient: the silent switch works, and other audio is left alone. Not while the microphone is
            // open, whose record-and-play mode already plays sound — switching to ambient would stop it.
            if !AudioSessionUsers.microphone {
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            }
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

        // The soundscape: a node the audio thread asks for samples, which the engine's synthesiser makes.
        let node = Self.soundscapeNode(voice: soundscape, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        soundscapeNode = node

        do {
            try engine.start()
        } catch {
            // Tidied up rather than left half-built, so a later attempt starts from a clean state
            // instead of attaching a second set of players to a dead engine.
            for player in players { engine.detach(player) }
            players.removeAll()
            if let soundscapeNode { engine.detach(soundscapeNode) }
            soundscapeNode = nil
            return false
        }

        isStarted = true
        AudioSessionUsers.speaker = true
        return true
    }

    /// The node the audio thread asks for the soundscape's samples.
    ///
    /// Made outside the main actor on purpose. A closure written inside this class would belong to the main thread,
    /// and in this language mode a closure that belongs to the main thread checks, when called, that it is on the main
    /// thread — which the audio thread never is, so the first buffer would close the app.
    private nonisolated static func soundscapeNode(voice: SoundscapeVoice, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { @Sendable _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let count = Int(frameCount)
            guard let first = buffers.first, let data = first.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            voice.render(into: UnsafeMutableBufferPointer(start: data, count: count))
            // The format is one channel, but copied into any others rather than leaving them with old memory.
            for other in buffers.dropFirst() {
                guard let copy = other.mData?.assumingMemoryBound(to: Float.self) else { continue }
                copy.update(from: data, count: count)
            }
            return noErr
        }
    }

    /// Shuts everything down and releases the audio session.
    func stop() {
        guard isStarted else { return }
        for player in players {
            player.stop()
            engine.detach(player)
        }
        players.removeAll()
        if let soundscapeNode { engine.detach(soundscapeNode) }
        soundscapeNode = nil
        soundscape.set(.silence, volume: volume)
        engine.stop()
        isStarted = false
        nextPlayer = 0
        // Let go of the session, so the app stops appearing in the now-playing machinery and stops
        // holding any audio hardware awake — unless the microphone is still using it.
        AudioSessionUsers.speaker = false
        if !AudioSessionUsers.microphone {
            try? AVAudioSession.sharedInstance().setActive(false)
        }
        // Cleared so that turning sound back on plays immediately rather than waiting out an
        // interval measured from before it was switched off.
        throttle.reset()
    }
}

/// The soundscape's synthesiser, shared between the main thread, which says how loud things should be, and the audio
/// thread, which asks for samples.
///
/// ## Why the audio thread never waits here
///
/// It must never wait for anything: a late buffer is a click. So the main thread leaves its new levels under a lock,
/// and the audio thread only *tries* the lock — if the main thread happens to be holding it at that instant, the
/// audio thread carries on with the levels it already had, and picks the new ones up a few milliseconds later on its
/// next turn. The synthesiser itself is only ever touched by the audio thread.
final class SoundscapeVoice: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: (levels: SoundscapeLevels, volume: Double)?
    private var synth: SoundscapeSynth

    init(sampleRate: Double) {
        synth = SoundscapeSynth(sampleRate: sampleRate)
    }

    /// Leaves new levels for the audio thread. Called on the main thread.
    func set(_ levels: SoundscapeLevels, volume: Double) {
        lock.lock()
        waiting = (levels, volume)
        lock.unlock()
    }

    /// Makes the next samples. Called on the audio thread.
    func render(into samples: UnsafeMutableBufferPointer<Float>) {
        if lock.try() {
            if let waiting {
                synth.target = waiting.levels
                synth.volume = waiting.volume
                self.waiting = nil
            }
            lock.unlock()
        }
        synth.render(into: samples)
    }
}
