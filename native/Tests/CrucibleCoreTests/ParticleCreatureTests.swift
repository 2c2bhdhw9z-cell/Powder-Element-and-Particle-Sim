@testable import CrucibleCore
import Foundation
import Testing

@Suite("Creatures of bones and muscles")
struct ParticleCreatureTests {
    static func field(width: Double = 1400, height: Double = 500) -> ParticleEngine {
        let engine = ParticleEngine(width: width, height: height, seed: 11)
        engine.screenWidth = width
        engine.screenHeight = height
        return engine
    }

    static func run(_ engine: ParticleEngine, seconds: Double) {
        for _ in 0 ..< Int(seconds * 60) { engine.step() }
    }

    @Test("The walker walks: steadily one way, and never falls over on the way")
    func theWalkerWalks() throws {
        let engine = Self.field()
        #expect(engine.addReadyCreature(.walker))
        var last = 0.0
        for second in 1 ... 12 {
            Self.run(engine, seconds: 1)
            let status = try #require(engine.creatureStatus(0))
            #expect(status.isStanding, "the walker fell over after \(second) seconds")
            if second % 4 == 0 {
                #expect(status.walked > last + 20, "the walker only got from \(last) to \(status.walked)")
                last = status.walked
            }
        }
    }

    @Test("A table stands still, and the same box without its diagonal falls over")
    func balance() throws {
        let table = Self.field()
        #expect(table.addReadyCreature(.table))
        Self.run(table, seconds: 8)
        let standing = try #require(table.creatureStatus(0))
        #expect(standing.isStanding && standing.heightShare > 0.9)
        #expect(abs(standing.walked) < 5, "a table with no muscles went \(standing.walked)")

        let tumbler = Self.field()
        #expect(tumbler.addReadyCreature(.tumbler))
        Self.run(tumbler, seconds: 8)
        let fallen = try #require(tumbler.creatureStatus(0))
        #expect(!fallen.isStanding, "a square of bones stayed up at \(fallen.heightShare)")
    }

    @Test("Only a creature's feet grip: anything else on the floor slides as it always has")
    func gripIsForCreatures() {
        let engine = Self.field()
        _ = engine.addReadyCreature(.table, atX: 300)
        let id = engine.addParticle(
            x: 900, y: 500 - 3, velocityX: 6, velocityY: 0, radius: 3, mass: 1, charge: 0, color: .init(hue: 0, saturation: 0, lightness: 1)
        )
        Self.run(engine, seconds: 0.5)
        let body = engine.particles.first { $0.id == id }
        #expect((body?.x ?? 0) > 1000, "a body sliding on the floor was stopped at \(body?.x ?? 0)")
    }

    @Test("A limb snaps its ends to joints already there, and short strokes and doubled limbs are not limbs")
    func drawing() {
        var plan = CreaturePlan()
        #expect(plan.problem != nil)
        let drew1 = plan.addLimb(fromX: 100, y: 100, toX: 160, y: 100, kind: .bone)
        #expect(drew1)
        // Starts a few pixels off the first joint: the same joint.
        let drew2 = plan.addLimb(fromX: 104, y: 97, toX: 130, y: 60, kind: .bone)
        #expect(drew2)
        #expect(plan.joints.count == 3)
        let drew3 = plan.addLimb(fromX: 160, y: 100, toX: 163, y: 101, kind: .bone)
        #expect(!drew3, "a tap is not a limb")
        let drew4 = plan.addLimb(fromX: 160, y: 100, toX: 100, y: 100, kind: .muscle)
        #expect(!drew4, "the same two joints again")
        #expect(plan.limbs.count == 2)
        #expect(plan.problem == nil)
        // Muscles drawn one after another take turns.
        plan.addLimb(fromX: 160, y: 100, toX: 130, y: 60, kind: .muscle)
        plan.addLimb(fromX: 130, y: 60, toX: 130, y: 20, kind: .muscle)
        let muscles = plan.limbs.filter { $0.kind == .muscle }
        #expect(muscles.map(\.phase) == [0, 0.5])
    }

    @Test("What stops a plan living is said in words: no bone, or a piece not joined on")
    func problems() {
        var musclesOnly = CreaturePlan()
        musclesOnly.addLimb(fromX: 0, y: 0, toX: 50, y: 0, kind: .muscle)
        #expect(musclesOnly.problem?.contains("bone") == true)
        var twoPieces = CreaturePlan()
        twoPieces.addLimb(fromX: 0, y: 0, toX: 50, y: 0, kind: .bone)
        twoPieces.addLimb(fromX: 200, y: 0, toX: 250, y: 0, kind: .bone)
        #expect(!twoPieces.isInOnePiece)
        #expect(twoPieces.problem?.contains("joined") == true)
        let engine = Self.field()
        #expect(!engine.bringToLife(twoPieces, named: "Broken"))
        #expect(engine.creatures.isEmpty && engine.particles.isEmpty)
    }

    @Test("Taking the last limb away takes any joint it leaves joined to nothing")
    func removingLimbs() {
        var plan = CreaturePlan()
        plan.addLimb(fromX: 0, y: 0, toX: 50, y: 0, kind: .bone)
        plan.addLimb(fromX: 50, y: 0, toX: 50, y: 50, kind: .bone)
        plan.removeLast()
        #expect(plan.limbs.count == 1 && plan.joints.count == 2)
        plan.removeLast()
        #expect(plan.limbs.isEmpty && plan.joints.isEmpty)
    }

    @Test("A drawn creature comes to life where it was drawn, as bones and muscles, and one undo takes it away")
    func bringingToLife() {
        let engine = Self.field()
        var plan = CreaturePlan()
        plan.addLimb(fromX: 600, y: 300, toX: 660, y: 300, kind: .bone)
        plan.addLimb(fromX: 660, y: 300, toX: 630, y: 250, kind: .bone)
        plan.addLimb(fromX: 630, y: 250, toX: 600, y: 300, kind: .muscle)
        #expect(engine.bringToLifeWhereDrawn(plan, named: "Mine"))
        #expect(engine.particles.count == 3)
        #expect(engine.springs.count == 3)
        #expect(engine.springs.filter(\.isMuscle).count == 1)
        #expect(engine.creatures.first?.name == "Mine")
        // Drawn in the air, so it falls.
        Self.run(engine, seconds: 2)
        #expect((engine.particles.map(\.y).max() ?? 0) > 480)
        engine.undo()
        #expect(engine.creatures.isEmpty && engine.particles.isEmpty && engine.springs.isEmpty)
    }

    @Test("A creature survives being saved with the world, and goes on walking")
    func saving() throws {
        let engine = Self.field()
        _ = engine.addReadyCreature(.walker)
        Self.run(engine, seconds: 4)
        let before = try #require(engine.creatureStatus(0)).walked
        let data = try JSONEncoder().encode(engine.captureState())
        let again = Self.field()
        #expect(again.apply(try JSONDecoder().decode(ParticleState.self, from: data)))
        #expect(again.creatures.count == 1)
        #expect(again.creatures.first?.name == "Walker")
        let restored = try #require(again.creatureStatus(0)).walked
        #expect(abs(restored - before) < 2, "it came back \(restored) along, having been \(before)")
        Self.run(again, seconds: 6)
        #expect(try #require(again.creatureStatus(0)).walked > before + 30)
    }

    @Test("Creatures can all be taken away, and there is a limit to how many")
    func removingAndLimits() {
        let engine = Self.field()
        for index in 0 ..< ParticleEngine.creatureLimit + 3 {
            _ = engine.addReadyCreature(.table, atX: Double(80 + index * 90))
        }
        #expect(engine.creatures.count == ParticleEngine.creatureLimit)
        engine.removeCreatures()
        #expect(engine.creatures.isEmpty && engine.particles.isEmpty)
        #expect(engine.creatureStatus(0) == nil)
    }

    @Test("A creature whose joints are all taken is forgotten")
    func forgotten() {
        let engine = Self.field()
        _ = engine.addReadyCreature(.table)
        _ = engine.removeParticles { _ in true }
        engine.step()
        #expect(engine.creatures.isEmpty)
    }
}
