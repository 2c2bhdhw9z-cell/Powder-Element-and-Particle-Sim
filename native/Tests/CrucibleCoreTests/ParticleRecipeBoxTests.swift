import Foundation
import Testing

@testable import CrucibleCore

/// A shape described by formula, that can still be pushed.
///
/// The idea came from a site where every dot's place comes from a short formula and nothing has physics. What makes
/// this version worth having is the two things that site cannot do: shove the shape and it comes back, and turn a knob
/// and it becomes a different shape while every body walks there. Both are what these check.
@Suite("Describe a shape and the bodies go and be it")
struct ParticleRecipeBoxTests {
    private func field() -> ParticleEngine {
        let engine = ParticleEngine(width: 400, height: 700, seed: 11)
        engine.clear()
        return engine
    }

    /// How far a body is from where it belongs, on average, over the whole crowd.
    private func averageStrayed(_ engine: ParticleEngine) -> Double {
        let crowd = engine.swarm
        guard crowd.count > 0 else { return 0 }
        var total = 0.0
        for index in 0 ..< crowd.count {
            let x = Double(crowd.positions[index * 2])
            let y = Double(crowd.positions[index * 2 + 1])
            let homeX = Double(crowd.homes[index * Swarm.homeStride])
            let homeY = Double(crowd.homes[index * Swarm.homeStride + 1])
            total += ((x - homeX) * (x - homeX) + (y - homeY) * (y - homeY)).squareRoot()
        }
        return total / Double(crowd.count)
    }

    @Test("Every recipe it comes with lays out")
    func theBuiltOnesAllWork() throws {
        for recipe in ParticleRecipe.built {
            let engine = field()
            let result = engine.spawnRecipe(recipe)
            let placed = try #require(try? result.get(), "\(recipe.title) would not lay out")
            #expect(placed > 1_000, "\(recipe.title) placed almost nothing")
            #expect(engine.swarm.count == placed)
        }
    }

    @Test("Every recipe it comes with fills the field rather than a corner of it")
    func theBuiltOnesAreOnScreen() {
        // The fault this is really about: a formula whose numbers do not happen to land in nought-to-one produces a
        // shape squashed into a corner or a single dot, and it is still a perfectly valid layout.
        for recipe in ParticleRecipe.built {
            let engine = field()
            _ = engine.spawnRecipe(recipe)
            let crowd = engine.swarm
            var lowX = Double.greatestFiniteMagnitude
            var highX = -Double.greatestFiniteMagnitude
            var lowY = Double.greatestFiniteMagnitude
            var highY = -Double.greatestFiniteMagnitude
            for index in 0 ..< crowd.count {
                let x = Double(crowd.positions[index * 2])
                let y = Double(crowd.positions[index * 2 + 1])
                lowX = min(lowX, x); highX = max(highX, x)
                lowY = min(lowY, y); highY = max(highY, y)
            }
            let spread = max(highX - lowX, highY - lowY)
            // The fill is a bit over eight tenths of the shorter side, which here is four hundred.
            #expect(spread > 250, "\(recipe.title) came out tiny — \(Int(spread)) pixels across")
            #expect(lowX > -10 && highX < 410, "\(recipe.title) hung off the sides")
            #expect(lowY > -10 && highY < 710, "\(recipe.title) hung off the top or bottom")
        }
    }

    @Test("Shove it and it pulls itself back together")
    func itReforms() {
        let engine = field()
        _ = engine.spawnRecipe(ParticleRecipe.named("Rose")!)
        #expect(averageStrayed(engine) < 0.01, "the bodies did not start at home")

        // Everything flung a long way off, as a finger through the middle would.
        let crowd = engine.swarm
        for index in 0 ..< crowd.count {
            crowd.positions[index * 2] += 90
            crowd.positions[index * 2 + 1] -= 60
        }
        let thrown = averageStrayed(engine)
        #expect(thrown > 100)

        for _ in 0 ..< 600 { engine.step() }
        let settled = averageStrayed(engine)
        #expect(settled < thrown / 5, "a shoved shape did not come back: \(Int(thrown)) then \(Int(settled))")
    }

    @Test("Turning a knob changes the shape without replacing the bodies")
    func aKnobReshapes() {
        let engine = field()
        _ = engine.spawnRecipe(ParticleRecipe.named("Rose")!)
        let before = engine.swarm.count
        let firstHome = (
            Double(engine.swarm.homes[0]),
            Double(engine.swarm.homes[1])
        )
        // Where the bodies are right now, which a knob must not disturb.
        let firstPlace = (Double(engine.swarm.positions[0]), Double(engine.swarm.positions[1]))

        #expect(engine.turnRecipeKnob("b", to: 9))
        #expect(engine.swarm.count == before, "turning a knob replaced the bodies")
        #expect(engine.recipe?.knob("b")?.settled == 9)
        let afterHome = (Double(engine.swarm.homes[0]), Double(engine.swarm.homes[1]))
        #expect(afterHome != firstHome, "the knob moved nothing")
        // The bodies themselves have not been teleported — only what they are pulled towards has changed.
        #expect(abs(Double(engine.swarm.positions[0]) - firstPlace.0) < 0.001)
        #expect(abs(Double(engine.swarm.positions[1]) - firstPlace.1) < 0.001)

        // And they walk there.
        let strayedAtOnce = averageStrayed(engine)
        #expect(strayedAtOnce > 1)
        for _ in 0 ..< 600 { engine.step() }
        #expect(averageStrayed(engine) < strayedAtOnce / 3, "the bodies never reached their new homes")
    }

    @Test("A knob that counts things clicks to whole numbers")
    func countingKnobsClick() {
        // Two and a half petals is not a rose.
        let rose = ParticleRecipe.named("Rose")!
        #expect(rose.turning("b", to: 5.4).knob("b")?.settled == 5)
        #expect(rose.turning("b", to: 5.6).knob("b")?.settled == 6)
        // And a smooth one does not.
        #expect(rose.turning("a", to: 0.234).knob("a")?.settled == 0.234)
        // Out of range is pulled in, not refused.
        #expect(rose.turning("b", to: 900).knob("b")?.settled == 12)
        #expect(rose.turning("b", to: -900).knob("b")?.settled == 2)
        #expect(rose.turning("a", to: .nan).knob("a")?.settled == 0.1)
    }

    @Test("A knob a recipe does not have is refused")
    func unknownKnobsAreRefused() {
        let engine = field()
        _ = engine.spawnRecipe(ParticleRecipe.named("Heart")!)
        #expect(engine.turnRecipeKnob("a", to: 0.3))
        #expect(engine.turnRecipeKnob("b", to: 4) == false, "a knob the heart does not have was accepted")
        #expect(engine.turnRecipeKnob("a", to: .infinity) == false)
        // And there is nothing to turn before a recipe is loaded.
        #expect(field().turnRecipeKnob("a", to: 1) == false)
    }

    @Test("A formula using a force's words is refused, with the word named")
    func wrongWordsAreCaught() {
        // The point of this: without the check, a shape saying sin(t) would silently be sin(0) — every body in one
        // place, no message, and nothing to tell anybody why.
        let engine = field()
        var recipe = ParticleRecipe(title: "Wrong", across: "sin(t) * 0.4 + 0.5", down: "u")
        var failure: ParticleRecipe.Failure?
        if case .failure(let why) = engine.spawnRecipe(recipe) { failure = why }
        #expect(failure == .wrongWord("t"))
        #expect(failure?.message.contains("‘t’") == true)

        recipe.across = "vx * 0.1"
        if case .failure(let why) = engine.spawnRecipe(recipe) { failure = why } else { failure = nil }
        #expect(failure == .wrongWord("vx"))

        // And the words a shape *should* know are accepted.
        recipe.across = "0.5 + cos(u * pi * 2) * a"
        recipe.down = "0.5 + sin(u * pi * 2) * a"
        recipe.knobs = [ParticleRecipe.Knob(symbol: "a", name: "How big", low: 0.1, high: 0.5, value: 0.4)]
        #expect((try? engine.spawnRecipe(recipe).get()) != nil)
    }

    @Test("A force using a shape's words is caught too, in the other direction")
    func theCheckGoesBothWays() {
        // The same silence, the other way round: a force saying sin(u * 4) would be sin(0), a force of nothing.
        let compiled = try? ParticleForceExpression.compile("sin(u * 4)").get()
        #expect(compiled != nil, "the compiler should still understand the word")
        let used = compiled?.variablesUsed ?? []
        #expect(used.contains(.u))
        #expect(used.isDisjoint(with: ParticleForceExpression.forceOnlyVariables))
        // Which is what lets a caller tell the two apart rather than guessing.
        #expect(!used.isDisjoint(with: ParticleForceExpression.recipeOnlyVariables))
        let force = try? ParticleForceExpression.compile("sin(y * 4) - vy * 0.2").get()
        #expect(force?.variablesUsed.isDisjoint(with: ParticleForceExpression.recipeOnlyVariables) == true)
    }

    @Test("Nonsense is refused with something to read")
    func nonsenseIsRefused() {
        let engine = field()
        var failure: ParticleRecipe.Failure?
        if case .failure(let why) = engine.spawnRecipe(
            ParticleRecipe(title: "Broken", across: "sin(", down: "u")) { failure = why }
        #expect(failure != nil)
        #expect(failure?.message.contains("sideways") == true, "it did not say which formula was wrong")

        if case .failure(let why) = engine.spawnRecipe(
            ParticleRecipe(title: "Empty", across: "", down: "")) { failure = why } else { failure = nil }
        #expect(failure == .nothingToDraw)
        #expect(engine.recipe == nil, "a recipe that failed was remembered anyway")
    }

    @Test("A formula that gives nonsense for some bodies leaves those out")
    func unusableNumbersAreLeftOut() {
        // sqrt of a negative, division by nought: the compiler gives nought for those rather than spreading a
        // meaningless number, and a body placed at nought would be a stripe down the left edge that reads as shape.
        let engine = field()
        let recipe = ParticleRecipe(
            title: "Half there",
            across: "0.5 + cos(u * pi * 2) * 0.4",
            down: "0.5 + sin(u * pi * 2) * 0.4",
            count: 3_000
        )
        _ = engine.spawnRecipe(recipe)
        let crowd = engine.swarm
        var onTheEdge = 0
        for index in 0 ..< crowd.count where Double(crowd.positions[index * 2]) < 1 { onTheEdge += 1 }
        #expect(onTheEdge == 0)
    }

    @Test("A sheet spreads bodies both ways, a line only one")
    func spreadsDiffer() {
        let line = field()
        _ = line.spawnRecipe(ParticleRecipe(
            title: "Line", across: "u", down: "0.5", count: 4_000))
        let sheet = field()
        _ = sheet.spawnRecipe(ParticleRecipe(
            title: "Sheet", across: "u", down: "v", spread: .sheet, count: 4_000))

        /// How many different vertical places the bodies occupy, roughly.
        func rows(_ engine: ParticleEngine) -> Int {
            var seen = Set<Int>()
            for index in 0 ..< engine.swarm.count {
                seen.insert(Int(engine.swarm.positions[index * 2 + 1] / 4))
            }
            return seen.count
        }
        #expect(rows(line) <= 2, "a line recipe used more than one row")
        #expect(rows(sheet) > 20, "a sheet recipe came out as a line")
    }

    @Test("The title hangs in the field")
    func theTitleShows() {
        let engine = field()
        _ = engine.spawnRecipe(ParticleRecipe.named("Spirograph")!)
        #expect(engine.showsLabels)
        #expect(engine.labels.count == 1)
        #expect(engine.labels.first?.text == "Spirograph")
        // Free-floating rather than pinned to a body, so it stays put when the shape is shoved about.
        #expect(engine.labels.first?.body == nil)
    }

    @Test("Absurd recipes are pulled into range rather than refused")
    func absurdNumbersAreSettled() {
        var recipe = ParticleRecipe(title: String(repeating: "x", count: 500), across: "u", down: "v")
        recipe.count = 9_000_000
        recipe.hold = .nan
        recipe.fill = 40
        let settled = recipe.sanitized
        #expect(settled.count == 120_000)
        #expect(settled.hold == 0.02)
        #expect(settled.fill == 1)
        #expect(settled.title.count == 60)
    }

    @Test("A recipe survives being written down and read back")
    func itSurvivesTheRoundTrip() throws {
        // Recipes are meant to be shared — a formula somebody wrote is worth keeping — so they have to encode.
        for recipe in ParticleRecipe.built {
            let written = try JSONEncoder().encode(recipe)
            let read = try JSONDecoder().decode(ParticleRecipe.self, from: written)
            #expect(read == recipe, "\(recipe.title) did not survive being written down")
        }
    }

    @Test("Two knobs on the same shape do different things")
    func knobsAreIndependent() {
        // A recipe whose knobs both did the same thing would be a slider for the sake of having one.
        let engine = field()
        let star = ParticleRecipe.named("Star")!
        _ = engine.spawnRecipe(star)

        func homes() -> [Float] {
            Array(UnsafeBufferPointer(start: engine.swarm.homes, count: engine.swarm.count * Swarm.homeStride))
        }
        let start = homes()
        _ = engine.turnRecipeKnob("a", to: 11)
        let afterPoints = homes()
        _ = engine.turnRecipeKnob("a", to: star.knob("a")!.value)
        _ = engine.turnRecipeKnob("b", to: 0.03)
        let afterSharpness = homes()
        #expect(afterPoints != start)
        #expect(afterSharpness != start)
        #expect(afterPoints != afterSharpness, "two knobs produced the same shape")
    }
}
