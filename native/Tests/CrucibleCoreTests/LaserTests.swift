import Testing

@testable import CrucibleCore

/// The laser beam.
///
/// ## Why this is not a comparison against the web engine
///
/// Because the web engine's laser does not work, and the port was faithful to it. Painting one
/// produced a red lump that sat exactly where it was put and did nothing at all: it looked three
/// cells ahead, could pass through no more of its own beam than that, and a brush is wider than
/// three cells — so every cell inside the lump found more laser in front of it and stayed. Only
/// the outermost edge could ever move, and it stalled on the fire it had just made.
///
/// So the one scenario in the golden fixture that recorded that behaviour is retired (see
/// `PowderGoldenTests.comparedScenarios`) and this suite says what a beam is for instead. Every
/// test below fails on the old implementation.
@Suite("The laser shoots")
struct LaserTests {
    /// A world with a floor, so nothing falls out of the bottom.
    private func makeWorld(width: Int = 40, height: Int = 60) -> PowderEngine {
        let engine = PowderEngine(width: width, height: height, seed: 5)
        for x in 0 ..< width { engine.setElement(x, height - 1, Element.bedrock) }
        return engine
    }

    private func count(_ engine: PowderEngine, _ id: ElementID) -> Int {
        var total = 0
        for i in 0 ..< engine.cellCount where engine.type[i] == id { total += 1 }
        return total
    }

    /// The lowest row holding a given material, or `nil`.
    private func deepest(_ engine: PowderEngine, _ id: ElementID) -> Int? {
        var found: Int?
        for y in 0 ..< engine.height {
            for x in 0 ..< engine.width where engine.type[y * engine.width + x] == id {
                found = y
                break
            }
        }
        return found
    }

    // MARK: It travels

    /// The headline. A lump of laser in open air should leave, fast.
    @Test("A beam travels down the world instead of sitting still")
    func beamTravels() {
        let engine = makeWorld()
        // Deliberately wider and thicker than the old three-cell look-ahead, which is the case
        // that could not move at all.
        for x in 16 ..< 24 {
            for y in 4 ..< 12 { engine.setElement(x, y, Element.laser) }
        }
        let startDeepest = deepest(engine, Element.laser) ?? 0

        engine.step()

        let after = deepest(engine, Element.laser) ?? 0
        #expect(
            after > startDeepest,
            "the beam did not advance at all: it reached row \(after), having started at \(startDeepest)"
        )
        #expect(
            after - startDeepest >= 6,
            "the beam crept \(after - startDeepest) cells in a moment; a laser should not creep"
        )
    }

    /// A thick lump is the exact shape the old code could not move. Every cell in it found more
    /// laser ahead, ran out of look-ahead at three, and gave up.
    @Test("A lump thicker than the old look-ahead still moves")
    func thickLumpMoves() {
        let engine = makeWorld(width: 40, height: 80)
        for x in 14 ..< 26 {
            for y in 6 ..< 26 { engine.setElement(x, y, Element.laser) }
        }
        let before = deepest(engine, Element.laser) ?? 0

        engine.step()

        #expect(
            (deepest(engine, Element.laser) ?? 0) > before,
            "a twenty-cell-thick beam did not move, which is the original fault exactly"
        )
    }

    // MARK: It cuts

    /// The other half of a laser: it should go through things.
    @Test("A beam cuts a channel down through stone")
    func beamCutsStone() {
        let engine = makeWorld(width: 30, height: 70)
        // A thick slab, and the beam held just above it.
        for x in 0 ..< 30 {
            for y in 20 ..< 50 { engine.setElement(x, y, Element.stone) }
        }
        let stoneBefore = count(engine, Element.stone)
        for y in 10 ..< 18 { engine.setElement(15, y, Element.laser) }

        for _ in 0 ..< 12 { engine.step() }

        let stoneAfter = count(engine, Element.stone)
        #expect(
            stoneAfter < stoneBefore,
            "the beam was held against a stone slab for twelve moments and removed none of it"
        )
        // And it should have got *into* the slab rather than only scorching the surface.
        var cutDepth = 0
        for y in 20 ..< 50 where engine.type[y * engine.width + 15] != Element.stone {
            cutDepth += 1
        }
        #expect(cutDepth >= 3, "the beam only marked the surface, cutting \(cutDepth) cells deep")
    }

    /// Burning *and* advancing in the same moment is what cutting is. The old code did one or
    /// the other and returned, so it could never clear a path and move into it.
    @Test("A beam boils water on contact rather than stopping at it")
    func beamBoilsWater() {
        let engine = makeWorld(width: 30, height: 60)
        for x in 0 ..< 30 {
            for y in 25 ..< 40 { engine.setElement(x, y, Element.water) }
        }
        let waterBefore = count(engine, Element.water)
        for y in 12 ..< 20 { engine.setElement(15, y, Element.laser) }

        for _ in 0 ..< 10 { engine.step() }

        #expect(count(engine, Element.water) < waterBefore, "the beam did not boil any water")
        #expect(count(engine, Element.steam) > 0, "boiling water should produce steam")
    }

    /// Sand melts rather than burning, which is the one distinction the reference got right and
    /// is worth keeping.
    @Test("Sand and stone melt, they do not catch fire")
    func sandMelts() {
        let engine = makeWorld(width: 20, height: 40)
        for x in 0 ..< 20 {
            for y in 20 ..< 30 { engine.setElement(x, y, Element.sand) }
        }
        for y in 8 ..< 14 { engine.setElement(10, y, Element.laser) }

        for _ in 0 ..< 8 { engine.step() }

        #expect(count(engine, Element.lava) > 0, "sand under a beam should melt into lava")
    }

    // MARK: It stops where it should

    /// The one thing the reference's own scenario was testing, and it still has to hold: a beam
    /// must not turn up on the far side of a wall.
    @Test("Bedrock absorbs a beam completely")
    func bedrockStopsIt() {
        let engine = makeWorld(width: 30, height: 60)
        let wall = 30
        for x in 0 ..< 30 { engine.setElement(x, wall, Element.bedrock) }
        // Something on the far side that would obviously burn if the beam got through.
        for x in 0 ..< 30 {
            for y in 34 ..< 40 { engine.setElement(x, y, Element.wood) }
        }
        let woodBefore = count(engine, Element.wood)
        for y in 10 ..< 20 { engine.setElement(15, y, Element.laser) }

        for _ in 0 ..< 40 { engine.step() }

        #expect(count(engine, Element.wood) == woodBefore, "the beam reached through bedrock")
        for x in 0 ..< 30 {
            #expect(
                engine.type[wall * engine.width + x] == Element.bedrock,
                "the beam damaged the bedrock at x=\(x)"
            )
        }
        var beyond = 0
        for y in (wall + 1) ..< engine.height {
            for x in 0 ..< engine.width where engine.type[y * engine.width + x] == Element.laser {
                beyond += 1
            }
        }
        #expect(beyond == 0, "\(beyond) laser cells appeared past the wall")
    }

    @Test("A beam does not escape the world")
    func staysInsideTheWorld() {
        let engine = makeWorld(width: 24, height: 30)
        for x in 8 ..< 16 {
            for y in 20 ..< 27 { engine.setElement(x, y, Element.laser) }
        }
        // Straight at the floor, from close up, for long enough to have left if it could.
        for _ in 0 ..< 30 { engine.step() }

        for x in 0 ..< engine.width {
            #expect(
                engine.type[(engine.height - 1) * engine.width + x] == Element.bedrock,
                "the floor was broken at x=\(x)"
            )
        }
    }

    /// Beams run along gravity, so turning the world over turns the beam over.
    @Test("An inverted world fires the beam upward")
    func followsGravity() {
        let engine = PowderEngine(width: 30, height: 60, seed: 5)
        engine.gravityY = -1
        for x in 12 ..< 18 {
            for y in 40 ..< 48 { engine.setElement(x, y, Element.laser) }
        }
        var shallowest = engine.height
        for y in 0 ..< engine.height {
            for x in 0 ..< engine.width where engine.type[y * engine.width + x] == Element.laser {
                shallowest = min(shallowest, y)
            }
        }

        engine.step()

        var after = engine.height
        for y in 0 ..< engine.height {
            for x in 0 ..< engine.width where engine.type[y * engine.width + x] == Element.laser {
                after = min(after, y)
            }
        }
        #expect(after < shallowest, "with gravity reversed the beam should travel upward")
    }

    /// It is still a beam, not a cloud: it should stay in the column it was fired down.
    @Test("A beam does not spread sideways")
    func staysInItsColumn() {
        let engine = makeWorld(width: 40, height: 60)
        for y in 6 ..< 14 { engine.setElement(20, y, Element.laser) }

        for _ in 0 ..< 5 { engine.step() }

        for y in 0 ..< engine.height {
            for x in 0 ..< engine.width where engine.type[y * engine.width + x] == Element.laser {
                #expect(x == 20, "a beam fired down column 20 appeared at column \(x)")
            }
        }
    }
}
