import Foundation
import Testing

@testable import CrucibleCore

/// The slingshot, the jelly pen, recorded loops, foxes and rabbits, and sand on a drum — plus the faults they turned up.
@Suite("Slingshot, jelly, loops, foxes and the drum")
struct ParticleToysTests {
    private func field(width: Double = 400, height: Double = 700, seed: UInt32 = 3) -> ParticleEngine {
        let engine = ParticleEngine(width: width, height: height, seed: seed)
        engine.screenWidth = width
        engine.screenHeight = height
        return engine
    }

    // MARK: - Slingshot

    @Test("Pulling back throws the other way, and never faster than the limit")
    func slingshotAims() {
        let gentle = ParticleEngine.slingshotVelocity(anchorX: 100, anchorY: 100, pullX: 60, pullY: 130)
        #expect(gentle.x > 0 && gentle.y < 0, "pulled down and left, it should fly up and right")
        let hard = ParticleEngine.slingshotVelocity(anchorX: 0, anchorY: 0, pullX: -9_000, pullY: 0)
        #expect(abs(hard.x - ParticleEngine.slingshotFastest) < 1e-9)
        #expect(ParticleEngine.slingshotVelocity(anchorX: .nan, anchorY: 0, pullX: 1, pullY: 1) == (0, 0))
    }

    @Test("A thrown body goes where the dotted path said it would, round a black hole")
    func thePathIsTheFlight() {
        let engine = field()
        engine.gravityY = 0
        engine.placeWell(x: 220, y: 330)
        // Thrown across the well rather than at it, fast enough to swing round it.
        let path = engine.predictedPath(fromX: 80, y: 520, velocityX: 6.4, velocityY: 4.7, moments: 90)
        #expect(path.count == 91)
        engine.launch(fromX: 80, y: 520, velocityX: 6.4, velocityY: 4.7)
        let thrown = engine.particles.count - 1
        for moment in 1 ... 90 {
            guard moment < path.count else { break }
            engine.step()
            let body = engine.particles[thrown]
            let dx = body.x - path[moment].x
            let dy = body.y - path[moment].y
            #expect((dx * dx + dy * dy).squareRoot() < 0.01, "at moment \(moment) it was \(dx), \(dy) off the path")
            if (dx * dx + dy * dy).squareRoot() >= 0.01 { return }
        }
        // And the well really did bend it: the path is not a straight line.
        guard path.count == 91 else { return }
        let bend = abs((path[90].y - 520) - (4.7 * 90))
        #expect(bend > 20)
    }

    @Test("The path bounces off the floor with gravity, and stops at a black hole's edge")
    func thePathKnowsTheEdges() {
        let engine = field()
        let arc = engine.predictedPath(fromX: 50, y: 500, velocityX: 2, velocityY: 0, moments: 150)
        #expect(arc.allSatisfy { $0.y <= engine.height })
        let floorAt = arc.indices.max { arc[$0].y < arc[$1].y }!
        #expect(arc[floorAt].y > 680, "it never reached the floor")
        #expect(arc[floorAt...].contains { $0.y < arc[floorAt].y - 50 }, "it never came back up off the floor")

        engine.gravityY = 0
        engine.placeWell(x: 200, y: 350)
        let into = engine.predictedPath(fromX: 200, y: 450, velocityX: 0, velocityY: -4, moments: 150)
        #expect(into.count < 60, "the path went on through a black hole")
    }

    // MARK: - Jelly pen

    /// A closed outline: a rounded square with its corners cut.
    private func outline(centreX: Double, centreY: Double, size: Double) -> [ParticleFingerPoint] {
        var points: [ParticleFingerPoint] = []
        for step in 0 ..< 64 {
            let angle = Double(step) / 64 * 2 * Double.pi
            let c = cos(angle)
            let s = sin(angle)
            // A squircle: halfway between a circle and a square.
            let r = size / pow(pow(abs(c), 4) + pow(abs(s), 4), 0.25)
            points.append(ParticleFingerPoint(x: centreX + c * r, y: centreY + s * r))
        }
        return points
    }

    @Test("An outline becomes a jelly of that shape, which falls and keeps its shape")
    func jellyHoldsTogether() {
        let engine = field()
        let made = engine.makeJelly(outline: outline(centreX: 200, centreY: 200, size: 70))
        #expect(made > 40 && made <= ParticleEngine.jellyMostBodies, "\(made) bodies")
        #expect(engine.springs.count > made * 2, "too few springs to draw it as a mesh")
        #expect(engine.jellies.count == 1)
        func extent() -> (width: Double, height: Double, bottom: Double) {
            let xs = engine.particles.map(\.x)
            let ys = engine.particles.map(\.y)
            return (xs.max()! - xs.min()!, ys.max()! - ys.min()!, ys.max()!)
        }
        let before = extent()
        for _ in 0 ..< 400 { engine.step() }
        let after = extent()
        #expect(engine.particles.allSatisfy { $0.isFinite })
        #expect(after.bottom > before.bottom + 200, "it did not fall")
        #expect(after.width > before.width * 0.7 && after.width < before.width * 1.5, "it spread out flat")
        #expect(after.height > before.height * 0.5, "it collapsed")
    }

    @Test("A scribble with nothing inside it makes nothing, and drawing is reset each time")
    func scribblesAreNotJellies() throws {
        let engine = field()
        let line = (0 ..< 20).map { ParticleFingerPoint(x: 100 + Double($0) * 5, y: 300) }
        #expect(engine.makeJelly(outline: line) == 0)
        #expect(engine.particles.isEmpty)
        engine.beginJelly()
        for point in outline(centreX: 200, centreY: 300, size: 60) { engine.extendJelly(toX: point.x, y: point.y) }
        #expect(engine.jellyOutline.count > 10)
        #expect(engine.finishJelly() > 0)
        #expect(engine.jellyOutline.isEmpty)
        // Saved and reopened, it is still a jelly and not a heap of loose bodies.
        let text = try JSONEncoder().encode(engine.captureState())
        let reopened = field()
        #expect(reopened.apply(try JSONDecoder().decode(ParticleState.self, from: text)))
        #expect(reopened.jellies.count == 1)
        #expect(reopened.jellies.first?.ids.count == engine.jellies.first?.ids.count)
        // And a single undo takes the whole jelly back.
        #expect(engine.undo())
        #expect(engine.particles.isEmpty)
        #expect(engine.jellies.isEmpty)
    }

    @Test("The two new tools push nothing, and only the jelly pen draws")
    func newToolsAreNotForces() {
        #expect(!ParticleBrush.touchesBodies(.slingshot))
        #expect(!ParticleBrush.touchesBodies(.jelly))
        #expect(ParticleMouseMode.jelly.drawsIntoTheWorld)
        #expect(!ParticleMouseMode.slingshot.drawsIntoTheWorld)
    }

    // MARK: - Recorded loops

    /// Records a circle with the finger, as the app would, one moment at a time.
    private func recordCircle(_ engine: ParticleEngine, centreX: Double, centreY: Double, radius: Double, moments: Int) {
        #expect(engine.beginLoopRecording())
        for moment in 0 ..< moments {
            let angle = Double(moment) / Double(moments) * 2 * Double.pi
            engine.step(mouseX: centreX + cos(angle) * radius, mouseY: centreY + sin(angle) * radius, mouseActive: true)
        }
    }

    @Test("A recorded movement plays back on its own, with its own tool")
    func loopsPlayBack() {
        let engine = field()
        engine.gravityY = 0
        engine.collisionsEnabled = false
        // Enough to go to the crowd rather than the individual bodies.
        engine.spawnBatch(count: 5_000, color: PackedColor(r: 255, g: 255, b: 255))
        #expect(engine.swarm.count == 5_000)
        engine.mouseMode = .attract
        engine.mouseRadius = 220
        recordCircle(engine, centreX: 200, centreY: 350, radius: 30, moments: 60)
        #expect(engine.finishLoopRecording())
        #expect(engine.forceLoops.count == 1)
        #expect(engine.forceLoops[0].mode == .attract)
        // The tool changes; the loop keeps its own.
        engine.mouseMode = .repel

        func meanDistance() -> Double {
            var total = 0.0
            for i in 0 ..< engine.swarm.count {
                let dx = Double(engine.swarm.positions[i * 2]) - 200
                let dy = Double(engine.swarm.positions[i * 2 + 1]) - 350
                total += (dx * dx + dy * dy).squareRoot()
            }
            return total / Double(max(1, engine.swarm.count))
        }
        // A fresh crowd, so what the real finger did while it was being recorded does not count.
        engine.swarm.removeAll()
        engine.spawnBatch(count: 5_000, color: PackedColor(r: 255, g: 255, b: 255))
        #expect(engine.forceLoops.count == 1, "adding bodies stopped the loop")
        let before = meanDistance()
        // No finger on the field at all: only the loop is pulling.
        for _ in 0 ..< 120 { engine.step() }
        #expect(meanDistance() < before - 10, "the loop did not pull anything in")
        #expect(engine.forceLoops[0].playhead < 60)
    }

    @Test("A tap is not a loop, a drawing tool cannot be recorded, and loops are saved")
    func loopRules() throws {
        let engine = field()
        engine.mouseMode = .wall
        #expect(!engine.beginLoopRecording())
        engine.mouseMode = .vortex
        #expect(engine.beginLoopRecording())
        engine.step(mouseX: 100, mouseY: 100, mouseActive: true)
        #expect(!engine.finishLoopRecording(), "a single moment was kept as a loop")
        recordCircle(engine, centreX: 200, centreY: 300, radius: 40, moments: 40)
        #expect(engine.finishLoopRecording())

        let text = try JSONEncoder().encode(engine.captureState())
        let reopened = field()
        #expect(reopened.apply(try JSONDecoder().decode(ParticleState.self, from: text)))
        #expect(reopened.forceLoops.count == 1)
        #expect(reopened.forceLoops.first?.mode == .vortex)
        #expect(reopened.forceLoops.first?.length == 40)

        engine.clear()
        #expect(engine.forceLoops.isEmpty, "loops outlived the world they were made in")
    }

    // MARK: - Foxes and rabbits

    @Test("Foxes and rabbits rise and fall, and neither dies out in a minute")
    func theHerdCycles() {
        let engine = field(seed: 2)
        #expect(engine.loadArrangement("foxes"))
        #expect(engine.predatorsEnabled)
        var rabbits: [Int] = []
        var foxes: [Int] = []
        for _ in 0 ..< 60 {
            for _ in 0 ..< 60 { engine.step() }
            let count = engine.herdCount
            rabbits.append(count.rabbits)
            foxes.append(count.foxes)
        }
        #expect(rabbits.last! > 0 && foxes.last! > 0, "one kind died out: \(rabbits.last!) rabbits, \(foxes.last!) foxes")
        #expect(rabbits.max()! - rabbits.min()! > 100, "the rabbits barely changed: \(rabbits)")
        #expect(foxes.max()! - foxes.min()! > 15, "the foxes barely changed: \(foxes)")
        #expect(engine.herdHistory.count > 200)
        #expect(engine.herdHistory.count <= ParticleEngine.herdHistoryLength)
    }

    @Test("A few rabbits are not flung apart as if electric")
    func kindsAreNotCharges() {
        // Fewer than three hundred bodies, which is when the charge force switches on.
        let engine = field()
        engine.spawnFoxesAndRabbits(rabbits: 6, foxes: 0)
        for index in engine.particles.indices {
            engine.withParticle(at: index) { body in
                body.x = 200 + Double(index) * 4
                body.y = 350
                body.velocityX = 0
                body.velocityY = 0
            }
        }
        engine.step()
        let fastest = engine.particles.map { ($0.velocityX * $0.velocityX + $0.velocityY * $0.velocityY).squareRoot() }.max()!
        // Wandering alone moves a rabbit about a tenth of a pixel a moment; the charge force between neighbours four
        // pixels apart would have thrown them at the speed limit.
        #expect(fastest < 0.5, "rabbits sprang apart at \(fastest)")
    }

    // MARK: - Sand on a drum

    @Test("The plate is still along its lines, and sand gathers onto them")
    func sandFindsTheLines() {
        // For the first note the diagonal is a still line.
        for share in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(ParticleEngine.drumAmplitude(note: 0, u: share, v: share) < 1e-9)
        }
        #expect(ParticleEngine.drumAmplitude(note: 0, u: 0, v: 1) > 0.9)

        let engine = field()
        engine.setMaxParticles(60_000)
        #expect(engine.loadArrangement("drum"))
        engine.drumNote = 1
        func meanAmplitude() -> Double {
            let plate = engine.drumPlate
            var total = 0.0
            for i in 0 ..< engine.swarm.count {
                let u = (Double(engine.swarm.positions[i * 2]) - plate.left) / plate.side
                let v = (Double(engine.swarm.positions[i * 2 + 1]) - plate.top) / plate.side
                total += ParticleEngine.drumAmplitude(note: 1, u: u, v: v)
            }
            return total / Double(max(1, engine.swarm.count))
        }
        let scattered = meanAmplitude()
        for _ in 0 ..< 360 { engine.step() }
        #expect(engine.drumNote == 1)
        #expect(meanAmplitude() < scattered * 0.5, "the sand did not gather: \(scattered) to \(meanAmplitude())")
    }

    @Test("Listening, silence leaves the sand where it is and a bright sound picks a higher note")
    func theDrumListens() {
        let engine = field()
        #expect(engine.loadArrangement("drum"))
        engine.drumHearing = ParticleDrumHearing(loudness: 0, brightness: 0.5)
        let before = (0 ..< 100).map { engine.swarm.positions[$0] }
        for _ in 0 ..< 30 { engine.step() }
        #expect((0 ..< 100).map { engine.swarm.positions[$0] } == before, "the sand moved in silence")

        engine.drumHearing = ParticleDrumHearing(loudness: 0.8, brightness: 0.95)
        for _ in 0 ..< (ParticleEngine.drumShortestHeardNote + 2) { engine.step() }
        #expect(engine.drumNote >= ParticleEngine.drumNotes.count - 2)
    }

    // MARK: - What these turned up

    @Test("A scene's own drag goes when the scene does")
    func sceneDragIsGivenBack() {
        let engine = field()
        let usual = engine.damping
        #expect(engine.loadArrangement("pendulums"))
        #expect(engine.damping > usual)
        #expect(engine.loadArrangement("galaxy"))
        #expect(engine.damping == usual, "the pendulums' drag was left behind")
        #expect(engine.loadArrangement("life"))
        #expect(engine.loadArrangement("cloth"))
        #expect(engine.damping == usual && engine.maxSpeed == 30, "particle life's drag and speed limit stayed")
    }

    @Test("Undo brings a scene back alive, not only its bodies")
    func undoKeepsTheBehaviour() {
        let engine = field()
        #expect(engine.loadArrangement("life"))
        let rules = engine.particleLifeRules
        #expect(engine.loadArrangement("galaxy"))
        #expect(!engine.particleLifeEnabled)
        #expect(engine.undo())
        #expect(engine.particleLifeEnabled, "undo gave back the bodies without their feelings")
        #expect(engine.particleLifeRules == rules)
    }

    @Test("Letting a body go keeps every muscle a muscle")
    func removalKeepsMuscles() {
        let engine = field()
        #expect(engine.loadArrangement("jellyfish"))
        let muscles = engine.springs.filter(\.isMuscle).count
        #expect(muscles > 0)
        let firstFree = engine.particles.firstIndex { !$0.isFixed }!
        let id = engine.particles[firstFree].id
        engine.removeParticles { $0.id == id }
        let after = engine.springs.filter(\.isMuscle).count
        #expect(after > 0 && after >= muscles - 8, "removing one body turned \(muscles - after) muscles into plain springs")
    }
}
