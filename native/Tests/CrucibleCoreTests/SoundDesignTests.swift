import Testing

@testable import CrucibleCore

/// The six sounds, checked as signals rather than as settings.
///
/// There is no recorded comparison here and there cannot be a useful one: a browser generates these
/// through its own oscillators and filter, which are not reproducible to the sample, so a fixture
/// would only record my implementation agreeing with itself.
///
/// What *can* be checked is that each sound is actually the thing it claims to be — that the meteor
/// really does fall in pitch, that the explosion really does lose its brightness, that every
/// envelope reaches silence and nothing clips. Those are the properties that make a sound
/// recognisable, and they are the ones a porting error would break.
@Suite("The lab's sounds are the sounds they claim to be")
struct SoundDesignTests {
    private static let sampleRate = 44100.0

    private func render(_ sound: LabSound, intensity: Double = 1, volume: Double = 0.4) -> [Float] {
        var random = Mulberry32(seed: 4242)
        return SoundSynthesis.render(
            sound,
            intensity: intensity,
            volume: volume,
            sampleRate: Self.sampleRate,
            random: &random
        )
    }

    /// The loudest sample in a stretch, which is how these are compared.
    private func peak(_ samples: [Float], from: Double, to: Double) -> Double {
        let start = max(0, Int(from * Self.sampleRate))
        let end = min(samples.count, Int(to * Self.sampleRate))
        guard start < end else { return 0 }
        var highest = 0.0
        for i in start ..< end { highest = max(highest, abs(Double(samples[i]))) }
        return highest
    }

    /// How often the signal crosses zero in a stretch, which stands in for its pitch.
    ///
    /// Crude, and enough: a sound an octave lower crosses half as often, and that is the kind of
    /// difference these tests exist to catch.
    private func zeroCrossings(_ samples: [Float], from: Double, to: Double) -> Int {
        let start = max(1, Int(from * Self.sampleRate))
        let end = min(samples.count, Int(to * Self.sampleRate))
        guard start < end else { return 0 }
        var count = 0
        for i in start ..< end where (samples[i - 1] < 0) != (samples[i] < 0) {
            count += 1
        }
        return count
    }

    // MARK: Shape

    @Test("Every sound lasts as long as its recipe says", arguments: LabSound.allCases)
    func durationsMatch(sound: LabSound) {
        let samples = render(sound)
        let recipe = SoundDesign.recipe(for: sound)
        let expected = Int(Self.sampleRate * recipe.duration)
        #expect(abs(samples.count - expected) <= 1, "\(sound) is \(samples.count) samples, expected about \(expected)")
    }

    @Test("Every sound starts at its loudest and fades to nothing", arguments: LabSound.allCases)
    func envelopesFall(sound: LabSound) {
        let samples = render(sound)
        let recipe = SoundDesign.recipe(for: sound)
        let start = peak(samples, from: 0, to: recipe.duration * 0.15)
        let end = peak(samples, from: recipe.duration * 0.9, to: recipe.duration)
        #expect(start > 0, "\(sound) is silent at the start")
        #expect(end < start * 0.2, "\(sound) does not fade: starts at \(start), ends at \(end)")
    }

    @Test("Nothing clips", arguments: LabSound.allCases)
    func nothingClips(sound: LabSound) {
        // At the master volume the app ships with. Clipping is a click, and a click on every
        // explosion is worse than a quiet explosion.
        let samples = render(sound)
        let highest = peak(samples, from: 0, to: 10)
        #expect(highest <= 1.0, "\(sound) reaches \(highest)")
        #expect(highest > 0.001, "\(sound) is inaudible")
    }

    @Test("Every sample is a usable number", arguments: LabSound.allCases)
    func noNaNs(sound: LabSound) {
        // A single unusable sample is a loud click on some hardware and silence on others. The
        // exponential ramps are the risk: through zero they are undefined.
        let samples = render(sound)
        let bad = samples.filter { !$0.isFinite }.count
        #expect(bad == 0, "\(sound) has \(bad) unusable samples")
    }

    // MARK: Character

    @Test("The meteor falls in pitch")
    func meteorDescends() {
        // 800Hz down to 80. The whole identity of the sound.
        let samples = render(.meteor)
        let early = zeroCrossings(samples, from: 0, to: 0.05)
        let late = zeroCrossings(samples, from: 0.4, to: 0.45)
        #expect(early > late * 3, "meteor should fall steeply: \(early) crossings early, \(late) late")
    }

    @Test("The freeze rises in pitch")
    func freezeAscends() {
        // 200Hz up to 1200 — the opposite direction to the meteor, and swapping the two would be an
        // easy porting error that still produced a sound.
        let samples = render(.freeze)
        let early = zeroCrossings(samples, from: 0, to: 0.05)
        let late = zeroCrossings(samples, from: 0.2, to: 0.25)
        #expect(late > early * 2, "freeze should rise: \(early) crossings early, \(late) late")
    }

    @Test("The acid fizz falls in pitch")
    func acidFizzDescends() {
        let samples = render(.acidFizz)
        let early = zeroCrossings(samples, from: 0, to: 0.02)
        let late = zeroCrossings(samples, from: 0.05, to: 0.07)
        #expect(early > late, "acid should fall: \(early) early, \(late) late")
    }

    @Test("The fire crackle holds one pitch")
    func fireCrackleHoldsPitch() {
        // No sweep in the recipe. If a sweep crept in, this would drift.
        let samples = render(.fireCrackle)
        let early = zeroCrossings(samples, from: 0, to: 0.02)
        let late = zeroCrossings(samples, from: 0.02, to: 0.04)
        #expect(abs(early - late) <= 3, "fire should hold pitch: \(early) then \(late)")
    }

    /// The explosion is noise pushed through a closing filter. The closing is what makes it read as
    /// a blast rather than as a hiss, and the way to see it is that the signal gets smoother.
    @Test("The explosion loses its brightness")
    func explosionDarkens() {
        let samples = render(.explosion)
        let early = zeroCrossings(samples, from: 0, to: 0.05)
        let late = zeroCrossings(samples, from: 0.3, to: 0.35)
        #expect(early > late * 2, "explosion should darken: \(early) crossings early, \(late) late")
    }

    @Test("A bigger explosion is louder and brighter")
    func explosionIntensityMatters() {
        let quiet = render(.explosion, intensity: 1)
        let loud = render(.explosion, intensity: 3)
        #expect(peak(loud, from: 0, to: 0.05) > peak(quiet, from: 0, to: 0.05))
        // Intensity opens the filter as well as raising the volume, so a big blast is sharper.
        #expect(zeroCrossings(loud, from: 0, to: 0.05) > zeroCrossings(quiet, from: 0, to: 0.05))
    }

    // MARK: Volume

    @Test("The master volume scales everything, and zero is silence", arguments: LabSound.allCases)
    func volumeScales(sound: LabSound) {
        let half = peak(render(sound, volume: 0.2), from: 0, to: 10)
        let full = peak(render(sound, volume: 0.4), from: 0, to: 10)
        #expect(full > half, "\(sound) did not get louder")

        // Silence is returned as no samples at all, so the caller can skip the work entirely.
        var random = Mulberry32(seed: 1)
        let muted = SoundSynthesis.render(
            sound,
            volume: 0,
            sampleRate: Self.sampleRate,
            random: &random
        )
        #expect(muted.isEmpty, "\(sound) at zero volume should render nothing")
    }

    // MARK: Waveforms

    @Test("The triangle starts at zero and reaches both extremes")
    func triangleShape() {
        #expect(SoundSynthesis.triangle(0) == 0)
        #expect(SoundSynthesis.triangle(0.25) == 1)
        #expect(abs(SoundSynthesis.triangle(0.5)) < 1e-12)
        #expect(SoundSynthesis.triangle(0.75) == -1)
        #expect(abs(SoundSynthesis.triangle(1)) < 1e-12)
    }

    @Test("The sawtooth ramps from bottom to top and stays in range")
    func sawtoothShape() {
        // Away from the wrap the correction does nothing, so the plain ramp shows through.
        #expect(abs(SoundSynthesis.bandLimitedSawtooth(phase: 0.5, increment: 0.01) - 0) < 1e-12)
        #expect(SoundSynthesis.bandLimitedSawtooth(phase: 0.25, increment: 0.01) < 0)
        #expect(SoundSynthesis.bandLimitedSawtooth(phase: 0.75, increment: 0.01) > 0)

        // Across the whole cycle, including the corrected region, nothing leaves range.
        for step in 0 ... 1000 {
            let phase = Double(step) / 1000
            let value = SoundSynthesis.bandLimitedSawtooth(phase: phase, increment: 0.02)
            #expect(value >= -1.5 && value <= 1.5, "sawtooth at \(phase) is \(value)")
        }
    }

    /// The correction exists to remove aliasing, and the way to see that it does is that the
    /// waveform no longer jumps the full range between neighbouring samples.
    @Test("The sawtooth's correction softens the step")
    func sawtoothStepIsSoftened() {
        let increment = 0.05
        var worstNaive = 0.0
        var worstCorrected = 0.0
        var previousNaive = 0.0
        var previousCorrected = 0.0
        var phase = 0.0
        for i in 0 ..< 200 {
            let naive = 2 * (phase - phase.rounded(.down)) - 1
            let corrected = SoundSynthesis.bandLimitedSawtooth(phase: phase, increment: increment)
            if i > 0 {
                worstNaive = max(worstNaive, abs(naive - previousNaive))
                worstCorrected = max(worstCorrected, abs(corrected - previousCorrected))
            }
            previousNaive = naive
            previousCorrected = corrected
            phase += increment
        }
        #expect(worstNaive > 1.5, "the plain sawtooth should jump nearly the full range")
        #expect(
            worstCorrected < worstNaive,
            "the correction should soften the jump: \(worstCorrected) against \(worstNaive)"
        )
    }

    // MARK: Ramps

    @Test("An exponential ramp holds its endpoints and never returns an unusable number")
    func rampsBehave() {
        #expect(SoundSynthesis.exponentialRamp(from: 100, to: 10, over: 1, at: 0) == 100)
        #expect(SoundSynthesis.exponentialRamp(from: 100, to: 10, over: 1, at: 1) == 10)
        #expect(SoundSynthesis.exponentialRamp(from: 100, to: 10, over: 1, at: 2) == 10)
        // Halfway along in time is the geometric middle, not the arithmetic one — which is the whole
        // reason for using a ratio scale.
        let middle = SoundSynthesis.exponentialRamp(from: 100, to: 1, over: 1, at: 0.5)
        #expect(abs(middle - 10) < 1e-9, "halfway should be 10, got \(middle)")

        // Through zero the curve is undefined; a browser refuses the instruction outright. Returning
        // the target is the only usable answer, and returning 'not a number' would reach the speaker.
        #expect(SoundSynthesis.exponentialRamp(from: 0, to: 10, over: 1, at: 0.5) == 10)
        #expect(SoundSynthesis.exponentialRamp(from: 10, to: 0, over: 1, at: 0.5) == 0)
        #expect(SoundSynthesis.exponentialRamp(from: -1, to: 10, over: 1, at: 0.5) == 10)
    }

    // MARK: Throttling

    @Test("A sound will not repeat until its interval has passed")
    func throttleHolds() {
        // Computed into locals first: an expectation cannot contain a call that mutates.
        var throttle = SoundThrottle()
        let first = throttle.allows(.explosion, at: 0)
        let tooSoon = throttle.allows(.explosion, at: 0.1)
        // The explosion's interval is two tenths of a second.
        let afterWaiting = throttle.allows(.explosion, at: 0.2)
        #expect(first)
        #expect(!tooSoon)
        #expect(afterWaiting)
    }

    /// Each sound keeps its own clock. Without that, a burning field's crackle would suppress the
    /// explosion it is about to cause.
    @Test("One sound being held back does not hold back the others")
    func throttlesAreIndependent() {
        var throttle = SoundThrottle()
        let crackle = throttle.allows(.fireCrackle, at: 0)
        let crackleAgain = throttle.allows(.fireCrackle, at: 0.01)
        let explosion = throttle.allows(.explosion, at: 0.01)
        let freeze = throttle.allows(.freeze, at: 0.01)
        #expect(crackle)
        #expect(!crackleAgain, "the same sound should be held back")
        #expect(explosion, "a different sound should not be held back")
        #expect(freeze, "a different sound should not be held back")
    }

    /// The reason the throttle exists at all: a field on fire asks for a crackle from every flame on
    /// every tick. Hundreds a second, summing into a roar.
    @Test("A flood of requests is reduced to a listenable rate")
    func throttleThinsAFlood() {
        var throttle = SoundThrottle()
        var allowed = 0
        // One second of requests at sixty a second.
        for frame in 0 ..< 60 {
            let permitted = throttle.allows(.fireCrackle, at: Double(frame) / 60)
            if permitted { allowed += 1 }
        }
        // The crackle's interval is 0.15s, so about seven a second at most.
        #expect(allowed <= 8, "let through \(allowed) crackles in a second")
        #expect(allowed >= 5, "throttled too hard: only \(allowed) in a second")
    }
}
