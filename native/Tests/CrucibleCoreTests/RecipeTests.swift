import Testing

@testable import CrucibleCore

/// The built-in scenes.
///
/// ## Why these are not compared against the web engine any more
///
/// They used to be, cell for cell, and that was right while the job was transcribing them.
/// It stopped being right the moment the scenes were deliberately rewritten: the old ones
/// were rectangles and circles at fixed fractions, which produced a dead-flat slab of ground,
/// seven identical trees at exactly equal spacing, and the *same picture every single time*.
/// Holding the new ones to the old grid would be holding them to the fault.
///
/// So the comparison is retired and replaced with tests for the things that actually have to
/// be true. Several of them would have failed on the old scenes, which is the point — in
/// particular ``groundIsNotFlat`` and ``differentSeedsDifferentWorlds``.
@Suite("Built-in scenes")
struct RecipeTests {
    /// Sizes worth laying a scene out at.
    ///
    /// The tiny ones are the interesting ones. Most scenes compute positions that fall well
    /// outside a world that small, so what is under test is the clipping and the `max(…)`
    /// guards rather than the layout — which is where this code is most likely to go wrong
    /// and where nobody looks.
    static let sizes: [(width: Int, height: Int)] = [
        (400, 700), (330, 454), (120, 90), (64, 48), (20, 16), (200, 40), (8, 8), (1, 1),
    ]

    /// The materials that make up ground rather than weather.
    ///
    /// Used to find the top of the ground. Taking simply the highest non-empty cell would
    /// find falling snow or a cloud instead, and measure the sky.
    static let groundMaterials: Set<ElementID> = [
        Element.sand, Element.stone, Element.dirt, Element.plant, Element.ice,
        Element.snow, Element.obsidian, Element.concrete, Element.mud, Element.bedrock,
        Element.coal, Element.wetMix, Element.salt, Element.metal, Element.wood, Element.glass,
    ]

    private func build(_ recipe: PowderRecipe, width: Int, height: Int, seed: UInt32) -> PowderEngine {
        let engine = PowderEngine(width: width, height: height, seed: 1)
        var generator = Mulberry32(seed: seed)
        recipe.apply(to: engine, random: &generator)
        return engine
    }

    /// The top of the solid ground in one column, found from the floor upwards.
    ///
    /// Walking up from the bottom while cells stay solid is what makes this the *ground* and
    /// not whatever happens to be floating above it.
    private func groundTop(_ engine: PowderEngine, _ x: Int) -> Int? {
        guard x >= 0, x < engine.width else { return nil }
        var y = engine.height - 3
        var found: Int?
        while y >= 0 {
            let id = engine.type[y * engine.width + x]
            guard Self.groundMaterials.contains(id) else { break }
            found = y
            y -= 1
        }
        return found
    }

    // MARK: It lays out at all, at every size

    /// Every scene at every size, which is mostly a test that nothing traps.
    ///
    /// Swift is stricter than JavaScript here in a way that matters: a range whose start is
    /// past its end stops the program rather than doing nothing, so a scene whose arithmetic
    /// produces a negative span is a crash and not a cosmetic problem. The 1×1 case exists
    /// entirely for that.
    @Test("Every scene lays out at every size without trapping")
    func everySceneEverySize() {
        for recipe in powderRecipes {
            for size in Self.sizes {
                let engine = build(recipe, width: size.width, height: size.height, seed: 7)
                #expect(
                    engine.width == size.width && engine.height == size.height,
                    "\(recipe.id) at \(size.width)x\(size.height) disturbed the world's size"
                )
            }
        }
    }

    @Test("Every scene puts something in a world big enough to hold it")
    func everySceneFillsSomething() {
        for recipe in powderRecipes {
            let engine = build(recipe, width: 200, height: 300, seed: 3)
            let filled = engine.activeParticleCount
            let total = engine.cellCount
            #expect(filled > total / 50, "\(recipe.id) left the world all but empty (\(filled)/\(total))")
            // And not solid, or there is nowhere for anything to happen.
            #expect(filled < (total * 19) / 20, "\(recipe.id) filled the world solid (\(filled)/\(total))")
        }
    }

    @Test("Every scene keeps the basin it is built in")
    func basinSurvives() {
        for recipe in powderRecipes {
            let engine = build(recipe, width: 120, height: 90, seed: 11)
            for x in 0 ..< engine.width {
                let bottom = engine.type[(engine.height - 1) * engine.width + x]
                #expect(bottom == Element.bedrock, "\(recipe.id) lost the floor at x=\(x)")
            }
        }
    }

    // MARK: The two faults the rewrite existed to fix

    /// The scenes used to be laid out purely from the width and the height, so the same size
    /// always produced exactly the same world — thirteen fixed pictures. This is the test that
    /// says they are arrangements rather than pictures.
    @Test("Two seeds build two different worlds")
    func differentSeedsDifferentWorlds() {
        for recipe in powderRecipes {
            let a = build(recipe, width: 200, height: 300, seed: 1)
            let b = build(recipe, width: 200, height: 300, seed: 424_242)
            var differences = 0
            for i in 0 ..< a.cellCount where a.type[i] != b.type[i] { differences += 1 }
            #expect(
                differences > a.cellCount / 100,
                "\(recipe.id) built nearly the same world from a different seed: \(differences) of \(a.cellCount) cells differ"
            )
        }
    }

    /// Ground was a filled rectangle, so its top edge was a perfectly straight line across the
    /// whole world. That single fact is most of why the scenes looked like diagrams.
    ///
    /// Only the scenes that have open ground are checked. A reactor and a circuit board are
    /// built things and are supposed to have straight edges.
    @Test("The ground is not flat")
    func groundIsNotFlat() {
        let outdoors = ["volcano", "ants", "oil", "dam", "storm", "snow", "beach", "forest"]
        for id in outdoors {
            guard let recipe = powderRecipes.first(where: { $0.id == id }) else {
                Issue.record("no scene called \(id)")
                continue
            }
            let engine = build(recipe, width: 220, height: 300, seed: 5)

            var lowest = Int.max
            var highest = Int.min
            var sampled = 0
            for x in 4 ..< (engine.width - 4) {
                guard let top = groundTop(engine, x) else { continue }
                lowest = min(lowest, top)
                highest = max(highest, top)
                sampled += 1
            }
            #expect(sampled > engine.width / 2, "\(id): could not find ground in most columns")
            #expect(
                highest - lowest > 3,
                "\(id): the ground rises and falls by only \(highest - lowest) cells, which is flat"
            )
        }
    }

    // MARK: Reproducible, which is what makes a shared world possible

    /// The day's world is the same for everybody, so a seed has to mean one world exactly.
    @Test("The same seed builds the same world twice")
    func sameSeedSameWorld() {
        for recipe in powderRecipes {
            let a = build(recipe, width: 160, height: 200, seed: 99)
            let b = build(recipe, width: 160, height: 200, seed: 99)
            var differences = 0
            for i in 0 ..< a.cellCount where a.type[i] != b.type[i] { differences += 1 }
            #expect(differences == 0, "\(recipe.id) built \(differences) cells differently from one seed")
            #expect(a.hashLite() == b.hashLite())
        }
    }

    // MARK: Each scene is the thing it says it is

    /// Ground in layers, which is the other half of not being a slab: a skin of grass over
    /// soil over rock, all following the same rolling surface.
    @Test("Forest has grass over soil over rock")
    func forestIsLayered() throws {
        let recipe = try #require(powderRecipes.first { $0.id == "forest" })
        let engine = build(recipe, width: 220, height: 300, seed: 21)

        var layered = 0
        var checked = 0
        for x in stride(from: 6, to: engine.width - 6, by: 5) {
            guard let top = groundTop(engine, x) else { continue }
            checked += 1
            let surface = engine.type[top * engine.width + x]
            let mid = engine.type[min(engine.height - 3, top + 3) * engine.width + x]
            let deep = engine.type[min(engine.height - 3, top + 9) * engine.width + x]
            // Allowing for a pond, a boulder or a trunk at any given column.
            if surface == Element.plant, mid == Element.dirt || mid == Element.plant,
               deep == Element.stone || deep == Element.dirt {
                layered += 1
            }
        }
        #expect(checked > 10, "not enough columns had ground")
        #expect(
            layered > checked / 2,
            "only \(layered) of \(checked) columns were grass over soil over rock"
        )
    }

    /// Trees used to be seven identical shapes at exactly equal spacing. Measured through the
    /// canopy tops, because that is what the eye actually reads as "these are all the same".
    @Test("Forest trees are different heights at uneven spacing")
    func forestTreesVary() throws {
        let recipe = try #require(powderRecipes.first { $0.id == "forest" })
        let engine = build(recipe, width: 260, height: 320, seed: 33)

        // The highest plant cell in each column, which is a canopy top where there is one.
        var tops: [Int] = []
        for x in 0 ..< engine.width {
            var y = 0
            while y < engine.height {
                if engine.type[y * engine.width + x] == Element.plant {
                    tops.append(y)
                    break
                }
                y += 1
            }
        }
        let distinct = Set(tops)
        #expect(tops.count > 20, "found almost no foliage")
        #expect(
            distinct.count > 6,
            "the canopies sit at only \(distinct.count) different heights, so they are clones"
        )
    }

    /// A regression guard with a story: the canopies were once made of ants, which eat wood and
    /// plants, so every tree devoured its own trunk moments after the scene loaded.
    @Test("Forest contains nothing that eats it")
    func forestHasNoAnts() throws {
        let recipe = try #require(powderRecipes.first { $0.id == "forest" })
        let engine = build(recipe, width: 200, height: 260, seed: 4)
        var ants = 0
        for i in 0 ..< engine.cellCount where engine.type[i] == Element.ant { ants += 1 }
        #expect(ants == 0, "\(ants) ants in the forest, which will eat the trees")
    }

    @Test("The scenes that promise something contain it")
    func scenesContainTheirSubject() throws {
        let expectations: [(id: String, id2: ElementID, what: String)] = [
            ("volcano", Element.lava, "lava"),
            ("ants", Element.ant, "ants"),
            ("oil", Element.oil, "oil"),
            ("dam", Element.ice, "ice"),
            ("reactor", Element.metal, "a vessel"),
            ("storm", Element.copper, "a rod"),
            ("circuit", Element.copper, "traces"),
            ("vacuum", Element.void, "a void"),
            ("snow", Element.snow, "snow"),
            ("beach", Element.water, "sea"),
            ("forest", Element.wood, "trees"),
            ("kiln", Element.lava, "a fire"),
        ]
        for case let (id, wanted, what) in expectations {
            let recipe = try #require(powderRecipes.first { $0.id == id })
            let engine = build(recipe, width: 200, height: 280, seed: 8)
            var count = 0
            for i in 0 ..< engine.cellCount where engine.type[i] == wanted { count += 1 }
            #expect(count > 0, "\(id) contains no \(what)")
        }
    }

    // MARK: The list itself

    /// The daily scene is chosen by taking a hash of the date modulo this count, so the order
    /// is part of the contract rather than a presentation detail.
    @Test("The list is the thirteen scenes, in order, with unique names")
    func listIsStable() {
        #expect(powderRecipes.count == 13)
        #expect(powderRecipes.map(\.id) == [
            "volcano", "ants", "oil", "dam", "reactor", "storm", "circuit",
            "vacuum", "snow", "beach", "forest", "kiln", "remix",
        ])
        #expect(Set(powderRecipes.map(\.id)).count == 13)
        #expect(Set(powderRecipes.map(\.name)).count == 13)
        for recipe in powderRecipes {
            #expect(!recipe.name.isEmpty, "\(recipe.id) has no name")
        }
    }
}
