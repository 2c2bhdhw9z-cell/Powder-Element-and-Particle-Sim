// Describe a shape, and the bodies go and be it.
//
// ## Where this came from
//
// There is a site — particles.casberry.in — where every dot's position comes from a short formula, often one an AI
// wrote, and the result is genuinely beautiful. Nothing there has physics. Nothing can be pushed. The shape is a
// picture of a formula and that is all it is.
//
// This is that idea with the physics left in. A recipe is a title, two short formulas, and up to three knobs of its
// own. The bodies go to where the formulas say, and they are *held* there rather than placed there: shove a rose apart
// with a finger and it pulls itself back into a rose. Turn a knob and the shape becomes a different shape while every
// body walks to its new home, still shovable the whole way.
//
// ## Why it borrows the force compiler rather than growing a second one
//
// The field already has a formula reader, for forces somebody writes themselves. It was built carefully: the text is
// compiled once into a flat list of steps, and evaluating it is a loop over that list with no allocation. Writing a
// second parser for shapes would mean two grammars to keep the same, two sets of mistakes to report, and two places
// for a subtle difference in how `sin` behaves to hide.
//
// So this uses that one. What it adds is five words it understands — `u` and `v` for where a body sits in the run, and
// `a`, `b`, `c` for the knobs — and a check, in both directions, that a formula is not using words that mean nothing
// where it is being used. Without the check a force saying `sin(u * 4)` would quietly be `sin(0)`, which is a force of
// nothing, with no message and no symptom except that nothing happens. That silence is the failure this codebase keeps
// finding in the implementation it was ported from, and it is not worth repeating for the sake of five lines.
//
// ## Why the bodies are held rather than fixed
//
// A fixed body cannot be pushed, and being able to push it is the whole point. A held body has a home and a spring
// back to it, which is the mechanism the text cloud, the sunflower and the morph already use — so a recipe's shape
// behaves like the rest of the lab rather than like a special case, and it costs nothing new in the step.

/// A shape described rather than drawn.
public struct ParticleRecipe: Sendable, Hashable, Codable {
    /// One knob a recipe declares for itself.
    ///
    /// The point of a recipe declaring its own knobs is that a rose's number of petals and a knot's number of turns
    /// are not the same slider with a different label — they want different ranges, different steps and different
    /// names, and no fixed set of sliders in the interface could be right for both. So the recipe says.
    public struct Knob: Sendable, Hashable, Codable {
        /// Which letter the formulas call it: `a`, `b` or `c`.
        public var symbol: String
        /// What to call it on screen, in words.
        public var name: String
        public var low: Double
        public var high: Double
        /// Where it starts.
        public var value: Double
        /// How coarsely the slider moves. Nought means smoothly.
        ///
        /// A rose with two and a half petals is not a rose, so a knob that counts things says so and the slider
        /// clicks from one whole number to the next instead of sliding through the nonsense between them.
        public var step: Double

        public init(
            symbol: String,
            name: String,
            low: Double,
            high: Double,
            value: Double,
            step: Double = 0
        ) {
            self.symbol = symbol
            self.name = name
            self.low = low
            self.high = high
            self.value = value
            self.step = step
        }

        /// The value, pulled into range and onto the step.
        public var settled: Double {
            guard value.isFinite else { return low }
            var held = max(low, min(high, value))
            if step > 0 {
                held = (held / step).rounded() * step
                held = max(low, min(high, held))
            }
            return held
        }
    }

    /// How the bodies are spread over the formulas' parameters.
    public enum Spread: String, Sendable, Hashable, Codable, CaseIterable {
        /// A line: one parameter, bodies strung along it. A rose, a knot, a wave.
        case line
        /// A sheet: two parameters, bodies on a grid. A ripple, a cloth, a filled shape.
        case sheet

        public var displayName: String {
            switch self {
            case .line: return "Along a line"
            case .sheet: return "Over a sheet"
            }
        }
    }

    /// What it is called, and what the field shows on screen while it is loaded.
    public var title: String
    /// A sentence about what the shape is, for whoever is looking at the knobs.
    public var about: String
    /// The formula for sideways, in `u`, `v`, `a`, `b`, `c` and `pi`. Nought to one is the field's width.
    public var across: String
    /// The formula for up and down. Nought to one is the field's height, nought at the top.
    public var down: String
    public var spread: Spread
    /// How many bodies to use.
    public var count: Int
    public var knobs: [Knob]
    /// How hard the bodies are pulled home. Larger snaps back faster.
    public var hold: Double
    /// How much of the field the shape fills, nought to one.
    ///
    /// Applied after the formulas rather than inside them, so a recipe's author writes the shape they mean and the
    /// fitting is somebody else's problem. A formula that wanders outside nought-to-one still ends up on screen.
    public var fill: Double

    public init(
        title: String,
        about: String = "",
        across: String,
        down: String,
        spread: Spread = .line,
        count: Int = 9_000,
        knobs: [Knob] = [],
        hold: Double = 0.02,
        fill: Double = 0.82
    ) {
        self.title = title
        self.about = about
        self.across = across
        self.down = down
        self.spread = spread
        self.count = count
        self.knobs = knobs
        self.hold = hold
        self.fill = fill
    }

    /// Why a recipe could not be used.
    public enum Failure: Error, Sendable, Hashable {
        /// One of the two formulas would not compile. Which one, and what was wrong with it.
        case badFormula(which: String, why: ParticleForceExpression.Failure)
        /// A formula used a word that only means something to a force.
        case wrongWord(String)
        /// Both formulas were empty, so there is no shape.
        case nothingToDraw
        /// The field could not fit that many more bodies.
        case noRoom

        public var message: String {
            switch self {
            case .badFormula(let which, let why):
                return "The \(which) formula: \(why.message)"
            case .wrongWord(let word):
                return "‘\(word)’ means something to a force, not to a shape. A shape knows u, v, a, b, c and pi."
            case .nothingToDraw:
                return "Both formulas are empty, so there is no shape to make."
            case .noRoom:
                return "There is no room left in the field for that many bodies."
            }
        }
    }

    /// The knob a letter refers to, if the recipe declares one.
    public func knob(_ symbol: String) -> Knob? {
        knobs.first { $0.symbol == symbol }
    }

    /// The recipe with one knob turned.
    public func turning(_ symbol: String, to value: Double) -> ParticleRecipe {
        var copy = self
        for index in copy.knobs.indices where copy.knobs[index].symbol == symbol {
            copy.knobs[index].value = value
        }
        return copy
    }

    /// Every number pulled into a sensible range.
    public var sanitized: ParticleRecipe {
        var copy = self
        copy.count = max(50, min(120_000, count))
        copy.hold = hold.isFinite ? max(0.002, min(0.3, hold)) : 0.02
        copy.fill = fill.isFinite ? max(0.1, min(1, fill)) : 0.82
        copy.title = String(title.prefix(60))
        return copy
    }

    /// The compiled form of a recipe, ready to be laid out.
    struct Compiled {
        var across: ParticleForceExpression
        var down: ParticleForceExpression
        var first: Double
        var second: Double
        var third: Double
    }

    /// Compiles both formulas and reads the knobs, or says what is wrong.
    func compiled() -> Result<Compiled, Failure> {
        func read(_ text: String, called what: String) -> Result<ParticleForceExpression, Failure> {
            switch ParticleForceExpression.compile(text) {
            case .failure(let why):
                return .failure(.badFormula(which: what, why: why))
            case .success(let expression):
                // A word that means nothing here would otherwise be nought, silently. See the note at the top.
                let wrong = expression.variablesUsed.intersection(ParticleForceExpression.forceOnlyVariables)
                if let first = wrong.sorted(by: { $0.rawValue < $1.rawValue }).first {
                    return .failure(.wrongWord(first.rawValue))
                }
                return .success(expression)
            }
        }
        let sideways: ParticleForceExpression
        let vertical: ParticleForceExpression
        switch read(across, called: "sideways") {
        case .failure(let why): return .failure(why)
        case .success(let expression): sideways = expression
        }
        switch read(down, called: "up-and-down") {
        case .failure(let why): return .failure(why)
        case .success(let expression): vertical = expression
        }
        guard !sideways.isEmpty || !vertical.isEmpty else { return .failure(.nothingToDraw) }
        return .success(
            Compiled(
                across: sideways,
                down: vertical,
                first: knob("a")?.settled ?? 0,
                second: knob("b")?.settled ?? 0,
                third: knob("c")?.settled ?? 0
            )
        )
    }
}

// MARK: - The recipes that come with it

extension ParticleRecipe {
    /// The ready-made recipes.
    ///
    /// Chosen so that every one of them is *worth turning the knobs on*: a shape whose knob changes its colour or
    /// its size would be a slider for the sake of having one. Each of these becomes a different shape — a rose gains
    /// petals, a knot gains turns, a wave gains ripples — which is the thing the feature is for.
    public static let built: [ParticleRecipe] = [
        ParticleRecipe(
            title: "Rose",
            about: "A flower drawn by one line going round. Odd numbers of petals and even numbers behave differently.",
            across: "0.5 + cos(u * pi * 2 * b) * cos(u * pi * 2) * a",
            down: "0.5 + cos(u * pi * 2 * b) * sin(u * pi * 2) * a",
            count: 12_000,
            knobs: [
                Knob(symbol: "a", name: "How big", low: 0.1, high: 0.5, value: 0.45),
                Knob(symbol: "b", name: "Petals", low: 2, high: 12, value: 5, step: 1),
            ]
        ),
        ParticleRecipe(
            title: "Lissajous",
            about: "Two swings at once, one sideways and one up and down. Whole-number ratios close into a loop.",
            across: "0.5 + sin(u * pi * 2 * a) * 0.42",
            down: "0.5 + sin(u * pi * 2 * b + c) * 0.42",
            count: 14_000,
            knobs: [
                Knob(symbol: "a", name: "Sideways swings", low: 1, high: 9, value: 3, step: 1),
                Knob(symbol: "b", name: "Up-and-down swings", low: 1, high: 9, value: 2, step: 1),
                Knob(symbol: "c", name: "Out of step by", low: 0, high: 3.1416, value: 0),
            ]
        ),
        ParticleRecipe(
            title: "Spirograph",
            about: "A small wheel rolling round a big one, with a pen in it — the toy, exactly.",
            across: "0.5 + (cos(u * pi * 2) * 0.32 + cos(u * pi * 2 * a) * b)",
            down: "0.5 + (sin(u * pi * 2) * 0.32 + sin(u * pi * 2 * a) * b)",
            count: 16_000,
            knobs: [
                Knob(symbol: "a", name: "Turns of the small wheel", low: 2, high: 24, value: 7, step: 1),
                Knob(symbol: "b", name: "How far out the pen is", low: 0.02, high: 0.18, value: 0.1),
            ]
        ),
        ParticleRecipe(
            title: "Spiral",
            about: "A line winding out from the middle. Tighten it until it is nearly a disc.",
            across: "0.5 + cos(u * pi * 2 * a) * u * b",
            down: "0.5 + sin(u * pi * 2 * a) * u * b",
            count: 12_000,
            knobs: [
                Knob(symbol: "a", name: "Turns", low: 1, high: 20, value: 6, step: 1),
                Knob(symbol: "b", name: "How far out", low: 0.1, high: 0.48, value: 0.44),
            ]
        ),
        ParticleRecipe(
            title: "Heart",
            about: "The proper one, from the formula rather than from two circles and a triangle.",
            across: "0.5 + sin(u * pi * 2) * sin(u * pi * 2) * sin(u * pi * 2) * a",
            down: "0.52 - (cos(u * pi * 2) * 0.8125 - cos(u * pi * 4) * 0.3125"
                + " - cos(u * pi * 6) * 0.125 - cos(u * pi * 8) * 0.0625) * a",
            count: 11_000,
            knobs: [
                Knob(symbol: "a", name: "How big", low: 0.2, high: 0.55, value: 0.42),
            ]
        ),
        ParticleRecipe(
            title: "Ripples",
            about: "A sheet of bodies with waves running across it. Two knobs: how many, and how deep.",
            across: "0.08 + u * 0.84",
            down: "0.5 + sin(u * pi * 2 * a + v * pi * 2) * b + (v - 0.5) * 0.3",
            spread: .sheet,
            count: 18_000,
            knobs: [
                Knob(symbol: "a", name: "Ripples", low: 1, high: 12, value: 4, step: 1),
                Knob(symbol: "b", name: "How deep", low: 0.01, high: 0.2, value: 0.08),
            ]
        ),
        ParticleRecipe(
            title: "Ring of rings",
            about: "A big circle made of small circles. Turn the knob and the small ones multiply.",
            across: "0.5 + cos(u * pi * 2) * 0.3 + cos(v * pi * 2 * a) * b",
            down: "0.5 + sin(u * pi * 2) * 0.3 + sin(v * pi * 2 * a) * b",
            spread: .sheet,
            count: 16_000,
            knobs: [
                Knob(symbol: "a", name: "Small rings", low: 1, high: 8, value: 3, step: 1),
                Knob(symbol: "b", name: "How big they are", low: 0.02, high: 0.16, value: 0.1),
            ]
        ),
        ParticleRecipe(
            title: "Star",
            about: "Points that go in and out. An odd number of points looks unlike an even one.",
            across: "0.5 + cos(u * pi * 2) * (0.3 + cos(u * pi * 2 * a) * b)",
            down: "0.5 + sin(u * pi * 2) * (0.3 + cos(u * pi * 2 * a) * b)",
            count: 12_000,
            knobs: [
                Knob(symbol: "a", name: "Points", low: 3, high: 14, value: 5, step: 1),
                Knob(symbol: "b", name: "How sharp", low: 0.02, high: 0.18, value: 0.12),
            ]
        ),
        ParticleRecipe(
            title: "Knot",
            about: "A loop that goes over and under itself. Flattened onto the screen, so the crossings show.",
            across: "0.5 + (cos(u * pi * 2 * a) * (2 + cos(u * pi * 2 * b))) * 0.14",
            down: "0.5 + (sin(u * pi * 2 * a) * (2 + cos(u * pi * 2 * b))) * 0.14",
            count: 15_000,
            knobs: [
                Knob(symbol: "a", name: "Times round", low: 1, high: 7, value: 2, step: 1),
                Knob(symbol: "b", name: "Times through", low: 1, high: 9, value: 3, step: 1),
            ]
        ),
        ParticleRecipe(
            title: "Grid that bends",
            about: "A square grid pushed out of shape. At nought it is a plain grid; turn it up and it swirls.",
            across: "0.1 + u * 0.8 + sin(v * pi * 2 * b) * a",
            down: "0.1 + v * 0.8 + sin(u * pi * 2 * b) * a",
            spread: .sheet,
            count: 16_000,
            knobs: [
                Knob(symbol: "a", name: "How bent", low: 0, high: 0.2, value: 0.07),
                Knob(symbol: "b", name: "How often", low: 1, high: 8, value: 2, step: 1),
            ]
        ),
    ]

    /// A recipe by name.
    public static func named(_ title: String) -> ParticleRecipe? {
        built.first { $0.title.lowercased() == title.lowercased() }
    }
}

// MARK: - Laying one out

extension ParticleEngine {
    /// The recipe the field is currently holding, if any.
    public var recipe: ParticleRecipe? {
        storedRecipe
    }

    /// Lays out a recipe: every body sent to where the formulas say, and held there.
    ///
    /// - Returns: how many bodies were placed, or why it could not be done.
    @discardableResult
    public func spawnRecipe(_ recipe: ParticleRecipe) -> Result<Int, ParticleRecipe.Failure> {
        let wanted = recipe.sanitized
        let compiled: ParticleRecipe.Compiled
        switch wanted.compiled() {
        case .failure(let why): return .failure(why)
        case .success(let ready): compiled = ready
        }

        beginScene("recipe", gravityY: 0)
        let room = maxParticles - particles.count - swarm.count
        guard room > 0 else {
            storedRecipe = nil
            return .failure(.noRoom)
        }
        let count = min(wanted.count, room)

        let places = Self.recipePlaces(wanted, compiled, count: count, width: width, height: height)
        var placed = 0
        for (index, place) in places.enumerated() {
            // Coloured along the run rather than at random, so the shape shows which way round it was drawn — which
            // is most of what makes a knot readable as a knot rather than as a tangle.
            let along = places.count > 1 ? Double(index) / Double(places.count - 1) : 0
            let placedOne = swarm.append(
                x: place.x,
                y: place.y,
                velocityX: 0,
                velocityY: 0,
                color: PackedColor(hue: 200 + along * 140, saturation: 0.85, lightness: 0.62).packedRGBA,
                budget: maxParticles - particles.count,
                role: .holds,
                home: Swarm.Home(anchorX: place.x, anchorY: place.y, stiffness: wanted.hold)
            )
            guard placedOne else { break }
            placed += 1
        }

        storedRecipe = wanted
        // The title, hung in the field rather than only in the panel — a recipe with no name on screen is a shape
        // nobody can say the name of afterwards.
        labels = wanted.title.isEmpty ? [] : [ParticleLabel(wanted.title, x: width / 2, y: height * 0.08)]
        showsLabels = !wanted.title.isEmpty
        return .success(placed)
    }

    /// Turns one of the current recipe's knobs, and lets the bodies walk to their new homes.
    ///
    /// The bodies are not moved and not replaced — only their homes are. So the shape flows into the new shape under
    /// the same spring that holds it together, and it stays shovable the whole way across. Replacing the bodies would
    /// make a slider a series of jumps, and would throw away anything a finger was in the middle of doing.
    ///
    /// - Returns: whether there was a recipe to turn, and the new value was usable.
    @discardableResult
    public func turnRecipeKnob(_ symbol: String, to value: Double) -> Bool {
        guard let current = storedRecipe, current.knob(symbol) != nil, value.isFinite else { return false }
        let wanted = current.turning(symbol, to: value).sanitized
        let compiled: ParticleRecipe.Compiled
        switch wanted.compiled() {
        case .failure: return false
        case .success(let ready): compiled = ready
        }
        let places = Self.recipePlaces(wanted, compiled, count: swarm.count, width: width, height: height)
        guard !places.isEmpty else { return false }
        // Written straight into the crowd's own memory, which is how the morph moves homes too: the bodies stay where
        // they are and only what they are pulled towards changes, so the shape flows rather than jumping.
        for index in 0 ..< min(swarm.count, places.count) {
            let at = index * Swarm.homeStride
            swarm.homes[at] = JS.toFloat32(places[index].x)
            swarm.homes[at + 1] = JS.toFloat32(places[index].y)
            // The seventh number of the seven is the stiffness. The four in between are the radius, angle, spin and
            // squash an orbiting body uses, which a held body leaves alone.
            swarm.homes[at + 6] = JS.toFloat32(wanted.hold)
        }
        storedRecipe = wanted
        return true
    }

    /// Where a recipe's bodies belong, in pixels, fitted to the field.
    ///
    /// Fitted from what the formulas actually produced rather than from the nought-to-one they are supposed to
    /// produce: a formula is somebody's arithmetic, and `cos(u) * 3` is a perfectly reasonable thing to write. Reading
    /// the extent back out means a shape that wandered off the field is brought onto it, centred, with its proportions
    /// kept — a shape squashed to fit its box is a different shape.
    static func recipePlaces(
        _ recipe: ParticleRecipe,
        _ compiled: ParticleRecipe.Compiled,
        count: Int,
        width: Double,
        height: Double
    ) -> [(x: Double, y: Double)] {
        guard count > 0, width > 0, height > 0 else { return [] }

        // A sheet's grid is as square as the count allows, so a sheet recipe does not come out as a single line of
        // bodies when the count happens not to be a perfect square.
        let downCount: Int
        let acrossCount: Int
        switch recipe.spread {
        case .line:
            acrossCount = count
            downCount = 1
        case .sheet:
            let side = max(2, Int(Double(count).squareRoot()))
            acrossCount = side
            downCount = max(2, count / side)
        }

        var raw: [(x: Double, y: Double)] = []
        raw.reserveCapacity(acrossCount * downCount)
        var lowX = Double.greatestFiniteMagnitude
        var highX = -Double.greatestFiniteMagnitude
        var lowY = Double.greatestFiniteMagnitude
        var highY = -Double.greatestFiniteMagnitude

        for downIndex in 0 ..< downCount {
            let across = downCount > 1 ? Double(downIndex) / Double(downCount - 1) : 0
            for acrossIndex in 0 ..< acrossCount {
                let along = acrossCount > 1 ? Double(acrossIndex) / Double(acrossCount - 1) : 0
                let inputs = ParticleForceExpression.Inputs(
                    x: 0, y: 0, velocityX: 0, velocityY: 0, time: 0, radius: 0,
                    along: along, across: across,
                    first: compiled.first, second: compiled.second, third: compiled.third
                )
                let x = compiled.across.isEmpty ? 0.5 : compiled.across.value(for: inputs)
                let y = compiled.down.isEmpty ? 0.5 : compiled.down.value(for: inputs)
                // Anything that came out unusable is left out rather than placed at nought, which would be a stripe of
                // bodies down the left edge that reads as part of the shape.
                guard x.isFinite, y.isFinite else { continue }
                raw.append((x, y))
                lowX = min(lowX, x)
                highX = max(highX, x)
                lowY = min(lowY, y)
                highY = max(highY, y)
            }
        }
        guard !raw.isEmpty else { return [] }

        let spanX = highX - lowX
        let spanY = highY - lowY
        // The smaller side of the field, times the fill: a shape keeps its proportions rather than being stretched to
        // whatever shape the screen is.
        let room = min(width, height) * recipe.fill
        let widest = max(spanX, spanY)
        let scale = widest > 1e-9 ? room / widest : 1
        let middleX = (lowX + highX) / 2
        let middleY = (lowY + highY) / 2

        return raw.map { place in
            (
                x: width / 2 + (place.x - middleX) * scale,
                y: height / 2 + (place.y - middleY) * scale
            )
        }
    }
}
