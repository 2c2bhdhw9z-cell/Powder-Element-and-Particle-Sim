import Testing

@testable import CrucibleCore

/// What the arrangements are meant to do, checked directly.
///
/// These replace two recorded comparisons that were retired because the reference's scenes did not do what
/// they were named for (see `ParticleGoldenTests.retired`), and they check the things that people saw go
/// wrong on the phone: scenes that behaved differently depending on what had been chosen before, shapes that
/// slid to the floor within a second, a storm that struck once, and bodies added to a galaxy that ignored it.
@Suite("Arrangements")
struct ParticleArrangementTests {
    /// A phone-sized field, and a small one of the size the reference was written for.
    static let sizes: [(width: Double, height: Double)] = [(1_320, 2_868), (400, 700)]

    private func field(_ size: (width: Double, height: Double) = (400, 700), seed: UInt32 = 11) -> ParticleEngine {
        let engine = ParticleEngine(width: size.width, height: size.height, seed: seed)
        engine.setMaxParticles(400_000)
        return engine
    }

    private static let sceneIDs = ParticleArrangement.scenes.map(\.id).filter { $0 != "text" }

    // MARK: - The catalogue

    @Test("Every arrangement has a name, a description and a unique identifier")
    func catalogueIsComplete() {
        let ids = ParticleArrangement.all.map(\.id)
        #expect(Set(ids).count == ids.count, "an identifier is used twice")
        for entry in ParticleArrangement.all {
            #expect(!entry.name.isEmpty && !entry.about.isEmpty, "\(entry.id) is missing words")
            if entry.kind == .scene, entry.joining != .none {
                #expect(!entry.joinDescription.isEmpty, "\(entry.id) does not say what joining does")
            }
        }
        #expect(ParticleArrangement.named("burst")?.kind == .addition)
        #expect(ParticleArrangement.named("galaxy")?.kind == .scene)
    }

    @Test("Every scene lays itself out, at a phone's size and at a small one")
    func everySceneLoads() {
        for size in Self.sizes {
            for id in Self.sceneIDs {
                let engine = field(size)
                #expect(engine.loadArrangement(id), "\(id) is not known to the engine")
                #expect(engine.arrangement == id, "\(id) did not record itself as the arrangement")
                #expect(engine.bodyCount > 20, "\(id) placed only \(engine.bodyCount) at \(size)")
                for _ in 0 ..< 30 { engine.step() }
                #expect(engine.swarm.corruptCount() == 0, "\(id) produced unusable numbers")
                let finite = engine.particles.allSatisfy { $0.isFinite }
                #expect(finite, "\(id) produced unusable numbers")
            }
        }
    }

    @Test("A burst adds to the arrangement rather than replacing it")
    func burstIsAnAddition() {
        let engine = field()
        engine.loadArrangement("galaxy")
        let before = engine.bodyCount
        engine.loadArrangement("burst")
        #expect(engine.arrangement == "galaxy")
        #expect(engine.bodyCount > before)
    }

    @Test("Clearing ends the arrangement, and undo brings it back")
    func clearingAndUndo() {
        let engine = field()
        engine.loadArrangement("sunflower")
        engine.clear()
        #expect(engine.arrangement == nil)
        #expect(engine.undo())
        #expect(engine.arrangement == "sunflower")
        #expect(engine.swarm.count > 1_000)
    }

    @Test("A scene is one undo step, not two")
    func oneUndoPerScene() {
        let engine = field()
        engine.loadArrangement("galaxy")
        let galaxyBodies = engine.bodyCount
        engine.loadArrangement("mandala")
        #expect(engine.undo())
        #expect(engine.arrangement == "galaxy")
        #expect(engine.bodyCount == galaxyBodies)
    }

    // MARK: - Every scene sets its own world

    @Test("A scene comes out the same whatever was chosen before it")
    func scenesDoNotInheritTheLastOne() {
        for id in Self.sceneIDs {
            let fresh = field(seed: 5)
            fresh.loadArrangement(id)

            let used = field(seed: 5)
            // Something that leaves the world as unlike the default as possible: upward gravity, wind, and
            // collisions switched on.
            used.loadArrangement("fire")
            used.gravityX = 0.4
            used.flowEnabled = true
            used.collisionsEnabled = true
            used.rng = Mulberry32(seed: 5)
            used.loadArrangement(id)

            #expect(fresh.gravityX == used.gravityX, "\(id) kept the previous sideways gravity")
            #expect(fresh.gravityY == used.gravityY, "\(id) kept the previous gravity")
            #expect(fresh.collisionsEnabled == used.collisionsEnabled, "\(id) kept the previous collisions")
            #expect(fresh.flowEnabled == used.flowEnabled, "\(id) kept the previous wind")
            #expect(fresh.bodyCount == used.bodyCount, "\(id) came out differently after another scene")
        }
    }

    @Test("A recording left playing does not overwrite the scene")
    func timelineIsPausedByAScene() {
        let engine = field()
        engine.timeline = ParticleTimeline(keyframes: [
            ParticleKeyframe(at: 0, values: [.gravityY: 0.9]),
            ParticleKeyframe(at: 2, values: [.gravityY: 0.9]),
        ])
        engine.playhead = ParticlePlayhead(isPlaying: true)
        engine.loadArrangement("sunflower")
        engine.step()
        #expect(engine.gravityY == 0, "the recording overwrote the sunflower's gravity")
    }

    // MARK: - Shapes hold

    /// The fraction of the crowd lying along the floor.
    private func onTheFloor(_ engine: ParticleEngine) -> Double {
        guard engine.swarm.count > 0 else { return 0 }
        var low = 0
        for index in 0 ..< engine.swarm.count
        where Double(engine.swarm.positions[index * 2 + 1]) > engine.height * 0.97 {
            low += 1
        }
        return Double(low) / Double(engine.swarm.count)
    }

    @Test("No shape slides to the floor", arguments: [
        "sunflower", "mandala", "snowflakes", "sierpinski", "ring", "tornado", "aurora", "supernova", "nbody",
        "galaxy", "lightning", "fireworks",
    ])
    func shapesStayUp(id: String) {
        for size in Self.sizes {
            let engine = field(size)
            engine.loadArrangement(id)
            for _ in 0 ..< 600 { engine.step() }
            #expect(onTheFloor(engine) < 0.05, "\(id): \(Int(onTheFloor(engine) * 100))% on the floor at \(size)")
        }
    }

    @Test("A held shape reforms after a finger has pushed it about")
    func heldShapesReform() {
        let engine = field()
        engine.loadArrangement("sierpinski")
        func spread() -> Double {
            var total = 0.0
            for index in 0 ..< engine.swarm.count {
                guard let home = engine.swarm.home(at: index) else { continue }
                let place = home.point
                let dx = Double(engine.swarm.positions[index * 2]) - place.x
                let dy = Double(engine.swarm.positions[index * 2 + 1]) - place.y
                total += (dx * dx + dy * dy).squareRoot()
            }
            return total / Double(max(1, engine.swarm.count))
        }
        engine.mouseMode = .repel
        engine.mouseForceMultiplier = 6
        for _ in 0 ..< 60 { engine.step(mouseX: 200, mouseY: 350, mouseActive: true) }
        let pushed = spread()
        for _ in 0 ..< 600 { engine.step() }
        let settled = spread()
        #expect(pushed > 2, "the finger did not dent the shape at all (\(pushed))")
        #expect(settled < pushed * 0.3, "pushed \(pushed), still \(settled) out after ten seconds")
    }

    @Test("A turning shape turns")
    func shapesTurn() {
        let engine = field()
        engine.loadArrangement("sunflower")
        let startX = Double(engine.swarm.positions[engine.swarm.count / 2 * 2])
        let startY = Double(engine.swarm.positions[engine.swarm.count / 2 * 2 + 1])
        for _ in 0 ..< 300 { engine.step() }
        let endX = Double(engine.swarm.positions[engine.swarm.count / 2 * 2])
        let endY = Double(engine.swarm.positions[engine.swarm.count / 2 * 2 + 1])
        let moved = ((endX - startX) * (endX - startX) + (endY - startY) * (endY - startY)).squareRoot()
        #expect(moved > 5, "a seed moved only \(moved) in five seconds")
    }

    // MARK: - Scenes that keep going

    @Test("A storm strikes again, and each bolt fades")
    func lightningKeepsStriking() {
        let engine = field()
        engine.loadArrangement("lightning")
        let first = engine.swarm.count
        for _ in 0 ..< 70 { engine.step() }
        #expect(engine.swarm.count < first / 2, "the first bolt did not fade: \(engine.swarm.count) of \(first)")
        for _ in 0 ..< 100 { engine.step() }
        var seen = 0
        for _ in 0 ..< 400 {
            engine.step()
            seen = max(seen, engine.swarm.count)
        }
        #expect(seen > 300, "the storm did not strike again")
    }

    @Test("Fireworks keep going up, and old sparks go")
    func fireworksKeepLaunching() {
        let engine = field()
        engine.loadArrangement("fireworks")
        for _ in 0 ..< 900 { engine.step() }
        #expect(engine.swarm.count > 200, "the display stopped: \(engine.swarm.count) sparks left")
        #expect(engine.swarm.count < 2_800, "old sparks never went")
    }

    // MARK: - Rebuilt scenes

    @Test("Pour is a liquid that pours and settles")
    func pourIsLiquid() {
        let engine = field()
        engine.loadArrangement("pour")
        #expect(engine.fluidEnabled)
        #expect(engine.particles.isEmpty, "the liquid is in the object list, which the fluid does not reach")
        #expect(engine.emitters.count == 1)
        for _ in 0 ..< 400 { engine.step() }
        var nearFloor = 0
        for index in 0 ..< engine.swarm.count where Double(engine.swarm.positions[index * 2 + 1]) > 600 {
            nearFloor += 1
        }
        #expect(nearFloor > 300, "only \(nearFloor) bodies reached the bottom of the tank")
        // Spread across the floor as a liquid does, rather than stacked in a column where it landed.
        var minX = Double.infinity
        var maxX = -Double.infinity
        for index in 0 ..< engine.swarm.count where Double(engine.swarm.positions[index * 2 + 1]) > 650 {
            let x = Double(engine.swarm.positions[index * 2])
            minX = min(minX, x)
            maxX = max(maxX, x)
        }
        #expect(maxX - minX > 150, "the liquid did not spread: \(maxX - minX) wide")
    }

    @Test("N-body pulls, and its disc holds together")
    func nbodyPulls() {
        let engine = field()
        engine.loadArrangement("nbody")
        #expect(engine.nbodyEnabled)
        #expect(engine.particles.isEmpty, "the bodies are in the object list, which the pull does not reach")
        var weights = Set<Int>()
        for index in 0 ..< engine.swarm.count { weights.insert(Int(engine.swarm.masses[index].rounded())) }
        #expect(weights.count >= 3, "every body weighs the same")

        func medianDistance() -> Double {
            var distances: [Double] = []
            for index in 0 ..< engine.swarm.count {
                let dx = Double(engine.swarm.positions[index * 2]) - 200
                let dy = Double(engine.swarm.positions[index * 2 + 1]) - 350
                distances.append((dx * dx + dy * dy).squareRoot())
            }
            distances.sort()
            return distances[distances.count / 2]
        }
        let before = medianDistance()
        for _ in 0 ..< 600 { engine.step() }
        let after = medianDistance()
        #expect(after > before * 0.4 && after < before * 1.8, "the disc went from \(before) to \(after)")
    }

    // MARK: - Joining

    @Test("Bodies joining a galaxy orbit it; bodies merely added do not")
    func joiningAGalaxy() {
        func distances(_ engine: ParticleEngine) -> (inside: Int, total: Int) {
            let hole = engine.particles.first { $0.kind == .blackhole }!
            var inside = 0
            for index in 0 ..< engine.swarm.count {
                let dx = Double(engine.swarm.positions[index * 2]) - hole.x
                let dy = Double(engine.swarm.positions[index * 2 + 1]) - hole.y
                if (dx * dx + dy * dy).squareRoot() < engine.patternSpan * 0.5 { inside += 1 }
            }
            return (inside, engine.swarm.count)
        }

        let joined = field((1_320, 2_868))
        joined.loadArrangement("galaxy")
        let added = joined.spawnJoining(count: 10_000)
        #expect(added == 10_000)
        #expect(joined.swarm.role(at: 0).contains(.orbits))
        for _ in 0 ..< 600 { joined.step() }
        let held = distances(joined)
        #expect(Double(held.inside) > Double(held.total) * 0.85, "only \(held.inside) of \(held.total) stayed in orbit")
    }

    @Test("Bodies joining a sunflower take places in it")
    func joiningAShape() {
        let engine = field()
        engine.loadArrangement("sunflower")
        let before = engine.swarm.count
        engine.spawnJoining(count: 2_000)
        #expect(engine.swarm.count == before + 2_000)
        #expect(engine.swarm.home(at: engine.swarm.count - 1) != nil, "a joined seed holds no place")
        #expect(engine.arrangement == "sunflower")
        #expect(engine.undo())
        #expect(engine.swarm.count == before)
    }

    @Test("Joining a rope hangs another rope")
    func joiningAStructure() {
        let engine = field()
        engine.loadArrangement("rope")
        let springs = engine.springs.count
        let added = engine.spawnJoining(count: 10_000)
        #expect(added == 32)
        #expect(engine.springs.count == springs * 2)
    }

    @Test("Joining the object arrangements stops at a ceiling")
    func joiningObjectsIsCapped() {
        let engine = field()
        engine.loadArrangement("flare")
        engine.spawnJoining(count: 100_000)
        #expect(engine.particles.count <= ParticleEngine.joinedObjectLimit)
        #expect(engine.particles.count > 1_000)
    }

    @Test("Joining a flock stops at the number that flock")
    func joiningAFlockRespectsItsLimit() {
        let engine = field()
        engine.loadArrangement("flock")
        engine.spawnJoining(count: 100_000)
        #expect(engine.particles.count <= engine.flockSettings.sanitized.limit)
    }

    @Test("With nothing to join, adding scatters as it always did")
    func joiningNothingScatters() {
        let engine = field()
        engine.clear()
        let added = engine.spawnJoining(count: 5_000)
        #expect(added == 5_000)
        #expect(engine.swarm.role(at: 0).isEmpty)
    }

    @Test("A source in a galaxy pours a stream that orbits, when joining")
    func sourcesJoin() {
        let engine = field()
        engine.loadArrangement("galaxy")
        engine.joinsArrangement = true
        engine.addEmitter(atX: 50, y: 50, direction: 0)
        for _ in 0 ..< 30 { engine.step() }
        #expect(engine.swarm.count > 0)
        #expect(engine.swarm.role(at: 0).contains(.orbits))
    }

    // MARK: - The crowd and black holes

    @Test("A well dropped into a crowd pulls the crowd")
    func crowdFeelsAWell() {
        let engine = field()
        engine.loadArrangement("swarm")
        engine.gravityY = 0
        engine.placeWell(x: 200, y: 350)
        func meanDistance() -> Double {
            var total = 0.0
            for index in 0 ..< engine.swarm.count {
                let dx = Double(engine.swarm.positions[index * 2]) - 200
                let dy = Double(engine.swarm.positions[index * 2 + 1]) - 350
                total += (dx * dx + dy * dy).squareRoot()
            }
            return total / Double(engine.swarm.count)
        }
        let before = meanDistance()
        for _ in 0 ..< 60 { engine.step() }
        #expect(meanDistance() < before * 0.95, "the crowd ignored the well")
    }

    // MARK: - Saving

    @Test("A saved arrangement comes back as itself, roles, places and fading intact")
    func savingKeepsTheArrangement() {
        let engine = field()
        engine.loadArrangement("fire")
        for _ in 0 ..< 20 { engine.step() }
        let state = engine.captureState()

        let loaded = field(seed: 99)
        loaded.loadArrangement("mandala")
        #expect(loaded.apply(state))
        #expect(loaded.arrangement == "fire")
        #expect(loaded.emitters.count == engine.emitters.count)

        let shape = field()
        shape.loadArrangement("ring")
        let ringState = shape.captureState()
        let reloaded = field(seed: 3)
        #expect(reloaded.apply(ringState))
        #expect(reloaded.swarm.home(at: 0) == shape.swarm.home(at: 0))
    }

    @Test("Undo brings back walls, sources and painted wind along with the bodies")
    func undoRestoresTheDrawnWorld() {
        let engine = field()
        engine.addWall(fromFractionX: 0.1, y: 0.5, toFractionX: 0.9, y: 0.5)
        engine.addEmitter(atX: 100, y: 100)
        engine.paintCurrent(atX: 200, y: 200, directionX: 1, directionY: 0)
        engine.clear()
        #expect(engine.walls.isEmpty && engine.emitters.isEmpty && engine.current.isEmpty)
        #expect(engine.undo())
        #expect(engine.walls.count == 1)
        #expect(engine.emitters.count == 1)
        #expect(!engine.current.isEmpty)
    }
}
