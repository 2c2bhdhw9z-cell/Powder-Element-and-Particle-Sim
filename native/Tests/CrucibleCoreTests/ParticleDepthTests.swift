import Foundation
import Testing

@testable import CrucibleCore

/// The field in 3D, checked directly.
///
/// The app draws it and the finger works it, and neither can be built where these run — so everything the
/// app relies on is checked here: that the switch rebuilds and undoes, that every arrangement has a form in
/// the box and stays in it, that each force works through depth, that a finger acts on whatever is drawn under
/// it at any depth, and that the view's arithmetic puts a finger's line through what is drawn beneath it.
@Suite("The field in 3D")
struct ParticleDepthTests {
    static let screen = (width: 1_320.0, height: 2_868.0)

    private func phone(depth: Bool = true, seed: UInt32 = 5) -> ParticleEngine {
        let engine = ParticleEngine(width: Self.screen.width, height: Self.screen.height, seed: seed)
        engine.setMaxParticles(400_000)
        engine.screenWidth = Self.screen.width
        engine.screenHeight = Self.screen.height
        engine.mouseRadius = 0.12 * Self.screen.height
        if depth {
            engine.setDepthEnabled(true)
            engine.clearHistory()
        }
        return engine
    }

    /// An empty box with nothing acting on it.
    private func stillBox() -> ParticleEngine {
        let engine = phone()
        engine.clear()
        engine.gravityX = 0
        engine.gravityY = 0
        engine.collisionsEnabled = false
        return engine
    }

    private func depths(_ engine: ParticleEngine) -> [Double] {
        (0 ..< engine.swarm.count).map { Double(engine.swarm.depths[$0]) } + engine.particles.map(\.z)
    }

    private func spread(_ values: [Double]) -> Double {
        guard let low = values.min(), let high = values.max() else { return 0 }
        return high - low
    }

    // MARK: - The switch

    @Test("Turning 3D on rebuilds the arrangement in depth, and one undo brings the flat one back")
    func switchingRebuildsAndUndoes() {
        let engine = phone(depth: false)
        engine.loadArrangement("galaxy")
        let flatCount = engine.bodyCount
        #expect(depths(engine).allSatisfy { $0 == 0 })

        #expect(engine.setDepthEnabled(true))
        #expect(engine.depthEnabled)
        #expect(engine.arrangement == "galaxy")
        #expect(engine.worldDepth > 0)
        #expect(spread(depths(engine)) > engine.patternSpan * 0.5, "the 3D galaxy has no depth to it")

        #expect(engine.undo())
        #expect(!engine.depthEnabled, "undo left the field in 3D")
        #expect(engine.arrangement == "galaxy")
        #expect(engine.bodyCount == flatCount)
        #expect(depths(engine).allSatisfy { $0 == 0 }, "undo brought back bodies with depth on a flat field")
        #expect(!engine.undo() || engine.arrangement != "galaxy" || !engine.depthEnabled, "the switch took two undos")
    }

    @Test("A loose crowd is lifted into the box, and laid flat again")
    func liftingAndFlattening() {
        let engine = phone(depth: false)
        engine.clear()
        engine.spawnBatch(count: 20_000)
        #expect(engine.setDepthEnabled(true))
        #expect(engine.arrangement == nil)
        #expect(spread(depths(engine)) > engine.halfDepth * 0.5, "the crowd was not spread through the box")
        #expect(engine.swarm.count == 20_000)
        #expect(engine.setDepthEnabled(false))
        #expect(depths(engine).allSatisfy { $0 == 0 })
        #expect(!engine.swarm.hasDepth)
        #expect(!engine.setDepthEnabled(false), "switching to what it already is should change nothing")
    }

    @Test("Something that only exists in 3D turns 3D on, and undo turns it back off")
    func depthOnlyTurnsDepthOn() {
        let engine = phone(depth: false)
        engine.loadArrangement("galaxy")
        #expect(engine.loadArrangement("globe"))
        #expect(engine.depthEnabled)
        #expect(engine.arrangement == "globe")
        #expect(engine.undo())
        #expect(!engine.depthEnabled)
        #expect(engine.arrangement == "galaxy")
    }

    @Test("Turning 3D off with something that only exists in 3D showing clears it, and undo brings it back")
    func depthOnlyClearsWhenFlattened() {
        let engine = phone()
        engine.loadArrangement("globe")
        let count = engine.bodyCount
        #expect(engine.setDepthEnabled(false))
        #expect(engine.arrangement == nil)
        #expect(engine.bodyCount == 0)
        #expect(engine.undo())
        #expect(engine.depthEnabled)
        #expect(engine.arrangement == "globe")
        #expect(engine.bodyCount == count)
    }

    @Test("A flat field never moves anything into depth")
    func flatStaysFlat() {
        for id in ["galaxy", "sunflower", "tornado", "cloth", "swarm", "fire", "helix"] {
            let engine = phone(depth: false)
            engine.loadArrangement(id)
            engine.mouseMode = .vortex
            for moment in 0 ..< 120 {
                engine.step(mouseX: engine.width * 0.5, mouseY: engine.height * 0.5, mouseActive: moment < 30)
            }
            #expect(depths(engine).allSatisfy { $0 == 0 }, "\(id) moved into depth on a flat field")
            #expect(engine.worldDepth == 0)
        }
    }

    // MARK: - Every arrangement

    static let sceneIDs = ParticleArrangement.scenes.map(\.id).filter { $0 != "text" }

    private func inside(_ engine: ParticleEngine, margin: Double = 2) -> Bool {
        let half = engine.halfDepth + margin
        for index in 0 ..< engine.swarm.count {
            let x = Double(engine.swarm.positions[index * 2])
            let y = Double(engine.swarm.positions[index * 2 + 1])
            let z = Double(engine.swarm.depths[index])
            guard x >= -margin, x <= engine.width + margin, y >= -margin, y <= engine.height + margin, abs(z) <= half else {
                return false
            }
        }
        for body in engine.particles {
            guard body.x >= -margin - body.radius, body.x <= engine.width + margin + body.radius,
                  body.y >= -margin - body.radius, body.y <= engine.height + margin + body.radius,
                  abs(body.z) <= half + body.radius else { return false }
        }
        return true
    }

    @Test("Every arrangement has a form in 3D that uses the depth, and stays inside the box", arguments: sceneIDs)
    func everyArrangementInDepth(id: String) {
        for size in [(Self.screen.width, Self.screen.height), (400.0, 700.0)] {
            let engine = ParticleEngine(width: size.0, height: size.1, seed: 9)
            engine.setMaxParticles(400_000)
            engine.setDepthEnabled(true)
            #expect(engine.loadArrangement(id))
            #expect(engine.depthEnabled)
            #expect(engine.arrangement == id)
            #expect(engine.bodyCount > 20, "\(id) placed only \(engine.bodyCount) in 3D at \(size)")
            #expect(inside(engine), "\(id) was laid out outside the box at \(size)")
            let laidOut = spread(depths(engine))
            for _ in 0 ..< 180 { engine.step() }
            // A burst begins at a point, so its depth is in where it goes rather than where it starts.
            let deepest = max(laidOut, spread(depths(engine)))
            #expect(deepest > engine.patternSpan * 0.02, "\(id) has no depth to it at \(size)")
            #expect(engine.swarm.corruptCount() == 0, "\(id) produced unusable numbers in 3D")
            #expect(engine.particles.allSatisfy { $0.isFinite }, "\(id) produced unusable numbers in 3D")
            #expect(inside(engine, margin: 12), "\(id) left the box at \(size)")
        }
    }

    @Test("Every tool acts on every arrangement in 3D", arguments: sceneIDs)
    func everyToolInDepth(id: String) throws {
        let warmed = phone()
        warmed.loadArrangement(id)
        for _ in 0 ..< 60 { warmed.step() }
        var waited = 0
        while warmed.bodyCount < 200, waited < 300 {
            warmed.step()
            waited += 1
        }
        let state = warmed.captureState()
        // Looked at from the resting angle, with perspective, with a finger on one of the bodies there.
        var camera = ParticleCamera()
        camera.look(from: .angled)
        let aim: (x: Double, y: Double, z: Double)
        if warmed.swarm.count > 0 {
            let index = warmed.swarm.count / 2
            aim = (Double(warmed.swarm.positions[index * 2]), Double(warmed.swarm.positions[index * 2 + 1]), Double(warmed.swarm.depths[index]))
        } else {
            let body = warmed.particles.filter { !$0.isFixed }[warmed.particles.filter { !$0.isFixed }.count / 2]
            aim = (body.x, body.y, body.z)
        }
        let middle = camera.projectInDepth(
            x: aim.x, y: aim.y, z: aim.z,
            worldWidth: warmed.width, worldHeight: warmed.height, worldDepth: warmed.worldDepth,
            viewWidth: warmed.width, viewHeight: warmed.height
        )
        let ray = camera.fingerRay(
            screenX: (middle.x + 1) * 0.5 * warmed.width,
            screenY: (1 - middle.y) * 0.5 * warmed.height,
            worldWidth: warmed.width, worldHeight: warmed.height, worldDepth: warmed.worldDepth,
            viewWidth: warmed.width, viewHeight: warmed.height
        )
        for mode in [ParticleMouseMode.attract, .repel, .vortex, .freeze, .painter] {
            let control = phone()
            let touched = phone()
            #expect(control.apply(state) && touched.apply(state))
            #expect(touched.depthEnabled)
            touched.fingerRay = ray
            touched.mouseMode = mode
            control.mouseMode = mode
            for _ in 0 ..< 10 {
                control.step()
                touched.step(mouseX: 0, mouseY: 0, mouseActive: true)
            }
            try #require(control.swarm.count == touched.swarm.count && control.particles.count == touched.particles.count)
            if mode == .freeze {
                // Freezing something already nearly still moves nothing anybody could see, so what is checked is
                // that what is under the finger is stopped dead, far more of it than when it is left alone.
                func stillUnderTheFinger(_ engine: ParticleEngine) -> Int {
                    var still = 0
                    for index in 0 ..< engine.swarm.count {
                        let x = Double(engine.swarm.positions[index * 2])
                        let y = Double(engine.swarm.positions[index * 2 + 1])
                        let z = Double(engine.swarm.depths[index])
                        guard ray.reaches(x: x, y: y, z: z, within: engine.mouseRadius) else { continue }
                        if engine.swarm.velocities[index * 2] == 0, engine.swarm.velocities[index * 2 + 1] == 0,
                           engine.swarm.depthVelocities[index] == 0 { still += 1 }
                    }
                    return still
                }
                // The individual bodies by whether they moved over one more moment: their list keeps its order,
                // and a spring's pull on a frozen body is added after it has been held still, so is not movement.
                func objectsHeld(_ engine: ParticleEngine, step: () -> Void) -> Int {
                    let before = engine.particles
                    step()
                    guard engine.particles.count == before.count else { return 0 }
                    var held = 0
                    for (was, now) in zip(before, engine.particles) where !was.isFixed
                        && ray.reaches(x: was.x, y: was.y, z: was.z, within: engine.mouseRadius)
                        && was.x == now.x && was.y == now.y && was.z == now.z {
                        held += 1
                    }
                    return held
                }
                let heldTouched = objectsHeld(touched) { touched.step(mouseX: 0, mouseY: 0, mouseActive: true) }
                let heldControl = objectsHeld(control) { control.step() }
                let stopped = stillUnderTheFinger(touched) + heldTouched
                let left = stillUnderTheFinger(control) + heldControl
                #expect(stopped > left, "\(id): freeze left \(stopped) still, \(left) were still untouched")
                #expect(stopped >= 3, "\(id): freeze stopped only \(stopped) bodies in 3D")
                continue
            }
            var changed = 0
            for index in 0 ..< touched.swarm.count {
                let moved = abs(touched.swarm.positions[index * 2] - control.swarm.positions[index * 2])
                    + abs(touched.swarm.depths[index] - control.swarm.depths[index])
                if moved > 0.5 || touched.swarm.colors[index] != control.swarm.colors[index] { changed += 1 }
            }
            for (a, b) in zip(touched.particles, control.particles)
            where abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z) > 0.5 || a.color != b.color {
                changed += 1
            }
            #expect(changed >= 3, "\(id): \(mode) changed only \(changed) bodies in 3D")
        }
    }

    // MARK: - Saving

    @Test("Saving and loading keeps the depth, the box and the switch")
    func savingKeepsDepth() throws {
        let engine = phone()
        engine.depthRatio = 1.4
        engine.loadArrangement("galaxy")
        engine.spawnBatch(count: 5_000)
        for _ in 0 ..< 20 { engine.step() }
        let bytes = try JSONEncoder().encode(engine.captureState())
        let loaded = phone(depth: false, seed: 1)
        #expect(loaded.apply(try JSONDecoder().decode(ParticleState.self, from: bytes)))
        #expect(loaded.depthEnabled)
        #expect(loaded.depthRatio == 1.4)
        #expect(loaded.swarm.count == engine.swarm.count)
        for index in stride(from: 0, to: engine.swarm.count, by: 97) {
            #expect(loaded.swarm.depths[index] == engine.swarm.depths[index])
            #expect(loaded.swarm.depthVelocities[index] == engine.swarm.depthVelocities[index])
        }
        for (saved, back) in zip(engine.particles, loaded.particles) {
            #expect(abs(saved.z - back.z) < 1e-9 && abs(saved.velocityZ - back.velocityZ) < 1e-9)
        }
    }

    @Test("A field saved flat loads flat, even into a field that is in 3D")
    func flatFilesLoadFlat() throws {
        let flat = phone(depth: false)
        flat.loadArrangement("sunflower")
        let state = flat.captureState()
        #expect(state.depthEnabled == nil)
        let loaded = phone()
        #expect(loaded.apply(state))
        #expect(!loaded.depthEnabled)
        #expect(depths(loaded).allSatisfy { $0 == 0 })
    }

    @Test("Undo keeps each body's depth")
    func undoKeepsDepth() {
        let engine = phone()
        engine.loadArrangement("sunflower")
        let before = depths(engine)
        engine.pushUndo()
        for _ in 0 ..< 60 { engine.step(mouseX: engine.width / 2, mouseY: engine.height / 2, mouseActive: true) }
        #expect(engine.undo())
        #expect(depths(engine) == before)
    }

    // MARK: - Forces in depth

    @Test("A black hole pulls through depth")
    func blackHolesPullInDepth() {
        let engine = stillBox()
        engine.addParticle(
            x: engine.width / 2, y: engine.height / 2, velocityX: 0, velocityY: 0, radius: 14, mass: 80,
            isFixed: true, ignoresGravity: true, kind: .blackhole
        )
        engine.swarm.append(x: engine.width / 2, y: engine.height / 2, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF, budget: 100, z: 300)
        engine.addParticle(x: engine.width / 2, y: engine.height / 2, velocityX: 0, velocityY: 0, radius: 2, charge: 0, z: -300)
        for _ in 0 ..< 20 { engine.step() }
        #expect(Double(engine.swarm.depths[0]) < 290, "the crowd did not feel the hole through depth")
        #expect(engine.particles[1].z > -290, "a body did not feel the hole through depth")
    }

    @Test("Down is still down in 3D")
    func gravityPointsDown() {
        let engine = stillBox()
        engine.gravityY = 0.3
        engine.swarm.append(x: 400, y: 400, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF, budget: 100, z: 120)
        for _ in 0 ..< 30 { engine.step() }
        #expect(Double(engine.swarm.positions[1]) > 450)
        #expect(abs(Double(engine.swarm.depths[0]) - 120) < 1e-3)
    }

    @Test("The front and back of the box are walls like the sides", arguments: [ParticleBoundaryMode.bounce, .wrap, .void])
    func frontAndBack(boundary: ParticleBoundaryMode) {
        let engine = stillBox()
        engine.boundaryMode = boundary
        engine.swarm.append(x: 400, y: 400, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF, budget: 100, z: engine.halfDepth - 20, velocityZ: 9)
        engine.addParticle(x: 400, y: 400, velocityX: 0, velocityY: 0, radius: 2, charge: 0, z: -engine.halfDepth + 20, velocityZ: -9)
        for _ in 0 ..< 10 { engine.step() }
        switch boundary {
        case .bounce:
            #expect(engine.swarm.depthVelocities[0] < 0, "the crowd did not bounce off the back")
            #expect(engine.particles[0].velocityZ > 0, "a body did not bounce off the front")
            #expect(inside(engine))
        case .wrap:
            #expect(Double(engine.swarm.depths[0]) < 0, "the crowd did not come round to the front")
            #expect(engine.particles[0].z > 0, "a body did not come round to the back")
        case .void:
            #expect(engine.swarm.count == 0)
            #expect(engine.particles.isEmpty)
        }
    }

    @Test("Bodies only collide when they are really close, not when one is drawn over the other")
    func collisionsInDepth() {
        let engine = stillBox()
        engine.collisionsEnabled = true
        engine.swarm.append(x: 500, y: 500, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF, budget: 100, z: -200)
        engine.swarm.append(x: 500, y: 500, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF, budget: 100, z: 200)
        engine.swarm.append(x: 700, y: 700, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF, budget: 100, z: 0)
        engine.swarm.append(x: 701, y: 700, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF, budget: 100, z: 1)
        engine.step()
        #expect(engine.swarm.positions[0] == 500 && engine.swarm.positions[2] == 500, "bodies far apart in depth collided")
        let dx = Double(engine.swarm.positions[6] - engine.swarm.positions[4])
        let dz = Double(engine.swarm.depths[3] - engine.swarm.depths[2])
        #expect((dx * dx + dz * dz).squareRoot() > 2, "bodies together were not pushed apart")
    }

    @Test("Springs pull through depth")
    func springsInDepth() {
        let engine = stillBox()
        let a = engine.addParticle(x: 500, y: 500, velocityX: 0, velocityY: 0, radius: 2, charge: 0, z: -100)
        let b = engine.addParticle(x: 500, y: 500, velocityX: 0, velocityY: 0, radius: 2, charge: 0, z: 100)
        #expect(a == 0 && b == 1)
        engine.addSpring(a: 0, b: 1, rest: 50, k: 0.1)
        for _ in 0 ..< 10 { engine.step() }
        #expect(engine.particles[1].z - engine.particles[0].z < 190)
    }

    @Test("The liquid in 3D pours, spreads through the box, and never blows up")
    func liquidInDepth() {
        let engine = phone()
        engine.loadArrangement("pour")
        #expect(engine.fluidEnabled)
        for _ in 0 ..< 400 { engine.step() }
        #expect(engine.swarm.corruptCount() == 0)
        var low: [Double] = []
        for index in 0 ..< engine.swarm.count where Double(engine.swarm.positions[index * 2 + 1]) > engine.height * 0.9 {
            low.append(Double(engine.swarm.depths[index]))
        }
        #expect(low.count > 200, "only \(low.count) bodies reached the floor")
        #expect(spread(low) > engine.patternSpan * 0.1, "the liquid did not spread through depth: \(spread(low))")
    }

    @Test("Pull between bodies draws a cloud together in 3D, exactly or in lumps")
    func pullBetweenBodiesInDepth() {
        for count in [400, 3_000] {
            let engine = stillBox()
            engine.nbodyEnabled = true
            for k in 0 ..< count {
                let p = engine.goldenPoint(k, of: count)
                let out = 200.0 * Double(k % 7 + 3) / 9
                engine.swarm.append(
                    x: engine.width / 2 + p.x * out, y: engine.height / 2 + p.y * out,
                    velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF, budget: 1_000_000, z: p.z * out
                )
            }
            func meanDistance() -> Double {
                var total = 0.0
                for index in 0 ..< engine.swarm.count {
                    let dx = Double(engine.swarm.positions[index * 2]) - engine.width / 2
                    let dy = Double(engine.swarm.positions[index * 2 + 1]) - engine.height / 2
                    let dz = Double(engine.swarm.depths[index])
                    total += (dx * dx + dy * dy + dz * dz).squareRoot()
                }
                return total / Double(engine.swarm.count)
            }
            let before = meanDistance()
            for _ in 0 ..< 40 { engine.step() }
            #expect(engine.swarm.corruptCount() == 0)
            #expect(meanDistance() < before * 0.98, "\(count): the cloud did not draw together")
        }
    }

    @Test("The wind blows through depth as well as across")
    func windInDepth() {
        let engine = stillBox()
        engine.spawnBatch(count: 5_000)
        engine.flowEnabled = true
        for index in 0 ..< engine.swarm.count { engine.swarm.setDepth(Double(engine.swarm.depths[index]), velocity: 0, at: index) }
        for _ in 0 ..< 10 { engine.step() }
        let moving = (0 ..< engine.swarm.count).filter { abs(engine.swarm.depthVelocities[$0]) > 0.01 }.count
        #expect(moving > 2_500, "only \(moving) bodies were blown through depth")
    }

    @Test("The swirl turns things round the upright through the middle")
    func swirlInDepth() {
        let engine = stillBox()
        engine.vortexForce = 40
        engine.addParticle(x: engine.width / 2 + 200, y: 500, velocityX: 0, velocityY: 0, radius: 2, charge: 0, z: 0)
        for _ in 0 ..< 40 { engine.step() }
        #expect(abs(engine.particles[0].z) > 1, "the swirl did not carry the body round through depth")
        #expect(abs(engine.particles[0].y - 500) < 1e-9)
    }

    @Test("The helix in 3D is two strands winding round each other")
    func helixWinds() {
        let engine = phone()
        engine.loadArrangement("helix")
        for _ in 0 ..< 120 { engine.step() }
        var radii: [Double] = []
        for body in engine.particles {
            let dy = body.y - engine.height / 2
            radii.append((dy * dy + body.z * body.z).squareRoot())
        }
        let mean = radii.reduce(0, +) / Double(radii.count)
        let expected = 50 * engine.sceneScale
        #expect(abs(mean - expected) < expected * 0.35, "strands are \(mean) from the middle, not \(expected)")
    }

    @Test("A tornado in 3D goes round the funnel")
    func tornadoTurns() {
        let engine = phone()
        engine.loadArrangement("tornado")
        let index = engine.swarm.count / 2
        let startZ = Double(engine.swarm.depths[index])
        let startX = Double(engine.swarm.positions[index * 2])
        for _ in 0 ..< 30 { engine.step() }
        let moved = abs(Double(engine.swarm.depths[index]) - startZ) + abs(Double(engine.swarm.positions[index * 2]) - startX)
        #expect(moved > 5, "a body in the funnel moved only \(moved)")
    }

    @Test("The ocean's waves roll")
    func oceanRolls() {
        let engine = phone()
        engine.loadArrangement("ocean")
        let heights = (0 ..< engine.swarm.count).map { Double(engine.swarm.positions[$0 * 2 + 1]) }
        #expect(spread(heights) > engine.patternSpan * 0.02, "the sea is flat")
        let start = Double(engine.swarm.positions[1])
        var furthest = 0.0
        for _ in 0 ..< 90 {
            engine.step()
            furthest = max(furthest, abs(Double(engine.swarm.positions[1]) - start))
        }
        #expect(furthest > engine.patternSpan * 0.01, "a body on the sea rose and fell only \(furthest)")
    }

    @Test("Strange attractors hold their shape and never blow up", arguments: ["lorenz", "aizawa", "thomas", "halvorsen"])
    func attractorsHold(id: String) {
        let engine = phone()
        engine.loadArrangement(id)
        for _ in 0 ..< 600 { engine.step() }
        #expect(engine.swarm.corruptCount() == 0)
        #expect(inside(engine, margin: 12))
        let xs = (0 ..< engine.swarm.count).map { Double(engine.swarm.positions[$0 * 2]) }
        let ys = (0 ..< engine.swarm.count).map { Double(engine.swarm.positions[$0 * 2 + 1]) }
        #expect(spread(xs) > engine.patternSpan * 0.2 && spread(ys) > engine.patternSpan * 0.2, "\(id) collapsed")
        #expect(spread(depths(engine)) > engine.patternSpan * 0.1, "\(id) went flat")
    }

    @Test("Warp stars stream toward the viewer and come round again")
    func warpStreams() {
        let engine = phone()
        engine.loadArrangement("warp")
        let count = engine.swarm.count
        for _ in 0 ..< 400 { engine.step() }
        #expect(engine.swarm.count == count)
        #expect((0 ..< count).allSatisfy { engine.swarm.depthVelocities[$0] < 0 })
        #expect(inside(engine, margin: 12))
        #expect(spread(depths(engine)) > engine.halfDepth, "the stars bunched up")
    }

    @Test("Snow stays inside the globe")
    func snowStaysInTheGlass() {
        let engine = phone()
        engine.loadArrangement("snowglobe")
        engine.gravityY = 0.4
        for _ in 0 ..< 400 { engine.step() }
        let glass = engine.snowGlobeRadius
        for index in 0 ..< engine.swarm.count {
            let dx = Double(engine.swarm.positions[index * 2]) - engine.width / 2
            let dy = Double(engine.swarm.positions[index * 2 + 1]) - engine.height / 2
            let dz = Double(engine.swarm.depths[index])
            #expect((dx * dx + dy * dy + dz * dz).squareRoot() < glass * 1.08, "snow got out of the globe")
        }
    }

    // MARK: - Adding in depth

    @Test("Bodies joining a 3D galaxy go into level orbits and stay in the disc")
    func joiningInDepth() {
        let engine = phone()
        engine.loadArrangement("galaxy")
        #expect(engine.spawnJoining(count: 8_000) == 8_000)
        #expect(spread((0 ..< engine.swarm.count).map { Double(engine.swarm.depths[$0]) }) > engine.patternSpan * 0.5)
        for _ in 0 ..< 400 { engine.step() }
        let hole = engine.particles.first { $0.kind == .blackhole }!
        var held = 0
        for index in 0 ..< engine.swarm.count {
            let dx = Double(engine.swarm.positions[index * 2]) - hole.x
            let dy = Double(engine.swarm.positions[index * 2 + 1]) - hole.y
            let dz = Double(engine.swarm.depths[index]) - hole.z
            if (dx * dx + dz * dz).squareRoot() < engine.patternSpan * 0.5, abs(dy) < engine.patternSpan * 0.12 { held += 1 }
        }
        #expect(Double(held) > Double(engine.swarm.count) * 0.8, "only \(held) of \(engine.swarm.count) stayed in the disc")
    }

    @Test("Bodies added to an empty box fill a ball rather than a disc")
    func scatteringFillsABall() {
        let engine = phone()
        engine.clear()
        engine.spawnBatch(count: 20_000)
        let xs = (0 ..< engine.swarm.count).map { Double(engine.swarm.positions[$0 * 2]) }
        #expect(spread(depths(engine)) > spread(xs) * 0.6)
        engine.spawnBatch(count: 300)
        #expect(spread(engine.particles.map(\.z)) > engine.patternSpan * 0.3)
    }

    @Test("Bodies joining a shape in 3D take a place in it at its depth")
    func joiningAShapeInDepth() {
        let engine = phone()
        engine.loadArrangement("sierpinski")
        let before = engine.swarm.count
        engine.spawnJoining(count: 2_000)
        let joined = (before ..< engine.swarm.count).compactMap { engine.swarm.home(at: $0) }
        #expect(joined.count == 2_000)
        #expect(joined.contains { $0.radius > 0 && $0.anchorZ == 0 }, "joined bodies do not turn with the pyramid")
        #expect(engine.swarm.role(at: engine.swarm.count - 1).contains(.upright))
    }

    @Test("The word in 3D has a thickness")
    func wordsAreSolid() {
        let engine = phone()
        var coverage = [Double](repeating: 0, count: 40 * 20)
        for y in 5 ..< 15 { for x in 5 ..< 35 { coverage[y * 40 + x] = 1 } }
        #expect(engine.spawnTextCloud(coverage: coverage, width: 40, height: 20, count: 2_000) > 0)
        #expect(spread(depths(engine)) > engine.patternSpan * 0.03)
        #expect(engine.depthEnabled)
    }

    // MARK: - The finger in depth

    @Test("A finger acts on everything drawn under it, at every depth")
    func fingerReachesThroughDepth() {
        let engine = stillBox()
        let x = engine.width / 2
        let y = engine.height / 2
        for z in stride(from: -engine.halfDepth + 20, through: engine.halfDepth - 20, by: 60) {
            engine.swarm.append(x: x + 80, y: y, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF, budget: 1_000, z: z)
        }
        engine.mouseMode = .attract
        engine.step(mouseX: x, mouseY: y, mouseActive: true)
        for index in 0 ..< engine.swarm.count {
            #expect(engine.swarm.velocities[index * 2] < -0.5, "the body at depth \(engine.swarm.depths[index]) was not pulled")
            #expect(abs(engine.swarm.depthVelocities[index]) < 1e-3, "the pull was not toward the finger's line")
        }
    }

    @Test("A finger at an angle acts along its line, not level with where it touched")
    func fingerFollowsItsLine() {
        let engine = stillBox()
        var camera = ParticleCamera()
        camera.look(yaw: 55, pitch: 30)
        let ray = camera.fingerRay(
            screenX: engine.width * 0.62, screenY: engine.height * 0.4,
            worldWidth: engine.width, worldHeight: engine.height, worldDepth: engine.worldDepth,
            viewWidth: engine.width, viewHeight: engine.height
        )
        // Bodies strung along the part of the line inside the box, a little to one side of it, and one far from it.
        var inBox: [(x: Double, y: Double, z: Double)] = []
        for step in 0 ..< 400 {
            let distance = ray.focusDistance * 3 * Double(step) / 400
            let point = (
                x: ray.originX + ray.directionX * distance + 30,
                y: ray.originY + ray.directionY * distance,
                z: ray.originZ + ray.directionZ * distance
            )
            if point.x > 0, point.x < engine.width, point.y > 0, point.y < engine.height, abs(point.z) < engine.halfDepth - 2 {
                inBox.append(point)
            }
        }
        var along: [Int] = []
        for k in stride(from: 0, to: inBox.count, by: max(1, inBox.count / 6)) {
            engine.swarm.append(x: inBox[k].x, y: inBox[k].y, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF, budget: 1_000, z: inBox[k].z)
            along.append(engine.swarm.count - 1)
        }
        engine.swarm.append(x: 60, y: 60, velocityX: 0, velocityY: 0, color: 0xFFFF_FFFF, budget: 1_000, z: -engine.halfDepth + 40)
        #expect(along.count >= 3)
        engine.fingerRay = ray
        engine.mouseMode = .painter
        engine.step(mouseX: 0, mouseY: 0, mouseActive: true)
        for index in along { #expect(engine.swarm.colors[index] != 0xFFFF_FFFF, "a body on the line was not painted") }
        #expect(engine.swarm.colors[engine.swarm.count - 1] == 0xFFFF_FFFF, "a body nowhere near the line was painted")
    }

    @Test("Freeze stills everything under the finger at every depth, and it stays still")
    func freezeInDepth() {
        let engine = stillBox()
        engine.gravityY = 0.3
        let x = engine.width / 2
        let y = engine.height / 2
        for z in stride(from: -400.0, through: 400, by: 100) {
            engine.swarm.append(x: x, y: y, velocityX: 3, velocityY: 0, color: 0xFFFF_FFFF, budget: 1_000, z: z, velocityZ: 2)
            engine.addParticle(x: x + 10, y: y, velocityX: 3, velocityY: 0, radius: 2, charge: 0, z: z, velocityZ: 2)
        }
        engine.mouseMode = .freeze
        for _ in 0 ..< 3 { engine.step(mouseX: x, mouseY: y, mouseActive: true) }
        let before = (0 ..< engine.swarm.count).map { (engine.swarm.positions[$0 * 2 + 1], engine.swarm.depths[$0]) }
        engine.step(mouseX: x, mouseY: y, mouseActive: true)
        for index in 0 ..< engine.swarm.count {
            #expect(engine.swarm.positions[index * 2 + 1] == before[index].0 && engine.swarm.depths[index] == before[index].1)
        }
        #expect(engine.particles.allSatisfy { $0.velocityX == 0 && $0.velocityY == 0 && $0.velocityZ == 0 })
    }

    @Test("Swirl turns bodies round the finger's line")
    func swirlRoundTheLine() {
        let engine = stillBox()
        let x = engine.width / 2
        let y = engine.height / 2
        // Seen from the front, a ring round the finger turns in the plane of the screen at every depth.
        for k in 0 ..< 12 {
            let angle = Double(k) / 12 * 2 * Double.pi
            engine.swarm.append(
                x: x + cos(angle) * 100, y: y + sin(angle) * 100, velocityX: 0, velocityY: 0,
                color: 0xFFFF_FFFF, budget: 1_000, z: Double(k % 3 - 1) * 250
            )
        }
        engine.mouseMode = .vortex
        engine.step(mouseX: x, mouseY: y, mouseActive: true)
        for index in 0 ..< engine.swarm.count {
            let dx = Double(engine.swarm.positions[index * 2]) - x
            let dy = Double(engine.swarm.positions[index * 2 + 1]) - y
            let vx = Double(engine.swarm.velocities[index * 2])
            let vy = Double(engine.swarm.velocities[index * 2 + 1])
            let across = (dx * vy - dy * vx) / (dx * dx + dy * dy).squareRoot()
            #expect(abs(across) > 0.5, "a body was not turned round the finger")
            #expect(abs(engine.swarm.depthVelocities[index]) < 1e-3)
        }
    }

    @Test("With perspective, the finger's circle takes in more the further it reaches")
    func circleWidensWithDistance() {
        let ray = ParticleFingerRay(
            originX: 0, originY: 0, originZ: -1_000, directionX: 0, directionY: 0, directionZ: 1,
            focusDistance: 1_000, widens: true
        )
        #expect(abs(ray.reach(100, at: 2_000) - 200) < 1e-9)
        #expect(abs(ray.reach(100, at: 500) - 50) < 1e-9)
        #expect(ray.reaches(x: 150, y: 0, z: 1_000, within: 100))
        #expect(!ray.reaches(x: 150, y: 0, z: 0, within: 100))
        #expect(!ray.reaches(x: 0, y: 0, z: -2_000, within: 100), "something behind the eye was reached")
        let flat = ParticleFingerRay.straightIn(x: 0, y: 0, fromDepth: -1_000)
        #expect(flat.reach(100, at: 5_000) == 100)
        #expect(abs(flat.cursor.z) < 1e-9)
    }

    // MARK: - The view in 3D

    private let world = (width: 1_320.0, height: 2_868.0, depth: 1_320.0)

    private func project(_ camera: ParticleCamera, _ x: Double, _ y: Double, _ z: Double) -> ParticleDepthProjection {
        camera.projectInDepth(
            x: x, y: y, z: z, worldWidth: world.width, worldHeight: world.height, worldDepth: world.depth,
            viewWidth: world.width, viewHeight: world.height
        )
    }

    @Test("From the front with no perspective, 3D is drawn exactly as the flat field is")
    func frontOnIsFlat() {
        var camera = ParticleCamera(zoom: 2.5, panX: 40, panY: -70)
        camera.look(yaw: 0, pitch: 0)
        camera.perspective = 0
        for (x, y) in [(10.0, 20.0), (660, 1_434), (1_300, 2_800), (400, 900)] {
            let deep = project(camera, x, y, 300)
            let flat = camera.project(
                x: x, y: y, worldWidth: world.width, worldHeight: world.height,
                viewWidth: world.width, viewHeight: world.height
            )
            #expect(abs(deep.x - flat.x) < 1e-9 && abs(deep.y - flat.y) < 1e-9)
            #expect(deep.scale == 1)
        }
    }

    @Test("A finger's line goes through what is drawn under it, from any angle")
    func fingerLineThroughWhatIsDrawn() {
        var rng = Mulberry32(seed: 42)
        for _ in 0 ..< 200 {
            var camera = ParticleCamera(zoom: 0.5 + rng.next() * 3, panX: (rng.next() - 0.5) * 300, panY: (rng.next() - 0.5) * 300)
            camera.look(yaw: (rng.next() - 0.5) * 360, pitch: (rng.next() - 0.5) * 170)
            camera.perspective = rng.next() < 0.2 ? 0 : rng.next()
            let point = (x: rng.next() * world.width, y: rng.next() * world.height, z: (rng.next() - 0.5) * world.depth)
            let drawn = project(camera, point.x, point.y, point.z)
            guard drawn.isInFront else { continue }
            let ray = camera.fingerRay(
                screenX: (drawn.x + 1) * 0.5 * world.width, screenY: (1 - drawn.y) * 0.5 * world.height,
                worldWidth: world.width, worldHeight: world.height, worldDepth: world.depth,
                viewWidth: world.width, viewHeight: world.height
            )
            let near = ray.nearest(toX: point.x, y: point.y, z: point.z)
            let gap = ((near.x - point.x) * (near.x - point.x) + (near.y - point.y) * (near.y - point.y)
                + (near.z - point.z) * (near.z - point.z)).squareRoot()
            #expect(gap < 1e-4 * world.height, "the line missed what was drawn under the finger by \(gap)")
            #expect(near.along > 0, "what was drawn is behind the eye")
            // And the place under the finger is on the plane through the middle of the box, square to the view.
            let cursor = ray.cursor
            #expect(abs(camera.viewSpace(x: cursor.x, y: cursor.y, z: cursor.z, worldWidth: world.width, worldHeight: world.height).w) < 1e-6)
        }
    }

    @Test("Turning round the box moves the near side the way the finger went, and looking from above shows the top")
    func turningDirections() {
        var camera = ParticleCamera()
        camera.look(yaw: 0, pitch: 0)
        let front = project(camera, world.width / 2, world.height / 2, -300)
        camera.orbit(byYaw: 20, pitch: 0)
        #expect(project(camera, world.width / 2, world.height / 2, -300).x > front.x)
        camera.look(yaw: 0, pitch: 30)
        let near = project(camera, world.width / 2, world.height / 2, -300)
        let far = project(camera, world.width / 2, world.height / 2, 300)
        #expect(far.y > near.y, "from above, the back of the box should be drawn higher than the front")
        #expect(far.depth > near.depth)
    }

    @Test("Perspective draws near things bigger and far things smaller")
    func perspectiveSizes() {
        var camera = ParticleCamera()
        camera.look(yaw: 0, pitch: 0)
        camera.perspective = 0.8
        let near = project(camera, 660, 1_434, -500)
        let middle = project(camera, 660, 1_434, 0)
        let far = project(camera, 660, 1_434, 500)
        #expect(near.scale > 1 && abs(middle.scale - 1) < 1e-9 && far.scale < 1)
        camera.perspective = 0
        #expect(project(camera, 660, 1_434, -500).scale == 1)
    }

    @Test("Fitting in 3D brings everything there onto the screen, from any angle")
    func fittingInDepth() {
        var rng = Mulberry32(seed: 3)
        for _ in 0 ..< 60 {
            let framing = ParticleDepthFraming(
                minX: 100 + rng.next() * 400, maxX: 800 + rng.next() * 400,
                minY: 200 + rng.next() * 800, maxY: 1_500 + rng.next() * 1_200,
                minZ: -rng.next() * 600, maxZ: rng.next() * 600, bodyCount: 1_000
            )
            var camera = ParticleCamera()
            camera.look(yaw: (rng.next() - 0.5) * 360, pitch: (rng.next() - 0.5) * 120)
            camera.growsWorldWhenZoomedOut = rng.next() < 0.5
            camera.fitInDepth(
                to: framing, worldWidth: world.width, worldHeight: world.height, worldDepth: world.depth,
                viewWidth: world.width, viewHeight: world.height
            )
            let scale = camera.worldScale
            let grown = (world.width * scale, world.height * scale, world.depth * scale)
            let shiftX = (grown.0 - world.width) * 0.5
            let shiftY = (grown.1 - world.height) * 0.5
            for corner in framing.corners {
                let placed = camera.projectInDepth(
                    x: corner.x + shiftX, y: corner.y + shiftY, z: corner.z,
                    worldWidth: grown.0, worldHeight: grown.1, worldDepth: grown.2,
                    viewWidth: world.width, viewHeight: world.height
                )
                #expect(abs(placed.x) <= 1.05 && abs(placed.y) <= 1.05, "a corner fell off the screen at \(placed)")
            }
        }
    }

    @Test("The 3D view is saved, and a camera saved before there was one reads with the resting view")
    func viewIsSaved() throws {
        var camera = ParticleCamera(autoOrbit: true)
        camera.look(yaw: 70, pitch: -30)
        camera.perspective = 0.2
        camera.fog = 0.9
        camera.showsBox = false
        camera.glows = true
        camera.spinRate = 2.5
        let bytes = try JSONEncoder().encode(camera)
        #expect(try JSONDecoder().decode(ParticleCamera.self, from: bytes) == camera)
        let old = Data(#"{"zoom":2,"panX":0,"panY":0,"yaw":0,"pitch":10,"autoOrbit":false,"autoOrbitAngle":0}"#.utf8)
        let read = try JSONDecoder().decode(ParticleCamera.self, from: old)
        #expect(read.orbitYaw == ParticleCamera.restingOrbitYaw && read.orbitPitch == ParticleCamera.restingOrbitPitch)
        #expect(read.showsBox && !read.glows && read.spinRate == 1)
    }

    @Test("Resetting goes back round the box to where 3D starts, and keeps how it looks")
    func resetInDepth() {
        var camera = ParticleCamera(zoom: 3)
        camera.look(yaw: 120, pitch: 60)
        camera.fog = 0.1
        camera.reset()
        #expect(camera.isAtRestInDepth)
        #expect(camera.fog == 0.1)
    }

    @Test("The spin speed setting sets the pace of the spin")
    func spinSpeed() {
        var slow = ParticleCamera(autoOrbit: true, spinRate: 0.5)
        var fast = ParticleCamera(autoOrbit: true, spinRate: 2)
        slow.advance(bySeconds: 0.05)
        fast.advance(bySeconds: 0.05)
        #expect(abs(fast.autoOrbitAngle - slow.autoOrbitAngle * 4) < 1e-9)
    }

    @Test("The box's depth follows the world, and its setting is kept within reason")
    func boxDepth() {
        let engine = phone()
        #expect(engine.worldDepth == Self.screen.width)
        engine.depthRatio = 9
        #expect(engine.depthRatio == ParticleEngine.depthRatioRange.upperBound)
        engine.depthRatio = .nan
        #expect(engine.depthRatio == 1)
        engine.resizeKeepingContentsCentred(width: Self.screen.width * 2, height: Self.screen.height * 2)
        #expect(engine.worldDepth == Self.screen.width * 2)
    }

    @Test("Framing in 3D finds the extent of what is there")
    func framingFindsTheBox() {
        let engine = stillBox()
        for k in 0 ..< 2_000 {
            engine.swarm.append(
                x: 300 + Double(k % 100), y: 900 + Double(k % 37), velocityX: 0, velocityY: 0,
                color: 0xFFFF_FFFF, budget: 100_000, z: -200 + Double(k % 50) * 8
            )
        }
        let framing = engine.framingInDepth()
        #expect(framing.bodyCount == 2_000)
        #expect(abs(framing.minX - 300) < 12 && abs(framing.maxX - 400) < 12)
        #expect(abs(framing.minZ + 200) < 12 && abs(framing.maxZ - 192) < 12)
    }
}
