import Foundation
import Testing

@testable import CrucibleCore

/// The two switches that were wired to nothing: the liquid, and the pull between bodies.
///
/// Both of these are approximations with invented coefficients, so the tests do not check numbers
/// against a formula — they check that the thing behaves like the thing it claims to be. A liquid must
/// resist being squashed, hold a surface, and settle. A pull must pull, must fall off with distance, and
/// must treat heavy and light alike.
struct SwarmForcesTests {
    /// A swarm with bodies placed exactly, rather than scattered, so the tests have known answers.
    private func swarm(_ points: [(Double, Double)]) -> Swarm {
        let result = Swarm()
        var rng = Mulberry32(seed: 1)
        result.spawn(
            count: points.count,
            width: 400,
            height: 700,
            color: 0xFFFF_FFFF,
            budget: 10_000,
            rng: &rng
        )
        for (index, point) in points.enumerated() {
            result.positions[index * 2] = Float(point.0)
            result.positions[index * 2 + 1] = Float(point.1)
            result.velocities[index * 2] = 0
            result.velocities[index * 2 + 1] = 0
        }
        return result
    }

    /// A grid of bodies at a given spacing, which is the case the crowding figure has a right answer for.
    private func lattice(spacing: Double, across: Int, centredAt centre: (Double, Double)) -> [(Double, Double)] {
        var points: [(Double, Double)] = []
        let half = Double(across - 1) / 2
        for row in 0 ..< across {
            for column in 0 ..< across {
                points.append((
                    centre.0 + (Double(column) - half) * spacing,
                    centre.1 + (Double(row) - half) * spacing
                ))
            }
        }
        return points
    }

    // MARK: - The liquid

    @Test("Crowding comes out as mass per unit area, which is what makes the setting mean something")
    func crowdingIsMassPerArea() {
        // The whole practical benefit of normalising the weighting properly. At a spacing of five pixels
        // there is one body per twenty-five square pixels, so the crowding should read about four
        // hundredths — and the rest-crowding setting is in the same units, so asking for a spacing is
        // the same as asking for a number.
        //
        // The reference implementation's weighting adds up to two thirds rather than one, so its
        // equivalent reading would be two thirds of this and its rest setting is a figure with no
        // meaning.
        let spacing = 5.0
        let field = swarm(lattice(spacing: spacing, across: 21, centredAt: (200, 350)))
        let fluid = SwarmFluid()
        fluid.step(swarm: field, settings: .default, width: 400, height: 700)

        // The middle of the lattice, where the neighbourhood is full on every side.
        let middle = 21 * 10 + 10
        let measured = fluid.crowding(at: middle)
        let expected = 1 / (spacing * spacing)
        #expect(
            abs(measured - expected) / expected < 0.06,
            "read \(measured) where \(expected) was expected"
        )
    }

    @Test("Crowding follows the spacing, in the right direction")
    func crowdingTracksSpacing() {
        var readings: [Double] = []
        for spacing in [4.0, 6.0, 9.0] {
            let field = swarm(lattice(spacing: spacing, across: 21, centredAt: (200, 350)))
            let fluid = SwarmFluid()
            fluid.step(swarm: field, settings: .default, width: 400, height: 700)
            readings.append(fluid.crowding(at: 21 * 10 + 10))
        }
        #expect(readings[0] > readings[1], "closer together must read as more crowded")
        #expect(readings[1] > readings[2])
        // And roughly by the square of the spacing, since that is what area means.
        #expect(abs(readings[0] / readings[1] - 36.0 / 16.0) < 0.35)
    }

    @Test("A squashed liquid pushes itself apart")
    func compressedFluidExpands() {
        // The one thing a liquid has to do.
        let spacing = 2.5
        let points = lattice(spacing: spacing, across: 15, centredAt: (200, 350))
        let field = swarm(points)
        let fluid = SwarmFluid()

        func spread() -> Double {
            var total = 0.0
            for index in 0 ..< field.count {
                let dx = Double(field.positions[index * 2]) - 200
                let dy = Double(field.positions[index * 2 + 1]) - 350
                total += (dx * dx + dy * dy).squareRoot()
            }
            return total / Double(field.count)
        }

        let before = spread()
        for _ in 0 ..< 30 {
            fluid.step(swarm: field, settings: .default, width: 400, height: 700)
            field.step(Swarm.StepOptions(
                width: 400, height: 700, gravityX: 0, gravityY: 0,
                damping: 0.99, elasticity: 0.5, collide: false, maxSpeed: 30,
                boundaryMode: .bounce
            ))
        }
        let after = spread()
        #expect(after > before * 1.15, "spread went from \(before) to \(after)")
    }

    @Test("A liquid at its happy spacing stays roughly where it is")
    func restingFluidIsQuiet() {
        // The counterpart. A liquid that pushed itself apart at its own rest crowding would never settle,
        // and the rest setting would be decoration.
        let field = swarm(lattice(spacing: 5, across: 15, centredAt: (200, 350)))
        let fluid = SwarmFluid()

        func spread() -> Double {
            var total = 0.0
            for index in 0 ..< field.count {
                let dx = Double(field.positions[index * 2]) - 200
                let dy = Double(field.positions[index * 2 + 1]) - 350
                total += (dx * dx + dy * dy).squareRoot()
            }
            return total / Double(field.count)
        }

        let before = spread()
        for _ in 0 ..< 40 {
            fluid.step(swarm: field, settings: .default, width: 400, height: 700)
            field.step(Swarm.StepOptions(
                width: 400, height: 700, gravityX: 0, gravityY: 0,
                damping: 0.99, elasticity: 0.5, collide: false, maxSpeed: 30,
                boundaryMode: .bounce
            ))
        }
        let after = spread()
        #expect(abs(after - before) / before < 0.35, "spread went from \(before) to \(after)")
    }

    @Test("Turning the stiffness up pushes harder")
    func stiffnessMatters() {
        func spreadAfter(stiffness: Double) -> Double {
            let field = swarm(lattice(spacing: 2.5, across: 13, centredAt: (200, 350)))
            let fluid = SwarmFluid()
            var settings = SwarmFluid.Settings.default
            settings.stiffness = stiffness
            for _ in 0 ..< 20 {
                fluid.step(swarm: field, settings: settings, width: 400, height: 700)
                field.step(Swarm.StepOptions(
                    width: 400, height: 700, gravityX: 0, gravityY: 0,
                    damping: 0.99, elasticity: 0.5, collide: false, maxSpeed: 30,
                    boundaryMode: .bounce
                ))
            }
            var total = 0.0
            for index in 0 ..< field.count {
                let dx = Double(field.positions[index * 2]) - 200
                let dy = Double(field.positions[index * 2 + 1]) - 350
                total += (dx * dx + dy * dy).squareRoot()
            }
            return total / Double(field.count)
        }

        #expect(spreadAfter(stiffness: 4) > spreadAfter(stiffness: 0.4))
        // And at no stiffness the push apart is gone entirely, so the only thing left is the pull
        // together — which should not expand it.
        #expect(spreadAfter(stiffness: 0) < spreadAfter(stiffness: 2))
    }

    @Test("Thickness slows neighbours toward one another's speed")
    func viscosityEvensOutSpeeds() {
        // What makes it read as water rather than as a gas.
        func spreadOfSpeeds(viscosity: Double) -> Double {
            let field = swarm(lattice(spacing: 6, across: 11, centredAt: (200, 350)))
            // One half thrown one way, the other half the other.
            for index in 0 ..< field.count {
                field.velocities[index * 2] = index < field.count / 2 ? 4 : -4
            }
            let fluid = SwarmFluid()
            var settings = SwarmFluid.Settings.default
            settings.viscosity = viscosity
            settings.stiffness = 0
            settings.cohesion = 0
            for _ in 0 ..< 6 {
                fluid.step(swarm: field, settings: settings, width: 400, height: 700)
            }
            var total = 0.0
            for index in 0 ..< field.count { total += abs(Double(field.velocities[index * 2])) }
            return total / Double(field.count)
        }

        let thick = spreadOfSpeeds(viscosity: 0.6)
        let thin = spreadOfSpeeds(viscosity: 0)
        #expect(thick < thin, "thick \(thick) should be more evened out than thin \(thin)")
        #expect(thin > 3.9, "with no thickness nothing should have changed")
    }

    @Test("The pull together acts at the surface and not in the middle")
    func cohesionActsAtTheSurface() {
        // If it acted everywhere it would just add to the pressure it is fighting, and the two would
        // cancel into a slightly stiffer liquid rather than into a surface. The test: the outermost
        // bodies of a blob should be drawn inward, the middle ones should barely move.
        let points = lattice(spacing: 5, across: 15, centredAt: (200, 350))
        let field = swarm(points)
        let fluid = SwarmFluid()
        var settings = SwarmFluid.Settings.default
        settings.cohesion = 1.2
        settings.stiffness = 0
        fluid.step(swarm: field, settings: settings, width: 400, height: 700)

        // A corner body, which has neighbours on two sides only.
        let corner = 0
        let cornerDX = Double(field.velocities[corner * 2])
        let cornerDY = Double(field.velocities[corner * 2 + 1])
        let cornerInward = cornerDX > 0 && cornerDY > 0

        // A middle body, surrounded.
        let middle = 15 * 7 + 7
        let middleSpeed = (
            Double(field.velocities[middle * 2]) * Double(field.velocities[middle * 2])
                + Double(field.velocities[middle * 2 + 1]) * Double(field.velocities[middle * 2 + 1])
        ).squareRoot()

        #expect(cornerInward, "the corner should be drawn inward, not (\(cornerDX), \(cornerDY))")
        let cornerSpeed = (cornerDX * cornerDX + cornerDY * cornerDY).squareRoot()
        #expect(middleSpeed < cornerSpeed * 0.3, "the middle moved \(middleSpeed), the corner \(cornerSpeed)")
    }

    @Test("Every push apart has an equal and opposite one")
    func pressureIsSymmetric() {
        // The reference implementation divides both halves of the pair by the neighbour's crowding, so
        // the two get different amounts and the liquid invents momentum — it drifts, and it heats up.
        // Here the total momentum handed out by the push apart should be nought.
        let field = swarm(lattice(spacing: 3, across: 12, centredAt: (200, 350)))
        let fluid = SwarmFluid()
        var settings = SwarmFluid.Settings.default
        settings.viscosity = 0
        settings.cohesion = 0
        fluid.step(swarm: field, settings: settings, width: 400, height: 700)

        var totalX = 0.0
        var totalY = 0.0
        var magnitude = 0.0
        for index in 0 ..< field.count {
            let vx = Double(field.velocities[index * 2])
            let vy = Double(field.velocities[index * 2 + 1])
            totalX += vx
            totalY += vy
            magnitude += (vx * vx + vy * vy).squareRoot()
        }
        #expect(magnitude > 0.01, "the push apart should have done something")
        let drift = (totalX * totalX + totalY * totalY).squareRoot()
        #expect(drift < magnitude * 0.02, "the liquid drifted by \(drift) out of \(magnitude)")
    }

    @Test("The liquid says when it is past what it can represent")
    func overcrowdingIsReported() {
        // Rather than quietly under-counting, which does not gently lose accuracy — it makes the liquid
        // read as thinner than it is and stop holding itself apart.
        let sparse = swarm(lattice(spacing: 8, across: 10, centredAt: (200, 350)))
        let fluid = SwarmFluid()
        fluid.step(swarm: sparse, settings: .default, width: 400, height: 700)
        #expect(!fluid.isOverCrowded, "a sparse liquid should not be complaining")

        let packed = swarm(Array(repeating: (200.0, 350.0), count: 400))
        fluid.step(swarm: packed, settings: .default, width: 400, height: 700)
        #expect(fluid.isOverCrowded, "four hundred bodies in one spot is past the limit")
    }

    @Test("Bodies with unusable positions cannot poison the liquid")
    func fluidSurvivesCorruptBodies() {
        var points = lattice(spacing: 5, across: 9, centredAt: (200, 350))
        points.append((.nan, .nan))
        points.append((.infinity, 10))
        let field = swarm(points)
        field.velocities[0] = .nan

        let fluid = SwarmFluid()
        for _ in 0 ..< 5 {
            fluid.step(swarm: field, settings: .default, width: 400, height: 700)
        }

        // The good bodies must still be good. One body that has gone wrong must not spread.
        var usable = 0
        for index in 2 ..< field.count {
            let x = Double(field.positions[index * 2])
            let vx = Double(field.velocities[index * 2])
            if x.isFinite, vx.isFinite { usable += 1 }
        }
        #expect(usable >= field.count - 4, "only \(usable) of \(field.count) bodies survived")
    }

    @Test("Nonsense settings are pulled into range rather than breaking the liquid")
    func fluidSettingsAreSanitized() {
        let field = swarm(lattice(spacing: 5, across: 9, centredAt: (200, 350)))
        let fluid = SwarmFluid()
        for settings in [
            SwarmFluid.Settings(smoothing: .nan, restDensity: .nan, stiffness: .nan, viscosity: .nan, cohesion: .nan),
            SwarmFluid.Settings(smoothing: -50, restDensity: -1, stiffness: -5, viscosity: -1, cohesion: -1),
            SwarmFluid.Settings(smoothing: 1e9, restDensity: 1e9, stiffness: 1e9, viscosity: 1e9, cohesion: 1e9),
        ] {
            fluid.step(swarm: field, settings: settings, width: 400, height: 700)
            for index in 0 ..< field.count {
                #expect(Double(field.positions[index * 2]).isFinite)
                #expect(Double(field.velocities[index * 2]).isFinite)
            }
        }
    }

    @Test("One body, or none, is not a liquid and does not fall over")
    func fluidHandlesTinySwarms() {
        let fluid = SwarmFluid()
        let empty = Swarm()
        fluid.step(swarm: empty, settings: .default, width: 400, height: 700)
        #expect(!fluid.isOverCrowded)

        let single = swarm([(200, 350)])
        fluid.step(swarm: single, settings: .default, width: 400, height: 700)
        #expect(Double(single.velocities[0]) == 0, "a lone body has nothing to push against")
    }

    // MARK: - The pull between bodies

    @Test("Two bodies are drawn toward each other")
    func gravityPulls() {
        let field = swarm([(100, 350), (300, 350)])
        let gravity = SwarmGravity()
        gravity.step(swarm: field, settings: .default, width: 400, height: 700)

        #expect(Double(field.velocities[0]) > 0, "the left body should move right")
        #expect(Double(field.velocities[2]) < 0, "the right body should move left")
        #expect(abs(Double(field.velocities[1])) < 1e-6, "and neither should move vertically")
    }

    @Test("The pull falls off with distance")
    func gravityFallsOffWithDistance() {
        func pullAtSeparation(_ gap: Double) -> Double {
            let field = swarm([(200 - gap / 2, 350), (200 + gap / 2, 350)])
            let gravity = SwarmGravity()
            gravity.step(swarm: field, settings: .default, width: 400, height: 700)
            return abs(Double(field.velocities[0]))
        }
        let close = pullAtSeparation(30)
        let far = pullAtSeparation(120)
        #expect(close > far * 4, "close \(close) against far \(far)")
    }

    @Test("Heavy and light fall alike")
    func gravityIgnoresTheMassOfWhatIsPulled() {
        // The reference implementation multiplies by the pulled body's own mass and never divides it out,
        // so in its version a heavy body accelerates faster in the same field — which is the opposite of
        // the single most famous fact about gravity.
        //
        // The swarm holds no mass of its own, so what this checks is that two bodies in the same place
        // feel exactly the same pull from a distant clump, with nothing about them entering into it.
        var points = lattice(spacing: 6, across: 9, centredAt: (320, 600))
        points.append((80, 120))
        points.append((80.0001, 120))
        let field = swarm(points)
        let gravity = SwarmGravity()
        gravity.step(swarm: field, settings: .default, width: 400, height: 700)

        let first = field.count - 2
        let second = field.count - 1
        let dx = abs(Double(field.velocities[first * 2]) - Double(field.velocities[second * 2]))
        #expect(dx < 1e-4, "two bodies in the same place felt different pulls, differing by \(dx)")
    }

    @Test("A body is not pulled toward itself")
    func gravityExcludesTheBodyItself() {
        // The reference implementation leaves a body's own mass in its own square's lump, so every body
        // is attracted to where it already is. A single body in an empty world is the test: it should
        // not move at all.
        let field = swarm([(137, 421)])
        let gravity = SwarmGravity()
        for _ in 0 ..< 5 {
            gravity.step(swarm: field, settings: .default, width: 400, height: 700)
        }
        #expect(Double(field.velocities[0]) == 0)
        #expect(Double(field.velocities[1]) == 0)
    }

    @Test("A distant clump pulls about as hard as its bodies would one at a time")
    func theApproximationIsCloseEnough() {
        // The whole trick is treating a far-off clump as a single lump at its centre of mass. This is the
        // check that the shortcut is worth having: the same clump, felt as a lump, should pull within a
        // few percent of what it pulls one body at a time.
        let clump = lattice(spacing: 4, across: 7, centredAt: (330, 180))
        let target = (70.0, 600.0)

        let field = swarm(clump + [target])
        let gravity = SwarmGravity()
        gravity.step(swarm: field, settings: .default, width: 400, height: 700)
        let approximate = (
            Double(field.velocities[clump.count * 2]),
            Double(field.velocities[clump.count * 2 + 1])
        )

        // Worked out the long way, for comparison.
        var exactX = 0.0
        var exactY = 0.0
        let settings = SwarmGravity.Settings.default
        for point in clump {
            let dx = point.0 - target.0
            let dy = point.1 - target.1
            let distanceSquared = dx * dx + dy * dy + settings.softening * settings.softening
            let scale = settings.strength / (distanceSquared * distanceSquared.squareRoot())
            exactX += dx * scale
            exactY += dy * scale
        }

        let exactMagnitude = (exactX * exactX + exactY * exactY).squareRoot()
        let gap = (
            (approximate.0 - exactX) * (approximate.0 - exactX)
                + (approximate.1 - exactY) * (approximate.1 - exactY)
        ).squareRoot()
        #expect(
            gap < exactMagnitude * 0.05,
            "the shortcut was off by \(gap / exactMagnitude * 100) percent"
        )
    }

    @Test("Turning the strength to nothing does nothing at all")
    func gravityRespectsItsStrength() {
        let field = swarm(lattice(spacing: 20, across: 5, centredAt: (200, 350)))
        let gravity = SwarmGravity()
        gravity.step(
            swarm: field,
            settings: SwarmGravity.Settings(strength: 0, softening: 8),
            width: 400,
            height: 700
        )
        for index in 0 ..< field.count {
            #expect(Double(field.velocities[index * 2]) == 0)
        }
    }

    @Test("Two bodies on top of one another are not flung apart")
    func gravitySoftensCloseEncounters() {
        // Without the softening, two bodies that touch feel an unbounded pull and leave at a speed that
        // has nothing to do with anything.
        let field = swarm([(200, 350), (200.0001, 350)])
        let gravity = SwarmGravity()
        for _ in 0 ..< 20 {
            gravity.step(swarm: field, settings: .default, width: 400, height: 700)
        }
        for index in 0 ..< field.count {
            let speed = abs(Double(field.velocities[index * 2]))
            #expect(speed.isFinite && speed < 50, "body \(index) reached \(speed)")
        }
    }

    @Test("Bodies with unusable positions cannot poison the pull")
    func gravitySurvivesCorruptBodies() {
        var points = lattice(spacing: 12, across: 6, centredAt: (200, 350))
        points.append((.nan, 3))
        points.append((10, .infinity))
        let field = swarm(points)
        let gravity = SwarmGravity()
        for _ in 0 ..< 4 {
            gravity.step(swarm: field, settings: .default, width: 400, height: 700)
        }
        for index in 0 ..< 36 {
            #expect(Double(field.velocities[index * 2]).isFinite, "body \(index)")
        }
    }

    // MARK: - Joined up with the engine

    @Test("The two switches actually do something now")
    func theSwitchesAreWiredUp() {
        // These were reserved for a long time: the interface showed them, scenes saved them, clearing the
        // field reset them, and no physics read either one. This is the test that says they are connected.
        for mode in ["fluid", "gravity"] {
            let field = ParticleEngine(width: 400, height: 700, seed: 5)
            field.setMaxParticles(20_000)
            field.gravityX = 0
            field.gravityY = 0
            field.collisionsEnabled = false
            field.spawnBatch(count: 6_000, color: PackedColor(r: 255, g: 255, b: 255))
            #expect(field.swarm.count > 0)

            func snapshotPositions() -> [Float] {
                (0 ..< min(200, field.swarm.count)).map { field.swarm.positions[$0 * 2] }
            }

            // Off first, as the reference point.
            let before = snapshotPositions()
            for _ in 0 ..< 3 { field.step() }
            let withoutIt = snapshotPositions()

            let again = ParticleEngine(width: 400, height: 700, seed: 5)
            again.setMaxParticles(20_000)
            again.gravityX = 0
            again.gravityY = 0
            again.collisionsEnabled = false
            again.spawnBatch(count: 6_000, color: PackedColor(r: 255, g: 255, b: 255))
            if mode == "fluid" { again.fluidEnabled = true } else { again.nbodyEnabled = true }
            for _ in 0 ..< 3 { again.step() }
            let withIt = (0 ..< min(200, again.swarm.count)).map { again.swarm.positions[$0 * 2] }

            #expect(withoutIt != withIt, "\(mode) changed nothing")
            #expect(before != withIt, "\(mode) left everything exactly where it started")
            for value in withIt {
                #expect(Double(value).isFinite, "\(mode) produced an unusable position")
            }
        }
    }

    @Test("Both settings survive being written down and read back")
    func settingsRoundTrip() throws {
        let fluid = SwarmFluid.Settings(
            smoothing: 22, restDensity: 0.05, stiffness: 3, viscosity: 0.2, cohesion: 0.5
        )
        let encodedFluid = try JSONEncoder().encode(fluid)
        #expect(try JSONDecoder().decode(SwarmFluid.Settings.self, from: encodedFluid) == fluid)

        let gravity = SwarmGravity.Settings(strength: 4, softening: 12)
        let encodedGravity = try JSONEncoder().encode(gravity)
        #expect(try JSONDecoder().decode(SwarmGravity.Settings.self, from: encodedGravity) == gravity)
    }
}
