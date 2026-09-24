import Testing

@testable import CrucibleCore

/// These tests exist to prove one thing: the Swift generator produces the same
/// number stream as the JavaScript one in the web reference implementation.
///
/// That matters because the whole porting strategy rests on it. The reference
/// implementation's test suite is the specification for the physics, and those
/// tests are only reproducible because they seed the random generator. If the two
/// generators diverge even slightly, every ported physics test becomes
/// meaningless — a failure could mean "the physics is wrong" or merely "the dice
/// rolled differently", and there would be no way to tell which.
///
/// The expected values below were produced by executing the actual
/// `mulberry32` function from `web/src/sim/__tests__/helpers.ts` under Node, not
/// by reasoning about what it should emit.
@Suite("Mulberry32 matches the JavaScript reference stream")
struct Mulberry32Tests {
    @Test("Raw 32-bit output matches Node, across the seed range")
    func rawBitsMatchNode() {
        // Four seeds chosen to cover the interesting cases: the value the web
        // test helper defaults to, both arithmetic extremes, and one low seed
        // where a weak generator would show obvious structure.
        let expected: [(seed: UInt32, stream: [UInt32])] = [
            (
                1234,
                [314_799_534, 3_021_131_492, 3_877_737_075, 4_168_477_787,
                 175_938_938, 505_788_695, 694_861_204, 3_447_815_142]
            ),
            (
                0,
                [1_144_304_738, 1_416_247, 958_946_056, 627_933_444,
                 2_007_157_716, 2_340_967_985, 2_642_484_575, 2_787_370_982]
            ),
            (
                1,
                [2_693_262_067, 11_749_833, 2_265_367_787, 4_213_581_821,
                 4_159_151_403, 1_207_330_352, 2_632_122_864, 3_095_568_220]
            ),
            (
                4_294_967_295,
                [3_850_105_811, 813_802_916, 3_073_704_848, 4_054_706_436,
                 3_630_262_831, 2_315_588_663, 2_922_715_533, 2_042_566_601]
            ),
        ]

        for (seed, stream) in expected {
            var generator = Mulberry32(seed: seed)
            for (index, want) in stream.enumerated() {
                let got = generator.nextBits()
                #expect(got == want, "seed \(seed), draw \(index): got \(got), expected \(want)")
            }
        }
    }

    @Test("Doubles match Node to the last bit")
    func doublesMatchNode() {
        // Printed from Node at 17 significant digits, which round-trips a Double
        // exactly. Comparison is exact rather than approximate: the conversion
        // divides by a power of two, so both languages must agree bit for bit.
        let expected: [Double] = [
            0.073294978123158216,
            0.70341198984533548,
            0.90285601909272373,
            0.97054936620406806,
            0.040963976178318262,
        ]
        var generator = Mulberry32(seed: 1234)
        for (index, want) in expected.enumerated() {
            let got = generator.next()
            #expect(got == want, "draw \(index): got \(got), expected \(want)")
        }
    }

    @Test("Output stays inside the half-open unit interval and is unbiased")
    func distributionIsSane() {
        // Node over the same 200,000 draws from seed 99 reported
        // min 7.112976164e-7, max 0.9999805803, mean 0.5006806562.
        var generator = Mulberry32(seed: 99)
        var minimum = 1.0
        var maximum = 0.0
        var total = 0.0
        let draws = 200_000
        for _ in 0 ..< draws {
            let value = generator.next()
            minimum = min(minimum, value)
            maximum = max(maximum, value)
            total += value
        }
        #expect(minimum >= 0)
        #expect(maximum < 1, "next() must never reach 1.0, or floor-based index maths can run off the end")
        #expect(abs(minimum - 7.112976164e-7) < 1e-12)
        #expect(abs(maximum - 0.9999805803) < 1e-9)
        #expect(abs(total / Double(draws) - 0.5006806562) < 1e-9)
    }

    @Test("Stream position can be snapshotted and resumed")
    func stateRoundTrips() {
        // Undo, replay and save files all depend on being able to rewind the
        // generator to an exact point.
        var generator = Mulberry32(seed: 7)
        for _ in 0 ..< 10 { _ = generator.next() }
        let saved = generator.state

        let afterSave = (0 ..< 5).map { _ in generator.next() }

        var resumed = Mulberry32(seed: 0)
        resumed.state = saved
        let replayed = (0 ..< 5).map { _ in resumed.next() }

        #expect(afterSave == replayed)
    }

    @Test("Two generators on the same seed never diverge")
    func sameSeedSameStream() {
        var a = Mulberry32(seed: 2024)
        var b = Mulberry32(seed: 2024)
        for _ in 0 ..< 1000 {
            let left = a.nextBits()
            let right = b.nextBits()
            #expect(left == right)
        }
    }
}

/// The helpers wrap common JavaScript idioms from the engine. Each must consume
/// exactly one draw, because the *number* of draws determines what every
/// subsequent piece of physics sees.
@Suite("Mulberry32 helpers mirror the JavaScript idioms")
struct Mulberry32HelperTests {
    @Test("int(below:) equals Math.floor(Math.random() * bound)")
    func integerBelowMatchesFloorIdiom() {
        var viaHelper = Mulberry32(seed: 55)
        var viaIdiom = Mulberry32(seed: 55)
        for bound in [1, 2, 3, 7, 16, 100, 4096] {
            for _ in 0 ..< 200 {
                let got = viaHelper.int(below: bound)
                let want = Int((viaIdiom.next() * Double(bound)).rounded(.down))
                #expect(got == want)
                #expect(got >= 0 && got < bound, "must stay in range for array indexing")
            }
        }
    }

    @Test("int(below:) still consumes one draw when the bound is degenerate")
    func degenerateBoundStillAdvances() {
        // The engine computes bounds from live state, so zero and negative bounds
        // do occur. Returning early without drawing would desynchronise the
        // stream from the reference implementation, where the multiplication
        // happens regardless.
        for bound in [0, -1, -99] {
            var generator = Mulberry32(seed: 3)
            let before = generator.state
            let result = generator.int(below: bound)
            #expect(result == 0)
            #expect(generator.state != before, "bound \(bound) must not skip the draw")
        }
    }

    @Test("nudge() yields -1, 0 and 1 in equal thirds")
    func nudgeCoversThreeOffsets() {
        var generator = Mulberry32(seed: 11)
        var counts: [Int: Int] = [-1: 0, 0: 0, 1: 0]
        let draws = 90_000
        for _ in 0 ..< draws {
            let value = generator.nudge()
            #expect(counts[value] != nil, "nudge() returned \(value), outside -1...1")
            counts[value, default: 0] += 1
        }
        for offset in [-1, 0, 1] {
            let share = Double(counts[offset]!) / Double(draws)
            #expect(abs(share - 1.0 / 3.0) < 0.01, "offset \(offset) share was \(share)")
        }
    }

    @Test("sign() is an even split between -1 and 1")
    func signIsBalanced() {
        var generator = Mulberry32(seed: 12)
        var negatives = 0
        let draws = 40_000
        for _ in 0 ..< draws {
            let value = generator.sign()
            #expect(value == -1 || value == 1)
            if value == -1 { negatives += 1 }
        }
        #expect(abs(Double(negatives) / Double(draws) - 0.5) < 0.01)
    }

    @Test("chance() and percentChance() agree with their JavaScript forms")
    func probabilityHelpersMatchIdioms() {
        var viaChance = Mulberry32(seed: 77)
        var viaIdiom = Mulberry32(seed: 77)
        for probability in [0.0, 0.05, 0.5, 0.9, 1.0] {
            for _ in 0 ..< 200 {
                let got = viaChance.chance(probability)
                let want = viaIdiom.next() < probability
                #expect(got == want)
            }
        }

        var viaPercent = Mulberry32(seed: 78)
        var viaPercentIdiom = Mulberry32(seed: 78)
        for percent in [0.0, 15.0, 50.0, 99.0, 100.0] {
            for _ in 0 ..< 200 {
                let got = viaPercent.percentChance(percent)
                let want = viaPercentIdiom.next() * 100 < percent
                #expect(got == want)
            }
        }
    }

    @Test("Impossible and certain probabilities behave absolutely")
    func probabilityEdgesAreAbsolute() {
        // `Math.random()` never returns 1, so a probability of 1 must always
        // fire and a probability of 0 must never fire. Several reactions rely on
        // this to be switched fully on or fully off.
        var generator = Mulberry32(seed: 404)
        var certainAlwaysFired = true
        var impossibleNeverFired = true
        var certainPercentAlwaysFired = true
        var impossiblePercentNeverFired = true
        for _ in 0 ..< 20_000 {
            if !generator.chance(1.0) { certainAlwaysFired = false }
            if generator.chance(0.0) { impossibleNeverFired = false }
            if !generator.percentChance(100.0) { certainPercentAlwaysFired = false }
            if generator.percentChance(0.0) { impossiblePercentNeverFired = false }
        }
        #expect(certainAlwaysFired, "a probability of 1 must always fire")
        #expect(impossibleNeverFired, "a probability of 0 must never fire")
        #expect(certainPercentAlwaysFired, "100% must always fire")
        #expect(impossiblePercentNeverFired, "0% must never fire")
    }

    @Test("signedUnit() and range() match their JavaScript forms")
    func continuousHelpersMatchIdioms() {
        var viaHelper = Mulberry32(seed: 91)
        var viaIdiom = Mulberry32(seed: 91)
        for _ in 0 ..< 500 {
            let got = viaHelper.signedUnit()
            let want = viaIdiom.next() * 2 - 1
            #expect(got == want)
        }
        for (lower, upper) in [(0.0, 1.0), (-5.0, 5.0), (100.0, 200.0), (3.0, 3.0)] {
            for _ in 0 ..< 200 {
                let got = viaHelper.range(lower, upper)
                let want = lower + viaIdiom.next() * (upper - lower)
                #expect(got == want)
            }
        }
    }
}
