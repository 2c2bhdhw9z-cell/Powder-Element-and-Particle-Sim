import Foundation
import Testing

@testable import CrucibleCore

/// Every scene left running for thousands of moments, checked not against a recording but against the rules that must
/// hold however it turns out.
///
/// ## Why this is different from every other test here
///
/// Almost everything else compares the engine against the reference implementation, moment for moment. That proves the
/// two agree; it cannot prove either is sane, and it only ever covers the few hundred moments a recording holds. A
/// world left running for an hour is not covered by any of it — and that is how anybody actually uses the app.
///
/// So this runs every scene far past where any recording reaches and asserts only things that must be true whatever
/// happens: no cell holding a material that does not exist, no temperature that is not a number, nothing escaping the
/// world, nothing moving faster than the stated limit, and the counts adding up. Both engines already know how to
/// report those — `inspect()` — which is what makes this cheap to state.
///
/// ## Why it is not part of the ordinary run
///
/// It takes a couple of minutes even with the optimiser on, and ten times that without. So it is switched on by an
/// environment variable and has a job of its own in the checks (`.github/workflows/long-runs.yml`), in release, where
/// that is affordable. Set `CRUCIBLE_LONG_RUNS=short` to walk the same ground a tenth as far, which checks the tests
/// themselves rather than the engine.
@Suite("Long runs, with rules that must hold", .enabled(if: LongRun.isOn))
struct LongRunTests {
    @Test("Every powder scene, left running")
    func powderScenes() {
        for recipe in allPowderRecipes {
            // Smaller than a phone's grid, so every scene can be run a long way. The rules being checked hold at any
            // size; the cost does not.
            let engine = PowderEngine(width: 110, height: 200, seed: 20_260_927)
            var generator = Mulberry32(seed: 4_242)
            recipe.apply(to: engine, random: &generator)
            LongRun.run(engine, moments: LongRun.moments(5_000), what: "the \(recipe.name) scene")
        }
    }

    @Test("A powder world with a tide, left running")
    func tideRunsLong() {
        for side in PowderTide.Side.allCases {
            let engine = PowderEngine(width: 110, height: 200, seed: 11)
            for x in 0 ..< engine.width { engine.setElement(x, engine.height - 1, Element.bedrock) }
            // A sea wall to be overtopped, and a hollow behind it to be filled.
            for y in 120 ..< 199 { engine.setElement(55, y, Element.stone) }
            engine.tide = PowderTide(side: side, period: 900, strength: 10)
            LongRun.run(engine, moments: LongRun.moments(5_000), what: "a tide from the \(side.rawValue)")
            // Whatever the tide did, it may not have filled the world: the sea has a ceiling.
            let filled = Double(engine.activeParticleCount) / Double(engine.cellCount)
            #expect(filled < 0.75, "the tide from the \(side.rawValue) filled \(Int(filled * 100))% of the world")
        }
    }

    @Test("Every arrangement of the field, left running")
    func fieldArrangements() {
        for arrangement in ParticleArrangement.all where arrangement.depth != .only {
            let field = LongRun.field()
            _ = field.loadArrangement(arrangement.id)
            LongRun.run(field, moments: LongRun.moments(2_000), what: "the \(arrangement.name) arrangement")
        }
    }

    @Test("Every arrangement of the field in 3D, left running")
    func fieldArrangementsInDepth() {
        for arrangement in ParticleArrangement.all {
            let field = LongRun.field()
            _ = field.setDepthEnabled(true)
            _ = field.loadArrangement(arrangement.id)
            LongRun.run(field, moments: LongRun.moments(1_500), what: "the \(arrangement.name) arrangement in 3D")
        }
    }

    @Test("The field's scenes that look after themselves, left running")
    func fieldLivingScenes() {
        let life = LongRun.field()
        // spawnParticleLife and spawnFoxesAndRabbits set the scene themselves.
        life.spawnParticleLife()
        LongRun.run(life, moments: LongRun.moments(3_000), what: "particle life")

        let herd = LongRun.field()
        herd.spawnFoxesAndRabbits()
        LongRun.run(herd, moments: LongRun.moments(4_000), what: "foxes and rabbits")
        // However the hunt goes, neither kind may grow without end.
        #expect(herd.herdCount.rabbits <= ParticleEngine.rabbitCapacity)
        #expect(herd.herdCount.foxes <= ParticleEngine.foxLimit)

        let liquid = LongRun.field()
        _ = liquid.loadArrangement("pour")
        LongRun.run(liquid, moments: LongRun.moments(2_500), what: "the liquid pouring")
    }

    @Test("Both chambers together, left running")
    func bothChambersTogether() {
        // The two chambers feed each other: explosions here throw sparks there, bodies that settle there silt down
        // into sand here. Neither engine's own tests cover the pair, and the bridge between them is where a world that
        // grows without end would show up.
        let powder = PowderEngine(width: 110, height: 200, seed: 8)
        var generator = Mulberry32(seed: 99)
        allPowderRecipes[0].apply(to: powder, random: &generator)
        let field = LongRun.field()
        field.loadArrangement("galaxy")

        for moment in 0 ..< LongRun.moments(3_000) {
            powder.step()
            field.step()
            // What the app's bridge does every frame: bodies that have come to rest at the bottom silt down into the
            // powder, and every so often an explosion throws sparks the other way.
            _ = Hybrid.autoSettle(from: field, into: powder)
            if moment % 200 == 0 {
                Hybrid.burst(fromPowder: powder, into: field, gridX: 55, gridY: 100, radius: 12)
            }
            if moment % 500 == 0 {
                LongRun.check(powder, what: "the powder world beside the field, after \(moment) moments")
                LongRun.check(field, what: "the field beside the powder world, after \(moment) moments")
            }
        }
        LongRun.check(powder, what: "the powder world beside the field, at the end")
        LongRun.check(field, what: "the field beside the powder world, at the end")
    }
}

/// The rules, and how far to run. Kept apart from the tests so each reads as what it runs rather than as how it checks.
enum LongRun {
    /// Whether the long runs are switched on. See the note on ``LongRunTests``.
    static var isOn: Bool {
        !(ProcessInfo.processInfo.environment["CRUCIBLE_LONG_RUNS"] ?? "").isEmpty
    }

    /// A tenth of the way, for checking the tests themselves.
    static var isShort: Bool {
        ProcessInfo.processInfo.environment["CRUCIBLE_LONG_RUNS"] == "short"
    }

    static func moments(_ full: Int) -> Int {
        isShort ? max(50, full / 10) : full
    }

    /// How often the rules are checked while running. Often enough to say roughly when something went wrong, rarely
    /// enough that the checking is not most of the time spent.
    static let checkEvery = 500

    /// A field of the size a phone has, with a ceiling low enough to run a long way.
    static func field() -> ParticleEngine {
        let field = ParticleEngine(width: 400, height: 780, seed: 20_260_927)
        _ = field.setMaxParticles(8_000)
        return field
    }

    /// Runs a powder world, checking the rules as it goes.
    static func run(_ engine: PowderEngine, moments: Int, what: String) {
        let before = engine.frameCount
        for moment in 0 ..< moments {
            engine.step()
            if moment % checkEvery == 0 { check(engine, what: "\(what), after \(moment) moments") }
        }
        check(engine, what: "\(what), after \(moments) moments")
        #expect(engine.frameCount == before + moments, "\(what) lost count of its own moments")
    }

    /// Runs a field, checking the rules as it goes.
    static func run(_ field: ParticleEngine, moments: Int, what: String) {
        for moment in 0 ..< moments {
            field.step()
            if moment % checkEvery == 0 { check(field, what: "\(what), after \(moment) moments") }
        }
        check(field, what: "\(what), after \(moments) moments")
    }

    /// What must be true of a powder world however it turns out.
    static func check(_ engine: PowderEngine, what: String) {
        let health = engine.inspect()
        #expect(health.isHealthy, "\(what): \(health.issues.joined(separator: "; "))")
        #expect(health.corruptTypeCount == 0, "\(what): cells holding a material that does not exist")
        #expect(health.unreadableTempCount == 0, "\(what): temperatures that are not numbers")
        #expect(health.activeCells <= health.totalCells, "\(what): more cells filled than the world has")
        // Runaway heat: nothing in the world is hotter than the sun, and nothing is below absolute zero.
        #expect(health.maxTemp <= 20_000, "\(what): something reached \(health.maxTemp)°C")
        #expect(health.minTemp >= -273, "\(what): something reached \(health.minTemp)°C, below absolute zero")
    }

    /// What must be true of a field however it turns out.
    static func check(_ field: ParticleEngine, what: String) {
        let health = field.inspect()
        #expect(health.isHealthy, "\(what): \(health.issues.joined(separator: "; "))")
        #expect(health.corruptCount == 0, "\(what): bodies with places or speeds that are not numbers")
        #expect(health.swarmCorruptCount == 0, "\(what): bodies in the crowd with places that are not numbers")
        #expect(health.outOfBoundsCount == 0, "\(what): bodies escaped the world")
        #expect(health.overSpeedCount == 0, "\(what): bodies past the speed limit")
        #expect(health.bodyCount <= health.maxParticles, "\(what): more bodies than the ceiling allows")
    }
}
