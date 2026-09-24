// The six sounds the lab makes, and the arithmetic that produces them.
//
// Ported from web/src/sim/audio-engine.ts.
//
// ## Why the synthesis is in the engine
//
// The web version builds each sound out of Web Audio nodes — an oscillator, a gain, sometimes a
// filter — so the browser does the actual sample generation. There is no equivalent to lift
// across: on iOS something has to produce the samples. Doing that here rather than in the app
// means the waveforms, the sweeps and the envelopes can be tested on any machine, and it keeps the
// app layer to what it is genuinely for — opening an audio session and handing buffers to the
// speaker.
//
// ## Two places this cannot match a browser exactly, and why that is accepted
//
//  1. **Band-limiting.** A browser's sawtooth and triangle are built from a harmonic series cut off
//     below the Nyquist frequency, so they never alias. A naively computed sawtooth does, audibly,
//     as a gritty ring on a falling sweep. The sawtooth here is corrected with a polynomial
//     band-limited step, which removes nearly all of it; the triangle is left naive because its
//     harmonics fall away as the square of their number and the aliasing is inaudible.
//  2. **The filter's resonance.** Web Audio reads a lowpass filter's Q in decibels, so its default
//     of 1 means about 1.12 rather than 1. That figure is used here. It affects only how sharp the
//     shoulder of the explosion's filter sweep is.
//
// Neither is reproducible to the sample, and neither needs to be: these are short effects, and what
// has to carry across is the character — the waveform, the frequencies, the sweep direction and
// duration, the envelope, and how often a sound is allowed to repeat.

/// One of the six sounds.
public enum LabSound: String, CaseIterable, Sendable, Hashable, Codable {
    /// A filtered noise burst. The only one that takes an intensity.
    case explosion
    /// Acid eating something.
    case acidFizz
    /// Fire, ticking over.
    case fireCrackle
    /// The deep freeze: a rising shiver.
    case freeze
    /// A meteor falling: a long descending whistle.
    case meteor
    /// Two bodies meeting.
    case collisionChime
}

/// The shape of one cycle.
public enum SoundWaveform: Sendable, Hashable {
    case noise
    case sine
    case triangle
    case sawtooth
}

/// A filter sweep, which only the explosion uses.
///
/// It is what turns a half-second of white noise into a blast: the noise starts wide open and the
/// cutoff collapses to a rumble, so the sound seems to move away from you.
public struct SoundFilterSweep: Sendable, Hashable {
    /// Cutoff at the start, before intensity is applied.
    public var startHertz: Double
    /// Cutoff at the end of the sweep.
    public var endHertz: Double
    /// How long the cutoff takes to fall.
    public var rampSeconds: Double
    /// Resonance. A browser reads this in decibels, so its default of 1 is about 1.12 linear.
    public var resonance: Double
}

/// Everything about one sound except when to play it.
public struct SoundRecipe: Sendable, Hashable {
    public var waveform: SoundWaveform
    /// Pitch at the start.
    public var startHertz: Double
    /// A random amount added to the starting pitch, so repeats do not sound mechanical.
    public var randomHertzSpread: Double
    /// Pitch at the end of the sweep, or `nil` to hold the starting pitch.
    public var endHertz: Double?
    /// How long the pitch takes to travel.
    public var pitchRampSeconds: Double
    /// Loudness at the start, as a fraction of the master volume.
    public var peakGain: Double
    /// How long the envelope takes to fall to silence.
    public var gainRampSeconds: Double
    /// How long the sound lasts. Can be shorter than the envelope, which then cuts off.
    public var duration: Double
    /// The least time that must pass before this sound may play again.
    public var minimumInterval: Double
    public var filter: SoundFilterSweep?
}

/// What each sound is made of.
///
/// Every figure is the reference implementation's. They look arbitrary because they are — each was
/// arrived at by ear — which is exactly why they are written down in one place rather than spread
/// through the code that triggers them.
public enum SoundDesign {
    /// The value an exponential envelope falls to, standing in for silence.
    ///
    /// Not zero: an exponential curve cannot reach zero, and a browser refuses the instruction
    /// outright if asked. A thousandth of the peak is about sixty decibels down, which is inaudible.
    public static let silence = 0.001

    public static func recipe(for sound: LabSound) -> SoundRecipe {
        switch sound {
        case .explosion:
            return SoundRecipe(
                waveform: .noise,
                startHertz: 0,
                randomHertzSpread: 0,
                endHertz: nil,
                pitchRampSeconds: 0,
                peakGain: 0.8,
                gainRampSeconds: 0.45,
                duration: 0.45,
                minimumInterval: 0.2,
                filter: SoundFilterSweep(
                    startHertz: 800,
                    endHertz: 30,
                    rampSeconds: 0.4,
                    // A browser's default resonance of 1, read in decibels as it specifies.
                    resonance: 1.1220184543019633
                )
            )

        case .acidFizz:
            return SoundRecipe(
                waveform: .triangle,
                startHertz: 1200,
                randomHertzSpread: 600,
                endHertz: 300,
                pitchRampSeconds: 0.08,
                peakGain: 0.15,
                gainRampSeconds: 0.08,
                duration: 0.08,
                minimumInterval: 0.12,
                filter: nil
            )

        case .fireCrackle:
            return SoundRecipe(
                waveform: .sawtooth,
                startHertz: 150,
                randomHertzSpread: 200,
                endHertz: nil,
                pitchRampSeconds: 0,
                peakGain: 0.1,
                gainRampSeconds: 0.06,
                duration: 0.06,
                minimumInterval: 0.15,
                filter: nil
            )

        case .freeze:
            return SoundRecipe(
                waveform: .sine,
                startHertz: 200,
                randomHertzSpread: 0,
                endHertz: 1200,
                pitchRampSeconds: 0.3,
                peakGain: 0.3,
                // Longer than the sweep on purpose: the pitch settles and then fades, so the sound
                // has a tail rather than stopping the instant it arrives.
                gainRampSeconds: 0.35,
                duration: 0.35,
                minimumInterval: 0.3,
                filter: nil
            )

        case .meteor:
            return SoundRecipe(
                waveform: .sawtooth,
                startHertz: 800,
                randomHertzSpread: 0,
                endHertz: 80,
                pitchRampSeconds: 0.5,
                peakGain: 0.5,
                gainRampSeconds: 0.55,
                duration: 0.55,
                minimumInterval: 0.5,
                filter: nil
            )

        case .collisionChime:
            return SoundRecipe(
                waveform: .sine,
                startHertz: 500,
                randomHertzSpread: 800,
                endHertz: nil,
                pitchRampSeconds: 0,
                peakGain: 0.12,
                gainRampSeconds: 0.05,
                duration: 0.05,
                minimumInterval: 0.1,
                filter: nil
            )
        }
    }
}

/// Decides whether a sound is allowed to play yet.
///
/// Without this the lab is unlistenable: a burning field asks for a crackle from every flame on
/// every tick, which is hundreds a second, and they sum into a roar and clip. Each sound keeps its
/// own clock, so a fire crackling does not suppress an explosion.
public struct SoundThrottle: Sendable {
    /// When each sound last played, in seconds. Absent means never.
    private var lastPlayed: [LabSound: Double] = [:]

    public init() {}

    /// Whether the sound may play now, recording it if so.
    ///
    /// - Parameter now: a monotonic clock in seconds. The caller owns it, so tests can drive time.
    public mutating func allows(_ sound: LabSound, at now: Double) -> Bool {
        let interval = SoundDesign.recipe(for: sound).minimumInterval
        if let last = lastPlayed[sound], now - last < interval { return false }
        lastPlayed[sound] = now
        return true
    }

    /// Forgets every sound's clock, so the next of each may play immediately.
    public mutating func reset() {
        lastPlayed.removeAll()
    }
}

/// Turns a recipe into samples.
public enum SoundSynthesis {
    /// Renders one sound.
    ///
    /// - Parameters:
    ///   - intensity: only the explosion uses it — it scales both the loudness and the filter's
    ///     opening frequency, so a bigger blast is both louder and brighter.
    ///   - volume: the master volume, nought to one.
    ///   - random: the generator for the pitch jitter and the noise. Deliberately the caller's, and
    ///     it must **not** be the simulation's — a sound effect that consumed the physics' random
    ///     numbers would change how the sand falls, differently depending on whether the volume was
    ///     turned up.
    /// - Returns: mono samples in −1...1.
    public static func render(
        _ sound: LabSound,
        intensity: Double = 1,
        volume: Double,
        sampleRate: Double,
        random: inout Mulberry32
    ) -> [Float] {
        let recipe = SoundDesign.recipe(for: sound)
        guard sampleRate > 0, recipe.duration > 0 else { return [] }

        let count = Int((sampleRate * recipe.duration).rounded(.down))
        guard count > 0 else { return [] }

        let peak = volume * recipe.peakGain * (sound == .explosion ? intensity : 1)
        // A sound with no loudness still costs the time to render and play. Reported as silence so
        // the caller can decline to play it at all.
        guard peak > 0 else { return [] }

        let startHertz = recipe.startHertz + (recipe.randomHertzSpread > 0
            ? random.next() * recipe.randomHertzSpread
            : 0)

        var samples = [Float](repeating: 0, count: count)

        // The filter's running state, for the explosion.
        var filterState = BiquadState()

        var phase = 0.0
        for i in 0 ..< count {
            let t = Double(i) / sampleRate

            // The envelope. An exponential fall from the peak to near-silence, held at the floor
            // afterwards, which is what a browser's ramp does.
            let gain = exponentialRamp(
                from: peak,
                to: SoundDesign.silence,
                over: recipe.gainRampSeconds,
                at: t
            )

            var value: Double
            switch recipe.waveform {
            case .noise:
                // Full-scale white noise. Filtered below.
                value = random.next() * 2 - 1

            case .sine:
                value = jsSin(phase * 2 * Double.pi)

            case .triangle:
                value = triangle(phase)

            case .sawtooth:
                let hertz = currentHertz(recipe, startHertz: startHertz, at: t)
                value = bandLimitedSawtooth(phase: phase, increment: hertz / sampleRate)
            }

            // Advance the oscillator. Noise has no phase to advance.
            if recipe.waveform != .noise {
                let hertz = currentHertz(recipe, startHertz: startHertz, at: t)
                phase += hertz / sampleRate
                if phase >= 1 { phase -= phase.rounded(.down) }
            }

            if let sweep = recipe.filter {
                let cutoff = exponentialRamp(
                    from: sweep.startHertz * intensity,
                    to: sweep.endHertz,
                    over: sweep.rampSeconds,
                    at: t
                )
                value = filterState.lowpass(
                    value,
                    cutoff: cutoff,
                    resonance: sweep.resonance,
                    sampleRate: sampleRate
                )
            }

            let out = value * gain
            // Clamped rather than allowed to wrap. A sample past full scale is a click, and several
            // loud sounds at once genuinely reach it.
            samples[i] = Float(max(-1, min(1, out)))
        }

        return samples
    }

    /// The pitch at a moment, following the recipe's sweep.
    private static func currentHertz(
        _ recipe: SoundRecipe,
        startHertz: Double,
        at t: Double
    ) -> Double {
        guard let endHertz = recipe.endHertz, recipe.pitchRampSeconds > 0 else { return startHertz }
        return exponentialRamp(from: startHertz, to: endHertz, over: recipe.pitchRampSeconds, at: t)
    }

    /// A browser's exponential ramp: a constant *ratio* per unit time, held at the target after.
    ///
    /// Exponential rather than straight-line because both things it is used for — loudness and
    /// pitch — are heard on a ratio scale. A straight-line fall in amplitude is heard as a sound
    /// that hangs on and then disappears abruptly.
    static func exponentialRamp(from start: Double, to end: Double, over duration: Double, at t: Double) -> Double {
        if duration <= 0 { return end }
        if t >= duration { return end }
        if t <= 0 { return start }
        // Undefined through zero or across a sign change, exactly as a browser refuses it. The
        // target is the only sensible answer.
        guard start > 0, end > 0 else { return end }
        return start * jsPow(end / start, t / duration)
    }

    /// A triangle that starts at zero, as a browser's does.
    ///
    /// Left naive: its harmonics fall away as the square of their number, so what aliasing there is
    /// sits far below anything audible.
    static func triangle(_ phase: Double) -> Double {
        let p = phase - phase.rounded(.down)
        if p < 0.25 { return 4 * p }
        if p < 0.75 { return 2 - 4 * p }
        return 4 * p - 4
    }

    /// A sawtooth with the worst of its aliasing removed.
    ///
    /// A naive sawtooth steps from +1 to −1 in a single sample, and that discontinuity contains
    /// every frequency — including ones above what the sample rate can carry, which fold back down
    /// as an audible metallic ring. Worst on exactly what this is used for: a long sweep from 800Hz
    /// down to 80.
    ///
    /// The fix is to soften the step across the one sample either side of it, by an amount that
    /// depends on where *within* that sample the true crossing fell. Cheap, and it removes most of
    /// what a browser's band-limited version would never have produced in the first place.
    ///
    /// - Parameter increment: how much of a cycle one sample covers, which is the pitch divided by
    ///   the sample rate. It is also how wide the correction has to be.
    static func bandLimitedSawtooth(phase: Double, increment: Double) -> Double {
        let p = phase - phase.rounded(.down)
        let naive = 2 * p - 1
        guard increment > 0, increment < 0.5 else { return naive }
        return naive - stepCorrection(p, increment)
    }

    /// The correction either side of the wrap, and nothing in between.
    ///
    /// Two halves of one parabola: the first applies just after the step, the second just before it.
    private static func stepCorrection(_ t: Double, _ dt: Double) -> Double {
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1
        }
        if t > 1 - dt {
            let x = (t - 1) / dt
            return x * x + x + x + 1
        }
        return 0
    }
}

/// A two-pole lowpass, the shape a browser's filter node uses.
///
/// Its coefficients are recomputed every sample because the cutoff is sweeping. That is more
/// arithmetic than a fixed filter, and at a few tens of thousands of samples for a single explosion
/// it does not matter.
struct BiquadState {
    private var x1 = 0.0
    private var x2 = 0.0
    private var y1 = 0.0
    private var y2 = 0.0

    mutating func lowpass(
        _ input: Double,
        cutoff: Double,
        resonance: Double,
        sampleRate: Double
    ) -> Double {
        // Kept below the highest frequency the sample rate can represent; past that the filter
        // becomes unstable and produces a burst of noise rather than silence.
        let nyquist = sampleRate / 2
        let f = max(10, min(nyquist * 0.99, cutoff))
        let omega = 2 * Double.pi * f / sampleRate
        let cosOmega = jsCos(omega)
        let sinOmega = jsSin(omega)
        let alpha = sinOmega / (2 * max(0.0001, resonance))

        let b0 = (1 - cosOmega) / 2
        let b1 = 1 - cosOmega
        let b2 = (1 - cosOmega) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosOmega
        let a2 = 1 - alpha

        let output = (b0 / a0) * input
            + (b1 / a0) * x1
            + (b2 / a0) * x2
            - (a1 / a0) * y1
            - (a2 / a0) * y2

        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }
}
