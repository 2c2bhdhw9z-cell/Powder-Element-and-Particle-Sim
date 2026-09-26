import Testing

@testable import CrucibleCore

/// What the newer arrangements are each meant to be, checked directly.
///
/// The sweeps in `ParticleArrangementTests` and `ParticleDepthTests` already check that every scene loads,
/// stays finite, uses the depth and can be pushed about by every tool. They cannot check that a scene is the
/// thing it is named after — that a galaxy crash grows tails, that the inner planets are the fast ones, that a
/// row of pendulums actually falls out of step. That is what these are for, and each one is a claim the name
/// makes rather than a recording of whatever the code happened to do.
@Suite("Newer arrangements")
struct ParticleMoreArrangementTests {
    private func field(width: Double = 400, height: Double = 700, seed: UInt32 = 11, inDepth: Bool = false) -> ParticleEngine {
        let engine = ParticleEngine(width: width, height: height, seed: seed)
        engine.setMaxParticles(400_000)
        if inDepth { engine.setDepthEnabled(true) }
        return engine
    }

    /// How far the crowd is spread, as the distance from its middle that half of it is inside.
    private func spread(of engine: ParticleEngine) -> Double {
        let count = engine.swarm.count
        guard count > 0 else { return 0 }
        var middleX = 0.0
        var middleY = 0.0
        for index in 0 ..< count {
            middleX += Double(engine.swarm.positions[index * 2])
            middleY += Double(engine.swarm.positions[index * 2 + 1])
        }
        middleX /= Double(count)
        middleY /= Double(count)
        var total = 0.0
        for index in 0 ..< count {
            let dx = Double(engine.swarm.positions[index * 2]) - middleX
            let dy = Double(engine.swarm.positions[index * 2 + 1]) - middleY
            total += (dx * dx + dy * dy).squareRoot()
        }
        return total / Double(count)
    }

    // MARK: - Galaxy crash

    @Test("A galaxy crash has two cores that move, and pulls the stars out into tails")
    func galaxyCrashTearsTails() {
        let engine = field()
        #expect(engine.loadArrangement("crash"))

        let cores = engine.particles.filter { $0.kind == .blackhole }
        #expect(cores.count == 2, "a crash needs two galaxies, not \(cores.count)")
        // Neither core is pinned, and both are already on their way: a crash whose cores stand still is two
        // separate galaxies that happen to be near each other.
        let nonePinned = cores.allSatisfy { !$0.isFixed }
        let bothMoving = cores.allSatisfy { abs($0.velocityX) > 0.01 }
        #expect(nonePinned, "a core is pinned, so nothing can collide")
        #expect(bothMoving, "a core is not moving toward the other")
        let apartAtFirst = abs(cores[0].x - cores[1].x)

        let before = spread(of: engine)
        for _ in 0 ..< 400 { engine.step() }

        let after = spread(of: engine)
        // The stars end up further from each other than they began, which is what a tail is.
        #expect(after > before * 1.15, "the stars spread by only \(after / max(1, before))×")

        let moved = engine.particles.filter { $0.kind == .blackhole }
        #expect(moved.count == 2, "a core was lost")
        #expect(
            abs(abs(moved[0].x - moved[1].x) - apartAtFirst) > 1,
            "the cores never moved relative to each other"
        )
        #expect(engine.swarm.corruptCount() == 0)
    }

    // MARK: - The solar system

    @Test("The solar system has every planet in order, the inner ones fastest, each holding its circle")
    func solarSystemIsInOrderAndInProportion() {
        let engine = field(width: 1_320, height: 2_868)
        #expect(engine.loadArrangement("solar"))

        let sun = engine.particles.first
        #expect(sun?.isFixed == true, "the Sun should stay where it is")
        let centreX = engine.width * 0.5
        let centreY = engine.height * 0.5

        // The Sun and eight planets, and nothing else in the object list — see the note in the scene about why
        // there is no Moon.
        #expect(engine.particles.count == 9, "expected the Sun and eight planets, got \(engine.particles.count)")
        // Only the Sun pulls. That is what lets every planet hold an exact circle: a planet with a pull of its
        // own throws its neighbours off every time it passes them, because these distances are squeezed.
        let pullers = engine.particles.filter { $0.kind == .blackhole || $0.kind == .repulsor }
        #expect(pullers.count == 1, "\(pullers.count) things pull, so the orbits cannot hold")

        /// How far out each planet is, and how fast, in the order the scene placed them.
        var distances: [Double] = []
        var speeds: [Double] = []
        for planet in engine.particles.dropFirst().prefix(8) {
            let dx = planet.x - centreX
            let dy = planet.y - centreY
            distances.append((dx * dx + dy * dy).squareRoot())
            speeds.append((planet.velocityX * planet.velocityX + planet.velocityY * planet.velocityY).squareRoot())
        }
        #expect(distances.count == 8)

        // Each planet further out than the one before it, which is the whole claim of "in order".
        for index in 1 ..< distances.count {
            #expect(
                distances[index] > distances[index - 1],
                "\(ParticleEngine.solarPlanets[index].name) is not outside \(ParticleEngine.solarPlanets[index - 1].name)"
            )
            // And slower. This is the thing worth seeing, and it is not put in by hand: it follows from every
            // planet being given the speed that holds the circle it is drawn on.
            #expect(
                speeds[index] < speeds[index - 1],
                "\(ParticleEngine.solarPlanets[index].name) is not slower than the planet inside it"
            )
        }
        // Everything fits on the screen it was laid out for.
        let allOnScreen = distances.allSatisfy { $0 < engine.patternSpan * 0.5 }
        #expect(allOnScreen)

        // And each planet stays on roughly the circle it started on, rather than spiralling in or leaving.
        for _ in 0 ..< 600 { engine.step() }
        let stillThere = Array(engine.particles.dropFirst().prefix(8))
        for (index, planet) in stillThere.enumerated() {
            let dx = planet.x - centreX
            let dy = planet.y - centreY
            let now = (dx * dx + dy * dy).squareRoot()
            #expect(
                now > distances[index] * 0.6 && now < distances[index] * 1.5,
                "\(ParticleEngine.solarPlanets[index].name) left its orbit: \(distances[index]) became \(now)"
            )
        }

        // And the belt is still a belt, between Mars and Jupiter rather than scattered over everything.
        let mars = distances[3]
        let jupiter = distances[4]
        var insideTheBelt = 0
        for index in 0 ..< engine.swarm.count {
            let dx = Double(engine.swarm.positions[index * 2]) - centreX
            let dy = Double(engine.swarm.positions[index * 2 + 1]) - centreY
            let out = (dx * dx + dy * dy).squareRoot()
            if out > mars * 0.8, out < jupiter * 1.2 { insideTheBelt += 1 }
        }
        #expect(
            Double(insideTheBelt) > Double(engine.swarm.count) * 0.8,
            "only \(insideTheBelt) of \(engine.swarm.count) asteroids are still between Mars and Jupiter"
        )
    }

    // MARK: - Pendulum wave

    @Test("A row of pendulums starts in one line, then falls out of step, longest slowest")
    func pendulumsFallOutOfStep() {
        let engine = field(width: 1_320, height: 2_868)
        #expect(engine.loadArrangement("pendulums"))

        let weights = engine.particles.filter { !$0.isFixed }
        let pins = engine.particles.filter(\.isFixed)
        #expect(weights.count >= 8, "only \(weights.count) weights in the row")
        #expect(pins.count == weights.count, "every weight needs a pin of its own")
        // One string each, drawn as the spring between pin and weight.
        #expect(engine.springs.count == weights.count)

        /// How far each weight leans from its own pin, as a share of its string.
        func leans(_ engine: ParticleEngine) -> [Double] {
            var found: [Double] = []
            for spring in engine.springs {
                guard spring.a < engine.particles.count, spring.b < engine.particles.count else { continue }
                let pin = engine.particles[spring.a]
                let weight = engine.particles[spring.b]
                let length = max(1, spring.rest)
                found.append((weight.x - pin.x) / length)
            }
            return found
        }

        // They all start leaning the same way by the same amount: the row begins as one straight line.
        let atFirst = leans(engine)
        let widestAtFirst = (atFirst.max() ?? 0) - (atFirst.min() ?? 0)
        #expect(widestAtFirst < 0.02, "the row does not start in a line: \(widestAtFirst)")
        #expect((atFirst.min() ?? 0) > 0.01, "the weights are not held out to one side")

        // Every string a different length, growing along the row. That is what makes the pattern.
        let lengths = engine.springs.map(\.rest)
        for index in 1 ..< lengths.count {
            #expect(lengths[index] > lengths[index - 1], "string \(index) is not longer than the one before")
        }

        // Let go, they immediately begin to separate, and within a few seconds the row is plainly no longer one
        // line. Watched throughout rather than only at the end, because the row keeps gathering itself back up
        // — that is the whole point of it — so a single glance can land on a moment when it happens to be tidy.
        var widestSeen = 0.0
        var later = atFirst
        for _ in 0 ..< 8 {
            for _ in 0 ..< 30 { engine.step() }
            later = leans(engine)
            widestSeen = max(widestSeen, (later.max() ?? 0) - (later.min() ?? 0))
        }
        #expect(widestSeen > 0.1, "the row stayed in step: \(widestSeen)")

        // And over the same time the shortest string has swung through more than the longest, because a short
        // pendulum is a fast one. Measured as how far each one travelled, not where it ended up.
        var travelled: [Double] = Array(repeating: 0, count: atFirst.count)
        var previous = leans(engine)
        for _ in 0 ..< 120 {
            engine.step()
            let now = leans(engine)
            for index in 0 ..< min(travelled.count, now.count) {
                travelled[index] += abs(now[index] - previous[index])
            }
            previous = now
        }
        #expect(
            travelled[0] > travelled[travelled.count - 1],
            "the shortest string (\(travelled[0])) did not swing further than the longest (\(travelled[travelled.count - 1]))"
        )
        let allFinite = engine.particles.allSatisfy { $0.isFinite }
        #expect(allFinite)
    }

    // MARK: - Marbling

    @Test("A marbling tray is laid out in bands of colour that a finger can comb")
    func marblingHasBandsAFingerCanComb() {
        let engine = field(width: 1_320, height: 2_868)
        #expect(engine.loadArrangement("marbling"))
        #expect(engine.fluidEnabled, "marbling is made of liquid")

        let count = engine.swarm.count
        #expect(count > 500, "only \(count) in the tray")

        /// Which colours are used, and where across the tray each one sits.
        var leftmost: [UInt32: Double] = [:]
        var rightmost: [UInt32: Double] = [:]
        for index in 0 ..< count {
            let colour = engine.swarm.colors[index]
            let x = Double(engine.swarm.positions[index * 2])
            leftmost[colour] = min(leftmost[colour] ?? x, x)
            rightmost[colour] = max(rightmost[colour] ?? x, x)
        }
        // Several distinct colours, and each one confined to a band rather than scattered over the whole tray —
        // ink spread evenly everywhere is not marbling, it is a puddle.
        #expect(leftmost.count >= 5, "only \(leftmost.count) colours in the tray")
        for (colour, left) in leftmost {
            let width = (rightmost[colour] ?? left) - left
            #expect(width < engine.width * 0.45, "one colour covers \(width) of the tray, so it is not a band")
        }

        // Combed: a finger dragged across the bands moves the ink along its path, and nothing is lost doing it.
        let before = (0 ..< count).map { Double(engine.swarm.positions[$0 * 2]) }
        engine.mouseMode = .attract
        for moment in 0 ..< 40 {
            let along = Double(moment) / 40
            engine.step(
                mouseX: engine.width * (0.2 + 0.6 * along),
                mouseY: engine.height * 0.78,
                mouseActive: true
            )
        }
        var moved = 0
        for index in 0 ..< min(count, engine.swarm.count) {
            if abs(Double(engine.swarm.positions[index * 2]) - before[index]) > 4 { moved += 1 }
        }
        #expect(moved > 40, "the comb moved only \(moved) drops of ink")
        #expect(engine.swarm.corruptCount() == 0, "the tray burst")
    }

    // MARK: - The atom

    @Test("An atom's dumbbells are pinched in the middle, and it only exists in 3D")
    func atomHasRealOrbitalShapes() {
        #expect(ParticleArrangement.named("atom")?.depth == .only)

        // Chosen on a flat field, it turns 3D on rather than drawing itself flat.
        let flat = field()
        #expect(flat.loadArrangement("atom"))
        #expect(flat.depthEnabled, "the atom should have switched the field into 3D")

        let engine = field(width: 1_320, height: 2_868, inDepth: true)
        #expect(engine.loadArrangement("atom"))
        let count = engine.swarm.count
        #expect(count > 500, "only \(count) in the atom")

        let centreX = engine.width * 0.5
        let centreY = engine.height * 0.5

        // The three dumbbells are the three colours that are neither the nucleus nor the inner ball. Rather
        // than picking them out by colour, the shape is checked where it can only come from a dumbbell: along
        // each direction, well away from the middle, there has to be more of the cloud than there is on the
        // flat plane through the middle at the same distance.
        var alongAxis = 0
        var acrossMiddle = 0
        let near = engine.patternSpan * 0.12
        let far = engine.patternSpan * 0.3
        for index in 0 ..< count {
            let x = Double(engine.swarm.positions[index * 2]) - centreX
            let y = Double(engine.swarm.positions[index * 2 + 1]) - centreY
            let z = Double(engine.swarm.depths[index])
            let distance = (x * x + y * y + z * z).squareRoot()
            guard distance > near, distance < far else { continue }
            let leanX = abs(x) / distance
            let leanY = abs(y) / distance
            let leanZ = abs(z) / distance
            let strongest = max(leanX, max(leanY, leanZ))
            if strongest > 0.9 {
                alongAxis += 1
            } else if strongest < 0.62 {
                // Pointing into a corner, between all three directions: where a dumbbell is pinched away.
                acrossMiddle += 1
            }
        }
        #expect(alongAxis > 20, "nothing lies along the three directions, so there are no lobes")
        #expect(
            alongAxis > acrossMiddle,
            "the cloud is as full between the lobes (\(acrossMiddle)) as along them (\(alongAxis)), so it is a ball"
        )

        // It turns, so every lobe comes round to be seen.
        let firstX = engine.swarm.positions[0]
        let firstZ = engine.swarm.depths[0]
        for _ in 0 ..< 120 { engine.step() }
        #expect(
            abs(engine.swarm.positions[0] - firstX) > 0.5 || abs(engine.swarm.depths[0] - firstZ) > 0.5,
            "the atom does not turn"
        )
        #expect(engine.swarm.corruptCount() == 0)
    }
}
