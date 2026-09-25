import Foundation
import Testing

@testable import CrucibleCore

/// Making the field move to music.
struct ParticleAudioTests {
    private let baseline = ParticleAudioBaseline(
        particleSize: 2,
        gravityY: 0.3,
        swirl: 0,
        glowStrength: 0
    )

    private func respond(
        _ mappings: [ParticleAudioMapping],
        bass: Double = 0,
        mid: Double = 0,
        level: Double = 0,
        sensitivity: Double = 1
    ) -> ParticleAudioResponse {
        ParticleAudio.respond(
            to: ParticleAudioSignal(bass: bass, mid: mid, level: level),
            mappings: mappings,
            sensitivity: sensitivity,
            baseline: baseline
        )
    }

    // MARK: - Silence

    @Test("Silence leaves the field exactly as it was")
    func silenceChangesNothing() {
        // The whole reason nothing is written into the settings: switching the music off has to put the
        // field back. The reference implementation writes into its live settings, so its sliders drift
        // while music plays and stay drifted afterwards.
        let quiet = respond(ParticleAudio.defaultMappings)
        #expect(quiet.particleSize == baseline.particleSize)
        #expect(quiet.gravityY == baseline.gravityY)
        #expect(quiet.swirl == baseline.swirl)
        #expect(quiet.glowStrength == baseline.glowStrength)
        #expect(quiet.colourShift == 0)
        #expect(quiet.burst == 0)
    }

    @Test("No mappings means nothing happens, however loud it is")
    func noMappingsMeansNoEffect() {
        let loud = respond([], bass: 1, mid: 1, level: 1)
        #expect(loud.particleSize == baseline.particleSize)
        #expect(loud.glowStrength == baseline.glowStrength)
    }

    @Test("An amount of nothing is off")
    func zeroAmountIsOff() {
        let response = respond(
            [ParticleAudioMapping(source: .bass, target: .size, amount: 0)],
            bass: 1
        )
        #expect(response.particleSize == baseline.particleSize)
    }

    // MARK: - Each target

    @Test("Every target can be driven, and each drives a different thing")
    func everyTargetWorks() {
        // Six entries in the interface have to be six different effects. A choice that does nothing is a
        // fault this project has shipped before.
        var seen: [String: String] = [:]
        for target in ParticleAudioTarget.allCases {
            let response = respond(
                [ParticleAudioMapping(source: .level, target: target, amount: 1.5)],
                level: 1
            )
            let signature = [
                response.particleSize, response.gravityY, response.swirl,
                response.glowStrength, response.colourShift, response.burst,
            ].map { "\(Int($0 * 1000))" }.joined(separator: ",")

            let resting = [
                baseline.particleSize, baseline.gravityY, baseline.swirl,
                baseline.glowStrength, 0, 0,
            ].map { "\(Int($0 * 1000))" }.joined(separator: ",")
            #expect(signature != resting, "\(target.rawValue) changed nothing")

            if let twin = seen[signature] {
                Issue.record("\(target.rawValue) does exactly the same as \(twin)")
            }
            seen[signature] = target.rawValue
        }
    }

    @Test("Every target and source has a name and an explanation worth showing")
    func namesAreUsable() {
        for target in ParticleAudioTarget.allCases {
            #expect(!target.displayName.isEmpty)
            #expect(!target.explanation.isEmpty)
        }
        for source in ParticleAudioSignal.Source.allCases {
            #expect(!source.displayName.isEmpty)
        }
        #expect(
            Set(ParticleAudioTarget.allCases.map(\.displayName)).count
                == ParticleAudioTarget.allCases.count
        )
    }

    @Test("Size grows in proportion and gravity grows by addition")
    func sizeIsProportionalAndGravityIsNot() {
        // Size reads as a proportion — doubling a two-pixel body and a six-pixel one should both look like
        // doubling. Gravity has a natural nought, and a proportion of nought is nought, so a multiplied
        // version would do nothing in the common case of a weightless field.
        let grown = respond(
            [ParticleAudioMapping(source: .bass, target: .size, amount: 1)],
            bass: 1
        )
        #expect(grown.particleSize > baseline.particleSize * 1.5)

        let weightless = ParticleAudioBaseline(particleSize: 2, gravityY: 0, swirl: 0, glowStrength: 0)
        let pulled = ParticleAudio.respond(
            to: ParticleAudioSignal(bass: 1),
            mappings: [ParticleAudioMapping(source: .bass, target: .gravity, amount: 1)],
            sensitivity: 1,
            baseline: weightless
        )
        #expect(pulled.gravityY > 0, "gravity must move even from a resting value of nothing")
    }

    @Test("Two mappings on the same setting add up rather than one winning")
    func mappingsStack() {
        // The reference implementation computes each mapping from the *original* value, so the second
        // silently overwrites the first and one of the two does nothing at all.
        let single = respond(
            [ParticleAudioMapping(source: .bass, target: .size, amount: 0.6)],
            bass: 1,
            mid: 1
        )
        let both = respond(
            [
                ParticleAudioMapping(source: .bass, target: .size, amount: 0.6),
                ParticleAudioMapping(source: .mid, target: .size, amount: 0.6),
            ],
            bass: 1,
            mid: 1
        )
        #expect(both.particleSize > single.particleSize, "the second mapping did nothing")
    }

    @Test("Nothing sound does can push a setting out of its range")
    func everythingStaysInRange() {
        let everything = ParticleAudioTarget.allCases.map {
            ParticleAudioMapping(source: .level, target: $0, amount: 2)
        }
        let response = ParticleAudio.respond(
            to: ParticleAudioSignal(bass: 1, mid: 1, level: 1),
            mappings: everything + everything + everything,
            sensitivity: 4,
            baseline: ParticleAudioBaseline(
                particleSize: 8,
                gravityY: 1.2,
                swirl: 8,
                glowStrength: 4
            )
        )
        #expect(response.particleSize <= 8)
        #expect(response.gravityY <= 1.2)
        #expect(response.swirl <= 8)
        #expect(response.glowStrength <= 4)
        #expect(response.colourShift >= 0 && response.colourShift < 1)
        #expect(response.burst <= 1)
    }

    @Test("A colour shift goes round rather than stopping at the end")
    func colourShiftWraps() {
        // A ramp has no end, so the shift should keep going round. Clamping would make it stick on the last
        // colour and stay there for as long as the music was loud.
        let response = respond(
            [ParticleAudioMapping(source: .level, target: .colour, amount: 2)],
            level: 1,
            sensitivity: 4
        )
        #expect(response.colourShift >= 0 && response.colourShift < 1)
    }

    @Test("Readings that are not numbers cannot reach the settings")
    func unusableReadingsAreSafe() {
        for signal in [
            ParticleAudioSignal(bass: .nan, mid: .nan, level: .nan),
            ParticleAudioSignal(bass: .infinity, mid: -.infinity, level: 1e9),
            ParticleAudioSignal(bass: -5, mid: -5, level: -5),
        ] {
            let response = ParticleAudio.respond(
                to: signal,
                mappings: ParticleAudioTarget.allCases.map {
                    ParticleAudioMapping(source: .bass, target: $0, amount: .nan)
                } + ParticleAudio.defaultMappings,
                sensitivity: .nan,
                baseline: baseline
            )
            #expect(response.particleSize.isFinite)
            #expect(response.gravityY.isFinite)
            #expect(response.swirl.isFinite)
            #expect(response.glowStrength.isFinite)
            #expect(response.colourShift.isFinite)
            #expect(response.burst.isFinite)
        }
    }

    @Test("A resting value that is not a number does not spread")
    func unusableBaselineIsSafe() {
        let response = ParticleAudio.respond(
            to: ParticleAudioSignal(bass: 1),
            mappings: ParticleAudio.defaultMappings,
            sensitivity: 1,
            baseline: ParticleAudioBaseline(
                particleSize: .nan,
                gravityY: .nan,
                swirl: .nan,
                glowStrength: .nan
            )
        )
        #expect(response.particleSize.isFinite)
        #expect(response.gravityY.isFinite)
        #expect(response.swirl.isFinite)
        #expect(response.glowStrength.isFinite)
    }

    // MARK: - The envelope

    @Test("A signal rises quickly and falls slowly")
    func envelopeIsAsymmetric() {
        // The whole point. The reference has no envelope at all, so a drum hit lasts one frame — eight
        // milliseconds at a hundred and twenty frames a second, far too short to see.
        var follower = ParticleAudioFollower()
        follower.follow(ParticleAudioSignal(bass: 1))
        let afterOneLoudFrame = follower.held.bass
        #expect(afterOneLoudFrame > 0.4, "a beat should land at once, not creep in")

        // Let it settle, then go silent.
        for _ in 0 ..< 20 { follower.follow(ParticleAudioSignal(bass: 1)) }
        #expect(follower.held.bass > 0.98)
        follower.follow(.silence)
        #expect(follower.held.bass > 0.85, "the fall should be gentle, not a cliff")

        // Count how long each direction takes to cover most of the distance.
        var rising = ParticleAudioFollower()
        var framesToRise = 0
        while rising.held.bass < 0.9, framesToRise < 200 {
            rising.follow(ParticleAudioSignal(bass: 1))
            framesToRise += 1
        }
        var falling = ParticleAudioFollower()
        for _ in 0 ..< 40 { falling.follow(ParticleAudioSignal(bass: 1)) }
        var framesToFall = 0
        while falling.held.bass > 0.1, framesToFall < 400 {
            falling.follow(.silence)
            framesToFall += 1
        }
        #expect(
            framesToFall > framesToRise * 3,
            "rose in \(framesToRise) frames and fell in \(framesToFall) — those are too close"
        )
    }

    @Test("A signal held steady settles on that value")
    func envelopeSettles() {
        var follower = ParticleAudioFollower()
        for _ in 0 ..< 200 { follower.follow(ParticleAudioSignal(bass: 0.42, mid: 0.7, level: 0.9)) }
        #expect(abs(follower.held.bass - 0.42) < 0.02)
        #expect(abs(follower.held.mid - 0.7) < 0.02)
        #expect(abs(follower.held.level - 0.9) < 0.02)
    }

    @Test("Resetting the follower silences it")
    func envelopeResets() {
        var follower = ParticleAudioFollower()
        for _ in 0 ..< 20 { follower.follow(ParticleAudioSignal(bass: 1, mid: 1, level: 1)) }
        follower.reset()
        #expect(follower.held == .silence)
    }

    @Test("Nonsense envelope rates cannot stall or overshoot the follower")
    func envelopeRatesAreClamped() {
        for envelope in [
            ParticleAudioEnvelope(rise: .nan, fall: .nan),
            ParticleAudioEnvelope(rise: 0, fall: 0),
            ParticleAudioEnvelope(rise: -4, fall: -4),
            ParticleAudioEnvelope(rise: 99, fall: 99),
        ] {
            var follower = ParticleAudioFollower(envelope: envelope)
            for _ in 0 ..< 400 { follower.follow(ParticleAudioSignal(bass: 1)) }
            #expect(follower.held.bass.isFinite)
            #expect(follower.held.bass <= 1)
            #expect(follower.held.bass > 0.5, "the follower stalled and never reached the signal")
        }
    }

    @Test("A reading that is not a number does not poison the follower")
    func envelopeSurvivesUnusableReadings() {
        var follower = ParticleAudioFollower()
        for _ in 0 ..< 10 { follower.follow(ParticleAudioSignal(bass: 0.8)) }
        follower.follow(ParticleAudioSignal(bass: .nan, mid: .infinity, level: -.infinity))
        #expect(follower.held.bass.isFinite)
        #expect(follower.held.mid.isFinite)
        #expect(follower.held.level.isFinite)
    }

    // MARK: - Bursts

    @Test("Quiet music throws nothing in")
    func burstsNeedAFloor() {
        // Without a floor any music at all produces a continuous trickle rather than bursts on the beat,
        // and a trickle fills the field to its limit within seconds.
        #expect(ParticleAudio.burstCount(strength: 0) == 0)
        #expect(ParticleAudio.burstCount(strength: 0.3) == 0)
        #expect(ParticleAudio.burstCount(strength: ParticleAudio.burstFloor) == 0)
        #expect(ParticleAudio.burstCount(strength: .nan) == 0)
    }

    @Test("A burst is a visible handful, and a loud one is more")
    func burstsScale() {
        let quietest = ParticleAudio.burstCount(strength: ParticleAudio.burstFloor + 0.01)
        let loudest = ParticleAudio.burstCount(strength: 1)
        #expect(quietest >= 60, "the quietest burst that fires should still be visible, not one body")
        #expect(loudest > quietest * 3)
        #expect(loudest <= 400)
    }

    // MARK: - Turning a microphone into three numbers

    @Test("The bands are found from real frequencies, not from bin numbers")
    func bandsFollowFrequencies() {
        // The reference implementation hard-codes bin numbers, so which frequencies its bass and middle
        // actually cover drift with whatever device it happens to be running on. Here the same tone should
        // land in the same band at either sample rate.
        for sampleRate in [44_100.0, 48_000.0] {
            for bins in [128, 512] {
                var magnitudes = [Float](repeating: 0, count: bins)
                // A tone at a hundred hertz, which is bass by any reckoning.
                let topFrequency = sampleRate / 2
                let bin = Int(100 / topFrequency * Double(bins))
                magnitudes[max(0, min(bins - 1, bin))] = 1

                let signal = ParticleAudio.bands(magnitudes: magnitudes, sampleRate: sampleRate)
                #expect(signal.bass > 0, "a hundred hertz is not in the bass at \(sampleRate)/\(bins)")
                #expect(signal.mid == 0, "and it is not in the middle")
            }
        }
    }

    @Test("A tone in the middle lands in the middle")
    func middleBandIsCorrect() {
        let sampleRate = 48_000.0
        let bins = 512
        var magnitudes = [Float](repeating: 0, count: bins)
        // A thousand hertz, which is squarely a voice.
        magnitudes[Int(1_000 / (sampleRate / 2) * Double(bins))] = 1
        let signal = ParticleAudio.bands(magnitudes: magnitudes, sampleRate: sampleRate)
        #expect(signal.mid > 0)
        #expect(signal.bass == 0)
    }

    @Test("Loudness follows everything at once")
    func loudnessIsTheWhole() {
        let bins = 256
        let quiet = ParticleAudio.bands(
            magnitudes: [Float](repeating: 0.05, count: bins),
            sampleRate: 48_000
        )
        let loud = ParticleAudio.bands(
            magnitudes: [Float](repeating: 0.8, count: bins),
            sampleRate: 48_000
        )
        #expect(loud.level > quiet.level * 5)
        #expect(loud.level <= 1)
    }

    @Test("No sound, or nonsense, gives silence rather than an unusable number")
    func brokenInputGivesSilence() {
        #expect(ParticleAudio.bands(magnitudes: [], sampleRate: 48_000) == .silence)
        #expect(ParticleAudio.bands(magnitudes: [0.5], sampleRate: 0) == .silence)
        #expect(ParticleAudio.bands(magnitudes: [0.5], sampleRate: .nan) == .silence)

        let broken = ParticleAudio.bands(
            magnitudes: [.nan, .infinity, -1, 0.5],
            sampleRate: 48_000
        )
        #expect(broken.bass.isFinite)
        #expect(broken.mid.isFinite)
        #expect(broken.level.isFinite)
        #expect(broken.level >= 0 && broken.level <= 1)
    }

    // MARK: - Saving

    @Test("Mappings and envelopes survive being written down")
    func typesRoundTrip() throws {
        let mappings = [
            ParticleAudioMapping(source: .mid, target: .swirl, amount: 1.4),
            ParticleAudioMapping(source: .bass, target: .burst, amount: 0.9),
        ]
        let bytes = try JSONEncoder().encode(mappings)
        #expect(try JSONDecoder().decode([ParticleAudioMapping].self, from: bytes) == mappings)

        let envelope = ParticleAudioEnvelope(rise: 0.7, fall: 0.04)
        let envelopeBytes = try JSONEncoder().encode(envelope)
        #expect(
            try JSONDecoder().decode(ParticleAudioEnvelope.self, from: envelopeBytes) == envelope
        )
    }
}
