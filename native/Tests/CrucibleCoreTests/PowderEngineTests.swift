import Testing

@testable import CrucibleCore

/// Behaviors translated from the web implementation's own suite
/// (`web/src/sim/__tests__/powder.test.ts`), limited to the ones that depend only
/// on movement and decay. The rest arrive with the chemistry.
@Suite("Powder mechanics, from the reference suite")
struct PowderMechanicsTests {
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

    @Test("Sand falls to the bottom of the grid")
    func sandFalls() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        for y in 2 ..< 6 { engine.setElement(16, y, Element.sand) }
        for _ in 0 ..< 80 { engine.step() }

        #expect(countType(engine, in: (engine.height - 5) ..< engine.height, Element.sand) == 4)
        #expect(countType(engine, in: 0 ..< (engine.height - 5), Element.sand) == 0)
    }

    @Test("Inert elements are neither created nor destroyed")
    func countIsConserved() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        for x in 13 ... 19 {
            for y in 6 ... 10 { engine.setElement(x, y, Element.sand) }
        }
        let initial = engine.activeParticleCount
        #expect(initial == 35)

        for _ in 0 ..< 60 { engine.step() }
        #expect(engine.activeParticleCount == initial, "a grain appeared or vanished")
    }

    @Test("Bedrock never moves, and sand settles on the floor rather than on top of it")
    func bedrockIsImmovable() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        engine.setElement(16, 0, Element.bedrock)
        engine.setElement(16, 3, Element.sand)
        for _ in 0 ..< 120 { engine.step() }

        #expect(engine.type[engine.index(16, 0)] == Element.bedrock)
        #expect(engine.type[engine.index(16, engine.height - 1)] == Element.sand)
    }

    @Test("A decaying element becomes its successor when its lifetime runs out")
    func decayHappensOnSchedule() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        engine.setElement(16, 20, Element.fire, temp: 600, life: 2)

        engine.step()
        engine.step()
        #expect(countType(engine, Element.fire) == 1, "still alight while lifetime remains")

        engine.step()
        #expect(countType(engine, Element.fire) == 0, "lifetime exhausted on the third tick")
        #expect(countType(engine, Element.smoke) == 1, "fire leaves smoke behind")
    }

    @Test("Granular solids fall upward when gravity is inverted")
    func invertedGravityLiftsSand() {
        let engine = PowderEngine(width: 32, height: 32, seed: 1234)
        engine.gravityY = -1
        for x in 0 ..< engine.width { engine.setElement(x, 0, Element.bedrock) }
        for x in 12 ... 19 {
            for y in 24 ... 27 { engine.setElement(x, y, Element.sand) }
        }
        for _ in 0 ..< 80 { engine.step() }

        #expect(countType(engine, in: 1 ..< 8, Element.sand) == 32, "all of it piled against the ceiling")
        #expect(countType(engine, in: 12 ..< engine.height, Element.sand) == 0)
    }
}

@Suite("Powder engine grid primitives")
struct PowderEnginePrimitiveTests {
    @Test("Indexing is row-major and bounds checks agree with it")
    func indexingAndBounds() {
        let engine = PowderEngine(width: 10, height: 4)
        #expect(engine.cellCount == 40)
        #expect(engine.index(0, 0) == 0)
        #expect(engine.index(9, 0) == 9)
        #expect(engine.index(0, 1) == 10)
        #expect(engine.index(9, 3) == 39)

        #expect(engine.isValid(0, 0))
        #expect(engine.isValid(9, 3))
        #expect(!engine.isValid(-1, 0))
        #expect(!engine.isValid(0, -1))
        #expect(!engine.isValid(10, 0))
        #expect(!engine.isValid(0, 4))
    }

    @Test("Everything outside the grid reads as bedrock, which is what makes the walls solid")
    func outsideIsBedrock() {
        // The movement rules contain no special case for the edges. They do not
        // need one: anything off-grid reports as immovable bedrock, so a grain at
        // the boundary simply finds nowhere to go.
        let engine = PowderEngine(width: 8, height: 8)
        #expect(engine.typeAt(-1, 4) == Element.bedrock)
        #expect(engine.typeAt(8, 4) == Element.bedrock)
        #expect(engine.typeAt(4, -1) == Element.bedrock)
        #expect(engine.typeAt(4, 8) == Element.bedrock)
        #expect(engine.physics(at: -1, y: 4).state == .solidFixed)
        #expect(engine.physics(at: 4, y: 8).density == 9999)

        #expect(engine.typeAt(4, 4) == Element.empty, "inside is still empty")
    }

    @Test("A fresh grid is empty and sits at ambient temperature")
    func freshGridState() {
        let engine = PowderEngine(width: 6, height: 6)
        engine.ambientTemp = 20
        engine.resetGrid()
        for i in 0 ..< engine.cellCount {
            #expect(engine.type[i] == Element.empty)
            #expect(engine.temperature[i] == 20)
            #expect(engine.life[i] == 0)
            #expect(engine.visited[i] == 0)
            #expect(engine.velocityX[i] == 0)
            #expect(engine.velocityY[i] == 0)
            #expect(engine.pressure[i] == 0)
        }
        #expect(engine.activeParticleCount == 0)
    }

    @Test("Resetting honours a changed ambient temperature")
    func resetUsesCurrentAmbient() {
        let engine = PowderEngine(width: 4, height: 4)
        engine.ambientTemp = -40
        engine.resetGrid()
        #expect(engine.temperature[0] == -40)
    }

    @Test("Placing an element without a temperature uses the element's own, then ambient")
    func placementTemperature() {
        let engine = PowderEngine(width: 8, height: 8)
        engine.ambientTemp = 20

        // Lava declares 1200°C.
        engine.setElement(1, 1, Element.lava)
        #expect(engine.temperature[engine.index(1, 1)] == 1200)

        // Ice declares -15°C, which must survive as a negative.
        engine.setElement(2, 2, Element.ice)
        #expect(engine.temperature[engine.index(2, 2)] == -15)

        // Sand declares nothing, so it arrives at the world's ambient.
        engine.setElement(3, 3, Element.sand)
        #expect(engine.temperature[engine.index(3, 3)] == 20)

        // An explicit temperature always wins.
        engine.setElement(4, 4, Element.lava, temp: 300)
        #expect(engine.temperature[engine.index(4, 4)] == 300)
    }

    @Test("Placing an element seeds its lifetime from its decay time")
    func placementLifetime() {
        let engine = PowderEngine(width: 8, height: 8)
        engine.setElement(1, 1, Element.fire)
        #expect(engine.life[engine.index(1, 1)] == 40)

        engine.setElement(2, 2, Element.smoke)
        #expect(engine.life[engine.index(2, 2)] == 120)

        engine.setElement(3, 3, Element.sand)
        #expect(engine.life[engine.index(3, 3)] == 0, "a permanent element has no lifetime")

        engine.setElement(4, 4, Element.fire, life: 7)
        #expect(engine.life[engine.index(4, 4)] == 7, "an explicit lifetime wins")
    }

    @Test("Painting a fan over a fan keeps its rotation, but a fresh fan starts unrotated")
    func fanRemembersItsRotation() {
        // A fan stores which way it points in the same slot other elements use for
        // their lifetime. Resetting that on every repaint would make a fan
        // impossible to aim, since aiming it *is* repainting it.
        let engine = PowderEngine(width: 8, height: 8)
        engine.setElement(1, 1, Element.fan)
        #expect(engine.life[engine.index(1, 1)] == 0)

        engine.life[engine.index(1, 1)] = 3
        engine.setElement(1, 1, Element.fan)
        #expect(engine.life[engine.index(1, 1)] == 3, "rotation survived the repaint")

        // Painting something else there and then a fan starts from scratch.
        engine.setElement(1, 1, Element.sand)
        engine.setElement(1, 1, Element.fan)
        #expect(engine.life[engine.index(1, 1)] == 0)
    }

    @Test("Placing an element clears any momentum it inherited from the cell")
    func placementClearsMomentum() {
        let engine = PowderEngine(width: 8, height: 8)
        engine.velocityX[engine.index(2, 2)] = 40
        engine.velocityY[engine.index(2, 2)] = -40
        engine.setElement(2, 2, Element.sand)
        #expect(engine.velocityX[engine.index(2, 2)] == 0)
        #expect(engine.velocityY[engine.index(2, 2)] == 0)
    }

    @Test("Placing outside the grid does nothing at all")
    func placementOutsideIsIgnored() {
        let engine = PowderEngine(width: 8, height: 8)
        engine.setElement(-1, 0, Element.sand)
        engine.setElement(0, -1, Element.sand)
        engine.setElement(8, 0, Element.sand)
        engine.setElement(0, 8, Element.sand)
        #expect(engine.activeParticleCount == 0)
    }

    @Test("Swapping exchanges every attribute and marks both cells as moved")
    func swapExchangesEverything() {
        let engine = PowderEngine(width: 8, height: 8)
        let a = engine.index(1, 1)
        let b = engine.index(5, 5)

        engine.setElement(1, 1, Element.sand, temp: 111)
        engine.life[a] = 7
        engine.velocityX[a] = 3
        engine.velocityY[a] = -4
        engine.pressure[a] = 9

        engine.setElement(5, 5, Element.water, temp: 222)
        engine.life[b] = 11
        engine.velocityX[b] = -1
        engine.velocityY[b] = 2
        engine.pressure[b] = 13

        engine.swapCells(a, b)

        #expect(engine.type[a] == Element.water)
        #expect(engine.temperature[a] == 222)
        #expect(engine.life[a] == 11)
        #expect(engine.velocityX[a] == -1)
        #expect(engine.velocityY[a] == 2)
        #expect(engine.pressure[a] == 13)

        #expect(engine.type[b] == Element.sand)
        #expect(engine.temperature[b] == 111)
        #expect(engine.life[b] == 7)
        #expect(engine.velocityX[b] == 3)
        #expect(engine.velocityY[b] == -4)
        #expect(engine.pressure[b] == 9)

        #expect(engine.visited[a] == 1, "both ends must be marked or cells move twice per tick")
        #expect(engine.visited[b] == 1)
    }

    @Test("Temperatures round to single precision on every store")
    func temperatureIsSinglePrecision() {
        // The web grid holds temperatures in a Float32Array, so each write rounds.
        // Keeping full precision here would let values drift, and the chemistry
        // has hard thresholds — 700°C decides whether lava becomes obsidian.
        let engine = PowderEngine(width: 4, height: 4)
        engine.setElement(0, 0, Element.lava, temp: 0.1)
        #expect(engine.temperature[0] == Float(0.1))
        #expect(Double(engine.temperature[0]) != 0.1, "a Double would have held the exact value")
    }

    @Test("Wind is clamped to the range the physics is tuned for")
    func windClamping() {
        let engine = PowderEngine(width: 4, height: 4)
        engine.setWind(3)
        #expect(engine.windX == 3)
        engine.setWind(99)
        #expect(engine.windX == 5)
        engine.setWind(-99)
        #expect(engine.windX == -5)
    }

    @Test("Shake energy keeps the strongest jolt rather than the latest")
    func jostleKeepsTheStrongest() {
        let engine = PowderEngine(width: 4, height: 4)
        engine.jostle(5)
        engine.jostle(1)
        #expect(engine.jostleLeft == 5, "a gentle nudge must not cancel a violent one")
        engine.jostle(9)
        #expect(engine.jostleLeft == 9)
    }

    @Test("The world fingerprint is stable, and notices changes")
    func hashLiteBehaviour() {
        let engine = PowderEngine(width: 32, height: 32)
        let empty = engine.hashLite()
        #expect(engine.hashLite() == empty, "reading it twice gives the same answer")

        engine.setElement(0, 0, Element.sand)
        #expect(engine.hashLite() != empty, "a change in the sampled cells shows up")

        let other = PowderEngine(width: 33, height: 32)
        #expect(other.hashLite() != empty, "dimensions are part of the fingerprint")
    }
}

@Suite("Powder engine resizing")
struct PowderEngineResizeTests {
    @Test("Growing keeps what was there and leaves the new space empty")
    func growPreservesContents() {
        let engine = PowderEngine(width: 8, height: 8)
        engine.setElement(2, 3, Element.sand, temp: 42)
        engine.life[engine.index(2, 3)] = 5
        engine.velocityX[engine.index(2, 3)] = 6
        engine.velocityY[engine.index(2, 3)] = -7
        engine.pressure[engine.index(2, 3)] = 8

        engine.resize(width: 16, height: 16)

        #expect(engine.width == 16)
        #expect(engine.height == 16)
        #expect(engine.cellCount == 256)
        #expect(engine.type[engine.index(2, 3)] == Element.sand)
        #expect(engine.temperature[engine.index(2, 3)] == 42)
        #expect(engine.life[engine.index(2, 3)] == 5)
        #expect(engine.velocityX[engine.index(2, 3)] == 6)
        #expect(engine.velocityY[engine.index(2, 3)] == -7)
        #expect(engine.pressure[engine.index(2, 3)] == 8)
        #expect(engine.activeParticleCount == 1, "nothing was duplicated into the new space")
    }

    @Test("Shrinking keeps the overlap and discards the rest")
    func shrinkKeepsOverlap() {
        let engine = PowderEngine(width: 16, height: 16)
        engine.setElement(1, 1, Element.sand)
        engine.setElement(14, 14, Element.stone)

        engine.resize(width: 8, height: 8)

        #expect(engine.type[engine.index(1, 1)] == Element.sand, "inside the new bounds")
        #expect(engine.activeParticleCount == 1, "the far cell is gone")
    }

    @Test("Resizing to the same dimensions changes nothing")
    func resizeToSameIsANoOp() {
        let engine = PowderEngine(width: 8, height: 8)
        engine.setElement(3, 3, Element.sand)
        engine.visited[engine.index(3, 3)] = 1

        engine.resize(width: 8, height: 8)

        #expect(engine.type[engine.index(3, 3)] == Element.sand)
        #expect(engine.visited[engine.index(3, 3)] == 1, "not even the per-tick scratch was touched")
    }

    @Test("Resizing clears the per-tick scratch state")
    func resizeClearsScratch() {
        // Visited marks and the pressure scratch buffer are rebuilt every tick, so
        // carrying them across a resize would be meaningless — and carrying stale
        // visited marks would freeze cells for a frame.
        let engine = PowderEngine(width: 8, height: 8)
        engine.visited[engine.index(1, 1)] = 1
        engine.pressureNext[engine.index(1, 1)] = 99

        engine.resize(width: 12, height: 12)

        #expect(engine.visited[engine.index(1, 1)] == 0)
        #expect(engine.pressureNext[engine.index(1, 1)] == 0)
    }

    @Test("A resized world keeps simulating correctly")
    func simulationSurvivesResize() {
        let engine = PowderEngine(width: 16, height: 16, seed: 7)
        for x in 6 ... 9 { engine.setElement(x, 2, Element.sand) }
        for _ in 0 ..< 5 { engine.step() }

        engine.resize(width: 24, height: 32)
        for _ in 0 ..< 120 { engine.step() }

        #expect(engine.activeParticleCount == 4)
        var bottomRow = 0
        for x in 0 ..< engine.width where engine.type[engine.index(x, engine.height - 1)] == Element.sand {
            bottomRow += 1
        }
        #expect(bottomRow == 4, "the sand found the new floor")
    }

    @Test("A zero-sized world is inert rather than a crash")
    func degenerateSizesAreSafe() {
        // The grid is sized from a view's measured bounds, which is briefly zero
        // during layout.
        for (width, height) in [(0, 0), (0, 10), (10, 0), (-5, 10)] {
            let engine = PowderEngine(width: width, height: height)
            #expect(engine.cellCount == 0)
            engine.setElement(0, 0, Element.sand)
            engine.step()
            engine.resetGrid()
            #expect(engine.activeParticleCount == 0)
            #expect(engine.hashLite() != 0 || engine.cellCount == 0)

            // And it can grow into a usable world afterwards.
            engine.resize(width: 8, height: 8)
            engine.setElement(4, 1, Element.sand)
            for _ in 0 ..< 40 { engine.step() }
            #expect(engine.activeParticleCount == 1)
        }
    }
}
