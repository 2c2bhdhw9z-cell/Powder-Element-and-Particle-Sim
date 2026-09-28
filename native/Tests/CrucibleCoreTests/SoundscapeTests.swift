@testable import CrucibleCore
import Testing

@Suite("The living soundscape")
struct SoundscapeTests {
    // MARK: - Listening

    static func basin(width: Int = 120, height: Int = 90) -> PowderEngine {
        let engine = PowderEngine(width: width, height: height, seed: 5)
        for x in 0 ..< width {
            engine.setElement(x, height - 1, Element.bedrock)
            engine.setElement(x, height - 2, Element.bedrock)
        }
        for y in 0 ..< height {
            engine.setElement(0, y, Element.bedrock)
            engine.setElement(width - 1, y, Element.bedrock)
        }
        return engine
    }

    /// Listens across a stretch of the world's time, the way the lab does: every quarter of a second.
    static func listen(_ engine: PowderEngine, seconds: Double, during: (Int) -> Void = { _ in }) -> SoundscapeLevels {
        var listener = SoundscapeListener()
        var loudest = SoundscapeLevels.silence
        for moment in 0 ..< Int(seconds * 60) {
            during(moment)
            engine.step()
            if moment % 15 == 0 {
                let heard = listener.listen(to: engine)
                // After the first, which has nothing to compare against.
                if moment > 0 {
                    loudest.water = max(loudest.water, heard.water)
                    loudest.fire = max(loudest.fire, heard.fire)
                    loudest.glass = max(loudest.glass, heard.glass)
                    loudest.electricity = max(loudest.electricity, heard.electricity)
                    loudest.impacts = max(loudest.impacts, heard.impacts)
                }
            }
        }
        return loudest
    }

    @Test("A still lake is silent")
    func stillWaterIsSilent() {
        let engine = Self.basin()
        for y in 60 ..< 88 { for x in 1 ..< 119 { engine.setElement(x, y, Element.water) } }
        // Let it settle first; a lake just painted is still finding its level.
        for _ in 0 ..< 600 { engine.step() }
        let heard = Self.listen(engine, seconds: 3)
        #expect(heard.water < 0.1, "a still lake was heard at \(heard.water)")
        #expect(heard.isSilent || heard.water < 0.1)
    }

    @Test("Water pouring is heard as water")
    func pouringWaterIsHeard() {
        let engine = Self.basin()
        let heard = Self.listen(engine, seconds: 3) { _ in
            for x in 55 ..< 65 { engine.setElement(x, 2, Element.water) }
        }
        #expect(heard.water > 0.3, "pouring water was heard at \(heard.water)")
        #expect(heard.fire == 0 && heard.electricity == 0)
    }

    @Test("Fire is heard as hard as it is big")
    func fireIsHeard() {
        let small = Self.basin()
        let big = Self.basin()
        for y in 60 ..< 88 {
            for x in 50 ..< 54 { small.setElement(x, y, Element.wood) }
            for x in 10 ..< 110 { big.setElement(x, y, Element.wood) }
        }
        for x in 50 ..< 54 { small.setElement(x, 59, Element.fire) }
        for x in 10 ..< 110 { big.setElement(x, 59, Element.fire) }
        let quiet = Self.listen(small, seconds: 2)
        let loud = Self.listen(big, seconds: 2)
        #expect(loud.fire > 0.3)
        #expect(loud.fire > quiet.fire, "a big fire \(loud.fire) was no louder than a small one \(quiet.fire)")
    }

    @Test("Sparks buzz, sand landing hisses, and glass forming tinkles")
    func theOtherBeds() {
        let sparks = Self.basin()
        let electric = Self.listen(sparks, seconds: 1) { moment in
            if moment % 3 == 0 { for x in 40 ..< 80 { sparks.setElement(x, 10, Element.spark) } }
        }
        #expect(electric.electricity > 0.3, "sparks were heard at \(electric.electricity)")

        let sand = Self.basin()
        let pouring = Self.listen(sand, seconds: 2) { _ in
            for x in 55 ..< 65 { sand.setElement(x, 2, Element.sand) }
        }
        #expect(pouring.impacts > 0.3, "sand pouring was heard at \(pouring.impacts)")

        let glass = Self.basin()
        var row = 80
        let forming = Self.listen(glass, seconds: 2) { moment in
            if moment % 15 == 7, row > 40 {
                for x in 10 ..< 110 { glass.setElement(x, row, Element.glass) }
                row -= 1
            }
        }
        #expect(forming.glass > 0.3, "glass forming was heard at \(forming.glass)")
    }

    @Test("An explosion throws debris into the landing bed")
    func explosionsLand() {
        var listener = SoundscapeListener()
        let engine = Self.basin()
        _ = listener.listen(to: engine)
        let heard = listener.listen(to: engine, burst: 30)
        #expect(heard.impacts == 1)
    }

    @Test("A world that changes size is not heard as everything moving at once")
    func resizingIsNotMotion() {
        var listener = SoundscapeListener()
        let engine = Self.basin()
        for y in 40 ..< 88 { for x in 1 ..< 119 { engine.setElement(x, y, Element.sand) } }
        _ = listener.listen(to: engine)
        engine.resize(width: 150, height: 100)
        let heard = listener.listen(to: engine)
        #expect(heard.impacts == 0)
        #expect(heard.water == 0)
    }

    // MARK: - Making the sound

    static func render(_ levels: SoundscapeLevels, seconds: Double = 1, seed: UInt32 = 9) -> [Float] {
        var synth = SoundscapeSynth(sampleRate: 44_100, seed: seed)
        synth.target = levels
        synth.volume = 0.6
        var out = [Float](repeating: 0, count: Int(44_100 * seconds))
        // In the pieces the audio thread asks for.
        var start = 0
        while start < out.count {
            let count = min(512, out.count - start)
            out.withUnsafeMutableBufferPointer { all in
                let piece = UnsafeMutableBufferPointer(rebasing: all[start ..< start + count])
                synth.render(into: piece)
            }
            start += count
        }
        return out
    }

    static func loudness(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(samples.count)).squareRoot()
    }

    @Test("Silence is silence: nothing at all, not a hiss")
    func silenceIsSilent() {
        #expect(Self.render(.silence).allSatisfy { $0 == 0 })
    }

    @Test("Every bed makes a sound, louder the more there is, and never past full scale",
          arguments: ["water", "fire", "glass", "electricity", "impacts"])
    func everyBedSounds(bed: String) {
        func levels(_ amount: Double) -> SoundscapeLevels {
            switch bed {
            case "water": SoundscapeLevels(water: amount)
            case "fire": SoundscapeLevels(fire: amount)
            case "glass": SoundscapeLevels(glass: amount)
            case "electricity": SoundscapeLevels(electricity: amount)
            default: SoundscapeLevels(impacts: amount)
            }
        }
        let quiet = Self.loudness(Self.render(levels(0.2), seconds: 2))
        let loud = Self.loudness(Self.render(levels(1), seconds: 2))
        #expect(quiet > 0.0005, "\(bed) at a fifth made no sound")
        #expect(loud > quiet * 1.5, "\(bed): full \(loud) was not clearly louder than a fifth \(quiet)")
        let all = Self.render(levels(1))
        #expect(all.allSatisfy { $0.isFinite && abs($0) < 1 })
    }

    @Test("Everything at once is loud and not broken")
    func everythingAtOnce() {
        let all = Self.render(SoundscapeLevels(water: 1, fire: 1, glass: 1, electricity: 1, impacts: 1))
        #expect(all.allSatisfy { $0.isFinite && abs($0) < 1 })
        #expect(Self.loudness(all) > 0.01)
    }

    @Test("A bed swells in rather than clicking on")
    func swellsIn() {
        let samples = Self.render(SoundscapeLevels(fire: 1), seconds: 0.5)
        let first = Self.loudness(Array(samples[0 ..< 441]))
        let settled = Self.loudness(Array(samples[samples.count - 4410 ..< samples.count]))
        #expect(first < settled * 0.5, "the first hundredth of a second was \(first) against \(settled) later")
    }

    @Test("The same seed makes the same sound")
    func deterministic() {
        let levels = SoundscapeLevels(water: 0.7, fire: 0.3, glass: 0.5)
        #expect(Self.render(levels, seconds: 0.3, seed: 4) == Self.render(levels, seconds: 0.3, seed: 4))
        #expect(Self.render(levels, seconds: 0.3, seed: 4) != Self.render(levels, seconds: 0.3, seed: 5))
    }

    @Test("Levels that are not numbers are taken as silence, and too much as full")
    func badLevels() {
        let odd = SoundscapeLevels(water: .nan, fire: 7, glass: -2, electricity: .infinity, impacts: 0.5).clamped()
        #expect(odd.water == 0 && odd.fire == 1 && odd.glass == 0 && odd.electricity == 0 && odd.impacts == 0.5)
    }
}
