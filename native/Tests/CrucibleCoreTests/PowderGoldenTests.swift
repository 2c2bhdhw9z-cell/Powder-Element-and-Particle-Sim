import Foundation
import Testing

@testable import CrucibleCore

/// Verifies the native powder engine against the web engine's actual output,
/// tick for tick.
///
/// This is the test that decides whether the port is real. A falling-sand
/// simulation has no correct answer derivable from first principles — its
/// behavior is whatever thousands of small tuning decisions accumulated into.
/// The only way to know the port preserved it is to run the same world in both
/// engines and compare every cell.
///
/// The fixture is produced by `web/src/sim/__tests__/golden-powder.spec.ts`, which
/// runs the web engine over scenarios restricted to sand and bedrock. That
/// restriction is what makes the comparison valid: neither element appears in any
/// reaction branch or phase-change case, so movement is the only subsystem with
/// any effect — and the only one drawing from the random stream.
///
/// Alongside each grid the fixture records **how many random numbers the engine
/// consumed**. That check is as important as the grid itself: matching pictures
/// while consuming a different number of draws would mean the two engines make
/// their decisions at different points in the stream, and they would diverge on
/// some other scenario later. The draw count is recovered on this side by
/// replaying a fresh generator until it reaches the engine's final state, so
/// nothing test-only has to be added to the engine.
@Suite("Powder engine matches the web engine tick for tick")
struct PowderGoldenTests {
    struct PaintedCell: Decodable {
        var x: Int
        var y: Int
        var id: Int
        var temp: Double?
        var life: Int?
    }

    struct Scenario: Decodable {
        var name: String
        var why: String
        var width: Int
        var height: Int
        var gravityX: Double
        var gravityY: Double
        var windX: Double
        var ambientTemp: Double
        var pressureEnabled: Bool
        var heatConductionEnabled: Bool
        var jostle: Double
        /// Decoded through the web-compatible coding layer, so this also exercises
        /// element interchange between the two versions.
        var customElements: [ElementDefinition]
        var steps: Int
        var seed: UInt32
        var setup: [PaintedCell]
        var typeRows: [String]
        var temperatureRows: [String]
        var velocityNonZero: [[Int]]
        var activeCount: Int
        var hashLite: Int32
        var randomDraws: Int
        /// The compact multiplayer payload, byte for byte as the web engine sends it.
        var liteBase64: String
    }

    struct Fixture: Decodable {
        var note: String
        var scenarios: [Scenario]
    }

    static let fixture: Fixture = {
        guard let url = Bundle.module.url(
            forResource: "web-powder-golden",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? Bundle.module.url(forResource: "web-powder-golden", withExtension: "json") else {
            fatalError("Fixture web-powder-golden.json is missing from the test bundle")
        }
        do {
            return try JSONDecoder().decode(Fixture.self, from: try Data(contentsOf: url))
        } catch {
            fatalError("Could not decode the golden powder fixture: \(error)")
        }
    }()

    /// Runs one scenario on the native engine, set up exactly as the web side was.
    ///
    /// The world parameters are applied before painting and the shake after it,
    /// matching the order the fixture generator uses — the shake has to come last
    /// because it acts on cells that must already exist.
    /// Visible to the rest of the test target so other suites can replay the same
    /// scenarios — the persistence tests check the wire format against these worlds, and
    /// a second copy of this setup would be free to drift away from the fixture.
    func play(_ scenario: Scenario) -> PowderEngine {
        let registry = ElementRegistry()
        for custom in scenario.customElements {
            #expect(registry.register(custom), "scenario \(scenario.name): element \(custom.id) was refused")
        }
        let engine = PowderEngine(
            width: scenario.width,
            height: scenario.height,
            registry: registry,
            seed: scenario.seed
        )
        engine.gravityX = scenario.gravityX
        engine.gravityY = scenario.gravityY
        engine.windX = scenario.windX
        engine.ambientTemp = scenario.ambientTemp
        engine.pressureEnabled = scenario.pressureEnabled
        engine.heatConductionEnabled = scenario.heatConductionEnabled

        for cell in scenario.setup {
            engine.setElement(cell.x, cell.y, ElementID(cell.id), temp: cell.temp, life: cell.life)
        }
        if scenario.jostle > 0 {
            engine.jostle(scenario.jostle)
        }
        for _ in 0 ..< scenario.steps {
            engine.step()
        }
        return engine
    }

    /// Recovers how many draws a run consumed, by replaying the stream from the
    /// seed until it reaches the state the engine ended on.
    private func drawCount(seed: UInt32, endingAt finalState: UInt32, limit: Int) -> Int? {
        var generator = Mulberry32(seed: seed)
        if generator.state == finalState { return 0 }
        for count in 1 ... limit {
            _ = generator.nextBits()
            if generator.state == finalState { return count }
        }
        return nil
    }

    private func rows(of engine: PowderEngine) -> [String] {
        (0 ..< engine.height).map { y in
            (0 ..< engine.width)
                .map { x in String(engine.type[engine.index(x, y)]) }
                .joined(separator: ",")
        }
    }

    /// Temperatures formatted to two decimals, matching how the fixture records
    /// them. Formatted by hand because the grid holds single-precision floats and
    /// their full expansion is noise.
    private func temperatureRows(of engine: PowderEngine) -> [String] {
        (0 ..< engine.height).map { y in
            (0 ..< engine.width)
                .map { x in twoDecimals(engine.temperature[engine.index(x, y)].asDouble) }
                .joined(separator: ",")
        }
    }

    /// Mirrors JavaScript's `toFixed(2)`, including how it renders negative zero.
    private func twoDecimals(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "NaN" : (value > 0 ? "Infinity" : "-Infinity") }
        let scaled = (value * 100).rounded()
        // `toFixed` prints "-0.00" for a small negative, so the sign is taken from
        // the original value rather than from the rounded result.
        let negative = scaled < 0 || (scaled == 0 && value < 0)
        let magnitude = Int(abs(scaled))
        let whole = magnitude / 100
        let fraction = magnitude % 100
        let fractionText = fraction < 10 ? "0\(fraction)" : "\(fraction)"
        return "\(negative ? "-" : "")\(whole).\(fractionText)"
    }

    @Test("The fixture loaded and covers every scenario")
    func fixtureLoads() {
        #expect(Self.fixture.scenarios.count == 38)
        for scenario in Self.fixture.scenarios {
            #expect(scenario.typeRows.count == scenario.height)
            #expect(scenario.temperatureRows.count == scenario.height)
            #expect(!scenario.setup.isEmpty, "\(scenario.name) paints nothing")
        }
        // Not every scenario needs randomness — a beam meeting a wall is entirely
        // deterministic — but the set as a whole must exercise the random stream
        // heavily, or the draw-count check below would be proving nothing.
        let totalDraws = Self.fixture.scenarios.reduce(0) { $0 + $1.randomDraws }
        #expect(totalDraws > 500_000, "the suite consumed only \(totalDraws) random draws")
    }

    @Test("Every cell matches the web engine", arguments: Self.fixture.scenarios)
    func gridMatches(scenario: Scenario) {
        let engine = play(scenario)
        let produced = rows(of: engine)

        #expect(
            produced.count == scenario.typeRows.count,
            "\(scenario.name): produced \(produced.count) rows, expected \(scenario.typeRows.count)"
        )

        for (y, expected) in scenario.typeRows.enumerated() where y < produced.count {
            #expect(
                produced[y] == expected,
                """
                \(scenario.name): row \(y) differs.
                  why this scenario exists: \(scenario.why)
                  native: \(produced[y])
                  web:    \(expected)
                """
            )
        }
    }

    @Test("Temperatures match the web engine", arguments: Self.fixture.scenarios)
    func temperaturesMatch(scenario: Scenario) {
        // Temperature drives the chemistry. A port could place every element
        // correctly while running slightly hot or cold, and would then diverge at
        // one of the hard thresholds — 700°C for lava setting, 100°C for water
        // boiling, 1450°C for sand fusing.
        let engine = play(scenario)
        let produced = temperatureRows(of: engine)

        for (y, expected) in scenario.temperatureRows.enumerated() where y < produced.count {
            #expect(
                produced[y] == expected,
                """
                \(scenario.name): temperature row \(y) differs.
                  native: \(produced[y])
                  web:    \(expected)
                """
            )
        }
    }

    @Test("Momentum matches the web engine", arguments: Self.fixture.scenarios)
    func momentumMatches(scenario: Scenario) {
        let engine = play(scenario)

        var produced: [[Int]] = []
        for i in 0 ..< engine.cellCount where engine.velocityX[i] != 0 || engine.velocityY[i] != 0 {
            produced.append([i, Int(engine.velocityX[i]), Int(engine.velocityY[i])])
        }

        #expect(
            produced == scenario.velocityNonZero,
            "\(scenario.name): momentum differs. native \(produced), web \(scenario.velocityNonZero)"
        )
    }

    @Test("The same number of random draws is consumed", arguments: Self.fixture.scenarios)
    func randomDrawsMatch(scenario: Scenario) {
        let engine = play(scenario)
        // Generous ceiling: the heaviest scenario consumes about 34,000.
        let recovered = drawCount(
            seed: scenario.seed,
            endingAt: engine.rng.state,
            limit: max(200_000, scenario.randomDraws * 4)
        )

        #expect(recovered != nil, "\(scenario.name): could not recover the draw count")
        #expect(
            recovered == scenario.randomDraws,
            """
            \(scenario.name): consumed \(recovered.map(String.init) ?? "?") random draws, \
            web consumed \(scenario.randomDraws). Matching grids with a different draw count \
            means the two engines decide at different points in the stream and will diverge \
            elsewhere.
            """
        )
    }

    @Test("Occupied-cell count and world fingerprint match", arguments: Self.fixture.scenarios)
    func countsAndHashMatch(scenario: Scenario) {
        let engine = play(scenario)
        #expect(
            engine.activeParticleCount == scenario.activeCount,
            "\(scenario.name): \(engine.activeParticleCount) occupied cells, web had \(scenario.activeCount)"
        )
        #expect(
            engine.hashLite() == scenario.hashLite,
            "\(scenario.name): fingerprint \(engine.hashLite()), web had \(scenario.hashLite)"
        )
    }

    @Test("Replaying a scenario twice gives an identical world")
    func runsAreDeterministic() {
        // The whole verification strategy rests on this being true.
        guard let scenario = Self.fixture.scenarios.first(where: { $0.name == "tall-stack-settles" }) else {
            Issue.record("expected scenario is missing from the fixture")
            return
        }
        let first = play(scenario)
        let second = play(scenario)
        #expect(rows(of: first) == rows(of: second))
        #expect(first.rng.state == second.rng.state)
    }
}

extension PowderGoldenTests.Scenario: CustomTestStringConvertible {
    var testDescription: String { name }
}
