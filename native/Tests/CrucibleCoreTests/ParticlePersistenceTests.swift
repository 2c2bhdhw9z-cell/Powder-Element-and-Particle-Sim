import Foundation
import Testing

@testable import CrucibleCore

/// Saving and loading the particle field.
///
/// The thing under test is mostly *losslessness*. The web reference saved a body's position,
/// velocity, size and colour and little else; everything omitted was re-rolled at random or
/// re-derived from a guess on the way back in. The damage was easy to miss and impossible to
/// undo — a cloth came back as loose beads, and a scene built around attraction came back
/// scrambled. Each test below pins one of those.
@Suite("Particle saving and loading")
struct ParticlePersistenceTests {
    @Test("A cloth comes back as a cloth, not a handful of beads")
    func springsSurvive() throws {
        let source = ParticleEngine(width: 400, height: 300, seed: 7)
        source.spawnCloth(cols: 8, rows: 6)
        let springCount = source.springs.count
        #expect(springCount > 0)

        let target = ParticleEngine(width: 100, height: 100, seed: 1)
        #expect(target.apply(source.captureState()))

        // Springs were left out of the format entirely, so three of the presets — cloth,
        // rope and blob — silently became dust on the first save and reload.
        #expect(target.springs.count == springCount)
        #expect(target.springs == source.springs)
        for spring in target.springs {
            #expect(spring.a >= 0 && spring.a < target.particles.count)
            #expect(spring.b >= 0 && spring.b < target.particles.count)
        }
    }

    @Test("Every property of every body survives")
    func bodiesSurviveIntact() {
        let source = ParticleEngine(width: 500, height: 400, seed: 11)
        // One of everything the format has to carry.
        source.spawnGalaxy(count: 40)
        source.spawnQuantumLattice(rows: 3, cols: 4)
        source.spawnDnaHelix(count: 6)
        source.spawnSolarFlare(count: 8)

        let target = ParticleEngine(width: 50, height: 50, seed: 1)
        #expect(target.apply(source.captureState()))
        #expect(target.particles.count == source.particles.count)

        for (i, expected) in source.particles.enumerated() {
            let actual = target.particles[i]
            #expect(actual.x == expected.x, "body \(i) moved")
            #expect(actual.y == expected.y)
            #expect(actual.velocityX == expected.velocityX)
            #expect(actual.velocityY == expected.velocityY)
            #expect(actual.radius == expected.radius, "body \(i) changed size")
            #expect(actual.mass == expected.mass)
            // Charge was dropped and re-rolled at random, so an arrangement built around
            // attraction came back scrambled.
            #expect(actual.charge == expected.charge, "body \(i) lost its charge")
            #expect(actual.color == expected.color)
            #expect(actual.kind == expected.kind)
            // Being pinned was re-derived from the kind alone, so a pinned ordinary body
            // came back loose.
            #expect(actual.isFixed == expected.isFixed, "body \(i) lost its pin")
            #expect(actual.ignoresGravity == expected.ignoresGravity)
            // Dropped, so anything built to recycle stopped recycling.
            #expect(actual.lifespan == expected.lifespan, "body \(i) lost its lifespan")
            #expect(actual.maxLife == expected.maxLife)
            #expect(actual.originX == expected.originX, "body \(i) lost its origin")
            #expect(actual.originY == expected.originY)
            // Dropped, so a lattice stopped holding its shape and a helix stopped waving.
            #expect(actual.latticeBound == expected.latticeBound)
            #expect(actual.helixStrand == expected.helixStrand)
        }
    }

    @Test("A reloaded field behaves identically from then on")
    func reloadedFieldRunsTheSame() {
        // The real test of losslessness: not that the numbers match, but that the physics
        // carries on the same way. Anything the format dropped shows up here as divergence.
        let source = ParticleEngine(width: 400, height: 300, seed: 21)
        source.spawnCloth(cols: 6, rows: 5)
        for _ in 0 ..< 20 { source.step() }

        let target = ParticleEngine(width: 400, height: 300, seed: 21)
        #expect(target.apply(source.captureState()))

        for _ in 0 ..< 40 {
            source.step()
            target.step()
        }
        #expect(target.particles.count == source.particles.count)
        for (i, expected) in source.particles.enumerated() {
            #expect(target.particles[i].x == expected.x, "body \(i) drifted apart")
            #expect(target.particles[i].y == expected.y)
        }
    }

    @Test("The swarm survives, positions and colours together")
    func swarmSurvives() {
        let source = ParticleEngine(width: 300, height: 300, seed: 5)
        source.spawnBatch(count: 6000)
        let count = source.swarm.count
        #expect(count > 0)

        let target = ParticleEngine(width: 300, height: 300, seed: 1)
        #expect(target.apply(source.captureState()))
        #expect(target.swarm.count == count)
        for i in 0 ..< count {
            let pair = i * 2
            #expect(target.swarm.positions[pair] == source.swarm.positions[pair], "swarm \(i) moved")
            #expect(target.swarm.positions[pair + 1] == source.swarm.positions[pair + 1])
            #expect(target.swarm.colors[i] == source.swarm.colors[i], "swarm \(i) changed colour")
        }
    }

    @Test("A field survives a round trip through JSON")
    func roundTripsThroughJSON() throws {
        let source = ParticleEngine(width: 400, height: 300, seed: 33)
        source.spawnRope(length: 12)
        let data = try JSONEncoder().encode(source.captureState())
        let decoded = try JSONDecoder().decode(ParticleState.self, from: data)

        let target = ParticleEngine(width: 80, height: 80, seed: 1)
        #expect(target.apply(decoded))
        #expect(target.particles.count == source.particles.count)
        #expect(target.springs == source.springs)
        #expect(target.width == source.width)
    }

    @Test("Settings that are not usable numbers are refused")
    func badSettingsAreRefused() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 7)
        engine.spawnBurst(count: 10)
        var state = engine.captureState()
        state.damping = .nan
        state.gravityY = .infinity
        state.maxSpeed = .nan
        let originalDamping = engine.damping

        #expect(engine.apply(state))
        // Assigned straight through, a single unusable damping figure turned every velocity
        // into nonsense on the next step — and since the forces couple every body to every
        // other, the whole field was ruined one frame later with nothing to point at.
        #expect(engine.damping == originalDamping)
        #expect(engine.gravityY.isFinite)
        #expect(engine.maxSpeed.isFinite)
        engine.step()
        let allUsable = engine.particles.allSatisfy { $0.isFinite }
        #expect(allUsable, "the field should still be usable")
    }

    @Test("A field with no size is refused outright")
    func badSizeIsRefused() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 7)
        engine.spawnBurst(count: 10)
        let before = engine.particles.count

        var state = engine.captureState()
        state.width = 0
        #expect(!engine.apply(state))
        state.width = .nan
        #expect(!engine.apply(state))
        #expect(engine.particles.count == before)
        #expect(engine.width == 400)
    }

    @Test("The saved canvas size is applied")
    func savedSizeIsApplied() {
        let source = ParticleEngine(width: 1920, height: 1080, seed: 7)
        source.spawnBurst(count: 20)

        let target = ParticleEngine(width: 320, height: 240, seed: 1)
        #expect(target.apply(source.captureState()))
        // Exported and then ignored, so a scene captured on a large display dropped most of
        // its bodies outside a smaller field, where they piled against the walls.
        #expect(target.width == 1920)
        #expect(target.height == 1080)
    }

    @Test("A spring naming a body that is not there is dropped")
    func impossibleSpringsAreDropped() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 7)
        engine.spawnBurst(count: 4)
        var state = engine.captureState()
        state.springs = [
            SpringRecord(a: 0, b: 1, rest: 10, k: 0.2), // Fine.
            SpringRecord(a: 0, b: 99, rest: 10, k: 0.2), // Past the end.
            SpringRecord(a: 2, b: 2, rest: 10, k: 0.2), // Joined to itself.
            SpringRecord(a: -1, b: 1, rest: 10, k: 0.2), // Nonsense.
        ]
        #expect(engine.apply(state))
        // A spring pointing past the end waits to be dereferenced; one naming the wrong pair
        // cannot be detected at all once the frame loop is running. Both are rejected here,
        // where the information to judge them still exists.
        #expect(engine.springs.count == 1)
        #expect(engine.springs.first == Spring(a: 0, b: 1, rest: 10, k: 0.2))
    }

    @Test("Loading over an existing field leaves nothing of it behind")
    func loadingReplacesEverything() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 7)
        engine.spawnCloth(cols: 6, rows: 5)
        engine.spawnBatch(count: 5000)
        #expect(!engine.springs.isEmpty)
        #expect(engine.swarm.count > 0)

        let empty = ParticleEngine(width: 400, height: 300, seed: 1)
        #expect(engine.apply(empty.captureState()))
        // Springs from the previous scene would otherwise join whichever bodies now sit at
        // their indices, with a rest length measured for a different pair.
        #expect(engine.particles.isEmpty)
        #expect(engine.springs.isEmpty)
        #expect(engine.swarm.count == 0)
    }

    @Test("Bodies beyond the save limit are left out, with their springs")
    func saveLimitIsRespected() {
        let engine = ParticleEngine(width: 4000, height: 3000, seed: 7)
        _ = engine.setMaxParticles(20_000)
        engine.spawnCloth(cols: 20, rows: 20)
        let state = engine.captureState()
        #expect(state.particles.count <= ParticleEngine.saveBodyLimit)
        // Every saved spring has to name a body that was actually written out, or reloading
        // produces exactly the stale index this whole area exists to prevent.
        for spring in state.springs ?? [] {
            #expect(spring.a < state.particles.count)
            #expect(spring.b < state.particles.count)
        }
    }

    @Test("A colour ramp comes back exactly, including a hand-made gradient")
    func paletteSurvivesASave() throws {
        let source = ParticleEngine(width: 400, height: 300, seed: 3)
        source.colorMode = .velocity
        source.paletteEnabled = true
        source.palette = ParticlePaletteSpec(
            palette: .aurora,
            stops: [
                ParticleGradientStop(position: 0, color: PackedColor(r: 12, g: 200, b: 90)),
                ParticleGradientStop(position: 0.45, color: PackedColor(r: 250, g: 240, b: 30)),
                ParticleGradientStop(position: 1, color: PackedColor(r: 90, g: 20, b: 200)),
            ],
            tint: PackedColor(r: 240, g: 220, b: 255)
        )
        source.addParticle(x: 10, y: 20, velocityX: 1, velocityY: 2, radius: 2, charge: 0)

        let bytes = try JSONEncoder().encode(source.captureState())
        let state = try JSONDecoder().decode(ParticleState.self, from: bytes)
        let loaded = ParticleEngine(width: 100, height: 100, seed: 9)
        #expect(loaded.apply(state))

        #expect(loaded.colorMode == .velocity)
        #expect(loaded.paletteEnabled)
        #expect(loaded.palette == source.palette, "the gradient must come back, not a nearest ramp")
        #expect(loaded.palette.stops.count == 3)
    }

    @Test("A file written before ramps existed loads with ramps off")
    func olderFilesStillLoad() throws {
        // The three new fields are optional for this reason. A saved scene from an earlier build has
        // no opinion about ramps, and the right reading of no opinion is the original look.
        let source = ParticleEngine(width: 400, height: 300, seed: 3)
        source.addParticle(x: 10, y: 20, velocityX: 0, velocityY: 0, radius: 2, charge: 0)
        var state = source.captureState()
        state.colorMode = nil
        state.paletteEnabled = nil
        state.palette = nil

        let loaded = ParticleEngine(width: 100, height: 100, seed: 9)
        loaded.colorMode = .lifespan
        loaded.paletteEnabled = true
        #expect(loaded.apply(state))
        #expect(!loaded.paletteEnabled, "no opinion in the file means the original look")
        #expect(loaded.colorMode == .lifespan, "an absent mode leaves the current one alone")
    }

    @Test("A colour mode this build does not know about is ignored, not guessed at")
    func unknownColourModeIsIgnored() {
        let source = ParticleEngine(width: 400, height: 300, seed: 3)
        source.addParticle(x: 10, y: 20, velocityX: 0, velocityY: 0, radius: 2, charge: 0)
        var state = source.captureState()
        state.colorMode = "something-from-a-later-build"

        let loaded = ParticleEngine(width: 100, height: 100, seed: 9)
        loaded.colorMode = .rainbow
        #expect(loaded.apply(state))
        #expect(loaded.colorMode == .rainbow, "a setting that cannot be expressed is lost, not applied")
    }
}
