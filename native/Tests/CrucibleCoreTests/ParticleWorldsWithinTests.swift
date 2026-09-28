@testable import CrucibleCore
import Testing

@Suite("Worlds within worlds")
struct ParticleWorldsWithinTests {
    static func field() -> ParticleEngine {
        let engine = ParticleEngine(width: 800, height: 600, seed: 4)
        engine.screenWidth = 800
        engine.screenHeight = 600
        return engine
    }

    @Test("The same body, at the same depth, always holds the same world")
    func sameBodySameWorld() {
        let one = ParticleEngine.worldWithin(bodyID: 1234, hue: 200, depth: 1)
        let again = ParticleEngine.worldWithin(bodyID: 1234, hue: 200, depth: 1)
        #expect(one == again)
        #expect(ParticleEngine.worldWithin(bodyID: 1234, hue: 200, depth: 2) != one, "one level down is another place")
    }

    @Test("Neighbouring bodies hold all sorts of worlds, not a run of the same one")
    func variety() {
        let worlds = (0 ..< 200).map { ParticleEngine.worldWithin(bodyID: $0, hue: 30, depth: 1).arrangement }
        #expect(Set(worlds).count >= 10, "only \(Set(worlds))")
        var longestRun = 1
        var run = 1
        for (a, b) in zip(worlds, worlds.dropFirst()) {
            run = a == b ? run + 1 : 1
            longestRun = max(longestRun, run)
        }
        #expect(longestRun <= 4)
    }

    @Test("Every world a body can hold is one the field can lay out, flat", arguments: ParticleEngine.insideArrangements)
    func everyInsideWorks(id: String) {
        let engine = Self.field()
        engine.enter(WorldWithin(arrangement: id, name: id, seed: 9, hue: 120, depth: 1))
        #expect(engine.bodyCount > 0, "\(id) was empty inside")
        #expect(!engine.depthEnabled)
        for _ in 0 ..< 60 { engine.step() }
        #expect(engine.particles.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test("Going into the same world twice lays it out the same way both times")
    func insideIsTheSameEachVisit() {
        let world = ParticleEngine.worldWithin(bodyID: 77, hue: 10, depth: 1)
        let first = Self.field()
        first.enter(world)
        let second = Self.field()
        for _ in 0 ..< 10 { _ = second.addParticle(x: 5, y: 5) }
        second.enter(world)
        #expect(first.particles.map(\.x) == second.particles.map(\.x))
        #expect(first.particles.map(\.y) == second.particles.map(\.y))
    }

    @Test("A world inside a red body is a red world")
    func tinted() {
        let engine = Self.field()
        engine.enter(WorldWithin(arrangement: "flock", name: "Flock", seed: 3, hue: 0, depth: 1))
        let hues = engine.particles.map { ParticleEngine.hsl($0.color) }.filter { $0.saturation > 0.2 }.map(\.hue)
        #expect(!hues.isEmpty)
        let near = hues.filter { $0 < 80 || $0 > 280 }.count
        #expect(Double(near) / Double(hues.count) > 0.6, "most bodies should lean red: \(hues.prefix(8))")
    }

    @Test("Colours are read back the way they were made")
    func hslRoundTrip() {
        for hue in stride(from: 0.0, to: 360, by: 45) {
            let read = ParticleEngine.hsl(PackedColor(hue: hue, saturation: 0.8, lightness: 0.5))
            var gap = abs(read.hue - hue)
            if gap > 180 { gap = 360 - gap }
            #expect(gap < 2, "hue \(hue) read as \(read.hue)")
            #expect(abs(read.saturation - 0.8) < 0.03 && abs(read.lightness - 0.5) < 0.03)
        }
    }

    @Test("The body nearest a finger is found, and nothing when there is nothing near")
    func findingABody() {
        let engine = Self.field()
        let a = engine.addParticle(x: 100, y: 100, radius: 4)
        let b = engine.addParticle(x: 140, y: 100, radius: 4)
        #expect(engine.body(nearX: 105, y: 102, within: 20)?.id == a)
        #expect(engine.body(nearX: 133, y: 100, within: 20)?.id == b)
        #expect(engine.body(nearX: 400, y: 400, within: 20) == nil)
    }

    @Test("Going inside leaves no undo point: the world outside is kept by whoever went in")
    func noUndo() {
        let engine = Self.field()
        _ = engine.addParticle(x: 100, y: 100)
        let could = engine.canUndo
        engine.enter(ParticleEngine.worldWithin(bodyID: 5, hue: 0, depth: 1))
        #expect(engine.canUndo == could)
    }

    @Test("The fifth body of one world and the fifth of another hold different worlds")
    func outerWorldMatters() {
        let here = ParticleEngine.worldWithin(bodyID: 5, hue: 90, depth: 2, outerSeed: 1111)
        let there = ParticleEngine.worldWithin(bodyID: 5, hue: 90, depth: 2, outerSeed: 2222)
        #expect(here.seed != there.seed)
    }

    @Test("A world kept and put back is the same world, every body with the same identifier")
    func keepingTheWorldOutside() {
        let engine = Self.field()
        engine.loadArrangement("galaxy")
        for _ in 0 ..< 30 { engine.step() }
        let ids = engine.particles.map(\.id)
        let places = engine.particles.map(\.x)
        let kept = engine.keepWorld()
        engine.enter(ParticleEngine.worldWithin(bodyID: ids[3], hue: 50, depth: 1))
        #expect(engine.particles.map(\.id) != ids)
        engine.putBack(kept)
        #expect(engine.particles.map(\.id) == ids)
        #expect(engine.particles.map(\.x) == places)
    }
}
