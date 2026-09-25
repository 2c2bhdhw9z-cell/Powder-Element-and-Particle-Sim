import Foundation
import Testing

@testable import CrucibleCore

/// Sources that pour bodies into the world, and the weight and lifetime the crowd now carries.
struct ParticleEmitterTests {
    private func field() -> ParticleEngine {
        let engine = ParticleEngine(width: 400, height: 700, seed: 3)
        engine.setMaxParticles(60_000)
        engine.gravityX = 0
        engine.gravityY = 0
        engine.collisionsEnabled = false
        return engine
    }

    // MARK: - Pouring at a rate

    @Test("A rate below one body a moment still emits")
    func slowRatesStillEmit() {
        // The whole reason for carrying what is owed from one moment to the next. Without it any rate under
        // sixty a second rounds to nothing each moment and the source never emits at all — which is what the
        // old six-a-frame emitter could not express.
        let engine = field()
        // Six a second is one body every ten moments.
        engine.emitterTemplate.rate = 6
        engine.addEmitter(atX: 200, y: 100)

        for _ in 0 ..< 60 { engine.step() }
        #expect(engine.swarm.count >= 5, "only \(engine.swarm.count) after a second at six a second")
        #expect(engine.swarm.count <= 8, "and \(engine.swarm.count) is too many")
    }

    @Test("The rate is bodies a second, not bodies a frame")
    func rateIsPerSecond() {
        // The old one emitted six a frame, so it poured twice as fast on a phone running at a hundred and
        // twenty as on one at sixty — and slowed down whenever the field got busy, which is exactly when it
        // should not.
        let engine = field()
        engine.emitterTemplate.rate = 120
        engine.addEmitter(atX: 200, y: 100)
        for _ in 0 ..< 60 { engine.step() }
        #expect(abs(engine.swarm.count - 120) <= 3, "a second at 120 a second gave \(engine.swarm.count)")
    }

    @Test("Doubling the rate doubles what comes out")
    func rateScales() {
        func poured(rate: Double) -> Int {
            let engine = field()
            engine.emitterTemplate.rate = rate
            engine.addEmitter(atX: 200, y: 100)
            for _ in 0 ..< 60 { engine.step() }
            return engine.swarm.count
        }
        let slow = poured(rate: 60)
        let fast = poured(rate: 120)
        #expect(abs(Double(fast) / Double(max(1, slow)) - 2) < 0.15, "\(slow) then \(fast)")
    }

    @Test("A source with no rate pours nothing")
    func zeroRateIsOff() {
        let engine = field()
        engine.emitterTemplate.rate = 0
        engine.addEmitter(atX: 200, y: 100)
        for _ in 0 ..< 60 { engine.step() }
        #expect(engine.swarm.count == 0)
    }

    @Test("A stopped source pours nothing, and starting it again resumes")
    func runningCanBeToggled() {
        let engine = field()
        engine.emitterTemplate.rate = 120
        engine.addEmitter(atX: 200, y: 100)
        for _ in 0 ..< 30 { engine.step() }
        let after = engine.swarm.count
        #expect(after > 0)

        engine.emitters[0].isRunning = false
        for _ in 0 ..< 30 { engine.step() }
        #expect(engine.swarm.count == after, "a stopped source kept pouring")

        engine.emitters[0].isRunning = true
        for _ in 0 ..< 30 { engine.step() }
        #expect(engine.swarm.count > after, "starting it again did nothing")
    }

    @Test("A source keeps pouring after the finger is lifted")
    func sourcesArePersistent() {
        // Everything a source is good for — a waterfall that keeps falling, a chimney that keeps smoking,
        // two jets aimed at each other — needs it to stay where it was put.
        let engine = field()
        engine.emitterTemplate.rate = 60
        engine.addEmitter(atX: 200, y: 100)
        #expect(engine.emitters.count == 1)
        for _ in 0 ..< 120 { engine.step() }
        #expect(engine.swarm.count > 50)
        #expect(engine.emitters.count == 1, "the source should still be there")
    }

    // MARK: - What it pours

    @Test("Direction and spread decide where the bodies go")
    func directionAndSpreadWork() {
        func averageDirection(direction: Double, spread: Double) -> (x: Double, y: Double) {
            let engine = field()
            engine.emitterTemplate.rate = 600
            engine.emitterTemplate.direction = direction
            engine.emitterTemplate.spread = spread
            engine.emitterTemplate.speed = 5
            engine.emitterTemplate.speedVariation = 0
            engine.addEmitter(atX: 200, y: 350)
            engine.step()
            var totalX = 0.0
            var totalY = 0.0
            for index in 0 ..< engine.swarm.count {
                totalX += Double(engine.swarm.velocities[index * 2])
                totalY += Double(engine.swarm.velocities[index * 2 + 1])
            }
            let count = Double(max(1, engine.swarm.count))
            return (totalX / count, totalY / count)
        }

        // A quarter turn is downward, because the world's vertical axis grows downward.
        let down = averageDirection(direction: 1.5707963267948966, spread: 0)
        #expect(down.y > 4, "pointing down gave \(down.y)")
        #expect(abs(down.x) < 0.5)

        let right = averageDirection(direction: 0, spread: 0)
        #expect(right.x > 4, "pointing right gave \(right.x)")

        // A wide fan still averages the same way but with far less agreement between bodies.
        func agreement(spread: Double) -> Double {
            let engine = field()
            engine.emitterTemplate.rate = 600
            engine.emitterTemplate.direction = 1.5707963267948966
            engine.emitterTemplate.spread = spread
            engine.emitterTemplate.speed = 5
            engine.emitterTemplate.speedVariation = 0
            engine.addEmitter(atX: 200, y: 350)
            engine.step()
            var totalY = 0.0
            for index in 0 ..< engine.swarm.count {
                totalY += Double(engine.swarm.velocities[index * 2 + 1])
            }
            return totalY / Double(max(1, engine.swarm.count))
        }
        #expect(agreement(spread: 1.2) < agreement(spread: 0.05), "a wide fan should agree less")
    }

    @Test("Speed and its variation both bite")
    func speedWorks() {
        func speeds(speed: Double, variation: Double) -> (slowest: Double, fastest: Double) {
            let engine = field()
            engine.emitterTemplate.rate = 600
            engine.emitterTemplate.speed = speed
            engine.emitterTemplate.speedVariation = variation
            engine.addEmitter(atX: 200, y: 350)
            engine.step()
            var slowest = Double.infinity
            var fastest = 0.0
            for index in 0 ..< engine.swarm.count {
                let vx = Double(engine.swarm.velocities[index * 2])
                let vy = Double(engine.swarm.velocities[index * 2 + 1])
                let speed = (vx * vx + vy * vy).squareRoot()
                slowest = min(slowest, speed)
                fastest = max(fastest, speed)
            }
            return (slowest, fastest)
        }

        let steady = speeds(speed: 6, variation: 0)
        #expect(abs(steady.fastest - steady.slowest) < 0.1, "no variation should mean one speed")
        #expect(abs(steady.fastest - 6) < 0.2)

        let varied = speeds(speed: 6, variation: 0.8)
        #expect(varied.fastest - varied.slowest > 3, "variation should spread the speeds out")
    }

    @Test("A source can pour heavy bodies, and light ones")
    func weightIsPoured() {
        let engine = field()
        engine.emitterTemplate.rate = 600
        engine.emitterTemplate.weight = 4
        engine.emitterTemplate.weightVariation = 0
        engine.addEmitter(atX: 200, y: 350)
        engine.step()
        #expect(engine.swarm.count > 5)
        for index in 0 ..< engine.swarm.count {
            #expect(abs(Double(engine.swarm.masses[index]) - 4) < 0.01)
        }
    }

    @Test("A source can pour bodies that expire")
    func lifespanIsPoured() {
        let engine = field()
        engine.emitterTemplate.rate = 120
        engine.emitterTemplate.lifespan = 30
        engine.addEmitter(atX: 200, y: 350)

        for _ in 0 ..< 30 { engine.step() }
        let atPeak = engine.swarm.count
        #expect(atPeak > 20, "found \(atPeak)")

        // Beyond the lifespan the count settles rather than climbing: bodies expire as fast as they arrive.
        for _ in 0 ..< 90 { engine.step() }
        let settled = engine.swarm.count
        #expect(settled < atPeak * 3, "the count ran away to \(settled) from \(atPeak)")
        #expect(settled > 10, "and everything expired at \(settled)")
    }

    @Test("A fixed hue gives one colour, and no hue gives many")
    func hueIsPoured() {
        func colours(hue: Double) -> Int {
            let engine = field()
            engine.emitterTemplate.rate = 600
            engine.emitterTemplate.hue = hue
            engine.addEmitter(atX: 200, y: 350)
            engine.step()
            var seen = Set<UInt32>()
            for index in 0 ..< engine.swarm.count { seen.insert(engine.swarm.colors[index]) }
            return seen.count
        }
        #expect(colours(hue: 200) == 1, "a fixed hue should give exactly one colour")
        #expect(colours(hue: -1) > 3, "no hue should give a mixture")
    }

    // MARK: - Limits and safety

    @Test("There is a limit on how many sources there can be")
    func sourcesAreLimited() {
        let engine = field()
        for index in 0 ..< (ParticleEngine.emitterLimit + 6) {
            engine.addEmitter(atX: Double(index) * 10 + 10, y: 100)
        }
        #expect(engine.emitters.count == ParticleEngine.emitterLimit)
    }

    @Test("Sources stop when the field is full, and do not burst when room appears")
    func sourcesRespectTheLimit() {
        // A source that saved up what it was owed while full would dump all of it the moment a body expired,
        // which reads as a stutter rather than as a steady pour.
        let engine = ParticleEngine(width: 400, height: 700, seed: 3)
        engine.setMaxParticles(1_000)
        engine.gravityY = 0
        engine.collisionsEnabled = false
        engine.emitterTemplate.rate = 3_000
        engine.addEmitter(atX: 200, y: 100)

        for _ in 0 ..< 120 { engine.step() }
        #expect(engine.bodyCount <= 1_000, "poured \(engine.bodyCount) past a limit of 1,000")
        #expect(engine.emitters[0].owed < 2, "it saved up \(engine.emitters[0].owed) while full")
    }

    @Test("Removing and clearing sources works")
    func sourcesCanBeRemoved() {
        let engine = field()
        engine.addEmitter(atX: 100, y: 100)
        engine.addEmitter(atX: 200, y: 100)
        engine.addEmitter(atX: 300, y: 100)
        engine.removeEmitter(at: 1)
        #expect(engine.emitters.count == 2)
        engine.removeEmitter(at: 99)
        engine.removeEmitter(at: -1)
        #expect(engine.emitters.count == 2)
        engine.clearEmitters()
        #expect(engine.emitters.isEmpty)
    }

    @Test("Clearing the field removes the sources")
    func clearingRemovesSources() {
        let engine = field()
        engine.addEmitter(atX: 200, y: 100)
        engine.clear()
        #expect(engine.emitters.isEmpty)
    }

    @Test("Nonsense numbers on a source cannot break the field")
    func sourcesAreSanitized() {
        let engine = field()
        engine.emitterTemplate = ParticleEmitter(
            atFractionX: .nan, atFractionY: .nan, direction: .nan, rate: .nan, spread: .nan,
            speed: .nan, speedVariation: .nan, lifespan: .nan, weight: .nan,
            weightVariation: .nan, hue: .nan
        )
        engine.addEmitter(atX: 200, y: 100)
        for _ in 0 ..< 30 { engine.step() }
        for index in 0 ..< engine.swarm.count {
            #expect(Double(engine.swarm.positions[index * 2]).isFinite)
            #expect(Double(engine.swarm.velocities[index * 2]).isFinite)
            #expect(Double(engine.swarm.masses[index]) > 0)
        }
    }

    @Test("A source's direction is described in words")
    func directionsAreReadable() {
        // A list of sources reading "1.57 rad" tells nobody anything, and telling one source from another at
        // a glance is the whole reason for the list.
        #expect(ParticleEmitter.compass(0) == "right")
        #expect(ParticleEmitter.compass(1.5707963267948966) == "down")
        #expect(ParticleEmitter.compass(3.141592653589793) == "left")
        #expect(ParticleEmitter.compass(-1.5707963267948966) == "up")
        #expect(ParticleEmitter.compass(.nan) == "—")
        #expect(ParticleEmitter(atFractionX: 0.5, atFractionY: 0.5, rate: 90).summary.contains("90/s"))
    }

    // MARK: - Weight and lifetime in the crowd

    @Test("A crowd of equal weights behaves exactly as it did before weights existed")
    func equalWeightsChangeNothing() {
        // The arithmetic is arranged for this on purpose — at equal weights the share works out to a half
        // each and the bounce factor to one, which is what the crowd did before. It is what lets the recorded
        // comparison against the reference implementation stay exact.
        let engine = ParticleEngine(width: 400, height: 700, seed: 9)
        engine.setMaxParticles(40_000)
        engine.collisionsEnabled = true
        engine.spawnBatch(count: 5_000, color: PackedColor(r: 255, g: 255, b: 255))
        for index in 0 ..< engine.swarm.count {
            #expect(Double(engine.swarm.masses[index]) == 1, "a fresh body should weigh one")
            #expect(Double(engine.swarm.lives[index]) < 0, "and live forever")
        }
        #expect(!engine.swarm.hasMortalBodies)
    }

    @Test("A heavy body is shoved about less than a light one")
    func weightAffectsContact() {
        // Placed directly rather than spawned, because a small batch goes to the object list and this is
        // about the crowd.
        func displacement(ownWeight: Double) -> Double {
            let engine = ParticleEngine(width: 400, height: 700, seed: 9)
            engine.setMaxParticles(40_000)
            engine.collisionsEnabled = true
            engine.gravityX = 0
            engine.gravityY = 0
            // Left automatic. The contact size can never exceed the width of the search squares — a body
            // reaching beyond them would have neighbours the search never looks at — and with two bodies the
            // squares are four pixels across, so asking for twelve gets under four anyway.
            var rng = Mulberry32(seed: 1)
            engine.swarm.spawn(
                count: 2, width: 400, height: 700, color: 0xFFFF_FFFF, budget: 40_000, rng: &rng
            )
            // Overlapping, so the contact pass has to push them apart.
            engine.swarm.positions[0] = 200
            engine.swarm.positions[1] = 350
            engine.swarm.positions[2] = 202
            engine.swarm.positions[3] = 350
            for pair in 0 ..< 4 { engine.swarm.velocities[pair] = 0 }
            engine.swarm.setMass(ownWeight, at: 0)
            engine.swarm.setMass(1, at: 1)
            engine.step()
            return abs(Double(engine.swarm.positions[0]) - 200)
        }

        let heavy = displacement(ownWeight: 10)
        let light = displacement(ownWeight: 1)
        #expect(heavy < light * 0.5, "heavy moved \(heavy), light moved \(light)")
    }

    @Test("Heavy bodies pull harder than light ones")
    func weightAffectsGravity() {
        // And the body being pulled does not enter into it, which is why heavy and light fall alike.
        func pullFelt(otherWeight: Double) -> Double {
            let engine = ParticleEngine(width: 400, height: 700, seed: 1)
            engine.setMaxParticles(40_000)
            engine.nbodyEnabled = true
            engine.gravityY = 0
            engine.collisionsEnabled = false
            var rng = Mulberry32(seed: 1)
            engine.swarm.spawn(
                count: 2, width: 400, height: 700, color: 0xFFFF_FFFF, budget: 40_000, rng: &rng
            )
            engine.swarm.positions[0] = 100
            engine.swarm.positions[1] = 350
            engine.swarm.positions[2] = 300
            engine.swarm.positions[3] = 350
            engine.swarm.velocities[0] = 0
            engine.swarm.velocities[1] = 0
            engine.swarm.velocities[2] = 0
            engine.swarm.velocities[3] = 0
            engine.swarm.setMass(1, at: 0)
            engine.swarm.setMass(otherWeight, at: 1)
            engine.step()
            return abs(Double(engine.swarm.velocities[0]))
        }
        #expect(pullFelt(otherWeight: 8) > pullFelt(otherWeight: 1) * 4)
    }

    @Test("A body with a lifetime expires and is removed")
    func lifetimesExpire() {
        let engine = ParticleEngine(width: 400, height: 700, seed: 1)
        engine.setMaxParticles(40_000)
        var rng = Mulberry32(seed: 1)
        engine.swarm.spawn(
            count: 10, width: 400, height: 700, color: 0xFFFF_FFFF, budget: 40_000, rng: &rng
        )
        engine.swarm.setLife(20, at: 0)
        engine.swarm.setLife(40, at: 1)
        #expect(engine.swarm.hasMortalBodies)
        #expect(engine.swarm.count == 10)

        for _ in 0 ..< 25 { engine.step() }
        #expect(engine.swarm.count == 9, "the first should have gone")

        for _ in 0 ..< 25 { engine.step() }
        #expect(engine.swarm.count == 8, "and then the second")
        #expect(!engine.swarm.hasMortalBodies, "with nothing mortal left, the ageing pass should stop")
    }

    @Test("How faded a body is follows how much life it has left")
    func fadeFollowsLife() {
        let swarm = Swarm()
        var rng = Mulberry32(seed: 1)
        swarm.spawn(count: 3, width: 400, height: 700, color: 0xFFFF_FFFF, budget: 100, rng: &rng)
        #expect(swarm.fade(at: 0) == 1, "a body that never expires is fully solid")

        swarm.setLife(100, at: 1)
        #expect(swarm.fade(at: 1) == 1)
        swarm.age(by: 75)
        #expect(abs(swarm.fade(at: 1) - 0.25) < 0.01, "found \(swarm.fade(at: 1))")
    }

    @Test("Vanish works for the crowd now, instead of quietly bouncing")
    func vanishWorksForTheCrowd() {
        // It used to fall back to bouncing, because there was no per-body lifetime and a body left outside
        // the world would never come back. The code admitted it in a comment; the interface did not.
        let engine = ParticleEngine(width: 400, height: 700, seed: 1)
        engine.setMaxParticles(40_000)
        engine.boundaryMode = .void
        engine.gravityY = 2
        engine.collisionsEnabled = false
        engine.spawnBatch(count: 6_000, color: PackedColor(r: 255, g: 255, b: 255))
        let before = engine.swarm.count
        #expect(before > 0)

        for _ in 0 ..< 200 { engine.step() }
        #expect(engine.swarm.count < before / 2, "\(engine.swarm.count) of \(before) are still here")
    }

    @Test("Bouncing and wrapping still keep every body")
    func otherEdgesKeepEverything() {
        for mode in [ParticleBoundaryMode.bounce, .wrap] {
            let engine = ParticleEngine(width: 400, height: 700, seed: 1)
            engine.setMaxParticles(40_000)
            engine.boundaryMode = mode
            engine.gravityY = 2
            engine.collisionsEnabled = false
            engine.spawnBatch(count: 6_000, color: PackedColor(r: 255, g: 255, b: 255))
            let before = engine.swarm.count
            for _ in 0 ..< 200 { engine.step() }
            #expect(engine.swarm.count == before, "\(mode.rawValue) lost bodies")
        }
    }

    @Test("Weight and lifetime come back with a saved scene")
    func weightAndLifetimeSurviveASave() throws {
        let source = ParticleEngine(width: 400, height: 700, seed: 3)
        source.setMaxParticles(40_000)
        var rng = Mulberry32(seed: 1)
        source.swarm.spawn(
            count: 20, width: 400, height: 700, color: 0xFFFF_FFFF, budget: 40_000, rng: &rng
        )
        source.swarm.setMass(5.5, at: 3)
        source.swarm.setLife(42, at: 4)

        let bytes = try JSONEncoder().encode(source.captureState())
        let state = try JSONDecoder().decode(ParticleState.self, from: bytes)
        let loaded = ParticleEngine(width: 400, height: 700, seed: 9)
        loaded.setMaxParticles(40_000)
        #expect(loaded.apply(state))

        #expect(abs(Double(loaded.swarm.masses[3]) - 5.5) < 0.01)
        #expect(abs(Double(loaded.swarm.lives[4]) - 42) < 0.01)
        #expect(loaded.swarm.hasMortalBodies)
    }

    @Test("A crowd that is all ordinary is not saved with a list of ones")
    func plainCrowdsSaveCompactly() {
        // Four megabytes a save file at a million bodies, all of them the number one.
        let engine = ParticleEngine(width: 400, height: 700, seed: 3)
        engine.setMaxParticles(40_000)
        engine.spawnBatch(count: 5_000, color: PackedColor(r: 255, g: 255, b: 255))
        let snapshot = engine.swarm.snapshot()
        #expect(snapshot.masses.isEmpty, "weights were written for a crowd that has none")
        #expect(snapshot.lives.isEmpty, "lifetimes were written for a crowd that has none")
    }

    @Test("Sources survive being written down")
    func emittersRoundTrip() throws {
        let emitter = ParticleEmitter(
            atFractionX: 0.3, atFractionY: 0.8, direction: 2.1, rate: 240, spread: 0.9,
            speed: 7, speedVariation: 0.3, lifespan: 90, weight: 2.5,
            weightVariation: 0.2, hue: 40, isRunning: false
        )
        let bytes = try JSONEncoder().encode([emitter])
        #expect(try JSONDecoder().decode([ParticleEmitter].self, from: bytes) == [emitter])
    }

    @Test("Sources come back with a saved scene")
    func emittersSurviveASave() throws {
        let source = ParticleEngine(width: 400, height: 700, seed: 3)
        source.emitterTemplate.rate = 300
        source.emitterTemplate.hue = 120
        source.addEmitter(atX: 120, y: 90, direction: 0.4)
        source.addParticle(x: 10, y: 20, velocityX: 0, velocityY: 0, radius: 2, charge: 0)

        let bytes = try JSONEncoder().encode(source.captureState())
        let state = try JSONDecoder().decode(ParticleState.self, from: bytes)
        let loaded = ParticleEngine(width: 400, height: 700, seed: 9)
        #expect(loaded.apply(state))
        #expect(loaded.emitters.count == 1)
        #expect(abs((loaded.emitters.first?.rate ?? 0) - 300) < 0.01)
        #expect(abs((loaded.emitters.first?.hue ?? 0) - 120) < 0.01)
    }
}
