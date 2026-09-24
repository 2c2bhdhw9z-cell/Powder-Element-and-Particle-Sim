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
    struct Scenario: Decodable {
        var name: String
        var why: String
        var width: Int
        var height: Int
        var gravityX: Double
        var gravityY: Double
        var steps: Int
        var seed: UInt32
        var setup: [[Int]]
        var typeRows: [String]
        var velocityNonZero: [[Int]]
        var activeCount: Int
        var hashLite: Int32
        var randomDraws: Int
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
    private func play(_ scenario: Scenario) -> PowderEngine {
        let engine = PowderEngine(
            width: scenario.width,
            height: scenario.height,
            seed: scenario.seed
        )
        engine.gravityX = scenario.gravityX
        engine.gravityY = scenario.gravityY
        for cell in scenario.setup {
            engine.setElement(cell[0], cell[1], ElementID(cell[2]))
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

    @Test("The fixture loaded and covers every scenario")
    func fixtureLoads() {
        #expect(Self.fixture.scenarios.count == 8)
        for scenario in Self.fixture.scenarios {
            #expect(scenario.typeRows.count == scenario.height)
            #expect(!scenario.setup.isEmpty, "\(scenario.name) paints nothing")
            #expect(scenario.randomDraws > 0, "\(scenario.name) draws no random numbers")
        }
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
