// The guided lab book: experiments that set a world up, let somebody find the answer with their own hands, and then
// explain it with the numbers their own world produced.
//
// ## Why the explanation is written from the world rather than from a script
//
// A lab book that says "water boils at 100°C" is a textbook. The point of doing it in a world is that the world can
// say "the hottest water in *your* pan was 99.6°C, and the first of it boiled away four seconds after your lava
// arrived". So each experiment keeps a running record of what the world did while it was being done — how much of
// everything there was, how hot each material ever got, where each one sat — and its explanation is written from
// that record. Two people doing the same experiment get two different paragraphs, each true of their own world.
//
// ## Why every experiment can do itself
//
// Each one carries the action it asks for — "pour lava under the pan" — as a thing the engine can do on its own. That
// is the "Show me" button for somebody who is stuck, and it is also what the checks use: every experiment is set up,
// done, run, and required to reach its answer and explain it, on more than one size of world. An experiment that
// cannot be finished is found here rather than by a child who has been pouring lava for five minutes.
//
// ## Why nothing here remembers where things were put
//
// The world can be cropped or stretched while an experiment is running, so a watcher that remembered "the pan is rows
// 60 to 70" would be reading the wrong rows afterwards. Everything is read by material instead — all the copper, all
// the water — which survives any change of size.

/// What the world did while an experiment was running, gathered a few times a second.
public struct LabReadings: Sendable, Equatable {
    /// World seconds since the experiment was set up: sixty moments to the second.
    public var seconds = 0.0
    /// How many times the world has been looked at.
    public var looks = 0
    /// How much of each material there was when the experiment was set up.
    public var start: [ElementID: Int] = [:]
    /// How much of each there is now.
    public var counts: [ElementID: Int] = [:]
    /// The most of each there has ever been.
    public var most: [ElementID: Int] = [:]
    /// The least of each there has ever been, for materials that were there at the start.
    public var fewest: [ElementID: Int] = [:]
    /// When each material first appeared that was not there at the start, in seconds.
    public var firstSeen: [ElementID: Double] = [:]
    /// The hottest any cell of each material has ever been.
    public var hottestOf: [ElementID: Double] = [:]
    /// How warm each material is now, on average.
    public var warmthOf: [ElementID: Double] = [:]
    /// The warmest each material has ever been on average.
    public var warmestOf: [ElementID: Double] = [:]
    /// The coldest cell of each material now — for a bar standing in something hot, its far end.
    public var coldestOf: [ElementID: Double] = [:]
    /// The warmest the coldest cell of each material has ever been: how far heat has reached right through it.
    public var reachedOf: [ElementID: Double] = [:]
    /// The coldest any cell of each material has ever been.
    public var chilliestOf: [ElementID: Double] = [:]
    /// How far up the world each material sits now, on average: nought at the floor, one at the top.
    public var heightOf: [ElementID: Double] = [:]

    public init() {}

    /// How much of a material there is now.
    public func count(_ id: ElementID) -> Int { counts[id] ?? 0 }

    /// How much of a material has gone since the start, never less than nought.
    public func lost(_ id: ElementID) -> Int { max(0, (start[id] ?? 0) - (fewest[id] ?? start[id] ?? 0)) }

    /// How much of a material there is beyond what there was at the start, at the most.
    public func gained(_ id: ElementID) -> Int { max(0, (most[id] ?? 0) - (start[id] ?? 0)) }
}

extension LabReadings {
    /// Takes one look at the world.
    ///
    /// One pass over every cell, a few times a second. That is the same cost as the measurements the lab already
    /// takes once a second, and far less than one moment of the world itself.
    mutating func look(at engine: PowderEngine, seconds: Double) {
        // Tallied into flat arrays by material rather than into dictionaries: a dictionary costs a hash for every
        // cell, and boiling is watched every other moment on a world of a couple of hundred thousand cells. Every
        // material's number is below 256 — the engine's own noticing relies on the same bound.
        let kinds = 256
        var tallyByKind = [Int](repeating: 0, count: kinds)
        var heatByKind = [Double](repeating: 0, count: kinds)
        var rowsByKind = [Double](repeating: 0, count: kinds)
        var hottestByKind = [Double](repeating: -.infinity, count: kinds)
        var coldestByKind = [Double](repeating: .infinity, count: kinds)
        let width = engine.width
        let height = engine.height
        let empty = Int(Element.empty)
        let bedrock = Int(Element.bedrock)
        for y in 0 ..< height {
            // Nought at the floor and one at the top, which is how anybody would say "higher".
            let up = height > 1 ? Double(height - 1 - y) / Double(height - 1) : 0
            let row = y * width
            for x in 0 ..< width {
                let kind = Int(engine.type[row + x])
                guard kind != empty, kind != bedrock, kind < kinds else { continue }
                let temperature = Double(engine.temperature[row + x])
                tallyByKind[kind] += 1
                heatByKind[kind] += temperature
                rowsByKind[kind] += up
                if temperature > hottestByKind[kind] { hottestByKind[kind] = temperature }
                if temperature < coldestByKind[kind] { coldestByKind[kind] = temperature }
            }
        }
        var tally: [ElementID: Int] = [:]
        var heat: [ElementID: Double] = [:]
        var hottest: [ElementID: Double] = [:]
        var coldest: [ElementID: Double] = [:]
        var rows: [ElementID: Double] = [:]
        for kind in 0 ..< kinds where tallyByKind[kind] > 0 {
            let id = ElementID(kind)
            tally[id] = tallyByKind[kind]
            heat[id] = heatByKind[kind]
            rows[id] = rowsByKind[kind]
            hottest[id] = hottestByKind[kind]
            coldest[id] = coldestByKind[kind]
        }

        self.seconds = seconds
        if looks == 0 { start = tally }
        looks += 1
        counts = tally
        warmthOf = [:]
        heightOf = [:]
        coldestOf = coldest
        for (id, count) in tally {
            let many = Double(count)
            warmthOf[id] = heat[id, default: 0] / many
            heightOf[id] = rows[id, default: 0] / many
            if count > most[id] ?? 0 { most[id] = count }
            if (warmthOf[id] ?? 0) > warmestOf[id] ?? -.infinity { warmestOf[id] = warmthOf[id] }
            if let value = hottest[id], value > hottestOf[id] ?? -.infinity { hottestOf[id] = value }
            if let value = coldest[id] {
                if value > reachedOf[id] ?? -.infinity { reachedOf[id] = value }
                if value < chilliestOf[id] ?? .infinity { chilliestOf[id] = value }
            }
            if start[id] == nil, firstSeen[id] == nil { firstSeen[id] = seconds }
        }
        // Whatever was there at the start and has gone altogether counts as none, not as missing.
        for id in start.keys {
            let now = tally[id] ?? 0
            if now < fewest[id] ?? Int.max { fewest[id] = now }
        }
    }
}

/// One experiment in the lab book.
public struct LabExperiment: Sendable, Identifiable {
    public let id: String
    /// What it is called in the list.
    public let title: String
    /// The question, asked before anything is done.
    public let question: String
    /// What somebody might guess, one of which is right.
    public let guesses: [String]
    /// Which of the guesses is right.
    public let answer: Int
    /// What to do, in one sentence.
    public let task: String
    /// The material to put in somebody's hand for it, if there is one.
    public let material: ElementID?
    /// The symbol it is shown with.
    public let symbol: String
    /// How long, in world seconds, to wait before offering to show how. A little longer than doing it takes.
    public let patience: Double
    /// How often the world is looked at, in moments. Four times a second is plenty for almost everything; boiling is
    /// watched more closely, because water on its way to steam spends only a moment at its hottest.
    public let lookEvery: Int

    /// Lays the world out for the experiment.
    let setUp: @Sendable (PowderEngine) -> Void
    /// Does what the task asks, for somebody who is stuck and for the checks.
    let demonstrate: @Sendable (PowderEngine) -> Void
    /// Whether the world has answered the question yet.
    let isAnswered: @Sendable (LabReadings) -> Bool
    /// What happened, from the numbers this world produced. The first sentence says what the answer is.
    let explain: @Sendable (LabReadings) -> [String]

    /// The answer, in words.
    public var answerText: String { guesses[answer] }

    init(
        id: String, title: String, question: String, guesses: [String], answer: Int, task: String,
        material: ElementID?, symbol: String, patience: Double, lookEvery: Int = 15,
        setUp: @escaping @Sendable (PowderEngine) -> Void,
        demonstrate: @escaping @Sendable (PowderEngine) -> Void,
        isAnswered: @escaping @Sendable (LabReadings) -> Bool,
        explain: @escaping @Sendable (LabReadings) -> [String]
    ) {
        self.id = id
        self.title = title
        self.question = question
        self.guesses = guesses
        self.answer = answer
        self.task = task
        self.material = material
        self.symbol = symbol
        self.patience = patience
        self.lookEvery = lookEvery
        self.setUp = setUp
        self.demonstrate = demonstrate
        self.isAnswered = isAnswered
        self.explain = explain
    }
}

/// An experiment being done: the guess, what the world has done so far, and whether it has answered.
public struct LabBookRun: Sendable {
    public let experiment: LabExperiment
    /// Which guess was made, once one has been. Nothing if the guess was skipped.
    public private(set) var guess: Int?
    /// Whether the question has been answered with a guess, or skipped, and the world let go.
    public private(set) var hasStarted = false
    public private(set) var readings = LabReadings()
    /// Whether the world has answered. Once it has, it stays answered even if the world goes on to undo it — steam
    /// that has boiled does not un-boil the explanation.
    public private(set) var isAnswered = false
    /// The explanation, fixed at the moment of answering so it describes that moment and not whatever came after.
    public private(set) var explanation: [String] = []
    /// Whether "Show me" was used, which the lab book mentions rather than pretends did not happen.
    public private(set) var wasShown = false
    private let startFrame: Int

    /// Sets the experiment's world up and takes the first look, so there is something to compare against.
    public init(_ experiment: LabExperiment, in engine: PowderEngine) {
        self.experiment = experiment
        engine.resetGrid()
        experiment.setUp(engine)
        startFrame = engine.frameCount
        readings.look(at: engine, seconds: 0)
    }

    /// World seconds since it was set up.
    public func seconds(in engine: PowderEngine) -> Double {
        Double(max(0, engine.frameCount - startFrame)) / 60
    }

    /// Looks at the world again, and answers if it now can.
    ///
    /// - Returns: whether this look is the one that answered it.
    @discardableResult
    public mutating func look(at engine: PowderEngine) -> Bool {
        guard !isAnswered else { return false }
        readings.look(at: engine, seconds: seconds(in: engine))
        guard experiment.isAnswered(readings) else { return false }
        isAnswered = true
        explanation = experiment.explain(readings)
        return true
    }

    /// Takes the guess — or none, for somebody who would rather just watch — and starts the experiment.
    public mutating func start(guessing guess: Int?) {
        self.guess = guess.flatMap { experiment.guesses.indices.contains($0) ? $0 : nil }
        hasStarted = true
    }

    /// Does the task for somebody. Starts the experiment if it had not been.
    public mutating func showMe(in engine: PowderEngine) {
        hasStarted = true
        wasShown = true
        experiment.demonstrate(engine)
    }

    /// Whether the guess was right, once there has been one.
    public var guessedRight: Bool? { guess.map { $0 == experiment.answer } }

    /// A line about the guess, for the top of the explanation.
    public var verdict: String {
        guard let guess else { return "The answer: \(experiment.answerText)." }
        if guess == experiment.answer { return "You guessed \(experiment.guesses[guess].lowercasedFirst) — right." }
        return "You guessed \(experiment.guesses[guess].lowercasedFirst). "
            + "The answer is \(experiment.answerText.lowercasedFirst)."
    }
}

/// What has been done in the lab book, kept between launches.
public struct LabBookProgress: Codable, Sendable, Equatable {
    /// One experiment finished.
    public struct Entry: Codable, Sendable, Equatable {
        public var id: String
        public var guessedRight: Bool
        public var finishedAt: Double
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    /// Writes down an experiment as finished. Doing it again keeps the better result and the newer date.
    public mutating func finish(_ id: String, guessedRight: Bool, at time: Double) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].guessedRight = entries[index].guessedRight || guessedRight
            entries[index].finishedAt = time
        } else {
            entries.append(Entry(id: id, guessedRight: guessedRight, finishedAt: time))
        }
    }

    public func isDone(_ id: String) -> Bool { entries.contains { $0.id == id } }
    public func wasRight(_ id: String) -> Bool { entries.first { $0.id == id }?.guessedRight ?? false }
    public var doneCount: Int { entries.filter { entry in LabBook.named(entry.id) != nil }.count }
}

// MARK: - The book

public enum LabBook {
    /// Every experiment, in the order they are offered: easiest to see first.
    public static let experiments: [LabExperiment] = [
        floating, boiling, quenching, dissolving, acid, conducting, growing, freezing,
    ]

    public static func named(_ id: String) -> LabExperiment? { experiments.first { $0.id == id } }

    // MARK: Oil and water

    static let floating = LabExperiment(
        id: "floating",
        title: "Oil and water",
        question: "Pour oil into water. Where does the oil end up?",
        guesses: ["On top of the water", "At the bottom", "Mixed all through it"],
        answer: 0,
        task: "Pour oil into the tank of water.",
        material: Element.oil,
        symbol: "drop.halffull",
        patience: 20,
        setUp: { e in
            let tank = Tank(e, left: 0.2, right: 0.8, top: 0.35, bottom: 0.92)
            tank.build(Element.glass)
            tank.fill(Element.water, fromHeight: 0, toHeight: 0.55)
        },
        demonstrate: { e in
            // Poured in at the top of the tank, as a person would, so the oil has to find its own way.
            let tank = Tank(e, left: 0.2, right: 0.8, top: 0.35, bottom: 0.92)
            tank.fill(Element.oil, fromHeight: 0.62, toHeight: 0.85, inset: 0.15)
        },
        isAnswered: { r in
            // Enough oil to see, and it has had time to settle: at least three seconds since it arrived, and sitting
            // above the water.
            guard r.count(Element.oil) >= 40, let since = r.firstSeen[Element.oil] ?? (r.start[Element.oil] != nil ? 0 : nil)
            else { return false }
            let oil = r.heightOf[Element.oil] ?? 0
            let water = r.heightOf[Element.water] ?? 1
            return r.seconds - since >= 4 && oil > water
        },
        explain: { r in
            let oil = r.heightOf[Element.oil] ?? 0
            let water = r.heightOf[Element.water] ?? 0
            let density = LabBook.definition(Element.oil).density
            let waters = LabBook.definition(Element.water).density
            return [
                "Oil floats. \(LabBook.cells(r.count(Element.oil))) of your oil ended up sitting on "
                    + "\(LabBook.cells(r.count(Element.water))) of water.",
                "On average your oil is \(LabBook.percent(oil - water)) of the world's height above your water. "
                    + "Nothing pushed it there: wherever oil found itself under water, the water sank past it.",
                "That is because in this world oil weighs \(LabBook.number(density)) for every "
                    + "\(LabBook.number(waters)) that water weighs. The heavier of two liquids always falls through "
                    + "the lighter, so the lighter one ends up on top — the same reason a spill of oil on a puddle "
                    + "makes a rainbow on the surface instead of sinking.",
            ]
        }
    )

    // MARK: Boiling

    static let boiling = LabExperiment(
        id: "boiling",
        title: "How hot is boiling?",
        question: "Heat a pan of water from below. How hot does the water get before it boils away?",
        guesses: ["About 50°C", "About 100°C", "About 250°C", "It keeps getting hotter"],
        answer: 1,
        task: "Pour lava into the space under the copper pan.",
        material: Element.lava,
        symbol: "flame",
        patience: 25,
        // Every other moment. Water beside a hot pan goes from ninety-odd degrees to steam between two looks taken
        // a quarter of a second apart, so a quarter of a second apart it was never seen above eighty-three.
        lookEvery: 2,
        setUp: { e in Pan(e).build() },
        demonstrate: { e in
            let pan = Pan(e)
            LabBook.fill(e, pan.hearthLeft, pan.hearthTop, pan.hearthRight, pan.hearthBottom, Element.lava)
        },
        isAnswered: { r in
            // Some has boiled, and the hottest water has been seen close to boiling, so the number the explanation
            // gives is the world's own answer and not merely the warmest water that happened to be looked at.
            r.firstSeen[Element.lava] != nil
                && r.lost(Element.water) >= 30
                && (r.hottestOf[Element.water] ?? 0) >= 95
        },
        explain: { r in
            let hottest = r.hottestOf[Element.water] ?? 0
            let lava = r.hottestOf[Element.lava] ?? 1200
            let arrived = r.firstSeen[Element.lava] ?? 0
            var lines = [
                "About 100°C. The hottest water anywhere in your pan was \(LabBook.degrees(hottest)).",
                "Your lava was \(LabBook.degrees(lava)), more than ten times hotter, and its heat kept coming up "
                    + "through the copper — but the water never got past 100°C. That is where water stops being "
                    + "water: any hotter and it turns to steam, so the heat goes into boiling it rather than into "
                    + "making it hotter.",
                "\(LabBook.cells(r.lost(Element.water))) of your water boiled away.",
            ]
            if let first = r.firstSeen[Element.steam], first >= arrived {
                lines[2] += " The first of it went \(LabBook.seconds(first - arrived)) after your lava arrived."
            }
            return lines
        }
    )

    // MARK: Lava and water

    static let quenching = LabExperiment(
        id: "quenching",
        title: "Lava meets water",
        question: "Pour water onto lava. What does the lava turn into?",
        guesses: ["Sand", "Black glass — obsidian", "It stays lava", "Ordinary stone"],
        answer: 1,
        task: "Pour water onto the pool of lava.",
        material: Element.water,
        symbol: "water.waves",
        patience: 20,
        setUp: { e in
            // Bedrock, which lava cannot melt. A stone basin was melted into more lava a cell at a time, and the
            // count of how much lava set was then a count of lava that had partly been basin.
            let tank = Tank(e, left: 0.25, right: 0.75, top: 0.55, bottom: 0.92)
            tank.build(Element.bedrock)
            tank.fill(Element.lava, fromHeight: 0, toHeight: 0.45)
        },
        demonstrate: { e in
            let tank = Tank(e, left: 0.25, right: 0.75, top: 0.55, bottom: 0.92)
            // A deep layer of water, from well above the tank: lava throws the first of it straight back as steam.
            LabBook.fill(e, tank.innerLeft, Int(Double(e.height) * 0.12), tank.innerRight, tank.top - 1, Element.water)
        },
        isAnswered: { r in
            r.firstSeen[Element.water] != nil && r.gained(Element.obsidian) >= 30 && r.seconds >= 2
        },
        explain: { r in
            let lava = r.start[Element.lava] ?? 0
            var lines = [
                "Obsidian — black volcanic glass. \(LabBook.cells(r.gained(Element.obsidian))) of your "
                    + "\(LabBook.cells(lava)) of lava set into it.",
                "Your lava was \(LabBook.degrees(r.hottestOf[Element.lava] ?? 1200)). Water touching it boiled at "
                    + "once — \(LabBook.cells(r.gained(Element.steam))) of steam at the most — and every cell that "
                    + "boiled carried heat away with it. Lava that drops below 700°C cannot flow any more, and sets.",
                "Real obsidian forms exactly like this, where lava runs into the sea: it cools too fast for crystals "
                    + "to grow in it, so it sets as glass instead of as ordinary rock.",
            ]
            let still = r.count(Element.lava)
            if still > 0 {
                lines.append("Under the crust your water made, \(LabBook.cells(still)) of lava "
                    + "\(still == 1 ? "is" : "are") still hot enough to flow.")
            }
            return lines
        }
    )

    // MARK: Salt and water

    static let dissolving = LabExperiment(
        id: "dissolving",
        title: "Salt in water",
        question: "Pour salt into water. What happens to the salt?",
        guesses: ["It sinks and sits on the bottom", "It disappears into the water", "It floats"],
        answer: 1,
        task: "Pour salt into the tank of water.",
        material: Element.salt,
        symbol: "sparkle",
        patience: 20,
        setUp: { e in
            let tank = Tank(e, left: 0.2, right: 0.8, top: 0.4, bottom: 0.92)
            tank.build(Element.glass)
            tank.fill(Element.water, fromHeight: 0, toHeight: 0.8)
        },
        demonstrate: { e in
            let tank = Tank(e, left: 0.2, right: 0.8, top: 0.4, bottom: 0.92)
            LabBook.fill(e, tank.innerLeft + 4, tank.top - 12, tank.innerRight - 4, tank.top - 4, Element.salt)
        },
        isAnswered: { r in
            r.gained(Element.saltWater) >= 40 && r.seconds >= 3
        },
        explain: { r in
            let salted = r.gained(Element.saltWater)
            let salt = r.most[Element.salt] ?? 0
            let heavier = LabBook.definition(Element.saltWater).density
            let plain = LabBook.definition(Element.water).density
            var lines = [
                "It disappears into the water. \(LabBook.cells(salted)) of your water "
                    + "\(salted == 1 ? "has" : "have") salt dissolved in \(salted == 1 ? "it" : "them") now.",
                "The salt has not gone anywhere: it has broken up into pieces far too small to see and spread into "
                    + "the water. Taste the sea and it is all still there.",
            ]
            if let salty = r.heightOf[Element.saltWater], let fresh = r.heightOf[Element.water], salty < fresh {
                lines.append("Salt water is heavier than fresh — \(LabBook.number(heavier)) against "
                    + "\(LabBook.number(plain)) in this world — so your salty water has gathered low in the tank, "
                    + "under the fresh.")
            }
            if r.count(Element.salt) > 0 {
                lines.append("\(LabBook.cells(r.count(Element.salt))) of salt, out of the most there was "
                    + "(\(salt.grouped)), is still solid: salt that lands on salt has no water to dissolve into.")
            }
            return lines
        }
    )

    // MARK: Acid

    static let acid = LabExperiment(
        id: "acid",
        title: "What holds acid?",
        question: "Three cups: stone, metal and glass. Which one can hold acid?",
        guesses: ["Stone", "Metal", "Glass", "None of them"],
        answer: 2,
        task: "Pour acid into all three cups.",
        material: Element.acid,
        symbol: "testtube.2",
        patience: 25,
        setUp: { e in
            for (index, cup) in AcidCups.cups(e).enumerated() {
                cup.build(AcidCups.materials[index])
            }
        },
        demonstrate: { e in
            for cup in AcidCups.cups(e) {
                cup.fill(Element.acid, fromHeight: 0, toHeight: 0.7)
            }
        },
        isAnswered: { r in
            guard let arrived = r.firstSeen[Element.acid] else { return false }
            return r.seconds - arrived >= 6 && r.lost(Element.stone) >= 8
        },
        explain: { r in
            let stone = r.lost(Element.stone)
            let metal = r.lost(Element.metal)
            let glass = r.lost(Element.glass)
            let stoneWins = 100 - LabBook.definition(Element.stone).acidResistance
            let metalWins = 100 - LabBook.definition(Element.metal).acidResistance
            return [
                "Glass. Your acid ate \(LabBook.cells(stone)) of the stone cup and \(LabBook.cells(metal)) of the "
                    + "metal one, and \(glass == 0 ? "not one cell" : LabBook.cells(glass)) of the glass.",
                "Acid pulls other materials apart, and how often it wins depends on what it touches. Here, acid "
                    + "touching stone eats it \(LabBook.number(stoneWins)) times in a hundred, and metal only "
                    + "\(LabBook.number(metalWins)) — but a drop that fails once simply tries again the next moment, "
                    + "so metal holds out a little longer and then goes the same way. Glass never gives way at all.",
                "Each drop of acid is used up by what it eats, which is why the acid itself runs out. It is also why "
                    + "chemists keep acid in glass bottles.",
            ]
        }
    )

    // MARK: Heat along a bar

    static let conducting = LabExperiment(
        id: "conducting",
        title: "Heat along a bar",
        question: "Stand a copper bar and a glass rod in lava. Which one gets hot at the top?",
        guesses: ["Copper", "Glass", "Both the same"],
        answer: 0,
        task: "Pour lava into the trough, round the feet of both.",
        material: Element.lava,
        symbol: "thermometer.high",
        patience: 25,
        setUp: { e in Trough(e).build() },
        demonstrate: { e in
            let trough = Trough(e)
            LabBook.fill(e, trough.innerLeft, trough.lavaTop, trough.innerRight, trough.bottom - 1, Element.lava)
        },
        isAnswered: { r in
            guard let arrived = r.firstSeen[Element.lava] else { return false }
            let copper = r.coldestOf[Element.copper] ?? 0
            let glass = r.coldestOf[Element.glass] ?? 0
            return r.seconds - arrived >= 8 && copper >= glass + 10
        },
        explain: { r in
            let copperTop = r.coldestOf[Element.copper] ?? 20
            let glassTop = r.coldestOf[Element.glass] ?? 20
            let copperBottom = r.hottestOf[Element.copper] ?? 20
            let glassBottom = r.hottestOf[Element.glass] ?? 20
            return [
                "Copper. The top of your copper bar is \(LabBook.degrees(copperTop)); the top of your glass rod "
                    + "is \(LabBook.degrees(glassTop)).",
                "Their feet were in the same lava — the copper got to \(LabBook.degrees(copperBottom)) at the "
                    + "bottom and the glass to \(LabBook.degrees(glassBottom)). The difference is how readily each "
                    + "passes heat along from one piece of itself to the next. Copper is one of the best at it there "
                    + "is; glass passes on none at all here, so its heat stays where the lava put it. That is also why the "
                    + "copper is cooler at its foot: it is sending the heat on up.",
                "That is why pans are metal and their handles are not, and why a metal spoon in hot soup burns your "
                    + "fingers when a glass stirrer would not. Try the heat view to see it.",
            ]
        }
    )

    // MARK: Plants

    static let growing = LabExperiment(
        id: "growing",
        title: "What plants need",
        question: "Here are two plants. What will make them grow?",
        guesses: ["Sand", "Water", "Fire", "Nothing — they grow anyway"],
        answer: 1,
        task: "Give the plants some water.",
        material: Element.water,
        symbol: "leaf",
        patience: 25,
        setUp: { e in Bed(e).build() },
        demonstrate: { e in
            let bed = Bed(e)
            LabBook.fill(e, bed.left + 2, bed.soil - 16, bed.right - 2, bed.soil - 10, Element.water)
        },
        isAnswered: { r in
            r.firstSeen[Element.water] != nil && r.gained(Element.plant) >= 25 && r.seconds >= 3
        },
        explain: { r in
            let start = r.start[Element.plant] ?? 0
            let most = r.most[Element.plant] ?? start
            let poured = r.most[Element.water] ?? 0
            let gone = max(0, poured - r.count(Element.water))
            var lines = [
                "Water. Your plants grew from \(LabBook.cells(start)) to \(LabBook.cells(most)).",
                "Every piece of plant touching water can drink it and grow into the space it leaves. Of the most "
                    + "water there was at once — \(LabBook.cells(poured)) — \(gone.grouped) "
                    + "\(gone == 1 ? "has" : "have") gone, drunk by the plants or soaked into the soil.",
            ]
            if r.count(Element.mud) > 0 {
                lines[1] += " \(LabBook.cells(r.count(Element.mud))) of dirt soaked up enough to turn to mud."
            }
            lines.append("Left dry, a plant here never grows at all. Real plants need light and air as well, but "
                + "water is the one they run out of first — which is why a garden wilts in a dry week.")
            return lines
        }
    )

    // MARK: Freezing

    static let freezing = LabExperiment(
        id: "freezing",
        title: "Salt water and ice",
        question: "Pack ice round a cup of fresh water and a cup of salt water. Which one freezes?",
        guesses: ["The fresh water", "The salt water", "Both of them", "Neither"],
        answer: 0,
        task: "Pack ice all round both copper cups.",
        material: Element.ice,
        symbol: "snowflake",
        patience: 30,
        setUp: { e in Cups(e).build() },
        demonstrate: { e in Cups(e).packIce() },
        isAnswered: { r in
            // Fresh water that has become ice, and the salt water colder than fresh water can be and still liquid.
            guard let packed = r.firstSeen[Element.ice] else { return false }
            return r.seconds - packed >= 8
                && r.lost(Element.water) >= 20
                && (r.chilliestOf[Element.saltWater] ?? 20) < 0
                && r.count(Element.saltWater) > 0
        },
        explain: { r in
            let fresh = r.lost(Element.water)
            let salty = r.count(Element.saltWater)
            let cold = r.chilliestOf[Element.saltWater] ?? 0
            return [
                "The fresh water. \(LabBook.cells(fresh)) of it froze solid, while \(LabBook.cells(salty)) of salt "
                    + "water \(salty == 1 ? "is" : "are") still liquid beside it.",
                "Your salt water got as cold as \(LabBook.degrees(cold)) and stayed runny. Fresh water freezes at "
                    + "0°C; salt gets in the way of the water locking together into ice, so salt water has to be "
                    + "far colder before it will.",
                "That is why roads are salted in winter, and why the sea hardly ever freezes when ponds do.",
            ]
        }
    )

    // MARK: - Helpers

    static func definition(_ id: ElementID) -> ElementDefinition {
        // Every experiment is about built-in materials, which are always in this list.
        DefaultElements.all.first { $0.id == id } ?? DefaultElements.all[0]
    }

    static func cells(_ count: Int) -> String { count == 1 ? "1 cell" : "\(count.grouped) cells" }

    static func degrees(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded) >= 100 { return "\(Int(rounded.rounded()).grouped)°C" }
        return "\(LabBook.number(rounded))°C"
    }

    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return Int(rounded).grouped }
        let tenths = Int((abs(rounded) * 10).rounded())
        return (rounded < 0 ? "-" : "") + "\(tenths / 10).\(tenths % 10)"
    }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    static func seconds(_ value: Double) -> String {
        let whole = Int(value.rounded())
        if value < 0.75 { return "less than a second" }
        return whole == 1 ? "a second" : "\(whole) seconds"
    }

    /// Fills the empty part of a rectangle, inclusive, dropping anything off the edge.
    ///
    /// Only the empty part, because this is pouring: it used to write over whatever was there, and "pour lava round
    /// the feet of the bars" quietly replaced the bottom fifth of both bars with lava.
    static func fill(_ e: PowderEngine, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ id: ElementID, temp: Double? = nil) {
        guard x1 >= x0, y1 >= y0 else { return }
        for y in y0 ... y1 {
            for x in x0 ... x1 where e.isValid(x, y) && e.typeAt(x, y) == Element.empty {
                e.setElement(x, y, id, temp: temp)
            }
        }
    }
}

// MARK: - The shapes experiments are built from

/// An open-topped box with walls one cell thick... or thicker on a big world, so acid has something to get through.
struct Tank {
    let left: Int
    let right: Int
    let top: Int
    let bottom: Int
    let wall: Int
    let engine: PowderEngine

    init(_ e: PowderEngine, left: Double, right: Double, top: Double, bottom: Double, wall: Int? = nil) {
        engine = e
        self.left = Int(Double(e.width) * left)
        self.right = Int(Double(e.width) * right)
        self.top = Int(Double(e.height) * top)
        self.bottom = Int(Double(e.height) * bottom)
        self.wall = wall ?? max(2, e.width / 120)
    }

    var innerLeft: Int { left + wall }
    var innerRight: Int { right - wall }
    var innerBottom: Int { bottom - wall }

    func build(_ id: ElementID) {
        LabBook.fill(engine, left, top, left + wall - 1, bottom, id)
        LabBook.fill(engine, right - wall + 1, top, right, bottom, id)
        LabBook.fill(engine, left, bottom - wall + 1, right, bottom, id)
    }

    /// Fills the inside between two heights, as fractions of the inside from the floor up.
    func fill(_ id: ElementID, fromHeight low: Double, toHeight high: Double, inset: Double = 0) {
        let floor = innerBottom
        let span = Double(floor - top)
        let upper = floor - Int(span * high)
        let lower = floor - Int(span * low)
        let margin = Int(Double(innerRight - innerLeft) * inset)
        LabBook.fill(engine, innerLeft + margin, upper, innerRight - margin, lower, id)
    }
}

/// A copper pan with a hearth beneath it, walled in so lava poured there stays under the pan.
///
/// Copper, because lava melts stone: a stone pan was melted through a cell at a time, the lava reached the water
/// directly, and the water "boiled" at eighty degrees by being touched by lava rather than by being heated.
struct Pan {
    let engine: PowderEngine
    let left: Int
    let right: Int
    let panY: Int
    let thickness: Int
    let hearthBottom: Int

    init(_ e: PowderEngine) {
        engine = e
        left = Int(Double(e.width) * 0.25)
        right = Int(Double(e.width) * 0.75)
        panY = Int(Double(e.height) * 0.62)
        thickness = max(3, e.height / 60)
        hearthBottom = Int(Double(e.height) * 0.9)
    }

    var hearthLeft: Int { left + 2 }
    var hearthRight: Int { right - 2 }
    var hearthTop: Int { panY + thickness }

    func build() {
        // The pan: a floor of copper with low sides, holding water.
        LabBook.fill(engine, left, panY, right, panY + thickness - 1, Element.copper)
        let sides = Int(Double(engine.height) * 0.14)
        LabBook.fill(engine, left, panY - sides, left + 1, panY - 1, Element.copper)
        LabBook.fill(engine, right - 1, panY - sides, right, panY - 1, Element.copper)
        LabBook.fill(engine, left + 2, panY - sides + 3, right - 2, panY - 1, Element.water)
        // The hearth under it: bedrock walls and floor, so lava stays where it is poured and heats the pan.
        LabBook.fill(engine, left, hearthTop, left + 1, hearthBottom, Element.bedrock)
        LabBook.fill(engine, right - 1, hearthTop, right, hearthBottom, Element.bedrock)
        LabBook.fill(engine, left, hearthBottom + 1, right, hearthBottom + 2, Element.bedrock)
    }
}

/// Three cups side by side, each of a different material.
enum AcidCups {
    static let materials = [Element.stone, Element.metal, Element.glass]

    static func cups(_ e: PowderEngine) -> [Tank] {
        (0 ..< 3).map { index in
            let left = 0.08 + Double(index) * 0.3
            return Tank(e, left: left, right: left + 0.24, top: 0.55, bottom: 0.9, wall: max(3, e.width / 60))
        }
    }
}

/// A trough of bedrock with a copper bar and a glass rod standing in it.
///
/// Glass rather than stone for the poor conductor, because lava melts stone: the stone bar was eaten away from the
/// foot up while it was being compared.
struct Trough {
    let engine: PowderEngine
    let left: Int
    let right: Int
    let bottom: Int
    let lavaTop: Int
    let barTop: Int
    let copperX: Int
    let glassX: Int
    let barWidth: Int

    init(_ e: PowderEngine) {
        engine = e
        left = Int(Double(e.width) * 0.2)
        right = Int(Double(e.width) * 0.8)
        bottom = Int(Double(e.height) * 0.92)
        lavaTop = Int(Double(e.height) * 0.8)
        barTop = Int(Double(e.height) * Trough.barTopFraction)
        barWidth = max(3, e.width / 40)
        copperX = Int(Double(e.width) * 0.38)
        glassX = Int(Double(e.width) * 0.62) - barWidth
    }

    static let barTopFraction = 0.7

    var innerLeft: Int { left + 2 }
    var innerRight: Int { right - 2 }

    func build() {
        LabBook.fill(engine, left, lavaTop - 4, left + 1, bottom, Element.bedrock)
        LabBook.fill(engine, right - 1, lavaTop - 4, right, bottom, Element.bedrock)
        LabBook.fill(engine, left, bottom, right, bottom + 1, Element.bedrock)
        LabBook.fill(engine, copperX, barTop, copperX + barWidth - 1, bottom - 1, Element.copper)
        LabBook.fill(engine, glassX, barTop, glassX + barWidth - 1, bottom - 1, Element.glass)
    }
}

/// A bed of dirt with two plants in it.
struct Bed {
    let engine: PowderEngine
    let left: Int
    let right: Int
    let soil: Int
    let bottom: Int

    init(_ e: PowderEngine) {
        engine = e
        left = Int(Double(e.width) * 0.15)
        right = Int(Double(e.width) * 0.85)
        soil = Int(Double(e.height) * 0.8)
        bottom = Int(Double(e.height) * 0.92)
    }

    func build() {
        LabBook.fill(engine, left - 2, soil - 20, left - 1, bottom, Element.glass)
        LabBook.fill(engine, right + 1, soil - 20, right + 2, bottom, Element.glass)
        LabBook.fill(engine, left - 2, bottom + 1, right + 2, bottom + 2, Element.glass)
        LabBook.fill(engine, left, soil, right, bottom, Element.dirt)
        for fraction in [0.33, 0.66] {
            let x = left + Int(Double(right - left) * fraction)
            LabBook.fill(engine, x - 1, soil - 6, x + 1, soil - 1, Element.plant)
        }
    }
}

/// Two copper cups, one of fresh water and one of salt, in an insulated box with room round them for ice.
///
/// Copper, because glass passes no heat at all: in glass cups the ice could pack round the water for ever and the
/// water inside stayed at twenty degrees.
struct Cups {
    let engine: PowderEngine
    let fresh: Tank
    let salty: Tank
    let boxLeft: Int
    let boxRight: Int
    let boxTop: Int
    let boxBottom: Int

    init(_ e: PowderEngine) {
        engine = e
        fresh = Tank(e, left: 0.3, right: 0.44, top: 0.6, bottom: 0.8, wall: 1)
        salty = Tank(e, left: 0.56, right: 0.7, top: 0.6, bottom: 0.8, wall: 1)
        boxLeft = Int(Double(e.width) * 0.12)
        boxRight = Int(Double(e.width) * 0.88)
        boxTop = Int(Double(e.height) * 0.45)
        boxBottom = Int(Double(e.height) * 0.92)
    }

    func build() {
        LabBook.fill(engine, boxLeft, boxTop, boxLeft + 1, boxBottom, Element.bedrock)
        LabBook.fill(engine, boxRight - 1, boxTop, boxRight, boxBottom, Element.bedrock)
        LabBook.fill(engine, boxLeft, boxBottom + 1, boxRight, boxBottom + 2, Element.bedrock)
        fresh.build(Element.copper)
        salty.build(Element.copper)
        fresh.fill(Element.water, fromHeight: 0, toHeight: 0.9)
        salty.fill(Element.saltWater, fromHeight: 0, toHeight: 0.9)
    }

    /// Ice into every empty place in the box that is outside both cups — round them and under them, not in them.
    func packIce() {
        func inside(_ cup: Tank, _ x: Int, _ y: Int) -> Bool {
            x >= cup.left && x <= cup.right && y >= boxTop && y <= cup.bottom
        }
        for y in boxTop ... boxBottom {
            for x in (boxLeft + 2) ... (boxRight - 2)
                where engine.typeAt(x, y) == Element.empty && !inside(fresh, x, y) && !inside(salty, x, y)
            {
                engine.setElement(x, y, Element.ice)
            }
        }
    }
}

extension Int {
    /// With thousands separated, the same everywhere: the lab book's numbers are read, not parsed.
    var grouped: String {
        let digits = String(Swift.abs(self))
        var text = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { text.append(",") }
            text.append(character)
        }
        return (self < 0 ? "-" : "") + String(text.reversed())
    }
}

extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        // Names stay as they are: "Copper" is a word, "The fresh water" is a sentence start.
        let keep = ["Copper", "Stone", "Metal", "Glass", "Sand", "Water", "Fire"]
        if keep.contains(where: { hasPrefix($0) }) { return self }
        return first.lowercased() + dropFirst()
    }
}
