import Foundation
import Testing

@testable import CrucibleCore

/// Holds every built-in scene to the exact grid the web engine lays out.
///
/// Thirteen scenes of dense geometry, each built from fractions of the world's size with
/// its own set of constants. A transposed number there survives review easily, because the
/// result still looks like a volcano — so the port is not trusted to be faithful, it is
/// measured against the original cell by cell.
///
/// Each scene is checked at four sizes. The large ones exercise the intended layout; the
/// cramped ones exercise the clipping and the `max(…)` guards that only come into play when
/// the arithmetic produces a position outside the grid, which is where two implementations
/// are most likely to part company and where nobody thinks to look.
@Suite("Built-in scenes match the web engine")
struct RecipeGoldenTests {
    struct Scene: Decodable, CustomTestStringConvertible {
        var id: String
        var name: String
        var width: Int
        var height: Int
        var seed: UInt32
        var typeRows: [String]
        /// Cells away from ambient, as `index:value`. Sparse: see the generator.
        var temperatures: [String]
        /// Cells with a lifetime left to run, as `index:value`.
        var lifetimes: [String]
        var activeCount: Int
        var randomDraws: Int

        var testDescription: String { "\(id) at \(width)x\(height)" }
    }

    struct Fixture: Decodable {
        var note: String
        var scenes: [Scene]
    }

    static let fixture: Fixture = {
        guard let url = Bundle.module.url(
            forResource: "web-recipes-golden",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? Bundle.module.url(forResource: "web-recipes-golden", withExtension: "json") else {
            fatalError("Fixture web-recipes-golden.json is missing from the test bundle")
        }
        do {
            return try JSONDecoder().decode(Fixture.self, from: try Data(contentsOf: url))
        } catch {
            fatalError("Could not decode the golden recipe fixture: \(error)")
        }
    }()

    /// Lays out one scene exactly as the fixture generator did.
    private func build(_ scene: Scene) -> (engine: PowderEngine, draws: Int) {
        guard let recipe = powderRecipes.first(where: { $0.id == scene.id }) else {
            fatalError("No scene with id \(scene.id)")
        }
        let engine = PowderEngine(width: scene.width, height: scene.height, seed: 1)
        var generator = Mulberry32(seed: scene.seed)
        recipe.apply(to: engine, random: &generator)

        // Recovered by replaying from the seed until the generator reaches the state it
        // ended on, so nothing test-only has to be added to the engine.
        var replay = Mulberry32(seed: scene.seed)
        var draws = 0
        while replay.state != generator.state, draws < 10_000 {
            _ = replay.nextBits()
            draws += 1
        }
        return (engine, draws)
    }

    private func typeRows(_ engine: PowderEngine) -> [String] {
        (0 ..< engine.height).map { y in
            (0 ..< engine.width)
                .map { String(engine.type[y * engine.width + $0]) }
                .joined(separator: ",")
        }
    }

    /// Cells with a lifetime left to run, as `index:value`.
    private func lifetimes(_ engine: PowderEngine) -> [String] {
        var out: [String] = []
        for i in 0 ..< engine.cellCount where engine.life[i] != 0 {
            out.append("\(i):\(engine.life[i])")
        }
        return out
    }

    /// Two decimal places, formatted the way JavaScript's `toFixed(2)` does.
    private func twoDecimals(_ value: Double) -> String {
        let scaled = JS.round(value * 100) / 100
        let negative = scaled < 0
        let magnitude = negative ? -scaled : scaled
        let integral = Int(magnitude.rounded(.down))
        var hundredths = Int(JS.round((magnitude - Double(integral)) * 100))
        var whole = integral
        // A fraction that rounds to a full hundred carries into the whole part.
        if hundredths == 100 {
            hundredths = 0
            whole += 1
        }
        let fraction = hundredths < 10 ? "0\(hundredths)" : "\(hundredths)"
        return "\(negative ? "-" : "")\(whole).\(fraction)"
    }

    /// Cells away from ambient, as `index:value`.
    private func temperatures(_ engine: PowderEngine) -> [String] {
        let ambientText = twoDecimals(engine.ambientTemp)
        var out: [String] = []
        for i in 0 ..< engine.cellCount {
            let text = twoDecimals(Double(engine.temperature[i]))
            if text != ambientText { out.append("\(i):\(text)") }
        }
        return out
    }

    @Test("Every cell matches", arguments: fixture.scenes)
    func cellsMatch(scene: Scene) {
        let (engine, _) = build(scene)
        let actual = typeRows(engine)
        #expect(actual.count == scene.typeRows.count, "\(scene.testDescription): row count differs")

        // Reported a row at a time, so a failure names the row rather than dumping the
        // whole grid and burying the one line that changed.
        var reported = 0
        for y in 0 ..< min(actual.count, scene.typeRows.count) where actual[y] != scene.typeRows[y] {
            if reported < 3 {
                Issue.record(
                    """
                    \(scene.testDescription), row \(y) differs
                      native: \(actual[y])
                      web:    \(scene.typeRows[y])
                    """
                )
            }
            reported += 1
        }
        if reported > 3 {
            Issue.record("\(scene.testDescription): \(reported) rows differ in total")
        }
    }

    @Test("Placement temperatures match", arguments: fixture.scenes)
    func temperaturesMatch(scene: Scene) {
        // Several scenes place things deliberately hot or cold — lava at 1400, ice at minus
        // thirty — and those numbers decide what happens on the first few ticks.
        let (engine, _) = build(scene)
        let actual = temperatures(engine)
        #expect(
            actual.count == scene.temperatures.count,
            "\(scene.testDescription): \(actual.count) cells away from ambient, web engine had \(scene.temperatures.count)"
        )
        for i in 0 ..< min(actual.count, scene.temperatures.count) where actual[i] != scene.temperatures[i] {
            Issue.record(
                """
                \(scene.testDescription), temperature \(i) differs
                  native: \(actual[i])
                  web:    \(scene.temperatures[i])
                """
            )
            break
        }
    }

    @Test("Lifetimes match", arguments: fixture.scenes)
    func lifetimesMatch(scene: Scene) {
        // A lifetime of zero on something that decays means it vanishes on the very next
        // tick, so getting these wrong quietly empties parts of a scene.
        let (engine, _) = build(scene)
        let actual = lifetimes(engine)
        #expect(
            actual.count == scene.lifetimes.count,
            "\(scene.testDescription): \(actual.count) cells still counting down, web engine had \(scene.lifetimes.count)"
        )
        for i in 0 ..< min(actual.count, scene.lifetimes.count) where actual[i] != scene.lifetimes[i] {
            Issue.record(
                """
                \(scene.testDescription), lifetime \(i) differs
                  native: \(actual[i])
                  web:    \(scene.lifetimes[i])
                """
            )
            break
        }
    }

    @Test("The random source is consumed identically", arguments: fixture.scenes)
    func drawsMatch(scene: Scene) {
        let (_, draws) = build(scene)
        #expect(
            draws == scene.randomDraws,
            "\(scene.testDescription): drew \(draws) numbers, the web engine drew \(scene.randomDraws)"
        )
    }

    @Test("Every scene puts something in the world")
    func scenesAreNotEmpty() {
        for scene in Self.fixture.scenes {
            let (engine, _) = build(scene)
            #expect(
                engine.activeParticleCount == scene.activeCount,
                "\(scene.testDescription): \(engine.activeParticleCount) cells filled, web engine had \(scene.activeCount)"
            )
            #expect(engine.activeParticleCount > 0, "\(scene.testDescription) is empty")
        }
    }

    @Test("The scene list matches the web engine's, in order")
    func listMatches() {
        // The order is part of the contract: the daily scene is picked by taking a hash of
        // the date modulo the count, so reordering the list changes which scene a given day
        // gets — and the two implementations would then disagree about the shared daily.
        let expected = [
            "volcano", "ants", "oil", "dam", "reactor", "storm", "circuit",
            "vacuum", "snow", "beach", "forest", "kiln", "remix",
        ]
        #expect(powderRecipes.map(\.id) == expected)
    }

    @Test("A scene can be undone")
    func scenesAreUndoable() {
        // Loading a scene throws the previous world away, so it has to be recoverable.
        let engine = PowderEngine(width: 60, height: 40, seed: 1)
        engine.setElement(5, 5, Element.sand)
        let history = PowderHistory(maximumSteps: 3)
        history.push(engine)

        powderRecipes[0].apply(to: engine)
        #expect(engine.type[engine.index(5, 5)] != Element.sand)

        #expect(history.undo(engine))
        #expect(engine.type[engine.index(5, 5)] == Element.sand)
    }
}
