import Testing

@testable import CrucibleCore

/// What drives the palette: the number between nought and one that each colour mode produces.
struct ParticleMetricTests {
    /// A field with one body placed and set up exactly, so each metric has a definite right answer.
    private func engine(
        mode: ParticleColorMode,
        x: Double = 200,
        y: Double = 150,
        velocityX: Double = 0,
        velocityY: Double = 0,
        charge: Double = 0
    ) -> (ParticleEngine, ParticleObject) {
        let field = ParticleEngine(width: 400, height: 300, seed: 7)
        field.colorMode = mode
        field.paletteEnabled = true
        field.addParticle(
            x: x, y: y, velocityX: velocityX, velocityY: velocityY, radius: 2, charge: charge
        )
        return (field, field.particles[0])
    }

    // MARK: - Each metric

    @Test("Speed runs from nought to one and saturates where the hue version did")
    func speedMetric() {
        // Twelve, because the hue version ran 240 degrees down by twenty per unit and clamped at
        // nought, which is reached at exactly twelve. Switching a palette on should not also change
        // what the field considers fast.
        let (still, stillBody) = engine(mode: .velocity)
        #expect(still.paletteMetric(of: stillBody, density: nil) == 0)

        let (half, halfBody) = engine(mode: .velocity, velocityX: 6, velocityY: 0)
        #expect(abs(half.paletteMetric(of: halfBody, density: nil) - 0.5) < 1e-12)

        let (full, fullBody) = engine(mode: .velocity, velocityX: 12, velocityY: 0)
        #expect(full.paletteMetric(of: fullBody, density: nil) == 1)

        let (over, overBody) = engine(mode: .velocity, velocityX: 400, velocityY: 300)
        #expect(over.paletteMetric(of: overBody, density: nil) == 1, "clamped, not wrapped")
    }

    @Test("Neutral charge sits in the middle of the ramp")
    func chargeMetric() {
        // So a ramp running cool to warm reads the way the blue-white-red version did.
        let (neutral, neutralBody) = engine(mode: .charge, charge: 0)
        #expect(neutral.paletteMetric(of: neutralBody, density: nil) == 0.5)

        let (positive, positiveBody) = engine(mode: .charge, charge: 1)
        #expect(positive.paletteMetric(of: positiveBody, density: nil) == 1)

        let (negative, negativeBody) = engine(mode: .charge, charge: -1)
        #expect(negative.paletteMetric(of: negativeBody, density: nil) == 0)

        let (extreme, extremeBody) = engine(mode: .charge, charge: -400)
        #expect(extreme.paletteMetric(of: extremeBody, density: nil) == 0)
    }

    @Test("Position is measured outward from the centre of the world")
    func positionMetric() {
        // The hue version swept diagonally across the field, which reads as a gradient laid over
        // the scene. Radial reads as belonging to it, and every scene in this half of the app is
        // built around a centre.
        let (centre, centreBody) = engine(mode: .rainbow, x: 200, y: 150)
        #expect(centre.paletteMetric(of: centreBody, density: nil) == 0)

        // The reach is half the shorter side: 150 in a 400 by 300 world.
        let (edge, edgeBody) = engine(mode: .rainbow, x: 350, y: 150)
        #expect(abs(edge.paletteMetric(of: edgeBody, density: nil) - 1) < 1e-12)

        let (halfway, halfwayBody) = engine(mode: .rainbow, x: 275, y: 150)
        #expect(abs(halfway.paletteMetric(of: halfwayBody, density: nil) - 0.5) < 1e-12)

        let (corner, cornerBody) = engine(mode: .rainbow, x: 0, y: 0)
        #expect(corner.paletteMetric(of: cornerBody, density: nil) == 1, "the corners clamp")
    }

    @Test("A body with no lifetime reads as full rather than as about to die")
    func lifespanMetric() {
        let (immortal, immortalBody) = engine(mode: .lifespan)
        #expect(immortal.paletteMetric(of: immortalBody, density: nil) == 1)

        var dying = immortalBody
        dying.maxLife = 100
        dying.lifespan = 25
        #expect(abs(immortal.paletteMetric(of: dying, density: nil) - 0.25) < 1e-12)

        var gone = immortalBody
        gone.maxLife = 100
        gone.lifespan = 0
        #expect(immortal.paletteMetric(of: gone, density: nil) == 0)
    }

    @Test("Crowding spreads across the ramp instead of saturating immediately")
    func crowdingMetric() {
        // The hue version saturated at eleven bodies in a cell, so on a busy field almost
        // everything sat at the end of the range and the mode stopped telling anything apart.
        let field = ParticleEngine(width: 400, height: 300, seed: 7)
        field.colorMode = .density
        field.paletteEnabled = true
        for _ in 0 ..< 20 {
            field.addParticle(x: 100, y: 100, velocityX: 0, velocityY: 0, radius: 2, charge: 0)
        }
        let grid = field.densityGridIfNeeded()
        #expect(grid != nil, "crowding mode must build the grid")
        let metric = field.paletteMetric(of: field.particles[0], density: grid)
        #expect(abs(metric - 0.5) < 1e-12, "twenty in a cell is halfway to the ceiling of forty")
    }

    // MARK: - The fixed position per body

    @Test("A body's own colour becomes a fixed position, the same every time")
    func stablePhaseIsStable() {
        for identifier in [0, 1, 2, 7, 100, 9999, -3, Int.max] {
            let first = ParticleEngine.stablePhase(forIdentifier: identifier)
            #expect(first >= 0 && first < 1, "identifier \(identifier) produced \(first)")
            for _ in 0 ..< 4 {
                #expect(ParticleEngine.stablePhase(forIdentifier: identifier) == first)
            }
        }
    }

    @Test("Consecutive bodies get scattered positions, not neighbouring ones")
    func stablePhaseIsScattered() {
        // Identifiers are handed out in order. A palette driven by a counter paints the field in
        // bands that march across it as bodies spawn, which looks like a fault. The mix is what
        // stops that, so it is worth checking that it actually mixes.
        let phases = (0 ..< 64).map { ParticleEngine.stablePhase(forIdentifier: $0) }
        var adjacent = 0
        for index in 1 ..< phases.count where abs(phases[index] - phases[index - 1]) < 0.02 {
            adjacent += 1
        }
        #expect(adjacent <= 4, "\(adjacent) of 63 consecutive identifiers landed close together")

        // And the whole range gets used, rather than everything piling into one part of the ramp.
        var buckets = [Int](repeating: 0, count: 4)
        for phase in phases { buckets[min(3, Int(phase * 4))] += 1 }
        for (quarter, hits) in buckets.enumerated() {
            #expect(hits > 0, "nothing landed in quarter \(quarter) of the ramp")
        }
    }

    // MARK: - How it joins up with the drawing

    @Test("With no palette the six original looks are untouched")
    func paletteOffLeavesTheOriginalLooks() {
        // The comparison against the reference implementation measures those six. If switching a
        // palette on were the default, that comparison would be measuring something else.
        let field = ParticleEngine(width: 400, height: 300, seed: 7)
        #expect(!field.paletteEnabled, "palettes must be off unless asked for")

        field.addParticle(x: 100, y: 100, velocityX: 3, velocityY: 4, radius: 2, charge: 1)
        for mode in ParticleColorMode.allCases {
            field.colorMode = mode
            field.paletteEnabled = false
            let original = field.renderColor(of: field.particles[0], density: field.densityGridIfNeeded())
            field.paletteEnabled = true
            let withPalette = field.renderColor(of: field.particles[0], density: field.densityGridIfNeeded())
            #expect(original != withPalette, "\(mode.rawValue) looks the same either way")
        }
    }

    @Test("Each mode drives the palette to a different place")
    func modesDriveThePaletteDifferently() {
        // The whole point of separating the metric from the colours: six meanings, one set of
        // colours, six different pictures. If two modes produced the same number the interface
        // would be offering a choice that does nothing — which is exactly what the crowding mode
        // did before it was fixed.
        let field = ParticleEngine(width: 400, height: 300, seed: 7)
        field.paletteEnabled = true
        field.palette = ParticlePaletteSpec(palette: .rainbow)
        field.addParticle(x: 120, y: 90, velocityX: 5, velocityY: 2, radius: 2, charge: -0.4)
        var body = field.particles[0]
        body.maxLife = 60
        body.lifespan = 21
        field.particles[0] = body

        var seen: [String: String] = [:]
        for mode in ParticleColorMode.allCases {
            field.colorMode = mode
            let metric = field.paletteMetric(of: body, density: field.densityGridIfNeeded())
            let key = "\(Int(metric * 1000))"
            if let twin = seen[key] {
                Issue.record("\(mode.rawValue) drives the palette to the same place as \(twin)")
            }
            seen[key] = mode.rawValue
        }
    }

    @Test("The colours handed to the GPU match the palette, mode by mode")
    func gpuColoursFollowThePalette() {
        let field = ParticleEngine(width: 400, height: 300, seed: 7)
        field.paletteEnabled = true
        field.palette = ParticlePaletteSpec(palette: .plasma, tint: PackedColor(r: 255, g: 200, b: 160))
        for index in 0 ..< 12 {
            field.addParticle(
                x: Double(index) * 30,
                y: Double(index) * 20,
                velocityX: Double(index),
                velocityY: 1,
                radius: 2,
                charge: Double(index % 3) - 1
            )
        }

        for mode in ParticleColorMode.allCases {
            field.colorMode = mode
            var colors: [UInt32] = []
            field.fillRenderColors(into: &colors)
            let grid = field.densityGridIfNeeded()
            for (index, body) in field.particles.enumerated() {
                let expected = field.palette.sample(field.paletteMetric(of: body, density: grid))
                #expect(colors[index] == expected.packedRGBA, "\(mode.rawValue), body \(index)")
            }
        }
    }

    @Test("An unusable body still gets a colour under every mode")
    func corruptBodiesStillGetAColour() {
        let field = ParticleEngine(width: 400, height: 300, seed: 7)
        field.paletteEnabled = true
        field.addParticle(x: .nan, y: .infinity, velocityX: .nan, velocityY: -.infinity, radius: 2, charge: .nan)
        var body = field.particles[0]
        body.maxLife = 0
        field.particles[0] = body

        for mode in ParticleColorMode.allCases {
            field.colorMode = mode
            let metric = field.paletteMetric(of: body, density: field.densityGridIfNeeded())
            #expect(metric.isFinite, "\(mode.rawValue) produced \(metric)")
            #expect(metric >= 0 && metric <= 1, "\(mode.rawValue) produced \(metric)")
        }
    }

    // MARK: - The swarm

    @Test("Only the modes that actually move ask for repainting every frame")
    func dynamicModesAreIdentified() {
        // With up to a million bodies, the difference between repainting every frame and repainting
        // when something changes is the entire cost of the feature.
        let field = ParticleEngine(width: 400, height: 300, seed: 7)
        field.paletteEnabled = false
        for mode in ParticleColorMode.allCases {
            field.colorMode = mode
            #expect(!field.swarmColorsAreDynamic, "nothing repaints with palettes off")
        }

        field.paletteEnabled = true
        let expected: [ParticleColorMode: Bool] = [
            .velocity: true, .density: true, .rainbow: true,
            .native: false, .charge: false, .lifespan: false,
        ]
        for (mode, shouldMove) in expected {
            field.colorMode = mode
            #expect(field.swarmColorsAreDynamic == shouldMove, "\(mode.rawValue)")
        }
    }

    @Test("Repainting the swarm actually changes its colours")
    func swarmGetsRepainted() {
        let field = ParticleEngine(width: 400, height: 300, seed: 7)
        field.setMaxParticles(50_000)
        field.spawnBatch(count: 8_000, color: PackedColor(r: 255, g: 255, b: 255))
        #expect(field.swarm.count > 0, "the batch should have gone to the swarm")

        let before = (0 ..< 32).map { field.swarm.colors[$0] }
        field.paletteEnabled = true
        field.colorMode = .rainbow
        field.palette = ParticlePaletteSpec(palette: .ice)
        field.recolorSwarm()
        let after = (0 ..< 32).map { field.swarm.colors[$0] }

        #expect(before != after, "the swarm kept its old colours")
        for entry in after {
            #expect(PackedColor(packedRGBA: entry).a == 255, "a repainted body must stay opaque")
        }
    }

    @Test("Repainting the swarm by position matches what a single body would get")
    func swarmMatchesTheObjectPath() {
        // The two paths are separate code — one walks the swarm's buffers, one is called per object
        // — and they must agree, or the same field would be two different colours depending on
        // which store a body happened to land in.
        let field = ParticleEngine(width: 400, height: 300, seed: 7)
        field.setMaxParticles(50_000)
        field.spawnBatch(count: 5_000, color: PackedColor(r: 255, g: 255, b: 255))
        field.paletteEnabled = true
        field.colorMode = .rainbow
        field.palette = ParticlePaletteSpec(palette: .solar)

        let table = field.palette.bakeLookup()
        field.recolorSwarm(using: table)

        let reach = max(1e-4, 0.5 * min(field.width, field.height))
        for index in stride(from: 0, to: min(field.swarm.count, 400), by: 37) {
            let x = Double(field.swarm.positions[index * 2])
            let y = Double(field.swarm.positions[index * 2 + 1])
            let dx = x - field.width * 0.5
            let dy = y - field.height * 0.5
            let metric = max(0, min(1, (dx * dx + dy * dy).squareRoot() / reach))
            // The swarm path rounds to the nearest table entry rather than sampling exactly, so the
            // comparison allows one entry of slack — a quarter of a percent of the ramp.
            let expected = field.palette.sample(metric)
            let actual = PackedColor(packedRGBA: field.swarm.colors[index])
            let gap = max(
                abs(Int(actual.r) - Int(expected.r)),
                max(abs(Int(actual.g) - Int(expected.g)), abs(Int(actual.b) - Int(expected.b)))
            )
            #expect(gap <= 4, "body \(index): swarm says \(actual), object path says \(expected)")
        }
    }

    @Test("Repainting an empty swarm does nothing and does not fall over")
    func emptySwarmIsSafe() {
        let field = ParticleEngine(width: 400, height: 300, seed: 7)
        field.paletteEnabled = true
        field.recolorSwarm()
        field.recolorSwarm(using: [])
        #expect(field.swarm.count == 0)
    }
}
