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

    // MARK: - Muscles

    @Test("A muscle changes the length it holds; a plain spring does not")
    func aMuscleChangesItsLength() {
        let plain = Spring(a: 0, b: 1, rest: 100, k: 0.3)
        #expect(!plain.isMuscle)
        // Untouched at every moment, so a field with no muscles behaves exactly as it did before they existed.
        for moment in stride(from: 0.0, through: 240, by: 17) {
            #expect(plain.length(atMoment: moment) == 100)
        }

        let muscle = Spring(a: 0, b: 1, rest: 100, k: 0.3, pulse: 0.4, beat: 60, phase: 0)
        #expect(muscle.isMuscle)
        var shortest = Double.infinity
        var longest = -Double.infinity
        for moment in 0 ... 60 {
            let length = muscle.length(atMoment: Double(moment))
            shortest = min(shortest, length)
            longest = max(longest, length)
        }
        // It squeezes to well under its length and swells to well over it, within one cycle.
        #expect(shortest < 65, "a muscle set to squeeze by two fifths only reached \(shortest)")
        #expect(longest > 135, "a muscle set to swell by two fifths only reached \(longest)")
        // And it comes back: a full cycle later it is where it was.
        #expect(abs(muscle.length(atMoment: 60) - muscle.length(atMoment: 0)) < 0.01)

        // The phase is what makes a row of muscles move something rather than shake it. Two muscles set apart
        // in the cycle are doing different things at the same moment.
        let behind = Spring(a: 0, b: 1, rest: 100, k: 0.3, pulse: 0.4, beat: 60, phase: 0.25)
        #expect(abs(behind.length(atMoment: 0) - muscle.length(atMoment: 0)) > 20)

        // A muscle actually pulls the bodies it joins together and lets them apart again.
        let engine = field()
        engine.gravityY = 0
        engine.damping = 1
        let a = engine.addParticle(x: 200, y: 350, velocityX: 0, velocityY: 0, radius: 3, mass: 1)
        let b = engine.addParticle(x: 300, y: 350, velocityX: 0, velocityY: 0, radius: 3, mass: 1)
        engine.setSprings([Spring(a: a, b: b, rest: 100, k: 0.25, pulse: 0.35, beat: 70, phase: 0)])
        var closest = Double.infinity
        var widest = -Double.infinity
        for _ in 0 ..< 140 {
            engine.step()
            let gap = abs(engine.particles[b].x - engine.particles[a].x)
            closest = min(closest, gap)
            widest = max(widest, gap)
        }
        #expect(widest - closest > 20, "the muscle moved the bodies by only \(widest - closest)")
    }

    // MARK: - Jellyfish

    @Test("A jellyfish swims because its muscles squeeze, not because it is told to")
    func jellyfishSwimsUnderItsOwnPower() {
        let engine = field(width: 1_320, height: 2_868)
        #expect(engine.loadArrangement("jellyfish"))
        #expect(engine.fluidEnabled, "a jellyfish needs water to push against")

        // The bells are built from muscles, and the muscles are set apart in the cycle so the squeeze travels.
        let muscles = engine.springs.filter(\.isMuscle)
        #expect(muscles.count >= 14, "only \(muscles.count) muscles")
        let phases = Set(muscles.map { ($0.phase * 1_000).rounded() })
        #expect(phases.count > 1, "every muscle squeezes at the same moment, so nothing can travel")
        #expect(engine.springs.contains { !$0.isMuscle }, "the rim and the tentacles should be plain springs")

        /// Where the middle of the first bell is. The bell is the ring, which is the first fourteen bodies.
        func bell(_ engine: ParticleEngine) -> (x: Double, y: Double) {
            var x = 0.0
            var y = 0.0
            let ring = min(14, engine.particles.count)
            guard ring > 0 else { return (0, 0) }
            for index in 0 ..< ring {
                x += engine.particles[index].x
                y += engine.particles[index].y
            }
            return (x / Double(ring), y / Double(ring))
        }

        let state = engine.captureState()
        let swimming = field(width: 1_320, height: 2_868)
        #expect(swimming.apply(state))
        let from = bell(swimming)
        for _ in 0 ..< 400 { swimming.step() }
        let to = bell(swimming)
        let travelled = ((to.x - from.x) * (to.x - from.x) + (to.y - from.y) * (to.y - from.y)).squareRoot()

        // The same field with the squeeze taken out of the muscles and nothing else changed. Whatever the bell
        // still does is gravity, the water and drag; the difference is what the muscles are worth.
        let still = field(width: 1_320, height: 2_868)
        #expect(still.apply(state))
        still.setSprings(still.springs.map { Spring(a: $0.a, b: $0.b, rest: $0.rest, k: $0.k) })
        let stillFrom = bell(still)
        for _ in 0 ..< 400 { still.step() }
        let stillTo = bell(still)
        let drifted = ((stillTo.x - stillFrom.x) * (stillTo.x - stillFrom.x)
            + (stillTo.y - stillFrom.y) * (stillTo.y - stillFrom.y)).squareRoot()

        #expect(travelled > 12, "the jellyfish went only \(travelled) in about seven seconds")
        #expect(
            travelled > drifted * 1.5,
            "squeezing made almost no difference: \(travelled) with muscles against \(drifted) without"
        )
        let allFinite = swimming.particles.allSatisfy { $0.isFinite }
        #expect(allFinite, "the jellyfish tore itself apart")
        #expect(swimming.swarm.corruptCount() == 0)
    }

    // MARK: - Gravity toward the middle, and the tiny planet

    @Test("Gravity toward the middle pulls everything inward, and is off unless a scene asks for it")
    func gravityToCentrePullsInward() {
        let engine = field()
        // Off to begin with, and off after any ordinary scene, so nothing else in the field is affected by it.
        #expect(engine.gravityToCentre == 0)
        #expect(engine.loadArrangement("galaxy"))
        #expect(engine.gravityToCentre == 0)

        engine.gravityY = 0
        engine.damping = 1
        engine.gravityToCentre = 0.5
        let centreX = engine.width * 0.5
        let centreY = engine.height * 0.5

        // A body off to one side, and one of the crowd on the other: both should come inward.
        let body = engine.addParticle(x: centreX + 120, y: centreY, velocityX: 0, velocityY: 0, radius: 3, mass: 1)
        _ = engine.placeLoose(centreX, centreY + 140, hue: 40)
        let crowdIndex = engine.swarm.count - 1
        let bodyBefore = engine.particles[body].x - centreX
        let crowdBefore = Double(engine.swarm.positions[crowdIndex * 2 + 1]) - centreY

        for _ in 0 ..< 30 { engine.step() }

        let bodyAfter = engine.particles[body].x - centreX
        let crowdAfter = Double(engine.swarm.positions[crowdIndex * 2 + 1]) - centreY
        #expect(bodyAfter < bodyBefore - 5, "an object body was not drawn inward: \(bodyBefore) to \(bodyAfter)")
        #expect(crowdAfter < crowdBefore - 5, "a crowd body was not drawn inward: \(crowdBefore) to \(crowdAfter)")

        // Choosing any other scene turns it off again.
        #expect(engine.loadArrangement("swarm"))
        #expect(engine.gravityToCentre == 0)
    }

    // MARK: - More than one finger, and the kaleidoscope

    /// A field of still bodies spread evenly, for seeing exactly where a tool reached.
    private func scattered(inDepth: Bool = false) -> ParticleEngine {
        let engine = field(width: 800, height: 800, inDepth: inDepth)
        engine.gravityY = 0
        engine.damping = 1
        var y = 40.0
        while y < 760 {
            var x = 40.0
            while x < 760 {
                if inDepth {
                    _ = engine.placeInDepth(x, y, 0, hue: 200)
                } else {
                    _ = engine.placeLoose(x, y, hue: 200)
                }
                x += 20
            }
            y += 20
        }
        return engine
    }

    /// How many bodies are moving, and how many separate places they are moving in.
    private func stirred(_ engine: ParticleEngine) -> (moving: Int, places: Int) {
        var moving = 0
        var cells = Set<Int>()
        for index in 0 ..< engine.swarm.count {
            let vx = Double(engine.swarm.velocities[index * 2])
            let vy = Double(engine.swarm.velocities[index * 2 + 1])
            guard (vx * vx + vy * vy).squareRoot() > 0.05 else { continue }
            moving += 1
            let x = Int(Double(engine.swarm.positions[index * 2]) / 100)
            let y = Int(Double(engine.swarm.positions[index * 2 + 1]) / 100)
            cells.insert(y * 100 + x)
        }
        return (moving, cells.count)
    }

    @Test("Several fingers each work the field, and none of it happens with one finger")
    func extraFingersEachApplyTheTool() {
        // One finger: one patch of the field moves.
        let one = scattered()
        one.mouseMode = .repel
        one.step(mouseX: 200, mouseY: 200, mouseActive: true)
        let single = stirred(one)
        #expect(single.moving > 5, "one finger moved only \(single.moving)")

        // Four fingers, far apart: four patches move, and far more bodies altogether.
        let four = scattered()
        four.mouseMode = .repel
        four.extraFingers = [
            ParticleFingerPoint(x: 600, y: 200),
            ParticleFingerPoint(x: 200, y: 600),
            ParticleFingerPoint(x: 600, y: 600),
        ]
        four.step(mouseX: 200, mouseY: 200, mouseActive: true)
        let many = stirred(four)
        #expect(many.moving > single.moving * 3, "four fingers moved \(many.moving) against one finger's \(single.moving)")
        #expect(many.places > single.places * 2, "the four fingers did not act in separate places: \(many.places)")

        // The list is the app's to clear, and it is capped so a mistake cannot slow the field to a halt.
        four.extraFingers = (0 ..< 40).map { ParticleFingerPoint(x: Double($0) * 10, y: 400) }
        #expect(four.extraFingers.count == ParticleEngine.fingerLimit)
        four.extraFingers = []
        #expect(four.extraFingers.isEmpty)
    }

    @Test("A kaleidoscope copies one stroke evenly round the middle")
    func kaleidoscopeFoldsAStroke() {
        let plain = scattered()
        plain.mouseMode = .repel
        plain.step(mouseX: 240, mouseY: 400, mouseActive: true)
        let single = stirred(plain)

        let folded = scattered()
        folded.mouseMode = .repel
        folded.kaleidoscopeFolds = 6
        #expect(folded.kaleidoscopeFolds == 6)
        folded.step(mouseX: 240, mouseY: 400, mouseActive: true)
        let six = stirred(folded)

        // Six times the work in six separate places, from the one finger.
        #expect(six.moving > single.moving * 3, "folding six ways moved \(six.moving) against \(single.moving)")
        #expect(six.places >= 4, "the folds landed in only \(six.places) places")

        // Every copy is the same distance from the middle as the finger is, which is what makes it a pattern
        // rather than a scatter.
        let centreX = folded.width * 0.5
        let centreY = folded.height * 0.5
        let fingerOut = ((240 - centreX) * (240 - centreX) + (400 - centreY) * (400 - centreY)).squareRoot()
        let copies = folded.kaleidoscopePoints(fingerX: 240, fingerY: 400, fingerZ: 0)
        #expect(copies.count == 5, "six folds should add five copies, not \(copies.count)")
        for copy in copies {
            let out = ((copy.x - centreX) * (copy.x - centreX) + (copy.y - centreY) * (copy.y - centreY)).squareRoot()
            #expect(abs(out - fingerOut) < 0.001, "a copy sits \(out) out where the finger is \(fingerOut)")
        }

        // Off by default, and off means exactly one place.
        let off = scattered()
        #expect(off.kaleidoscopeFolds == 1)
        #expect(off.kaleidoscopePoints(fingerX: 240, fingerY: 400, fingerZ: 0).isEmpty)
    }

    @Test("A ribbon of light stays where it is put, and nothing can move it")
    func ribbonsStayPut() {
        let engine = field()
        #expect(engine.ribbons.isEmpty)
        #expect(engine.mouseMode == .attract)
        // It changes the world rather than pushing the bodies, like the wall and the wind.
        #expect(ParticleMouseMode.light.drawsIntoTheWorld)

        engine.beginRibbon(now: 1_000)
        engine.extendRibbon(toX: 100, y: 100)
        engine.extendRibbon(toX: 140, y: 130)
        engine.extendRibbon(toX: 180, y: 180)
        engine.finishRibbon()
        #expect(engine.ribbons.count == 1)
        #expect(engine.ribbons[0].segments == 2)

        // A finger resting still adds nothing, or a held touch would fill the ribbon without going anywhere.
        let before = engine.ribbons[0].count
        engine.beginRibbon(now: 1_100)
        for _ in 0 ..< 50 { engine.extendRibbon(toX: 300, y: 300) }
        #expect(engine.ribbons[1].count == 1, "a still finger added \(engine.ribbons[1].count) places")
        #expect(engine.ribbons[0].count == before, "the finished ribbon was changed")

        // A tap leaves nothing behind: a mark has to have gone somewhere to be a mark.
        engine.finishRibbon()
        #expect(engine.ribbons.count == 1, "a tap left an invisible ribbon")

        // Nothing the field does moves it. Gravity, a finger and hundreds of moments all leave it exactly as drawn.
        let drawnX = engine.ribbons[0].pointsX
        engine.gravityY = 0.8
        engine.mouseMode = .repel
        for _ in 0 ..< 200 { engine.step(mouseX: 140, mouseY: 130, mouseActive: true) }
        #expect(engine.ribbons[0].pointsX == drawnX, "something moved a ribbon")

        // It survives being saved and read back.
        let state = engine.captureState()
        let other = field()
        #expect(other.apply(state))
        #expect(other.ribbons.count == 1)
        #expect(other.ribbons[0].pointsX == drawnX)
        #expect(other.ribbons[0].color == engine.ribbons[0].color)

        // Loading a world with none rubs out whatever was drawn in the last one.
        let bare = field()
        #expect(other.apply(bare.captureState()))
        #expect(other.ribbons.isEmpty)

        // Clearing the field clears them, because they are marks made in that world.
        engine.clear()
        #expect(engine.ribbons.isEmpty)
    }

    @Test("Particle life sorts itself out, and the kinds do not feel the same about each other")
    func particleLifeOrganisesItself() {
        let engine = field(width: 1_320, height: 2_868)
        engine.screenWidth = 1_320
        engine.screenHeight = 2_868
        #expect(engine.loadArrangement("life"))
        #expect(engine.particleLifeEnabled)
        #expect(engine.particles.count > 100)

        // Five kinds, all present, each carrying which it is.
        let kinds = Set(engine.particles.map { ParticleEngine.particleLifeKind(of: $0) })
        #expect(kinds.count == ParticleEngine.particleLifeKinds, "only \(kinds.count) kinds are in the field")

        // The table is not mutual, which is the whole reason this looks alive: something has to be able to chase
        // something that flees it.
        let rules = engine.particleLifeRules
        #expect(rules.count == ParticleEngine.particleLifeKinds)
        var lopsided = 0
        for mine in 0 ..< rules.count {
            for theirs in 0 ..< rules.count where mine != theirs {
                if abs(rules[mine][theirs] - rules[theirs][mine]) > 0.2 { lopsided += 1 }
            }
        }
        #expect(lopsided > 2, "every kind feels the same about every other, so nothing can chase anything")

        /// How clumped the field is: the average number of others within noticing distance.
        func togetherness(_ engine: ParticleEngine) -> Double {
            let bodies = engine.particles
            guard bodies.count > 1 else { return 0 }
            let reach = engine.brushUnit * ParticleEngine.particleLifeReach
            let reachSquared = reach * reach
            var total = 0
            for i in 0 ..< bodies.count {
                for j in 0 ..< bodies.count where j != i {
                    let dx = bodies[j].x - bodies[i].x
                    let dy = bodies[j].y - bodies[i].y
                    if dx * dx + dy * dy < reachSquared { total += 1 }
                }
            }
            return Double(total) / Double(bodies.count)
        }

        // Scattered at random to begin with; after a while it has sorted itself into something.
        let atFirst = togetherness(engine)
        for _ in 0 ..< 600 { engine.step() }
        let later = togetherness(engine)
        #expect(
            abs(later - atFirst) > atFirst * 0.15,
            "nothing organised itself: \(atFirst) neighbours each, then \(later)"
        )
        let finite = engine.particles.allSatisfy { $0.isFinite }
        #expect(finite, "particle life flew apart")
        // Nothing has escaped the world, which a force this free could easily do.
        let inside = engine.particles.allSatisfy {
            $0.x > -20 && $0.x < engine.width + 20 && $0.y > -20 && $0.y < engine.height + 20
        }
        #expect(inside, "something left the world")

        // Shuffling gives a different world, and the same seed gives the same shuffle.
        let before = engine.particleLifeRules
        engine.shuffleParticleLife()
        #expect(engine.particleLifeRules != before, "shuffling changed nothing")
        let twice = ParticleEngine(width: 400, height: 700, seed: 5)
        let thrice = ParticleEngine(width: 400, height: 700, seed: 5)
        twice.shuffleParticleLife()
        thrice.shuffleParticleLife()
        #expect(twice.particleLifeRules == thrice.particleLifeRules, "the same seed gave two different worlds")

        // And it is off for every other scene, so nothing else is quietly dragged about by it.
        #expect(engine.loadArrangement("galaxy"))
        #expect(!engine.particleLifeEnabled)
    }

    @Test("A morph flows from one arrangement into another, and stays touchable all the way")
    func morphFlowsBetweenShapes() {
        let engine = field(width: 1_320, height: 2_868)
        #expect(engine.spawnMorph(from: "sunflower", to: "ring"))
        #expect(engine.morphBetween?.from == "sunflower")
        #expect(engine.morphBetween?.to == "ring")
        #expect(engine.morphAt == 0)
        #expect(engine.swarm.count > 20)

        /// Where the crowd is, and how hollow it is.
        ///
        /// Hollowness rather than size, because size barely separates these two shapes: a filled disc and a ring
        /// round the same middle have almost the same average distance from it. What tells them apart is whether the
        /// bodies are all at *one* distance — a ring — or spread across every distance from the middle outward — a
        /// disc. So this reports how varied the distances are, as a share of the average.
        func shape(_ engine: ParticleEngine) -> (midX: Double, midY: Double, hollow: Double) {
            let count = engine.swarm.count
            guard count > 0 else { return (0, 0, 0) }
            var midX = 0.0
            var midY = 0.0
            for index in 0 ..< count {
                midX += Double(engine.swarm.positions[index * 2])
                midY += Double(engine.swarm.positions[index * 2 + 1])
            }
            midX /= Double(count)
            midY /= Double(count)
            var radii: [Double] = []
            radii.reserveCapacity(count)
            for index in 0 ..< count {
                let dx = Double(engine.swarm.positions[index * 2]) - midX
                let dy = Double(engine.swarm.positions[index * 2 + 1]) - midY
                radii.append((dx * dx + dy * dy).squareRoot())
            }
            let mean = radii.reduce(0, +) / Double(count)
            guard mean > 0 else { return (midX, midY, 0) }
            let varied = (radii.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(count)).squareRoot()
            // Low when every body is at the same distance, which is a ring; high when they fill the disc.
            return (midX, midY, 1 - min(1, varied / mean))
        }

        for _ in 0 ..< 60 { engine.step() }
        let atStart = shape(engine)

        // All the way across, and given time to arrive.
        engine.morphAt = 1
        #expect(engine.morphAt == 1)
        for _ in 0 ..< 240 { engine.step() }
        let atEnd = shape(engine)

        // A sunflower fills its disc and a ring does not, so the end is plainly more ring-like than the start.
        #expect(
            atEnd.hollow > atStart.hollow + 0.08,
            "the shape did not change: hollowness \(atStart.hollow) then \(atEnd.hollow)"
        )
        #expect(engine.swarm.corruptCount() == 0)

        // Halfway is genuinely between the two rather than one or the other.
        engine.morphAt = 0.5
        for _ in 0 ..< 240 { engine.step() }
        let middle = shape(engine)
        #expect(
            middle.hollow > atStart.hollow && middle.hollow < atEnd.hollow,
            "halfway was not between the two: \(atStart.hollow), \(middle.hollow), \(atEnd.hollow)"
        )

        // And still touchable: a push moves bodies, and letting go brings them back to wherever the slider is.
        let before = (0 ..< engine.swarm.count).map { Double(engine.swarm.positions[$0 * 2]) }
        engine.mouseMode = .repel
        // Pushed where bodies actually are rather than at the middle of the shape, which for anything ring-like is
        // the one place with nothing in it.
        let pushX = Double(engine.swarm.positions[0])
        let pushY = Double(engine.swarm.positions[1])
        for _ in 0 ..< 20 {
            engine.step(mouseX: pushX, mouseY: pushY, mouseActive: true)
        }
        var moved = 0
        for index in 0 ..< min(before.count, engine.swarm.count) {
            if abs(Double(engine.swarm.positions[index * 2]) - before[index]) > 3 { moved += 1 }
        }
        #expect(moved > 10, "a half-finished morph could not be pushed: only \(moved) moved")
        for _ in 0 ..< 400 { engine.step() }
        let returned = shape(engine)
        #expect(
            abs(returned.hollow - middle.hollow) < 0.12,
            "the morph did not recover its shape: \(middle.hollow) then \(returned.hollow)"
        )

        // Two arrangements with no crowd between them cannot be morphed, and it says so rather than emptying the
        // field and leaving no explanation.
        let bare = field()
        #expect(!bare.spawnMorph(from: "cloth", to: "rope"))
        // And an unknown name is refused outright.
        #expect(!bare.spawnMorph(from: "sunflower", to: "not-a-scene"))
    }

    @Test("The lens says what is acting on one body, and names the biggest first")
    func theLensExplainsOneBody() {
        let engine = field()
        // Nothing where there is nothing, rather than whatever happened to be nearest across the world.
        #expect(!engine.reading(nearX: 100, y: 100).found)

        engine.gravityY = 0.4
        engine.damping = 0.99
        _ = engine.placeLoose(200, 300, velocityX: 3, velocityY: 0, hue: 40)
        for _ in 0 ..< 5 { engine.step() }

        let read = engine.reading(nearX: 200, y: 320, within: 90)
        #expect(read.found, "no body found near one that is there")
        #expect(read.isCrowd)
        #expect(read.speed > 0)
        #expect(read.mass > 0)
        // Gravity and drag are both acting, and both are named.
        let names = read.pushes.map(\.name)
        #expect(names.contains("Gravity"), "gravity was not named: \(names)")
        #expect(names.contains("Drag"), "drag was not named: \(names)")
        // Largest first, so the answer to "why did that move" is the first line.
        for index in 1 ..< read.pushes.count {
            #expect(read.pushes[index - 1].size >= read.pushes[index].size, "the pushes are not in order")
        }
        // And where it is heading, which is the other half of the question.
        #expect(read.path.count > 8)
        #expect(read.path.last?.y ?? 0 > read.y, "the path does not fall, though gravity is pulling down")

        // A black hole is named, and on a galaxy it is the biggest thing acting on a nearby star.
        let galaxy = field()
        #expect(galaxy.loadArrangement("galaxy"))
        for _ in 0 ..< 30 { galaxy.step() }
        let hole = galaxy.particles.first { $0.kind == .blackhole }
        #expect(hole != nil)
        if let hole {
            let near = galaxy.reading(nearX: hole.x + 60, y: hole.y, within: 60)
            #expect(near.found)
            #expect(near.pushes.first?.name == "Black hole", "the strongest force was \(near.pushes.first?.name ?? "none")")
        }

        // Painted wind is named too, which matters because it is the one force that is invisible unless drawn.
        let windy = field()
        windy.gravityX = 0
        windy.gravityY = 0
        windy.damping = 1
        windy.mouseMode = .current
        windy.paintCurrent(atX: 200, y: 350, directionX: 1, directionY: 0)
        _ = windy.placeLoose(200, 350, hue: 200)
        let felt = windy.reading(nearX: 200, y: 350)
        #expect(felt.pushes.contains { $0.name == "Painted wind" }, "the wind was not named: \(felt.pushes.map(\.name))")
    }

    @Test("The cost warning knows that the box costs more")
    func costWarningKnowsAboutDepth() {
        // Fewer bodies are affordable in the box than on a flat sheet, because each one costs more.
        #expect(SwarmCost.budget(inDepth: true) < SwarmCost.budget(inDepth: false))

        // A crowd that is comfortable flat can be too much in the box, and the warning has to say so — before
        // this, the number somebody was shown before setting off a big scene was a flat-world guess.
        let awkward = SwarmCost.budget(inDepth: true) + SwarmCost.budget(inDepth: false)
        let middling = awkward / 2 + 1
        #expect(SwarmCost.warning(bodies: middling, collisions: true, inDepth: false) == nil)
        #expect(SwarmCost.warning(bodies: middling, collisions: true, inDepth: true) != nil)

        // And it explains which box it is talking about, so the tap that fixes it is findable.
        let said = SwarmCost.warning(bodies: middling, collisions: true, inDepth: true) ?? ""
        #expect(said.contains("box"), "the warning in 3D does not mention the box: \(said)")

        // The same crowd costs more in the box either way, collisions or not.
        for collisions in [true, false] {
            let flat = SwarmCost.estimatedMilliseconds(bodies: 40_000, collisions: collisions, inDepth: false)
            let boxed = SwarmCost.estimatedMilliseconds(bodies: 40_000, collisions: collisions, inDepth: true)
            #expect(boxed > flat, "with collisions \(collisions), the box was not dearer: \(flat) then \(boxed)")
        }

        // Nothing at all to say about a crowd nobody is pushing apart.
        #expect(SwarmCost.warning(bodies: 900_000, collisions: false, inDepth: true) == nil)
    }

    @Test("The field says when something worth feeling happens")
    func bigMomentsAreReported() {
        let engine = field()
        // Nothing to report on a quiet field.
        #expect(engine.bigMomentStrength == 0)
        #expect(engine.loadArrangement("swarm"))
        for _ in 0 ..< 120 { engine.step() }
        #expect(engine.bigMomentStrength == 0, "a quiet crowd claimed something happened")

        // A storm does, when a bolt strikes — and only on the moments it strikes.
        #expect(engine.loadArrangement("lightning"))
        var struck = 0
        var quiet = 0
        for _ in 0 ..< 200 {
            engine.step()
            if engine.bigMomentStrength > 0.5 { struck += 1 } else if engine.bigMomentStrength == 0 { quiet += 1 }
        }
        #expect(struck >= 2, "the storm struck \(struck) times in over three seconds")
        #expect(quiet > 150, "the storm claimed something was happening on \(200 - quiet) of 200 moments")

        // Fireworks report too, and more gently than lightning: a shell is not a bolt.
        #expect(engine.loadArrangement("fireworks"))
        var strongest = 0.0
        for _ in 0 ..< 120 {
            engine.step()
            strongest = max(strongest, engine.bigMomentStrength)
        }
        #expect(strongest > 0.1 && strongest < 0.6, "a shell reported \(strongest)")
    }

    @Test("Laid flat, down points into the box")
    func gravityIntoTheBox() {
        // The phone held up to be looked at: down is down the screen and nothing falls into the box.
        var upright = TiltMapping()
        upright.apply(betaDegrees: 90, gammaDegrees: 0)
        #expect(abs(upright.particleGravityZ) < 0.01, "held up, \(upright.particleGravityZ) of down points inward")

        // Laid flat on a table: down points into the screen.
        var flat = TiltMapping()
        flat.apply(betaDegrees: 0, gammaDegrees: 0)
        #expect(flat.particleGravityZ > 0.1, "laid flat, only \(flat.particleGravityZ) of down points inward")

        // And the crowd actually falls that way, toward the back of the box.
        let engine = field(inDepth: true)
        engine.gravityY = 0
        engine.gravityZ = 0.3
        for _ in 0 ..< 60 {
            _ = engine.placeInDepth(
                engine.width * 0.5, engine.height * 0.5, 0, hue: 200
            )
        }
        let before = (0 ..< engine.swarm.count).reduce(0.0) { $0 + Double(engine.swarm.depths[$1]) }
        for _ in 0 ..< 40 { engine.step() }
        let after = (0 ..< engine.swarm.count).reduce(0.0) { $0 + Double(engine.swarm.depths[$1]) }
        #expect(after > before + 10, "the crowd did not fall into the box: \(before) became \(after)")
        // And stays inside it.
        let inside = (0 ..< engine.swarm.count).allSatisfy {
            abs(Double(engine.swarm.depths[$0])) <= engine.halfDepth + 2
        }
        #expect(inside, "something fell through the back of the box")

        // A flat field has no depth to fall through, and nothing moves into one.
        let flatField = field()
        flatField.gravityZ = 0.3
        for _ in 0 ..< 20 { _ = flatField.placeLoose(200, 350, hue: 40) }
        for _ in 0 ..< 30 { flatField.step() }
        let stillFlat = (0 ..< flatField.swarm.count).allSatisfy { flatField.swarm.depths[$0] == 0 }
        #expect(stillFlat, "a flat field moved into depth")
    }

    @Test("Several fingers work in 3D too")
    func extraFingersInDepth() {
        let one = scattered(inDepth: true)
        one.mouseMode = .repel
        one.step(mouseX: 200, mouseY: 200, mouseActive: true)
        let single = stirred(one)

        let several = scattered(inDepth: true)
        several.mouseMode = .repel
        several.extraFingers = [
            ParticleFingerPoint(x: 600, y: 200),
            ParticleFingerPoint(x: 200, y: 600),
            ParticleFingerPoint(x: 600, y: 600),
        ]
        several.step(mouseX: 200, mouseY: 200, mouseActive: true)
        let many = stirred(several)
        #expect(many.moving > single.moving * 2, "in 3D four fingers moved \(many.moving) against one's \(single.moving)")
        #expect(several.swarm.corruptCount() == 0)
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
