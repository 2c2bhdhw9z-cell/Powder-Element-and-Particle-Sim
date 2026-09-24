import Testing

@testable import CrucibleCore

/// Chemistry behaviours translated from the web implementation's own suite
/// (`web/src/sim/__tests__/powder.test.ts`).
///
/// The golden-fixture comparison already proves the port matches the web engine
/// cell for cell, which is a stronger guarantee than anything here. These exist
/// for a different reason: they say *what the simulation is supposed to do*, in
/// terms a person can read. When one of them fails it names the broken behaviour,
/// where a golden mismatch only says that row 23 differs.
@Suite("Powder chemistry")
struct PowderChemistryTests {
    private func countType(_ engine: PowderEngine, _ id: ElementID) -> Int {
        var count = 0
        for i in 0 ..< engine.cellCount where engine.type[i] == id { count += 1 }
        return count
    }

    private func countType(_ engine: PowderEngine, in rows: Range<Int>, _ id: ElementID) -> Int {
        var count = 0
        for y in rows where y >= 0 && y < engine.height {
            for x in 0 ..< engine.width where engine.type[engine.index(x, y)] == id {
                count += 1
            }
        }
        return count
    }

    private func maxTemperature(_ engine: PowderEngine, of id: ElementID) -> Double {
        var highest = -Double.greatestFiniteMagnitude
        for i in 0 ..< engine.cellCount where engine.type[i] == id {
            highest = max(highest, engine.temperature[i].asDouble)
        }
        return highest == -Double.greatestFiniteMagnitude ? 0 : highest
    }

    // MARK: - Phase changes

    @Test("Ice melts into water above freezing")
    func iceMelts() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        engine.setElement(16, 16, Element.ice, temp: 10)
        engine.step()
        #expect(engine.type[engine.index(16, 16)] == Element.water)
    }

    @Test("Cool lava sets into obsidian while hot lava stays molten")
    func lavaVitrifiesWhenCool() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        // A floor, so the lava cannot simply fall away from where it was placed.
        for x in 8 ... 24 { engine.setElement(x, 17, Element.bedrock) }
        engine.setElement(10, 16, Element.lava, temp: 500)   // below the threshold
        engine.setElement(20, 16, Element.lava, temp: 1200)  // still molten
        engine.step()

        #expect(engine.type[engine.index(10, 16)] == Element.obsidian)

        // The hot one may have flowed a cell sideways on its first tick, so count
        // rather than checking a fixed position.
        var stillMolten = 0
        for x in 8 ... 24 where engine.type[engine.index(x, 16)] == Element.lava {
            stillMolten += 1
        }
        #expect(stillMolten == 1, "the hot cell must still be lava somewhere on that row")
    }

    @Test("Fire becomes smoke, and smoke eventually becomes nothing")
    func fireDecayChain() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        engine.setElement(16, 20, Element.fire, temp: 600, life: 2)
        engine.step()
        engine.step()
        engine.step()
        #expect(countType(engine, Element.fire) == 0)
        #expect(countType(engine, Element.smoke) == 1)

        for _ in 0 ..< 160 { engine.step() }
        #expect(countType(engine, Element.smoke) == 0)
        #expect(countType(engine, Element.fire) == 0)
    }

    // MARK: - The lava and water fight

    @Test("A thin cap of water still drives a lava pocket below the threshold, without oscillating")
    func thinWaterCapVitrifiesLava() {
        // The hardest behaviour in the simulation, and the reason the web
        // implementation's cooling coefficients are shaped the way they are.
        //
        // The geometry matters: a *shallow* cap over a small pocket, not a deep
        // basin. A deep pool resolves even with weak cooling, so it would not
        // exercise the problem. Here the water flashes to steam within a few ticks,
        // so the lava cannot be beaten by water volume — it has to keep shedding
        // heat to its steam and obsidian neighbours, through terms proportional to
        // how much hotter it is than they are. With a fixed cooling amount instead,
        // the lava stalls around 1100°C and the pair oscillates forever.
        let engine = PowderEngine(width: 40, height: 40, seed: 1234)
        let floorY = 30
        let left = 17
        let right = 23

        for x in left ... right { engine.setElement(x, floorY, Element.bedrock) }
        for y in (floorY - 4) ... floorY {
            engine.setElement(left, y, Element.bedrock)
            engine.setElement(right, y, Element.bedrock)
        }
        for x in (left + 1) ... (right - 1) {
            for y in (floorY - 2) ... (floorY - 1) {
                engine.setElement(x, y, Element.lava, temp: 1300)
            }
        }
        for x in (left + 1) ... (right - 1) {
            engine.setElement(x, floorY - 3, Element.water)
        }

        #expect(countType(engine, Element.lava) == 10)

        let budget = 400
        var resolvedAt = -1
        for tick in 0 ..< budget {
            engine.step()
            if resolvedAt < 0 && countType(engine, Element.lava) == 0 {
                resolvedAt = tick
            }
        }

        #expect(resolvedAt >= 0, "the fight never finished")
        #expect(resolvedAt < budget)
        #expect(countType(engine, Element.lava) == 0)
        #expect(
            maxTemperature(engine, of: Element.lava) < 700,
            "no lava may be left stalled above the vitrification threshold"
        )
        #expect(
            countType(engine, Element.obsidian) > 0,
            "it must have set into obsidian, not merely boiled its surroundings away"
        )
    }

    @Test("Once a lava pocket has crusted over it stays crusted")
    func obsidianDoesNotRemelt() {
        // The complement to the test above. After the fight resolves, the leftover
        // steam and condensation must settle rather than re-quenching forever.
        let engine = PowderEngine(width: 40, height: 40, seed: 1234)
        let floorY = 30
        let left = 17
        let right = 23

        for x in left ... right { engine.setElement(x, floorY, Element.bedrock) }
        for y in (floorY - 4) ... floorY {
            engine.setElement(left, y, Element.bedrock)
            engine.setElement(right, y, Element.bedrock)
        }
        for x in (left + 1) ... (right - 1) {
            for y in (floorY - 2) ... (floorY - 1) {
                engine.setElement(x, y, Element.lava, temp: 1300)
            }
        }
        for x in (left + 1) ... (right - 1) {
            engine.setElement(x, floorY - 3, Element.water)
        }

        for _ in 0 ..< 400 { engine.step() }
        #expect(countType(engine, Element.lava) == 0)
        #expect(countType(engine, Element.obsidian) > 0)

        var remelted = false
        for _ in 0 ..< 200 {
            engine.step()
            if countType(engine, Element.lava) != 0 { remelted = true }
        }
        #expect(!remelted, "obsidian must not turn back into lava")
    }

    // MARK: - Reactions

    @Test("Acid dissolves sand and is used up doing it")
    func acidDissolvesAndIsConsumed() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        for x in 10 ... 22 {
            engine.setElement(x, engine.height - 1, Element.bedrock)
            engine.setElement(x, engine.height - 2, Element.sand)
        }
        for x in 14 ... 17 { engine.setElement(x, engine.height - 3, Element.acid) }

        let sandBefore = countType(engine, Element.sand)
        #expect(countType(engine, Element.acid) == 4)

        for _ in 0 ..< 40 { engine.step() }

        #expect(countType(engine, Element.acid) == 0, "acid is consumed by what it dissolves")
        #expect(countType(engine, Element.sand) < sandBefore)
    }

    @Test("Glass resists acid completely")
    func glassIsAcidProof() {
        let engine = PowderEngine(width: 24, height: 24, seed: 1234)
        for x in 6 ... 17 { engine.setElement(x, 16, Element.glass) }
        for x in 8 ... 15 { engine.setElement(x, 15, Element.acid) }
        for _ in 0 ..< 100 { engine.step() }
        #expect(countType(engine, Element.glass) == 12, "not one pane may be lost")
    }

    @Test("Fire spreads through wood and leaves smoke behind")
    func fireSpreads() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        for x in 0 ..< engine.width { engine.setElement(x, engine.height - 1, Element.bedrock) }
        for x in 8 ... 23 {
            for y in 20 ... 28 { engine.setElement(x, y, Element.wood) }
        }
        let woodBefore = countType(engine, Element.wood)
        engine.setElement(15, 19, Element.fire, temp: 600, life: 40)

        for _ in 0 ..< 150 { engine.step() }
        #expect(countType(engine, Element.wood) < woodBefore, "the fire took hold")
    }

    @Test("Water puts fire out, but only if it is still there when the fire looks")
    func waterExtinguishesFire() {
        // Supported water: the fire meets it and becomes steam.
        let supported = PowderEngine(width: 24, height: 24, seed: 1234)
        for x in 0 ..< supported.width { supported.setElement(x, 21, Element.bedrock) }
        supported.setElement(12, 20, Element.water)
        supported.setElement(12, 19, Element.fire, temp: 600, life: 200)
        supported.step()
        #expect(countType(supported, Element.fire) == 0, "the fire lost")
        #expect(countType(supported, Element.steam) == 1, "and left steam behind")

        // Unsupported water falls away before the fire is ever processed, because
        // the scan runs bottom-up and reaches the water first. The fire survives.
        // Worth pinning down: it looks like a bug in the extinguishing rule and is
        // really just the scan order doing exactly what it should.
        let unsupported = PowderEngine(width: 24, height: 24, seed: 1234)
        for x in 0 ..< unsupported.width { unsupported.setElement(x, unsupported.height - 1, Element.bedrock) }
        unsupported.setElement(12, 20, Element.water)
        unsupported.setElement(12, 19, Element.fire, temp: 600, life: 200)
        unsupported.step()
        #expect(countType(unsupported, Element.fire) == 1, "the water dropped out from under it")
    }

    @Test("A plant drinks the water beside it and grows into it")
    func plantsGrow() {
        let engine = PowderEngine(width: 24, height: 24, seed: 1234)
        engine.setElement(12, 12, Element.plant)
        engine.setElement(12, 11, Element.water)
        engine.step()
        #expect(engine.type[engine.index(12, 11)] == Element.plant)
    }

    @Test("Salt dissolving turns fresh water salty")
    func saltDissolves() {
        let engine = PowderEngine(width: 24, height: 24, seed: 1234)
        for x in 8 ... 15 { engine.setElement(x, 20, Element.bedrock) }
        for x in 8 ... 15 { engine.setElement(x, 19, Element.water) }
        for x in 8 ... 15 { engine.setElement(x, 18, Element.salt) }

        for _ in 0 ..< 60 { engine.step() }
        #expect(countType(engine, Element.saltWater) > 0, "the water became salty")
        #expect(countType(engine, Element.salt) < 8, "some salt was consumed")
    }

    @Test("A duplicator copies whatever touches it")
    func cloneDuplicates() {
        let engine = PowderEngine(width: 24, height: 24, seed: 1234)
        for x in 0 ..< engine.width { engine.setElement(x, engine.height - 1, Element.bedrock) }
        engine.setElement(12, 20, Element.clone)
        engine.setElement(12, 19, Element.stone)
        let before = countType(engine, Element.stone)
        for _ in 0 ..< 40 { engine.step() }
        #expect(countType(engine, Element.stone) > before, "the duplicator produced more stone")
    }

    @Test("The void consumes whatever reaches it")
    func voidConsumes() {
        let engine = PowderEngine(width: 24, height: 24, seed: 1234)
        engine.setElement(12, 20, Element.void)
        for x in 10 ... 14 {
            for y in 4 ... 8 { engine.setElement(x, y, Element.sand) }
        }
        for _ in 0 ..< 120 { engine.step() }
        #expect(countType(engine, Element.sand) < 25, "sand was swallowed")
        #expect(countType(engine, Element.void) == 1, "the void itself persists")
    }

    @Test("The blast wave spares bedrock, though stray embers can still land on it")
    func bedrockIsBlastProof() {
        // The blast itself has an explicit bedrock exemption and honours it
        // completely. The ember phase that follows does not check what it lands on,
        // so a small number of bedrock cells can be overwritten by flying debris.
        //
        // That is an inconsistency in the original — bedrock is documented as
        // indestructible — and it is reproduced here rather than corrected, because
        // the two engines are verified against each other cell for cell and a
        // one-sided fix would break that. Worth deciding on deliberately later.
        let engine = PowderEngine(width: 40, height: 40, seed: 1234)
        for x in 0 ..< engine.width { engine.setElement(x, 30, Element.bedrock) }
        let before = countType(engine, Element.bedrock)
        engine.triggerExplosion(centerX: 20, centerY: 30, radius: 12)
        let after = countType(engine, Element.bedrock)

        #expect(after >= before - 3, "the wall must survive essentially intact, not be blown open")
        #expect(
            after < before || after == before,
            "recorded for visibility: embers can overwrite bedrock (\(before) -> \(after))"
        )
    }

    @Test("An explosion fills the world and reports itself")
    func explosionFiresCallback() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        var bursts = 0
        engine.onBurst = { _, _, _ in bursts += 1 }
        engine.triggerExplosion(centerX: 16, centerY: 16, radius: 8)
        #expect(bursts == 1)
        #expect(engine.activeParticleCount > 0, "the blast left material behind")
    }

    @Test("Lightning reaches water and flashes it to steam")
    func sparkSeeksWater() {
        let engine = PowderEngine(width: 32, height: 24, seed: 1234)
        for x in 0 ..< engine.width { engine.setElement(x, engine.height - 1, Element.bedrock) }
        for x in 20 ... 27 {
            for y in 16 ... 20 { engine.setElement(x, y, Element.water) }
        }
        engine.setElement(4, 16, Element.spark, temp: 1000, life: 60)

        for _ in 0 ..< 60 { engine.step() }
        #expect(countType(engine, Element.steam) > 0, "water was flashed to steam")
    }

    @Test("Copper carries heat without carrying mass")
    func copperPipesHeat() {
        let engine = PowderEngine(width: 32, height: 24, seed: 1234)
        // The lava needs a cradle. Left unsupported it falls away from the pipe on
        // the first tick and nothing heats up at all — which is a genuinely easy
        // mistake to make when setting this up.
        for x in 3 ... 6 { engine.setElement(x, 18, Element.bedrock) }
        engine.setElement(3, 17, Element.bedrock)
        engine.setElement(6, 17, Element.bedrock)
        for x in 4 ... 27 { engine.setElement(x, 16, Element.copper) }
        for x in 4 ... 5 { engine.setElement(x, 17, Element.lava, temp: 1400) }

        let nearBefore = engine.temperature[engine.index(4, 16)].asDouble
        for _ in 0 ..< 200 { engine.step() }

        let near = engine.temperature[engine.index(4, 16)].asDouble
        let middle = engine.temperature[engine.index(16, 16)].asDouble

        #expect(near > nearBefore + 100, "the end touching the lava got hot")
        #expect(middle > nearBefore + 10, "and the heat travelled along the run")
        #expect(near > middle, "attenuating as it goes")
        #expect(engine.type[engine.index(27, 16)] == Element.copper, "the copper itself did not move")
    }

    @Test("Denser sand sinks through lighter water")
    func sandSinksThroughWater() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        for x in 0 ..< engine.width { engine.setElement(x, engine.height - 1, Element.bedrock) }
        for x in 1 ... 30 {
            for y in 26 ... 27 { engine.setElement(x, y, Element.sand) }
            for y in 28 ... 30 { engine.setElement(x, y, Element.water) }
        }

        for _ in 0 ..< 200 { engine.step() }

        let low = countType(engine, in: (engine.height - 4) ..< (engine.height - 1), Element.sand)
        let high = countType(engine, in: 26 ..< 28, Element.sand)
        #expect(low > high, "the sand ended up underneath")
    }

    @Test("Inverted gravity sends water to the ceiling")
    func waterRisesWithInvertedGravity() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        engine.gravityY = -1
        for x in 4 ..< 12 { engine.setElement(x, 20, Element.water) }
        for _ in 0 ..< 60 { engine.step() }
        #expect(countType(engine, in: 0 ..< 6, Element.water) == 8)
        #expect(countType(engine, in: 12 ..< engine.height, Element.water) == 0)
    }

    @Test("Under weightlessness flames still rise")
    func plasmaRisesInZeroGravity() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        engine.gravityY = 0
        engine.setElement(16, 24, Element.fire, temp: 600, life: 40)
        for _ in 0 ..< 10 { engine.step() }

        var foundAbove = false
        for y in 0 ..< 24 {
            let cell = engine.type[engine.index(16, y)]
            if cell == Element.fire || cell == Element.smoke {
                foundAbove = true
                break
            }
        }
        #expect(foundAbove, "fire or its smoke should have climbed above where it started")
    }
}

@Suite("Powder brush tools")
struct PowderBrushTests {
    private func countType(_ engine: PowderEngine, _ id: ElementID) -> Int {
        var count = 0
        for i in 0 ..< engine.cellCount where engine.type[i] == id { count += 1 }
        return count
    }

    @Test("A radius-one circle paints a plus shape of five cells")
    func circleBrushShape() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        engine.drawBrush(centerX: 8, centerY: 8, radius: 1, elementID: Element.sand, shape: .circle)
        for (x, y) in [(8, 8), (7, 8), (9, 8), (8, 7), (8, 9)] {
            #expect(engine.type[engine.index(x, y)] == Element.sand, "(\(x), \(y)) should be painted")
        }
        #expect(countType(engine, Element.sand) == 5)
    }

    @Test("A radius-one square paints nine cells")
    func squareBrushShape() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        engine.drawBrush(centerX: 8, centerY: 8, radius: 1, elementID: Element.sand, shape: .square)
        #expect(countType(engine, Element.sand) == 9)
    }

    @Test("Spray paints a scattered subset of the disc")
    func sprayBrushIsSparse() {
        let engine = PowderEngine(width: 64, height: 64, seed: 1234)
        engine.drawBrush(centerX: 32, centerY: 32, radius: 10, elementID: Element.sand, shape: .spray)
        let painted = countType(engine, Element.sand)
        #expect(painted > 0, "spray must paint something")
        #expect(painted < 300, "but far fewer cells than a solid disc of that radius")
    }

    @Test("Replace only paints over the chosen element")
    func replaceBrushIsSelective() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        for x in 4 ... 12 { engine.setElement(x, 8, Element.stone) }
        for x in 13 ... 20 { engine.setElement(x, 8, Element.wood) }

        engine.drawBrush(
            centerX: 12, centerY: 8, radius: 4,
            elementID: Element.sand, shape: .replace,
            targetElementID: Element.stone
        )

        #expect(countType(engine, Element.wood) == 8, "the wood was left alone")
        #expect(countType(engine, Element.sand) == 5, "only the stone inside the brush was replaced")
        #expect(countType(engine, Element.stone) == 4, "and the stone outside it survived")
    }

    @Test("A target element is ignored unless the shape is replace")
    func targetOnlyAppliesToReplaceShape() {
        // Easy to get wrong: passing a target element alongside a circle or square
        // shape does nothing, and the brush paints over everything. Pinned down
        // because the mistake is silent.
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        for x in 4 ... 12 { engine.setElement(x, 8, Element.stone) }
        for x in 13 ... 20 { engine.setElement(x, 8, Element.wood) }

        engine.drawBrush(
            centerX: 12, centerY: 8, radius: 4,
            elementID: Element.sand, shape: .square,
            targetElementID: Element.stone
        )

        #expect(countType(engine, Element.wood) == 4, "the wood inside the square was painted over regardless")
        #expect(countType(engine, Element.sand) == 81, "a full 9x9 block was painted")
    }

    @Test("Fill floods the connected region and stops at a boundary")
    func fillIsBounded() {
        let engine = PowderEngine(width: 24, height: 24, seed: 1234)
        // A sealed box; filling inside it must not leak out.
        for x in 6 ... 17 {
            engine.setElement(x, 6, Element.stone)
            engine.setElement(x, 17, Element.stone)
        }
        for y in 6 ... 17 {
            engine.setElement(6, y, Element.stone)
            engine.setElement(17, y, Element.stone)
        }

        engine.drawBrush(centerX: 12, centerY: 12, radius: 1, elementID: Element.water, shape: .fill)

        #expect(countType(engine, Element.water) == 100, "the 10x10 interior filled")
        #expect(engine.type[engine.index(2, 2)] == Element.empty, "and nothing escaped the box")
    }

    @Test("Filling with what is already there does nothing")
    func fillIsIdempotent() {
        let engine = PowderEngine(width: 16, height: 16, seed: 1234)
        engine.setElement(8, 8, Element.sand)
        engine.drawBrush(centerX: 8, centerY: 8, radius: 1, elementID: Element.sand, shape: .fill)
        #expect(countType(engine, Element.sand) == 1)
    }

    @Test("Bulk spawning places exactly the number asked for")
    func spawnAmountIsExact() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        engine.spawnAmount(elementID: Element.sand, amount: 50)
        #expect(engine.activeParticleCount == 50)
    }

    @Test("Bulk spawning cannot overfill a small world")
    func spawnAmountRespectsCapacity() {
        let engine = PowderEngine(width: 4, height: 4, seed: 1234)
        engine.spawnAmount(elementID: Element.sand, amount: 1000)
        #expect(engine.activeParticleCount == 16, "a sixteen-cell world holds sixteen cells")
    }

    @Test("Painting a fan onto a fan turns it, and the rate limit holds")
    func fanRotationIsRateLimited() {
        let engine = PowderEngine(width: 16, height: 16, seed: 1234)
        engine.setElement(8, 8, Element.fan)
        let idx = engine.index(8, 8)
        #expect(engine.life[idx] == 0)

        // A drag delivers many strokes in quick succession; only the first turns it.
        engine.drawBrush(centerX: 8, centerY: 8, radius: 0, elementID: Element.fan, shape: .square, now: 1000)
        #expect(engine.life[idx] == 1)
        engine.drawBrush(centerX: 8, centerY: 8, radius: 0, elementID: Element.fan, shape: .square, now: 1100)
        #expect(engine.life[idx] == 1, "too soon to turn again")

        engine.drawBrush(centerX: 8, centerY: 8, radius: 0, elementID: Element.fan, shape: .square, now: 2000)
        #expect(engine.life[idx] == 2)

        // Four positions, then back to the first.
        engine.drawBrush(centerX: 8, centerY: 8, radius: 0, elementID: Element.fan, shape: .square, now: 3000)
        engine.drawBrush(centerX: 8, centerY: 8, radius: 0, elementID: Element.fan, shape: .square, now: 4000)
        #expect(engine.life[idx] == 0, "rotation wraps after four")
    }
}
