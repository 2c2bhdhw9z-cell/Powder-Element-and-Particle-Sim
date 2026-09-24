import Foundation
import Testing

@testable import CrucibleCore

/// Verifies the native particle field against the web engine's actual output.
///
/// Same method as ``PowderGoldenTests``, and the same reasoning: the behaviour of this
/// simulation is whatever a long accumulation of small tuning decisions produced, not
/// something derivable from first principles. Hand-written expectations could only prove
/// the port matches what someone assumed. Running the same scene in both engines and
/// comparing every body proves it matches what actually happens.
///
/// The fixture comes from `web/src/sim/__tests__/golden-particle.spec.ts`.
///
/// ## Why the draw count is checked
///
/// Alongside the bodies, each scenario records how many numbers the engine pulled from
/// the random stream. That is as valuable as the positions. Two implementations can
/// produce a similar-looking scene while consuming a different count, and that means
/// their streams have separated — they will then diverge completely on some later scene,
/// for a reason that would be very hard to trace. Comparing the count catches it here.
///
/// The count is recovered by replaying a fresh generator from the seed until it reaches
/// the state the engine ended on, so nothing test-only has to be added to the engine.
///
/// ## Why this comparison can be exact
///
/// These scenes are orbits and springs, where a difference in the last bit of a position
/// doubles every few steps. Comparing them exactly is only possible because the engine
/// computes its own sine and cosine instead of calling the platform's library — see
/// `Support/FDLibm.swift`. Without that this test would need a tolerance, and a tolerance
/// cannot distinguish a porting mistake from a last-bit difference that grew.
@Suite("Particle field matches the web engine")
struct ParticleGoldenTests {
    // MARK: - Fixture

    // Note on `CustomTestStringConvertible` below: each scenario carries every recorded
    // body, and the testing library titles a parameterised case by describing its
    // argument. Without a short description, one failure prints hundreds of kilobytes
    // and the actual difference is impossible to find.

    struct Overrides: Decodable {
        var gravityX: Double?
        var gravityY: Double?
        var damping: Double?
        var elasticity: Double?
        var electrostaticFactor: Double?
        var vortexForce: Double?
        var maxSpeed: Double?
        var boundaryMode: String?
        var mouseMode: String?
        var mouseRadius: Double?
        var mouseForceMultiplier: Double?
        var particleSize: Double?
        var maxParticles: Int?
        var showTrails: Bool?
        var decaySpeed: Double?
        var collisionsEnabled: Bool?
        var fluidEnabled: Bool?
        var flockEnabled: Bool?
        var nbodyEnabled: Bool?
    }

    struct MouseScript: Decodable {
        var x: Double
        var y: Double
        var dx: Double?
        var dy: Double?
        var from: Int?
        var to: Int?
    }

    struct Scenario: Decodable, CustomTestStringConvertible {
        var name: String
        var why: String
        var width: Double
        var height: Double
        var preset: String
        var args: [Double]
        var overrides: Overrides
        var mouse: MouseScript?
        var steps: Int
        var seed: UInt32
        var nowStart: Double
        var nowStep: Double
        var bodyFields: [String]
        var bodies: [String]
        var springs: [String]
        var swarmCount: Int
        var swarmSample: [String]
        var bodyCount: Int
        var randomDraws: Int

        /// Just the name, in test output.
        var testDescription: String { name }
    }

    struct Fixture: Decodable {
        var note: String
        var scenarios: [Scenario]
    }

    static let fixture: Fixture = {
        guard let url = Bundle.module.url(
            forResource: "web-particle-golden",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? Bundle.module.url(forResource: "web-particle-golden", withExtension: "json") else {
            fatalError("Fixture web-particle-golden.json is missing from the test bundle")
        }
        do {
            return try JSONDecoder().decode(Fixture.self, from: try Data(contentsOf: url))
        } catch {
            fatalError("Could not decode the golden particle fixture: \(error)")
        }
    }()

    /// The field order the fixture writes bodies in. Asserted against the fixture's own
    /// declaration, so a reordering on the web side fails loudly instead of silently
    /// comparing the wrong columns.
    static let expectedBodyFields = [
        "x", "y", "vx", "vy", "radius", "mass", "charge", "colorUint32", "type",
        "fixed", "ignoreGravity", "latticeBound", "lifespan", "maxLife",
        "originX", "originY", "helixStrand", "trailLength",
    ]

    // MARK: - Formatting

    /// Formats a number the way the fixture does, so the two can be compared as text.
    ///
    /// Comparing text rather than parsing both sides into doubles is deliberate: it makes
    /// a failure message show exactly what the fixture holds next to what the engine
    /// produced, in the same notation, with no chance of the comparison itself rounding
    /// away the difference being hunted.
    static func format(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
        // Twelve decimal places, and a negative zero normalised away, matching the
        // generator.
        //
        // `JS.round`, not Swift's `rounded()`. The two disagree on exact halves of a
        // negative number: JavaScript rounds towards positive infinity, so -0.5 becomes
        // -0, while Swift rounds away from zero and gives -1. That difference showed up
        // as four apparent physics failures on negative velocities that were in fact
        // identical to the last bit.
        let rounded = JS.round(value * 1e12) / 1e12
        let settled = rounded == 0 ? 0 : rounded
        // Integers print without a decimal point, as JavaScript does.
        if settled == settled.rounded(), abs(settled) < 1e15 {
            return String(Int64(settled))
        }
        // JavaScript prints the shortest text that reads back as the same number, which
        // is what Swift's default description does too.
        return String(settled)
    }

    static func format(_ value: Double?) -> String {
        value.map(format) ?? "-"
    }

    static func format(_ value: Int?) -> String {
        value.map(String.init) ?? "-"
    }

    /// The name the fixture uses for a body's kind.
    static func name(of kind: ParticleKind) -> String {
        kind.rawValue
    }

    /// One body, rendered in the fixture's format.
    static func line(for body: ParticleObject) -> String {
        [
            format(body.x),
            format(body.y),
            format(body.velocityX),
            format(body.velocityY),
            format(body.radius),
            format(body.mass),
            format(body.charge),
            String(body.color.packedRGBA),
            name(of: body.kind),
            body.isFixed ? "1" : "0",
            body.ignoresGravity ? "1" : "0",
            body.latticeBound ? "1" : "0",
            format(body.lifespan),
            format(body.maxLife),
            format(body.originX),
            format(body.originY),
            format(body.helixStrand),
            String(body.trail.count),
        ].joined(separator: " ")
    }

    // MARK: - Playback

    static func boundaryMode(_ raw: String) -> ParticleBoundaryMode {
        guard let mode = ParticleBoundaryMode(rawValue: raw) else {
            fatalError("Unknown boundary mode in fixture: \(raw)")
        }
        return mode
    }

    static func mouseMode(_ raw: String) -> ParticleMouseMode {
        guard let mode = ParticleMouseMode(rawValue: raw) else {
            fatalError("Unknown cursor mode in fixture: \(raw)")
        }
        return mode
    }

    /// Builds the scene a scenario names, then applies its overrides.
    ///
    /// Overrides come after the preset, matching the generator. That order matters: most
    /// presets set gravity and some set the vortex, so applying the overrides first would
    /// have them silently overwritten and the scenario would not test what it claims to.
    private func play(_ scenario: Scenario) -> ParticleEngine {
        let engine = ParticleEngine(
            width: scenario.width,
            height: scenario.height,
            seed: scenario.seed
        )
        let args = scenario.args

        func arg(_ index: Int, _ fallback: Int) -> Int {
            index < args.count ? Int(args[index]) : fallback
        }

        switch scenario.preset {
        case "burst": engine.spawnBurst(count: arg(0, 100))
        case "galaxy": engine.spawnGalaxy(count: arg(0, 300))
        case "waterfall": engine.spawnWaterfall(count: arg(0, 250))
        case "shockwave": engine.spawnShockwave(count: arg(0, 300))
        case "blackHole": engine.spawnBlackHole(count: arg(0, 250))
        case "doubleVortex": engine.spawnDoubleVortex(count: arg(0, 300))
        case "repulsor": engine.spawnRepulsor()
        case "solarFlare": engine.spawnSolarFlare(count: arg(0, 350))
        case "quantumLattice": engine.spawnQuantumLattice(rows: arg(0, 18), cols: arg(1, 24))
        case "dnaHelix": engine.spawnDnaHelix(count: arg(0, 280))
        case "cosmicFountain": engine.spawnCosmicFountain(count: arg(0, 250))
        case "synchrotron": engine.spawnSynchrotron(count: arg(0, 300))
        case "pour": engine.spawnPour(count: arg(0, 400))
        case "flock": engine.spawnFlock(count: arg(0, 220))
        case "nbody": engine.spawnNbody(count: arg(0, 240))
        case "cloth": engine.spawnCloth(cols: arg(0, 16), rows: arg(1, 12))
        case "rope": engine.spawnRope(length: arg(0, 32))
        case "blob": engine.spawnBlob(nodes: arg(0, 24))
        case "batch": engine.spawnBatch(count: arg(0, 1000))
        case "well": engine.placeWell(x: args[0], y: args[1])
        default: fatalError("Unknown preset in fixture: \(scenario.preset)")
        }

        let overrides = scenario.overrides
        if let value = overrides.gravityX { engine.gravityX = value }
        if let value = overrides.gravityY { engine.gravityY = value }
        if let value = overrides.damping { engine.damping = value }
        if let value = overrides.elasticity { engine.elasticity = value }
        if let value = overrides.electrostaticFactor { engine.electrostaticFactor = value }
        if let value = overrides.vortexForce { engine.vortexForce = value }
        if let value = overrides.maxSpeed { engine.maxSpeed = value }
        if let value = overrides.boundaryMode { engine.boundaryMode = Self.boundaryMode(value) }
        if let value = overrides.mouseMode { engine.mouseMode = Self.mouseMode(value) }
        if let value = overrides.mouseRadius { engine.mouseRadius = value }
        if let value = overrides.mouseForceMultiplier { engine.mouseForceMultiplier = value }
        if let value = overrides.particleSize { engine.particleSize = value }
        if let value = overrides.showTrails { engine.showTrails = value }
        if let value = overrides.decaySpeed { engine.decaySpeed = value }
        if let value = overrides.collisionsEnabled { engine.collisionsEnabled = value }
        if let value = overrides.fluidEnabled { engine.fluidEnabled = value }
        if let value = overrides.flockEnabled { engine.flockEnabled = value }
        if let value = overrides.nbodyEnabled { engine.nbodyEnabled = value }
        // Through the setter, which also trims the swarm to fit.
        if let value = overrides.maxParticles { _ = engine.setMaxParticles(value) }

        for step in 0 ..< scenario.steps {
            let now = scenario.nowStart + Double(step) * scenario.nowStep
            guard let mouse = scenario.mouse else {
                engine.step(mouseX: nil, mouseY: nil, mouseActive: false, now: now)
                continue
            }
            let from = mouse.from ?? 0
            let to = mouse.to ?? (scenario.steps - 1)
            let active = step >= from && step <= to
            engine.step(
                mouseX: mouse.x + (mouse.dx ?? 0) * Double(step),
                mouseY: mouse.y + (mouse.dy ?? 0) * Double(step),
                mouseActive: active,
                now: now
            )
        }
        return engine
    }

    /// Recovers how many draws a run consumed, by replaying from the seed.
    private func drawCount(seed: UInt32, endingAt finalState: UInt32, limit: Int) -> Int? {
        var generator = Mulberry32(seed: seed)
        if generator.state == finalState { return 0 }
        guard limit >= 1 else { return nil }
        for count in 1 ... limit {
            _ = generator.nextBits()
            if generator.state == finalState { return count }
        }
        return nil
    }

    // MARK: - Tests

    @Test("The fixture and this test agree on the record format")
    func formatAgrees() {
        #expect(
            Self.fixture.scenarios.allSatisfy { $0.bodyFields == Self.expectedBodyFields },
            "The generator changed the field order; this test is now comparing the wrong columns"
        )
        #expect(Self.fixture.scenarios.count >= 38)
    }

    @Test("Every body matches the web engine", arguments: fixture.scenarios)
    func bodiesMatch(scenario: Scenario) {
        let engine = play(scenario)
        let actual = engine.particles.map(Self.line(for:))

        #expect(
            actual.count == scenario.bodies.count,
            "\(scenario.name): \(actual.count) bodies, web engine had \(scenario.bodies.count)"
        )

        // Reported per body rather than as one list comparison, so a failure names the
        // body and shows only the line that differs. A three-hundred-body diff is
        // unreadable and buries the one thing that changed.
        var reported = 0
        for index in 0 ..< min(actual.count, scenario.bodies.count) where actual[index] != scenario.bodies[index] {
            if reported < 5 {
                Issue.record(
                    """
                    \(scenario.name), body \(index) differs
                      fields: \(Self.expectedBodyFields.joined(separator: " "))
                      native: \(actual[index])
                      web:    \(scenario.bodies[index])
                    """
                )
            }
            reported += 1
        }
        if reported > 5 {
            Issue.record("\(scenario.name): \(reported) bodies differ in total")
        }
    }

    @Test("Springs match the web engine", arguments: fixture.scenarios)
    func springsMatch(scenario: Scenario) {
        let engine = play(scenario)
        let actual = engine.springs.map { spring in
            "\(spring.a) \(spring.b) \(Self.format(spring.rest)) \(Self.format(spring.k))"
        }
        #expect(actual == scenario.springs, "\(scenario.name): spring set differs")
    }

    @Test("The swarm matches the web engine", arguments: fixture.scenarios)
    func swarmMatches(scenario: Scenario) {
        let engine = play(scenario)
        #expect(
            engine.swarm.count == scenario.swarmCount,
            "\(scenario.name): swarm holds \(engine.swarm.count), web engine had \(scenario.swarmCount)"
        )

        // The same even stride the generator used.
        var sample: [String] = []
        let n = engine.swarm.count
        if n > 0 {
            let take = min(n, 64)
            let stride = max(1, n / take)
            var i = 0
            while i < n, sample.count < take {
                let pair = i * 2
                sample.append(
                    [
                        String(i),
                        Self.format(Double(engine.swarm.positions[pair])),
                        Self.format(Double(engine.swarm.positions[pair + 1])),
                        Self.format(Double(engine.swarm.velocities[pair])),
                        Self.format(Double(engine.swarm.velocities[pair + 1])),
                    ].joined(separator: " ")
                )
                i += stride
            }
        }

        for index in 0 ..< min(sample.count, scenario.swarmSample.count)
        where sample[index] != scenario.swarmSample[index] {
            Issue.record(
                """
                \(scenario.name), swarm sample \(index) differs
                  fields: index x y vx vy
                  native: \(sample[index])
                  web:    \(scenario.swarmSample[index])
                """
            )
            break
        }
        #expect(
            sample.count == scenario.swarmSample.count,
            """
            \(scenario.name): sampled \(sample.count) of \(n), web engine sampled \
            \(scenario.swarmSample.count) of \(scenario.swarmCount)
            """
        )
    }

    @Test("The random stream is consumed identically", arguments: fixture.scenarios)
    func drawCountsMatch(scenario: Scenario) {
        let engine = play(scenario)
        // A generous ceiling: enough to find the real count, bounded so a mismatch fails
        // rather than searching the whole 32-bit period.
        let limit = max(scenario.randomDraws * 4, 100_000)
        let recovered = drawCount(seed: scenario.seed, endingAt: engine.rng.state, limit: limit)
        #expect(
            recovered == scenario.randomDraws,
            """
            \(scenario.name): drew \(recovered.map(String.init) ?? "more than \(limit)") numbers, \
            web engine drew \(scenario.randomDraws). The two engines are making decisions at \
            different points in the stream and will diverge elsewhere.
            """
        )
    }

    @Test("The whole field's population matches")
    func populationMatches() {
        for scenario in Self.fixture.scenarios {
            let engine = play(scenario)
            #expect(
                engine.bodyCount == scenario.bodyCount,
                "\(scenario.name): \(engine.bodyCount) bodies in total, web engine had \(scenario.bodyCount)"
            )
        }
    }
}
