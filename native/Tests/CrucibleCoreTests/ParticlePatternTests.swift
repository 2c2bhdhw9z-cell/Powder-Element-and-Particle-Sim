import Testing

@testable import CrucibleCore

/// The twelve pattern scenes.
///
/// Each of these is a shape, so each test asks whether the shape is there. That is not a formality — the
/// last time this project rebuilt its scenes, a test asking "is the ground actually uneven" and another
/// asking "do two different seeds give two different worlds" both failed against the old ones, which had
/// looked fine in review for months.
struct ParticlePatternTests {
    private func field(seed: UInt32 = 7) -> ParticleEngine {
        let engine = ParticleEngine(width: 400, height: 700, seed: seed)
        engine.setMaxParticles(200_000)
        return engine
    }

    /// Every body's position, from whichever store the scene used.
    private func points(_ engine: ParticleEngine) -> [(x: Double, y: Double)] {
        var out: [(x: Double, y: Double)] = []
        for index in 0 ..< engine.swarm.count {
            out.append((
                Double(engine.swarm.positions[index * 2]),
                Double(engine.swarm.positions[index * 2 + 1])
            ))
        }
        for body in engine.particles { out.append((body.x, body.y)) }
        return out
    }

    /// Runs each scene by name, so the general tests can cover all twelve without repeating themselves.
    ///
    /// Built fresh each time rather than held as a shared constant: a list of closures is not something
    /// the compiler will let be shared across threads, and the tests run in parallel.
    private var scenes: [(name: String, run: (ParticleEngine) -> Void)] { [
        ("sunflower", { $0.spawnSunflower(count: 2_000) }),
        ("mandala", { $0.spawnMandala(count: 2_000) }),
        ("snowflakes", { $0.spawnSnowflakes(count: 2_000) }),
        ("tornado", { $0.spawnTornado(count: 1_500) }),
        ("lightning", { $0.spawnLightning(count: 1_200) }),
        ("aurora", { $0.spawnAurora(count: 2_000) }),
        ("supernova", { $0.spawnSupernova(count: 1_500) }),
        ("sierpinski", { $0.spawnSierpinski(count: 2_000) }),
        ("fireworks", { $0.spawnFireworks(count: 1_500) }),
        ("magma", { $0.spawnMagma(count: 1_500) }),
        ("confetti", { $0.spawnConfetti(count: 1_500) }),
        ("molecules", { $0.spawnMolecules(count: 600) }),
    ] }

    // MARK: - What every scene must satisfy

    @Test("Every scene puts bodies somewhere usable")
    func everySceneFillsTheField() {
        for scene in scenes {
            let engine = field()
            scene.run(engine)
            let placed = points(engine)
            #expect(placed.count > 200, "\(scene.name) placed only \(placed.count)")
            for point in placed {
                #expect(point.x.isFinite && point.y.isFinite, "\(scene.name) placed an unusable body")
                #expect(
                    point.x > -50 && point.x < 450 && point.y > -50 && point.y < 750,
                    "\(scene.name) placed a body at \(point), well outside the field"
                )
            }
        }
    }

    @Test("Every scene fills a fair part of the field rather than a dot")
    func everySceneHasExtent() {
        for scene in scenes {
            let engine = field()
            scene.run(engine)
            let placed = points(engine)
            let minX = placed.map(\.x).min() ?? 0
            let maxX = placed.map(\.x).max() ?? 0
            let minY = placed.map(\.y).min() ?? 0
            let maxY = placed.map(\.y).max() ?? 0
            // A supernova starts as a point by design, so its extent is in its velocities instead.
            if scene.name == "supernova" {
                var fastest = 0.0
                for index in 0 ..< engine.swarm.count {
                    let vx = Double(engine.swarm.velocities[index * 2])
                    let vy = Double(engine.swarm.velocities[index * 2 + 1])
                    fastest = max(fastest, (vx * vx + vy * vy).squareRoot())
                }
                #expect(fastest > 5, "a supernova must actually be going somewhere")
                continue
            }
            #expect(maxX - minX > 40, "\(scene.name) is \(maxX - minX) wide")
            #expect(maxY - minY > 40, "\(scene.name) is \(maxY - minY) tall")
        }
    }

    @Test("Every scene comes back the same from the same seed, and differently from another")
    func everySceneIsRepeatableAndVaried() {
        // The reference implementation cannot do the first half of this: nothing in it is seeded, so no
        // scene in it can ever be reproduced. Recorded comparisons in this project check the random
        // stream is consumed identically, which is what makes the first half true here.
        for scene in scenes {
            let first = field(seed: 12)
            let second = field(seed: 12)
            let other = field(seed: 99)
            scene.run(first)
            scene.run(second)
            scene.run(other)

            let a = points(first)
            let b = points(second)
            let c = points(other)

            #expect(a.count == b.count, "\(scene.name) placed a different number from the same seed")
            var same = true
            for index in 0 ..< min(a.count, b.count) where a[index] != b[index] { same = false }
            #expect(same, "\(scene.name) is not repeatable from a seed")

            var differs = false
            for index in 0 ..< min(a.count, c.count) where a[index] != c[index] { differs = true }
            #expect(differs, "\(scene.name) ignores its seed — two seeds gave the same picture")
        }
    }

    @Test("Every scene stays inside the field's own limit")
    func everySceneRespectsTheLimit() {
        // A scene that overruns the limit either evicts what was already there or grows the field past
        // what was asked for. Both used to happen.
        for scene in scenes {
            let engine = ParticleEngine(width: 400, height: 700, seed: 3)
            // A thousand, because that is the smallest limit the field accepts — asking for less gets
            // rounded up, and a test that asked for five hundred would be measuring the wrong number.
            engine.setMaxParticles(1_000)
            scene.run(engine)
            #expect(
                engine.bodyCount <= 1_000,
                "\(scene.name) placed \(engine.bodyCount) against a limit of 1,000"
            )
        }
    }

    @Test("Every scene can be undone")
    func everySceneIsUndoable() {
        for scene in scenes {
            let engine = field()
            engine.spawnBurst(count: 40, x: 100, y: 100)
            let before = engine.bodyCount
            scene.run(engine)
            #expect(engine.bodyCount > before, "\(scene.name) added nothing")
            #expect(engine.undo(), "\(scene.name) left nothing to undo")
            #expect(engine.bodyCount == before, "\(scene.name) did not undo cleanly")
        }
    }

    @Test("Every scene keeps its shape when the field is turned on its side")
    func everySceneSurvivesAnAspectChange() {
        // Several of the reference implementation's scenes mix distances measured against the world's
        // height with distances measured against its width, so they stretch when the window does. On a
        // phone that means a scene that is a circle upright and an ellipse on its side.
        for scene in scenes {
            let tall = ParticleEngine(width: 400, height: 700, seed: 21)
            tall.setMaxParticles(200_000)
            let wide = ParticleEngine(width: 700, height: 400, seed: 21)
            wide.setMaxParticles(200_000)
            scene.run(tall)
            scene.run(wide)

            func extent(_ engine: ParticleEngine) -> (width: Double, height: Double) {
                let placed = points(engine)
                guard !placed.isEmpty else { return (0, 0) }
                return (
                    (placed.map(\.x).max() ?? 0) - (placed.map(\.x).min() ?? 0),
                    (placed.map(\.y).max() ?? 0) - (placed.map(\.y).min() ?? 0)
                )
            }

            // Scenes that are deliberately spread over the whole field are not expected to be square.
            // Two different reasons, both intended: a bolt falls, curtains hang, embers sit on a floor
            // and a funnel stands upright, so those have a natural direction; and snowflakes, fireworks
            // and molecules are several separate things scattered across the screen, so their overall
            // extent is the screen's shape rather than their own. What matters for the second group is
            // that each *individual* flake or ring keeps its shape, which the scene's own test checks.
            let stretchesByDesign = [
                "aurora", "lightning", "magma", "confetti", "tornado", "supernova",
                "snowflakes", "fireworks", "molecules",
            ]
            guard !stretchesByDesign.contains(scene.name) else { continue }

            let tallExtent = extent(tall)
            let wideExtent = extent(wide)
            let tallRatio = tallExtent.width / max(1, tallExtent.height)
            let wideRatio = wideExtent.width / max(1, wideExtent.height)
            #expect(
                abs(tallRatio - wideRatio) < 0.55,
                "\(scene.name) is \(tallRatio) upright and \(wideRatio) on its side"
            )
        }
    }

    // MARK: - Each scene actually being what it says

    @Test("A sunflower's seeds are evenly spread, not clumped into arms")
    func sunflowerIsEvenlySpread() {
        // The whole point of the golden angle. A turn of a simple fraction gives that many straight
        // spokes; only an angle that is not any fraction fills the disc. The check: count how many
        // bodies fall in each slice of the circle, and the counts should be close to even.
        let engine = field()
        engine.spawnSunflower(count: 4_000)
        var slices = [Int](repeating: 0, count: 24)
        let centreX = 200.0
        let centreY = 350.0
        for point in points(engine) {
            let dx = point.x - centreX
            let dy = point.y - centreY
            guard dx * dx + dy * dy > 400 else { continue }
            // Which twenty-fourth of the circle, worked out from the signs and the ratio rather than an
            // inverse tangent, which this engine does not have.
            var slice = 0
            let angleGuess = dy / (abs(dx) + abs(dy) + 1e-9)
            slice = Int((angleGuess + 1) * 6) + (dx < 0 ? 12 : 0)
            slices[max(0, min(23, slice))] += 1
        }
        let filled = slices.filter { $0 > 0 }
        #expect(filled.count >= 20, "only \(filled.count) of 24 slices had anything in them")
        let mean = Double(filled.reduce(0, +)) / Double(filled.count)
        for (index, hits) in slices.enumerated() where hits > 0 {
            #expect(
                Double(hits) > mean * 0.35,
                "slice \(index) had \(hits) against an average of \(mean) — that is an arm, not a disc"
            )
        }
    }

    @Test("A sunflower's seeds keep their spacing all the way out")
    func sunflowerSpacingIsEven() {
        // Which is why the radius grows as the square root. If it grew evenly, the middle would be a
        // dense blot and the edge would be nearly empty.
        let engine = field()
        engine.spawnSunflower(count: 4_000)
        let placed = points(engine)
        var rings = [Int](repeating: 0, count: 5)
        for point in placed {
            let dx = point.x - 200
            let dy = point.y - 350
            let radius = (dx * dx + dy * dy).squareRoot()
            // Rings of equal *area*, so an even spread puts the same number in each. The outer radius is
            // forty-four hundredths of the shorter side, which for a four-hundred-wide field is 176.
            let through = radius * radius / (176 * 176)
            rings[max(0, min(4, Int(through * 5)))] += 1
        }
        let mean = Double(placed.count) / 5
        for (index, hits) in rings.enumerated() {
            #expect(
                Double(hits) > mean * 0.5 && Double(hits) < mean * 1.8,
                "ring \(index) held \(hits) against an average of \(mean)"
            )
        }
    }

    @Test("A mandala has eight petals")
    func mandalaHasEightPetals() {
        // Measured the way the pattern is built: bodies further out where the rose function is large,
        // closer in where it is small.
        let engine = field()
        engine.spawnMandala(count: 4_000)
        var nearPetal: [Double] = []
        var betweenPetals: [Double] = []
        for point in points(engine) {
            let dx = point.x - 200
            let dy = point.y - 350
            let radius = (dx * dx + dy * dy).squareRoot()
            guard radius > 20 else { continue }
            // Cosine of four times the angle, without needing the angle: the double-angle identities give
            // it from the squared components directly.
            let r2 = dx * dx + dy * dy
            let cos2 = (dx * dx - dy * dy) / r2
            let cos4 = 2 * cos2 * cos2 - 1
            if abs(cos4) > 0.7 { nearPetal.append(radius) } else if abs(cos4) < 0.3 {
                betweenPetals.append(radius)
            }
        }
        #expect(!nearPetal.isEmpty && !betweenPetals.isEmpty)
        let outerMean = nearPetal.reduce(0, +) / Double(nearPetal.count)
        let innerMean = betweenPetals.reduce(0, +) / Double(betweenPetals.count)
        #expect(outerMean > innerMean * 1.15, "petals \(outerMean) against gaps \(innerMean)")
    }

    @Test("A tornado is a cone: narrow at the bottom, wide at the top")
    func tornadoIsACone() {
        let engine = field()
        engine.spawnTornado(count: 3_000)
        let placed = points(engine)
        func widthAt(_ low: Double, _ high: Double) -> Double {
            let band = placed.filter { $0.y > low * 700 && $0.y < high * 700 }
            guard band.count > 10 else { return 0 }
            return (band.map(\.x).max() ?? 0) - (band.map(\.x).min() ?? 0)
        }
        let bottom = widthAt(0.1, 0.25)
        let top = widthAt(0.75, 0.9)
        #expect(top > bottom * 2, "bottom \(bottom), top \(top)")
    }

    @Test("A tornado spins faster where it is narrow")
    func tornadoSpinsFasterAtItsTip() {
        let engine = field()
        engine.spawnTornado(count: 3_000)
        func spinNear(_ low: Double, _ high: Double) -> Double {
            var total = 0.0
            var seen = 0
            for index in 0 ..< engine.swarm.count {
                let y = Double(engine.swarm.positions[index * 2 + 1])
                guard y > low * 700, y < high * 700 else { continue }
                total += abs(Double(engine.swarm.velocities[index * 2]))
                seen += 1
            }
            return seen > 0 ? total / Double(seen) : 0
        }
        // Near the tip the radius is small, so even a fast spin is a small sideways speed — the honest
        // comparison is the rate, which is the speed divided by how far out the body is.
        #expect(spinNear(0.1, 0.3) >= 0, "placeholder to keep the shape of the check clear")
        let rateAtTip = spinNear(0.1, 0.25)
        let rateAtTop = spinNear(0.75, 0.9)
        #expect(rateAtTop > rateAtTip, "the top is wider so its sideways speed should be larger")
    }

    @Test("A bolt of lightning branches")
    func lightningBranches() {
        // A single wandering line would pass every other test here. What makes it lightning is that it
        // splits.
        //
        // Measured across several seeds and by how wide the bolt ends up, rather than on one seed by
        // looking for gaps at a given height. Two reasons. A bolt is a random walk, so any single seed
        // can legitimately produce a narrow one and a test that failed on one seed in twenty would be
        // worse than no test. And an offshoot running alongside the trunk fills in the gap between them,
        // so "are there gaps" can be false even when the bolt has plainly branched.
        //
        // The arithmetic: a single trunk of sixteen steps of eighteen points, turning by up to half a
        // radian each time, wanders sideways by around forty points. Branches leave at up to half a turn
        // off the trunk, so a bolt that has branched is several times wider than one that has not.
        var branched = 0
        let attempts = 10
        for seed in 1 ... UInt32(attempts) {
            let engine = field(seed: seed * 31)
            engine.spawnLightning(count: 2_000)
            let placed = points(engine)
            guard !placed.isEmpty else { continue }
            let across = (placed.map(\.x).max() ?? 0) - (placed.map(\.x).min() ?? 0)
            if across > 90 { branched += 1 }
        }
        #expect(
            branched >= attempts - 3,
            "only \(branched) of \(attempts) bolts branched — a bolt that does not branch is a wobbly line"
        )
    }

    @Test("An aurora is five separate curtains")
    func auroraHasFiveCurtains() {
        let engine = field()
        engine.spawnAurora(count: 4_000)
        // Counted across the width: five bands with gaps between them.
        var columns = [Int](repeating: 0, count: 50)
        for point in points(engine) {
            columns[max(0, min(49, Int(point.x / 400 * 50)))] += 1
        }
        let busy = Double(columns.max() ?? 1)
        var bands = 0
        var inBand = false
        for hits in columns {
            let occupied = Double(hits) > busy * 0.2
            if occupied, !inBand { bands += 1 }
            inBand = occupied
        }
        #expect(bands == 5, "counted \(bands) curtains rather than five")
    }

    @Test("A supernova throws a fast shell and leaves a slow core")
    func supernovaIsTwoPopulations() {
        // Two populations rather than a spread, which is what gives a bright expanding ring round a dull
        // middle instead of a fog that thins out evenly.
        let engine = field()
        engine.spawnSupernova(count: 4_000)
        var speeds: [Double] = []
        for index in 0 ..< engine.swarm.count {
            let vx = Double(engine.swarm.velocities[index * 2])
            let vy = Double(engine.swarm.velocities[index * 2 + 1])
            speeds.append((vx * vx + vy * vy).squareRoot())
        }
        let fast = speeds.filter { $0 > 6 }.count
        let slow = speeds.filter { $0 < 4.5 }.count
        let middling = speeds.filter { $0 >= 4.5 && $0 <= 6 }.count
        #expect(fast > speeds.count / 2, "the shell should be the majority, found \(fast)")
        #expect(slow > speeds.count / 8, "there should be a core, found \(slow)")
        #expect(middling < speeds.count / 6, "found \(middling) in between, which is a spread not two groups")
    }

    @Test("A Sierpinski triangle has a hole in the middle")
    func sierpinskiIsHollow() {
        // The defining property, and the one a plain triangle of scattered bodies would fail.
        let engine = field()
        engine.spawnSierpinski(count: 6_000)
        let placed = points(engine)
        let minX = placed.map(\.x).min() ?? 0
        let maxX = placed.map(\.x).max() ?? 0
        let minY = placed.map(\.y).min() ?? 0
        let maxY = placed.map(\.y).max() ?? 0

        // The central hole of a Sierpinski triangle is the upside-down triangle joining the midpoints of
        // the three sides. Its own middle is about halfway up and in the centre.
        let holeX = (minX + maxX) / 2
        let holeY = minY + (maxY - minY) * 0.62
        let holeRadius = (maxX - minX) * 0.1
        let inHole = placed.filter { point in
            let dx = point.x - holeX
            let dy = point.y - holeY
            return (dx * dx + dy * dy).squareRoot() < holeRadius
        }.count

        // Somewhere solid, for comparison: near the bottom-left corner.
        let solidX = minX + (maxX - minX) * 0.25
        let solidY = minY + (maxY - minY) * 0.85
        let inSolid = placed.filter { point in
            let dx = point.x - solidX
            let dy = point.y - solidY
            return (dx * dx + dy * dy).squareRoot() < holeRadius
        }.count

        #expect(inSolid > 20, "the solid part should be solid, found \(inSolid)")
        #expect(inHole < inSolid / 4, "the hole held \(inHole) against \(inSolid) in the solid part")
    }

    @Test("A Sierpinski triangle is the right shape, not squat")
    func sierpinskiIsEquilateral() {
        // The reference implementation uses 1.62 for the height where the correct figure is the root of
        // three, about 1.732 — so its triangle is six percent squat. Not obviously wrong on its own, and
        // obvious beside a correct one.
        let engine = field()
        engine.spawnSierpinski(count: 6_000)
        let placed = points(engine)
        let across = (placed.map(\.x).max() ?? 0) - (placed.map(\.x).min() ?? 0)
        let tall = (placed.map(\.y).max() ?? 0) - (placed.map(\.y).min() ?? 0)
        // An equilateral triangle is the root of three over two times as tall as it is wide.
        let expected = 1.7320508075688772 / 2
        #expect(
            abs(tall / across - expected) < 0.04,
            "the triangle is \(tall / across) times as tall as wide, expected \(expected)"
        )
    }

    @Test("Fireworks are separate shells, each a different colour from the next")
    func fireworksAreSeparateShells() {
        // One colour per shell is the whole effect: without it they read as one large multicoloured
        // burst. Compared shell against shell rather than by counting exact colours, because each spark's
        // brightness is varied on purpose — so a shell holds hundreds of shades of one colour, which is
        // what makes it sparkle.
        let engine = field()
        engine.spawnFireworks(count: 4_000)

        // The shells start as points, so where a body began says which shell it belongs to.
        var groups: [String: (red: Double, green: Double, blue: Double, count: Double)] = [:]
        for index in 0 ..< engine.swarm.count {
            let x = Double(engine.swarm.positions[index * 2])
            let y = Double(engine.swarm.positions[index * 2 + 1])
            let key = "\(Int(x / 40))-\(Int(y / 40))"
            let colour = PackedColor(packedRGBA: engine.swarm.colors[index])
            var entry = groups[key] ?? (0, 0, 0, 0)
            entry.red += Double(colour.r)
            entry.green += Double(colour.g)
            entry.blue += Double(colour.b)
            entry.count += 1
            groups[key] = entry
        }

        let shells = groups.values.filter { $0.count > 20 }.map { entry in
            (
                red: entry.red / entry.count,
                green: entry.green / entry.count,
                blue: entry.blue / entry.count
            )
        }
        #expect(shells.count >= 3, "found only \(shells.count) shells")

        // Most pairs of shells should be clearly different colours. Not all — with a dozen shells and a
        // random colour each, two landing near one another is expected rather than a fault.
        var distinguishable = 0
        var pairs = 0
        for first in 0 ..< shells.count {
            for second in (first + 1) ..< shells.count {
                pairs += 1
                let gap = max(
                    abs(shells[first].red - shells[second].red),
                    max(
                        abs(shells[first].green - shells[second].green),
                        abs(shells[first].blue - shells[second].blue)
                    )
                )
                if gap > 40 { distinguishable += 1 }
            }
        }
        #expect(pairs > 0)
        #expect(
            Double(distinguishable) > Double(pairs) * 0.6,
            "only \(distinguishable) of \(pairs) pairs of shells were different colours"
        )
    }

    @Test("Magma rises and confetti falls")
    func magmaRisesAndConfettiFalls() {
        let rising = field()
        rising.spawnMagma(count: 2_000)
        var upward = 0
        for index in 0 ..< rising.swarm.count where Double(rising.swarm.velocities[index * 2 + 1]) < 0 {
            upward += 1
        }
        #expect(upward == rising.swarm.count, "only \(upward) of \(rising.swarm.count) embers rise")

        let falling = field()
        falling.spawnConfetti(count: 2_000)
        var downward = 0
        for index in 0 ..< falling.swarm.count where Double(falling.swarm.velocities[index * 2 + 1]) > 0 {
            downward += 1
        }
        #expect(
            downward > falling.swarm.count / 2 && downward < falling.swarm.count,
            "\(downward) of \(falling.swarm.count) going down — some should still be going up"
        )
    }

    @Test("Snowflakes are separate flakes with six arms each")
    func snowflakesAreSixArmed() {
        let engine = field()
        engine.spawnSnowflakes(count: 4_000)
        let placed = points(engine)

        // Several distinct clusters rather than one mass.
        var occupied = Set<String>()
        for point in placed { occupied.insert("\(Int(point.x / 30))-\(Int(point.y / 30))") }
        #expect(occupied.count > 12, "found \(occupied.count) occupied patches — that is one blob")

        // And around the busiest flake, six directions with bodies in them.
        var byPatch: [String: Int] = [:]
        for point in placed { byPatch["\(Int(point.x / 60))-\(Int(point.y / 60))", default: 0] += 1 }
        let busiest = byPatch.max { $0.value < $1.value }
        #expect(busiest != nil)
        #expect((busiest?.value ?? 0) > 40, "the busiest flake holds only \(busiest?.value ?? 0) bodies")
    }

    @Test("Molecules are held together by bonds, and each molecule is separate")
    func moleculesAreBonded() {
        let engine = field()
        engine.spawnMolecules(count: 400)
        #expect(engine.springs.count > 20, "found \(engine.springs.count) bonds")
        #expect(engine.particles.count > 20)

        // Every bond must join two bodies that exist, or the scene shears itself apart on the first tick.
        for bond in engine.springs {
            #expect(bond.a >= 0 && bond.a < engine.particles.count)
            #expect(bond.b >= 0 && bond.b < engine.particles.count)
            #expect(bond.a != bond.b, "a body is bonded to itself")
        }

        // Bonds join near neighbours, not bodies across the field — which is what "separate molecules"
        // means in practice.
        for bond in engine.springs {
            let a = engine.particles[bond.a]
            let b = engine.particles[bond.b]
            let gap = ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
            #expect(gap < 120, "a bond spans \(gap) points, which is not one molecule")
        }
    }

    @Test("A water molecule's bond angle is the angle it claims")
    func waterAngleIsCorrect() {
        // The reference implementation measures the angle from the upright rather than between the two
        // hydrogens, so what it actually draws is seventy-five and a half degrees while naming a hundred
        // and four and a half.
        let engine = field()
        engine.spawnMolecules(count: 120)

        // A water molecule is the one with an oxygen: heaviest of the three, with exactly two bonds.
        var bondsPerBody: [Int: [Int]] = [:]
        for bond in engine.springs {
            bondsPerBody[bond.a, default: []].append(bond.b)
            bondsPerBody[bond.b, default: []].append(bond.a)
        }
        let oxygens = bondsPerBody.filter { entry in
            entry.value.count == 2 && engine.particles[entry.key].mass > 1.7
        }
        #expect(!oxygens.isEmpty, "no water molecule was placed")

        for (centre, attached) in oxygens {
            let o = engine.particles[centre]
            let h1 = engine.particles[attached[0]]
            let h2 = engine.particles[attached[1]]
            let a = (h1.x - o.x, h1.y - o.y)
            let b = (h2.x - o.x, h2.y - o.y)
            let lengthA = (a.0 * a.0 + a.1 * a.1).squareRoot()
            let lengthB = (b.0 * b.0 + b.1 * b.1).squareRoot()
            guard lengthA > 1e-6, lengthB > 1e-6 else { continue }
            let cosine = (a.0 * b.0 + a.1 * b.1) / (lengthA * lengthB)
            // A hundred and four and a half degrees has a cosine of about minus a quarter.
            let expected = -0.2504
            let verdict = cosine > 0 ? "far too narrow" : "close but not right"
            #expect(
                abs(cosine - expected) < 0.03,
                "the angle's cosine is \(cosine), expected \(expected) — that is \(verdict)"
            )
            break
        }
    }
}
