import Testing

@testable import CrucibleCore

/// The health inspection and the repair tools.
///
/// These are what someone reaches for when the world has already gone wrong, which sets a
/// higher bar than ordinary code: a repair that claims success without repairing anything,
/// or that damages something unrelated on the way past, is worse than no repair at all —
/// it removes both the evidence and the reason to keep looking. Every test here was a real
/// instance of one of those in the web reference.
@Suite("Powder health inspection and repairs")
struct PowderDiagnosticsTests {
    @Test("A cell that is wrong in two ways is counted once")
    func noDoubleCounting() {
        let engine = PowderEngine(width: 16, height: 16, seed: 1)
        engine.type[0] = 9999
        engine.temperature[0] = .nan

        let report = engine.inspect()
        // Both faults incremented the same counter, so twenty damaged cells were reported
        // as forty — and the repair that followed then truthfully said twenty, which read
        // like a failure.
        #expect(report.corruptCellCount == 1)
        #expect(report.corruptTypeCount == 1)
        #expect(report.unreadableTempCount == 1)
    }

    @Test("An element the registry cannot describe counts as corrupt and can be cleared")
    func unknownElementIsCorrupt() {
        let engine = PowderEngine(width: 16, height: 16, seed: 1)
        // Past every real id, but below the loose threshold the web reference used. Such a
        // cell drew as air, behaved as air, was never reported, could not be cleared, and
        // still counted as a real particle forever.
        engine.type[5] = 300
        #expect(engine.inspect().corruptTypeCount == 1)
        #expect(!engine.inspect().isHealthy)

        #expect(engine.flushStuckCells() == 1)
        #expect(engine.type[5] == Element.empty)
        #expect(engine.inspect().corruptTypeCount == 0)
    }

    @Test("Temperature is averaged over the cells it could read")
    func averageSkipsUnreadableCells() {
        let engine = PowderEngine(width: 10, height: 10, seed: 1)
        engine.temperature.update(repeating: 100, count: engine.cellCount)
        for i in 0 ..< 50 { engine.temperature[i] = .nan }
        // Dividing by every cell while skipping the unreadable ones dragged the figure
        // toward zero in proportion to the damage, so it was least trustworthy exactly when
        // someone was consulting it.
        #expect(engine.inspect().avgTemp == 100)
    }

    @Test("A corrupt cell is emptied completely, not just its element")
    func flushClearsEverything() {
        let engine = PowderEngine(width: 8, height: 8, seed: 1)
        engine.type[3] = 9999
        engine.life[3] = 77
        engine.velocityX[3] = 5
        engine.velocityY[3] = -4

        engine.flushStuckCells()

        // Leaving the lifetime and momentum behind meant the next thing to occupy the cell
        // inherited a stranger's motion and a countdown to decay.
        #expect(engine.type[3] == Element.empty)
        #expect(engine.life[3] == 0)
        #expect(engine.velocityX[3] == 0)
        #expect(engine.velocityY[3] == 0)
    }

    @Test("Repairs use the world's own ambient temperature")
    func repairsUseAmbient() {
        let engine = PowderEngine(width: 8, height: 8, seed: 1)
        engine.ambientTemp = -40
        engine.temperature[0] = 9000
        engine.temperature[1] = .nan

        #expect(engine.normaliseTemperatures() == 2)
        #expect(engine.temperature[0] == Float(-40))
        #expect(engine.temperature[1] == Float(-40))

        engine.coolAllCells()
        #expect(engine.temperature[5] == Float(-40))
    }

    @Test("Unreadable temperatures are cleared by the automatic pass")
    func autoFixClearsUnreadableTemperatures() {
        let engine = PowderEngine(width: 12, height: 12, seed: 1)
        // The only fault. The thermal repair used to be gated on the hottest and coldest
        // readings, and an unreadable value is neither — so nothing was done and the pass
        // then declared the world recovered.
        for i in 0 ..< 20 { engine.temperature[i] = .nan }
        #expect(!engine.inspect().isHealthy)

        engine.runAutoFix()
        #expect(engine.inspect().unreadableTempCount == 0)
        #expect(engine.inspect().isHealthy)
    }

    @Test("The automatic pass does not wall the world in")
    func autoFixDoesNotSeal() {
        let engine = PowderEngine(width: 20, height: 20, seed: 1)
        for x in 0 ..< 20 { engine.setElement(x, 19, Element.bedrock) }
        engine.type[40] = 9999 // One unrelated fault.

        engine.runAutoFix()

        // Sealing replaces the whole perimeter with bedrock. Running that automatically, in
        // response to a fault nothing to do with the edges, destroyed the shape of every
        // scene built with an open top — which is all of them.
        var sealedTop = 0
        for x in 0 ..< 20 where engine.type[x] == Element.bedrock { sealedTop += 1 }
        #expect(sealedTop == 0)
    }

    @Test("Sealing still works when asked for directly")
    func sealingWorksOnDemand() {
        let engine = PowderEngine(width: 12, height: 12, seed: 1)
        #expect(engine.sealBedrockBorders() > 0)
        for x in 0 ..< 12 { #expect(engine.type[x] == Element.bedrock) }
    }

    @Test("Nothing is left burning inside the bedrock that is laid down")
    func sealingClearsWhatItReplaces() {
        let engine = PowderEngine(width: 12, height: 12, seed: 1)
        engine.setElement(3, 0, Element.fire, temp: 900)
        engine.sealBedrockBorders()

        let i = engine.index(3, 0)
        // Bedrock does not burn or decay, so whatever it replaced has to go with it. A
        // burning cell turned into bedrock that was still at nine hundred degrees with a
        // decay countdown kept cooking its neighbours from inside something inert.
        #expect(engine.type[i] == Element.bedrock)
        #expect(engine.temperature[i] == JS.toFloat32(engine.ambientTemp))
        #expect(engine.life[i] == 0)
    }

    @Test("A world with no cells is handled rather than mis-counted")
    func emptyWorldIsSafe() {
        let engine = PowderEngine(width: 0, height: 0, seed: 1)
        // With no cells there is no border. The loops used to compute an index of minus
        // one, whose write goes nowhere while the read beside it returns nothing — so the
        // count rose for writes that never landed.
        #expect(engine.sealBedrockBorders() == 0)
        #expect(engine.purgeOutOfBounds() == 0)
        #expect(engine.inspect().totalCells == 0)
        #expect(engine.runAutoFix().count > 0)
    }

    @Test("The pass reports what it could not fix")
    func autoFixAdmitsFailure() {
        // Near-maximum density has no corresponding repair, so the pass has to finish and
        // say so. Large enough that clearing the frame cannot by itself bring it back under
        // the threshold.
        let engine = PowderEngine(width: 200, height: 200, seed: 1)
        engine.type.update(repeating: Element.sand, count: engine.cellCount)
        #expect(!engine.inspect().isHealthy)

        let logs = engine.runAutoFix()
        #expect(!engine.inspect().isHealthy)
        // The old message announced recovery regardless, which is precisely the case where
        // the detail matters.
        #expect(logs.contains { $0.contains("could not be repaired") })
        #expect(logs.contains { $0.lowercased().contains("density") })
    }

    @Test("A thermal spike is still hot on the next tick")
    func thermalSpikeSurvivesATick() {
        let engine = PowderEngine(width: 40, height: 40, seed: 1)
        engine.injectThermalSpike()
        engine.step()
        // Written straight into the grid, the fire had no decay countdown — and anything
        // decaying with a spent countdown becomes its successor immediately, so the whole
        // spike turned to smoke before anyone could see it.
        #expect(engine.inspect().maxTemp > 1000)
    }

    @Test("Explosives are made inert without boiling")
    func explosivesBecomeStone() {
        let engine = PowderEngine(width: 8, height: 8, seed: 1)
        engine.setElement(2, 2, Element.c4)
        engine.setElement(3, 2, Element.gunpowder)
        #expect(engine.extinguishFires() == 2)
        // Turning an explosive into water at 250 degrees is above boiling, so the old
        // "make it safe" produced a steam burst on the very next tick.
        #expect(engine.type[engine.index(2, 2)] == Element.stone)
        #expect(engine.type[engine.index(3, 2)] == Element.stone)
        #expect(engine.temperature[engine.index(2, 2)] == JS.toFloat32(engine.ambientTemp))
    }

    @Test("Acid becomes water, not something flammable")
    func acidBecomesWater() {
        let engine = PowderEngine(width: 8, height: 8, seed: 1)
        engine.setElement(4, 4, Element.acid)
        #expect(engine.neutraliseAcids() == 1)
        #expect(engine.type[engine.index(4, 4)] == Element.water)
    }

    @Test("Clearing the frame leaves the walls alone")
    func purgeKeepsBedrock() {
        let engine = PowderEngine(width: 10, height: 10, seed: 1)
        engine.setElement(0, 0, Element.bedrock)
        engine.setElement(1, 0, Element.sand)
        // Bedrock is the wall, not something stuck against it.
        #expect(engine.purgeOutOfBounds() == 1)
        #expect(engine.type[engine.index(0, 0)] == Element.bedrock)
        #expect(engine.type[engine.index(1, 0)] == Element.empty)
    }
}

@Suite("Particle field health inspection and repairs")
struct ParticleDiagnosticsTests {
    @Test("A corrupt swarm is repaired rather than reported forever")
    func swarmIsRepairable() {
        let engine = ParticleEngine(width: 300, height: 300, seed: 99)
        engine.spawnBatch(count: 5000)
        engine.swarm.positions[0] = .nan
        engine.swarm.velocities[3] = .infinity

        let before = engine.inspect()
        #expect(before.swarmCorruptCount > 0)
        #expect(!before.isHealthy)

        // Purging only ever touched the object list, so the report said "N corrupt" and the
        // repair said it had removed none, leaving the issue permanently unresolvable.
        engine.runAutoFix()
        #expect(engine.inspect().swarmCorruptCount == 0)
    }

    @Test("A speed limit of zero does not freeze the field")
    func zeroLimitMeansNoLimit() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 7)
        engine.spawnBurst(count: 40)
        engine.maxSpeed = 0
        engine.clampVelocities()
        // The inspection reads zero as "no limit"; the repair took it literally and
        // multiplied every velocity by zero, stopping the whole field dead — while the
        // inspection that triggered it had reported nothing wrong.
        #expect(engine.particles.contains { $0.velocityX != 0 || $0.velocityY != 0 })
    }

    @Test("A radius of zero survives being brought back in bounds")
    func zeroRadiusIsPreserved() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 7)
        engine.addParticle(x: -500, y: 150, velocityX: -1, velocityY: 0, radius: 0, charge: 1)
        #expect(engine.recentreOutOfBounds() == 1)
        // Zero is a legitimate radius the engine goes out of its way to preserve; a
        // truthiness test silently replaced it with the default, resizing a body inside a
        // repair that is only supposed to move it.
        #expect(engine.particles[0].radius == 0)
        #expect(engine.particles[0].x >= 0)
    }

    @Test("Charge balances to exactly zero")
    func chargeBalances() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 7)
        for i in 0 ..< 5 {
            engine.addParticle(x: Double(i) * 10, y: 10, radius: 2, charge: 5)
        }
        #expect(engine.resetCharges() == 5)
        // With an odd number the last one used to keep whatever it had — possibly five —
        // while the function reported a balanced field it had not produced.
        #expect(engine.particles.reduce(0) { $0 + $1.charge } == 0)
    }

    @Test("Swarm bodies past the speed limit are counted")
    func swarmSpeedIsCounted() {
        let engine = ParticleEngine(width: 300, height: 300, seed: 99)
        engine.spawnBatch(count: 5000)
        engine.maxSpeed = 10
        engine.swarm.velocities[0] = 900
        engine.swarm.velocities[1] = 0
        // The swarm only fed the headline top speed, so the report could show nine hundred
        // beside a count of zero over the limit, and an escaped swarm was invisible.
        #expect(engine.inspect().overSpeedCount > 0)
    }

    @Test("A corrupt velocity is reset rather than scaled")
    func corruptVelocityIsReset() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 7)
        engine.addParticle(x: 10, y: 10, velocityX: .infinity, velocityY: 5, radius: 2, charge: 1)
        engine.clampVelocities()
        // Dividing the limit by infinity gives zero, and infinity times zero is not a
        // number — so scaling made this repair manufacture the very corruption it removes.
        #expect(engine.particles[0].velocityX == 0)
        #expect(engine.particles[0].velocityY == 0)
    }

    @Test("Purging a corrupt body keeps the springs valid")
    func purgeKeepsSpringsValid() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 7)
        engine.spawnCloth(cols: 6, rows: 5)
        #expect(!engine.springs.isEmpty)
        engine.withParticle(at: 3) { $0.x = .nan }

        #expect(engine.purgeCorruptParticles() == 1)
        for spring in engine.springs {
            #expect(spring.a >= 0 && spring.a < engine.particles.count)
            #expect(spring.b >= 0 && spring.b < engine.particles.count)
            #expect(spring.a != spring.b)
        }
    }

    @Test("Bringing the field to rest leaves pinned bodies pinned")
    func haltSkipsPinned() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 7)
        engine.spawnRope(length: 8)
        engine.withParticle(at: 4) { $0.velocityX = 9 }
        let stopped = engine.haltAllMotion()
        #expect(stopped > 0)
        #expect(engine.particles.allSatisfy { $0.isFixed || ($0.velocityX == 0 && $0.velocityY == 0) })
    }

    @Test("A healthy field is left alone")
    func healthyFieldIsUntouched() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 7)
        engine.spawnBurst(count: 30)
        let report = engine.inspect()
        #expect(report.isHealthy)
        let logs = engine.runAutoFix()
        #expect(logs.contains { $0.contains("No anomalies detected") })
    }

    @Test("The injectors produce the faults the repairs look for")
    func injectorsWork() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 7)
        engine.injectCorruptParticles()
        #expect(engine.inspect().corruptCount >= 15)
        engine.runAutoFix()
        #expect(engine.inspect().corruptCount == 0)

        let fast = ParticleEngine(width: 400, height: 300, seed: 7)
        fast.injectHyperVelocityExplosion()
        #expect(fast.inspect().overSpeedCount > 0)
        fast.runAutoFix()
        #expect(fast.inspect().overSpeedCount == 0)
    }
}
