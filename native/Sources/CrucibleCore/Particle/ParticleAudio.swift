/// Making the field move to music.
///
/// Sound arrives as three numbers between nought and one — how much low, how much middle, and how loud
/// overall — and those numbers drive whichever settings have been pointed at them. Everything in this file
/// is arithmetic on those three numbers, so it compiles and is tested anywhere; capturing the sound itself
/// needs a microphone and belongs to the app.
///
/// ## What is different from the reference implementation
///
/// Three things, and the first is the one that matters:
///
///   - **There is an envelope.** The reference has none at all — no rise, no fall, no peak held — so the
///     only smoothing in its whole chain is whatever the analyser applies before the numbers arrive. The
///     result is limp: a drum hits and the field twitches for a single frame. Here each signal rises
///     quickly and falls slowly, which is what makes a beat read as a beat rather than as a flicker.
///   - **Mappings stack.** In the reference, two mappings pointed at the same setting each compute from
///     the *original* value, so the second silently overwrites the first and one of the two does nothing.
///   - **Sound cannot leave a setting changed.** Everything here produces a value for one frame from the
///     setting's own resting value, so switching the music off puts the field back exactly as it was. The
///     reference writes into the live settings, so the sliders drift while music plays.
public struct ParticleAudioSignal: Sendable, Hashable, Codable {
    /// How much low end there is, nought to one.
    public var bass: Double
    /// How much middle, nought to one.
    public var mid: Double
    /// How loud it is overall, nought to one.
    public var level: Double

    public init(bass: Double = 0, mid: Double = 0, level: Double = 0) {
        self.bass = bass
        self.mid = mid
        self.level = level
    }

    public static let silence = ParticleAudioSignal()

    /// The signal with every number pulled into range.
    public var clamped: ParticleAudioSignal {
        ParticleAudioSignal(
            bass: Self.usable(bass),
            mid: Self.usable(mid),
            level: Self.usable(level)
        )
    }

    private static func usable(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, min(1, value))
    }

    /// Which of the three a mapping reads.
    public enum Source: String, Sendable, Hashable, CaseIterable, Codable {
        case bass
        case mid
        case level

        public var displayName: String {
            switch self {
            case .bass: return "Bass"
            case .mid: return "Middle"
            case .level: return "Loudness"
            }
        }
    }

    /// The value of one of the three.
    public func value(of source: Source) -> Double {
        switch source {
        case .bass: return Self.usable(bass)
        case .mid: return Self.usable(mid)
        case .level: return Self.usable(level)
        }
    }
}

// MARK: - Smoothing

/// Holds a signal's shape over time: quick to rise, slow to fall.
///
/// Without this a drum hit lasts exactly one frame, which at a hundred and twenty frames a second is eight
/// milliseconds — far too short to see. The rise is fast so a beat lands on time; the fall is slow so it
/// can be seen at all. That asymmetry is the whole point, and it is why one smoothing figure would not do.
public struct ParticleAudioEnvelope: Sendable, Hashable, Codable {
    /// How much of the way toward a louder reading to move each frame. One follows instantly.
    public var rise: Double = 0.55
    /// How much of the way toward a quieter reading to move each frame.
    public var fall: Double = 0.08

    public init(rise: Double = 0.55, fall: Double = 0.08) {
        self.rise = rise
        self.fall = fall
    }

    public static let `default` = ParticleAudioEnvelope()

    /// Whichever of the two applies, given which way the reading is going.
    func rate(rising: Bool) -> Double {
        let value = rising ? rise : fall
        guard value.isFinite else { return rising ? 0.55 : 0.08 }
        return max(0.01, min(1, value))
    }
}

/// A signal with an envelope applied, carried from frame to frame.
public struct ParticleAudioFollower: Sendable, Hashable, Codable {
    /// Where the three signals currently sit.
    public private(set) var held = ParticleAudioSignal.silence
    /// How quickly they rise and fall.
    public var envelope = ParticleAudioEnvelope.default

    public init(envelope: ParticleAudioEnvelope = .default) {
        self.envelope = envelope
    }

    /// Moves the held signals toward a new reading.
    public mutating func follow(_ reading: ParticleAudioSignal) {
        let target = reading.clamped
        held = ParticleAudioSignal(
            bass: Self.approach(held.bass, target.bass, envelope),
            mid: Self.approach(held.mid, target.mid, envelope),
            level: Self.approach(held.level, target.level, envelope)
        )
    }

    /// Back to silence, for when the music stops.
    public mutating func reset() {
        held = .silence
    }

    private static func approach(
        _ current: Double,
        _ target: Double,
        _ envelope: ParticleAudioEnvelope
    ) -> Double {
        let rate = envelope.rate(rising: target > current)
        let moved = current + (target - current) * rate
        return moved.isFinite ? max(0, min(1, moved)) : 0
    }
}

// MARK: - What sound is allowed to change

/// One thing sound can drive.
public enum ParticleAudioTarget: String, Sendable, Hashable, CaseIterable, Codable {
    /// How large the bodies are drawn.
    case size
    /// How hard the world pulls downward.
    case gravity
    /// How strongly the field swirls.
    case swirl
    /// How brightly the field glows.
    case glow
    /// How far along its ramp the whole field's colour shifts.
    case colour
    /// A signal the app uses to throw new bodies in on a beat.
    case burst

    public var displayName: String {
        switch self {
        case .size: return "Size"
        case .gravity: return "Gravity"
        case .swirl: return "Swirl"
        case .glow: return "Glow"
        case .colour: return "Colour"
        case .burst: return "Bursts"
        }
    }

    /// What the target does with its number, in a sentence, for the interface.
    public var explanation: String {
        switch self {
        case .size: return "Bodies swell on the beat."
        case .gravity: return "The world pulls harder as it gets louder."
        case .swirl: return "The field turns more strongly."
        case .glow: return "Everything brightens."
        case .colour: return "The colours shift along the ramp."
        case .burst: return "New bodies are thrown in on a beat."
        }
    }
}

/// A pointing of one sound signal at one setting.
public struct ParticleAudioMapping: Sendable, Hashable, Codable {
    public var source: ParticleAudioSignal.Source
    public var target: ParticleAudioTarget
    /// How much. Nought is off; two is as far as it goes.
    public var amount: Double

    public init(source: ParticleAudioSignal.Source, target: ParticleAudioTarget, amount: Double) {
        self.source = source
        self.target = target
        self.amount = amount
    }

    /// How much this mapping contributes, for a given signal and overall sensitivity.
    func contribution(from signal: ParticleAudioSignal, sensitivity: Double) -> Double {
        guard amount.isFinite, amount > 0 else { return 0 }
        let sense = sensitivity.isFinite ? max(0, min(4, sensitivity)) : 1
        return signal.value(of: source) * min(2, amount) * sense
    }
}

/// What sound has decided the field should look like, for one frame.
///
/// Every number here is a *replacement* worked out from the setting's own resting value, not a change
/// written into it. That is what makes switching the music off put the field back exactly as it was — the
/// reference implementation writes into its live settings, so its sliders drift while music plays and stay
/// drifted afterwards.
public struct ParticleAudioResponse: Sendable, Hashable {
    public var particleSize: Double
    public var gravityY: Double
    public var swirl: Double
    public var glowStrength: Double
    /// How far along the ramp to shift every colour, nought to one, wrapping.
    public var colourShift: Double
    /// How strongly to throw new bodies in, nought to one. Nought means do not.
    public var burst: Double

    public init(
        particleSize: Double,
        gravityY: Double,
        swirl: Double,
        glowStrength: Double,
        colourShift: Double,
        burst: Double
    ) {
        self.particleSize = particleSize
        self.gravityY = gravityY
        self.swirl = swirl
        self.glowStrength = glowStrength
        self.colourShift = colourShift
        self.burst = burst
    }
}

/// The resting values sound works from.
public struct ParticleAudioBaseline: Sendable, Hashable {
    public var particleSize: Double
    public var gravityY: Double
    public var swirl: Double
    public var glowStrength: Double

    public init(particleSize: Double, gravityY: Double, swirl: Double, glowStrength: Double) {
        self.particleSize = particleSize
        self.gravityY = gravityY
        self.swirl = swirl
        self.glowStrength = glowStrength
    }
}

public enum ParticleAudio {
    /// What the field starts out listening for.
    ///
    /// Bass to size and loudness to glow. Two mappings rather than one because one is not obviously
    /// reacting to anything — and rather than all six, because everything moving at once reads as noise.
    public static let defaultMappings: [ParticleAudioMapping] = [
        ParticleAudioMapping(source: .bass, target: .size, amount: 1),
        ParticleAudioMapping(source: .level, target: .glow, amount: 0.8),
    ]

    /// Works out what the field should look like this frame.
    ///
    /// Contributions to the same setting **add up**, which is where the reference implementation goes
    /// wrong: each of its mappings computes from the original value, so pointing two signals at one setting
    /// means the second silently overwrites the first and one of them does nothing at all.
    public static func respond(
        to signal: ParticleAudioSignal,
        mappings: [ParticleAudioMapping],
        sensitivity: Double,
        baseline: ParticleAudioBaseline
    ) -> ParticleAudioResponse {
        var sizeShare = 0.0
        var gravityShare = 0.0
        var swirlShare = 0.0
        var glowShare = 0.0
        var colourShare = 0.0
        var burstShare = 0.0

        let heard = signal.clamped
        for mapping in mappings {
            let amount = mapping.contribution(from: heard, sensitivity: sensitivity)
            guard amount > 0 else { continue }
            switch mapping.target {
            case .size: sizeShare += amount
            case .gravity: gravityShare += amount
            case .swirl: swirlShare += amount
            case .glow: glowShare += amount
            case .colour: colourShare += amount
            case .burst: burstShare += amount
            }
        }

        func settled(_ value: Double, fallback: Double) -> Double {
            value.isFinite ? value : fallback
        }

        return ParticleAudioResponse(
            // Multiplied, because size reads as a proportion: doubling a two-pixel body and doubling a
            // six-pixel one should both look like doubling.
            particleSize: max(
                1,
                min(8, settled(baseline.particleSize, fallback: 2) * (1 + sizeShare * 0.9))
            ),
            // Added, because gravity has a natural nought and a natural direction — a proportion of nought
            // is nought, so a multiplied version of this would do nothing in the common case.
            gravityY: max(-1.2, min(1.2, settled(baseline.gravityY, fallback: 0) + gravityShare * 0.5)),
            swirl: max(-8, min(8, settled(baseline.swirl, fallback: 0) + swirlShare * 2.5)),
            glowStrength: max(0, min(4, settled(baseline.glowStrength, fallback: 0) + glowShare * 1.2)),
            // Wrapped rather than clamped: a colour ramp has no end, so the shift should keep going round
            // rather than stopping when it reaches the last colour.
            // A whole number of turns is kept just short of the next one rather than dropping to nought: at
            // exactly full loudness the shift used to snap from all the way round back to none, which read
            // as the colour flickering off on every loud beat.
            colourShift: colourShare > 0 && colourShare.truncatingRemainder(dividingBy: 1) == 0
                ? 0.9999
                : colourShare.truncatingRemainder(dividingBy: 1),
            burst: min(1, burstShare)
        )
    }

    /// How loud a burst has to be before bodies are actually thrown in.
    ///
    /// Without a floor, any music at all produces a continuous trickle rather than bursts on the beat — and
    /// a trickle fills the field to its limit within seconds.
    public static let burstFloor = 0.45

    /// The shortest gap between bursts, in seconds.
    ///
    /// An eighth of a second, which is about the fastest a beat goes on anything anybody dances to. Without
    /// it a single drum hit spread over several frames fires several times.
    public static let burstInterval = 0.125

    /// How many bodies a burst of a given strength throws in.
    public static func burstCount(strength: Double) -> Int {
        guard strength.isFinite, strength > burstFloor else { return 0 }
        // Measured from the floor rather than from nought, so the quietest burst that fires is still a
        // visible handful rather than a single body.
        let over = (strength - burstFloor) / max(1e-6, 1 - burstFloor)
        return 60 + Int((over * 340).rounded())
    }

    /// Separates the frequencies a microphone reports into the three bands.
    ///
    /// Given as *fractions of the range* rather than as bin numbers, so it works whatever the sample rate
    /// and however many bins arrive. The reference implementation hard-codes bin numbers, so the actual
    /// frequencies its "bass" and "middle" cover drift with whatever device it happens to be running on.
    ///
    /// - Parameter magnitudes: How much energy is at each frequency, lowest first, each nought to one.
    /// - Parameter sampleRate: How many samples a second the sound was captured at.
    public static func bands(
        magnitudes: [Float],
        sampleRate: Double
    ) -> ParticleAudioSignal {
        guard !magnitudes.isEmpty, sampleRate > 0, sampleRate.isFinite else { return .silence }

        // The highest frequency a recording can describe is half its sample rate, and the bins cover that
        // range evenly — so which bin a frequency falls in is that frequency over the top one.
        let topFrequency = sampleRate / 2
        let binsPerHertz = Double(magnitudes.count) / topFrequency

        /// The average energy between two frequencies.
        func average(from low: Double, to high: Double) -> Double {
            let first = max(0, min(magnitudes.count - 1, Int(low * binsPerHertz)))
            let last = max(first, min(magnitudes.count - 1, Int(high * binsPerHertz)))
            var total = 0.0
            for index in first ... last {
                let value = Double(magnitudes[index])
                total += value.isFinite ? max(0, value) : 0
            }
            return total / Double(last - first + 1)
        }

        var whole = 0.0
        for value in magnitudes {
            let usable = Double(value)
            whole += usable.isFinite ? max(0, usable) : 0
        }

        return ParticleAudioSignal(
            // Up to two hundred and fifty, which is where a kick drum and a bass line live.
            bass: min(1, average(from: 20, to: 250)),
            // Two hundred and fifty to two thousand, which is most of what a voice and a guitar occupy.
            mid: min(1, average(from: 250, to: 2_000)),
            level: min(1, whole / Double(magnitudes.count))
        )
    }
}
