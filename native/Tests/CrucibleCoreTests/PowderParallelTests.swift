@testable import CrucibleCore
import Testing

@Suite("Parallel worlds")
struct PowderParallelTests {
    /// A world with everything going on at once: sand falling, water running, fire on wood, lava, people.
    static func busyWorld() -> PowderEngine {
        let engine = PowderEngine(width: 160, height: 120, seed: 21)
        for x in 0 ..< 160 {
            engine.setElement(x, 118, Element.bedrock)
            engine.setElement(x, 119, Element.bedrock)
        }
        for y in 80 ..< 118 { for x in 10 ..< 40 { engine.setElement(x, y, Element.wood) } }
        for x in 10 ..< 40 { engine.setElement(x, 79, Element.fire) }
        for y in 20 ..< 50 { for x in 60 ..< 90 { engine.setElement(x, y, Element.sand) } }
        for y in 20 ..< 40 { for x in 100 ..< 130 { engine.setElement(x, y, Element.water) } }
        for y in 90 ..< 100 { for x in 130 ..< 150 { engine.setElement(x, y, Element.lava) } }
        _ = engine.addPerson(atX: 75, y: 110)
        for _ in 0 ..< 60 { engine.step() }
        return engine
    }

    static func identical(_ a: PowderEngine, _ b: PowderEngine) -> Bool {
        guard a.cellCount == b.cellCount else { return false }
        for index in 0 ..< a.cellCount {
            if a.type[index] != b.type[index] || a.temperature[index] != b.temperature[index] || a.life[index] != b.life[index] {
                return false
            }
        }
        return a.people == b.people
    }

    @Test("Two untouched copies of a busy world stay the same to the last cell")
    func twinsStayTwins() {
        let world = Self.busyWorld()
        let copy = world.twin()
        #expect(Self.identical(world, copy))
        for moment in 0 ..< 600 {
            world.step()
            copy.step()
            if moment % 100 == 99 {
                #expect(Self.identical(world, copy), "the copies came apart by moment \(moment)")
            }
        }
        #expect(PowderEngine.difference(world, copy) == 0)
    }

    @Test("Every change makes the second world go differently", arguments: PowderParallelChange.allCases)
    func everyChangeMatters(change: PowderParallelChange) {
        let world = Self.busyWorld()
        let copy = world.twin()
        change.apply(to: copy)
        for _ in 0 ..< 600 {
            world.step()
            copy.step()
        }
        #expect(PowderEngine.difference(world, copy) > 0, "\(change.title) changed nothing")
    }

    @Test("One grain of sand is enough for two worlds to come apart, and the gap grows")
    func oneGrainGrows() {
        let world = Self.busyWorld()
        let copy = world.twin()
        PowderParallelChange.oneGrain.apply(to: copy)
        var early = 0.0
        for moment in 0 ..< 900 {
            world.step()
            copy.step()
            if moment == 30 { early = PowderEngine.difference(world, copy) }
        }
        let late = PowderEngine.difference(world, copy)
        #expect(late > early, "the difference went from \(early) to \(late)")
    }

    @Test("A copy made to match another is exactly it, even from a different size")
    func becomingACopy() {
        let world = Self.busyWorld()
        let other = PowderEngine(width: 50, height: 40, seed: 3)
        #expect(other.becomeCopy(of: world))
        #expect(Self.identical(world, other))
        #expect(other.rng == world.rng)
    }

    @Test("How different two worlds are is measured against what is in them, not against the air")
    func differenceIgnoresAir() {
        let a = PowderEngine(width: 100, height: 100, seed: 1)
        let b = PowderEngine(width: 100, height: 100, seed: 1)
        for x in 0 ..< 10 {
            a.setElement(x, 50, Element.sand)
            b.setElement(x, 50, Element.sand)
        }
        b.setElement(0, 50, Element.water)
        #expect(abs(PowderEngine.difference(a, b) - 0.1) < 1e-9)
        #expect(PowderEngine.difference(a, PowderEngine(width: 5, height: 5)) == 1)
    }

    @Test("The second world follows the first's settings as they change, apart from the one that differs")
    func followsTheFirst() {
        let world = Self.busyWorld()
        let copy = world.twin()
        PowderParallelChange.warmerRoom.apply(to: copy)
        world.ambientTemp = 5
        world.gravityY = -1
        world.setWind(-0.3)
        PowderParallelChange.warmerRoom.keep(copy, following: world)
        #expect(copy.ambientTemp == 65)
        #expect(copy.gravityY == -1)
        #expect(copy.windX == world.windX)
        PowderParallelChange.upsideDown.keep(copy, following: world)
        #expect(copy.gravityY == 1 && copy.ambientTemp == 5)
        PowderParallelChange.noPressure.keep(copy, following: world)
        #expect(!copy.pressureEnabled && copy.heatConductionEnabled == world.heatConductionEnabled)
    }

    @Test("Kept in step with no change at all, the two stay the same")
    func keptInStepStaySame() {
        let world = Self.busyWorld()
        let copy = world.twin()
        for _ in 0 ..< 300 {
            PowderParallelChange.oneGrain.keep(copy, following: world)
            world.step()
            copy.step()
        }
        #expect(Self.identical(world, copy))
    }
}
