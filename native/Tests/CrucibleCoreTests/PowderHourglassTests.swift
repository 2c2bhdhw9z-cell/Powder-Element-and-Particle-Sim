import Testing

@testable import CrucibleCore

/// The hourglass, turning the world over, the powder kaleidoscope, and the sweep that stopped sand leaning.
@Suite("Hourglass, turning over, and the powder kaleidoscope")
struct PowderHourglassTests {
    private func hourglass(width: Int, height: Int, seed: UInt32 = 3) throws -> PowderEngine {
        let recipe = try #require(ownPowderRecipes.first { $0.id == "hourglass" })
        let engine = PowderEngine(width: width, height: height, seed: seed)
        var random = Mulberry32(seed: seed)
        recipe.apply(to: engine, random: &random)
        return engine
    }

    private func count(_ id: ElementID, in engine: PowderEngine) -> Int {
        var found = 0
        for i in 0 ..< engine.cellCount where engine.type[i] == id { found += 1 }
        return found
    }

    /// Sand above the neck, below it, and how the sand above is split between the two sides.
    private func sand(_ engine: PowderEngine, _ shape: HourglassShape)
        -> (above: Int, below: Int, aboveLeft: Int, aboveRight: Int)
    {
        var result = (above: 0, below: 0, aboveLeft: 0, aboveRight: 0)
        for y in 0 ..< engine.height {
            for x in 0 ..< engine.width where engine.type[engine.index(x, y)] == Element.sand {
                if y < shape.upperNeckY {
                    result.above += 1
                    if x < shape.centreX { result.aboveLeft += 1 } else { result.aboveRight += 1 }
                } else if y > shape.lowerNeckY {
                    result.below += 1
                }
            }
        }
        return result
    }

    @Test("The shared scenes are untouched: the day's world still chooses from the same thirteen")
    func sharedScenesUnchanged() {
        #expect(powderRecipes.count == 13)
        #expect(!powderRecipes.contains { $0.id == "hourglass" })
        #expect(allPowderRecipes.count == powderRecipes.count + ownPowderRecipes.count)
        #expect(Set(allPowderRecipes.map(\.id)).count == allPowderRecipes.count, "two scenes share a name")
    }

    @Test("It lays out at every size without trapping, and never leaves the world empty")
    func everySize() throws {
        for (width, height) in [(1, 1), (8, 8), (30, 20), (40, 120), (81, 151), (300, 160), (270, 555)] {
            let engine = try hourglass(width: width, height: height)
            #expect(engine.width == width && engine.height == height)
            #expect(count(Element.sand, in: engine) > 0, "no sand at \(width)x\(height)")
        }
    }

    @Test("The glass is the same turned over, so turning the world over puts it back where it was")
    func theGlassIsSymmetric() throws {
        for (width, height) in [(80, 150), (81, 151)] {
            let shape = try #require(HourglassShape(width: width, height: height))
            for y in 0 ..< height {
                #expect(shape.halfWidth(atRow: y) == shape.halfWidth(atRow: height - 1 - y), "row \(y) of \(height)")
            }
            let engine = try hourglass(width: width, height: height)
            var glass: [Int] = []
            for i in 0 ..< engine.cellCount where engine.type[i] == Element.glass { glass.append(i) }
            engine.flipUpsideDown()
            var turned: [Int] = []
            for i in 0 ..< engine.cellCount where engine.type[i] == Element.glass { turned.append(i) }
            #expect(glass == turned, "the glass moved when the world was turned over")
        }
    }

    @Test("The sand pours evenly from both sides, steadily, and none of it escapes the glass")
    func itPours() throws {
        let engine = try hourglass(width: 80, height: 150)
        let shape = try #require(HourglassShape(width: 80, height: 150))
        let total = count(Element.sand, in: engine)
        let start = sand(engine, shape)
        #expect(start.below == 0, "sand started in the lower bulb")
        #expect(total > 800)

        for _ in 0 ..< 500 { engine.step() }
        let middle = sand(engine, shape)
        // About a grain a moment: the neck is two columns and each carries one every other moment.
        #expect(middle.below > 350 && middle.below < 560, "\(middle.below) grains came through in 500 moments")
        // Both sides run down together. Before the sweep was scrambled one side emptied completely first.
        let lean = abs(middle.aboveLeft - middle.aboveRight)
        #expect(lean < middle.above / 8, "the sand leans: \(middle.aboveLeft) left against \(middle.aboveRight) right")

        for _ in 0 ..< 1100 { engine.step() }
        #expect(count(Element.sand, in: engine) == total, "sand was lost or made")
        for y in 0 ..< engine.height {
            for x in 0 ..< engine.width where engine.type[engine.index(x, y)] == Element.sand {
                #expect(shape.contains(x, y), "a grain escaped the glass to \(x), \(y)")
            }
        }
        let end = sand(engine, shape)
        #expect(end.above < total / 50, "it stopped pouring with \(end.above) of \(total) still at the top")
    }

    @Test("Turned over, it pours again")
    func turnedOverItPoursAgain() throws {
        let engine = try hourglass(width: 80, height: 150)
        let shape = try #require(HourglassShape(width: 80, height: 150))
        for _ in 0 ..< 1600 { engine.step() }
        let total = count(Element.sand, in: engine)
        engine.flipUpsideDown()
        #expect(sand(engine, shape).below < total / 50, "turning it over did not put the sand at the top")
        for _ in 0 ..< 400 { engine.step() }
        let after = sand(engine, shape)
        #expect(after.below > total / 5, "it did not start pouring again")
        #expect(abs(after.aboveLeft - after.aboveRight) < max(40, after.above / 6), "turned over, it leans")
        #expect(count(Element.sand, in: engine) == total)
    }

    @Test("Turning over twice gives back exactly the world, and a fan turned over points the other way")
    func turningOverTwiceIsNothing() {
        for height in [9, 10] {
            let engine = PowderEngine(width: 7, height: height, seed: 1)
            engine.setElement(1, 1, Element.sand)
            engine.setElement(2, 1, Element.lava)
            engine.setElement(3, 4, Element.fan, life: 1)
            engine.setElement(4, 0, Element.stone)
            engine.setTint(4, 0, PowderEngine.tintWord(red: 200, green: 10, blue: 90))
            engine.velocityY[engine.index(1, 1)] = -128
            let types = Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount))
            let temps = Array(UnsafeBufferPointer(start: engine.temperature, count: engine.cellCount))

            engine.flipUpsideDown()
            #expect(engine.type[engine.index(1, height - 2)] == Element.sand)
            #expect(engine.type[engine.index(4, height - 1)] == Element.stone)
            #expect(engine.tintAt(4, height - 1) == PowderEngine.tintWord(red: 200, green: 10, blue: 90))
            #expect(engine.velocityY[engine.index(1, height - 2)] == 127, "the fastest rise overflowed")
            let fan = engine.index(3, height - 1 - 4)
            #expect(engine.type[fan] == Element.fan)
            #expect(engine.life[fan] == 3, "a fan blowing down was still blowing down after turning over")

            engine.flipUpsideDown()
            #expect(Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount)) == types)
            #expect(Array(UnsafeBufferPointer(start: engine.temperature, count: engine.cellCount)) == temps)
            #expect(engine.life[engine.index(3, 4)] == 1)
        }
    }

    @Test("The sweep is scrambled the same way as the website's, and favours neither side")
    func sweepMatchesTheWebsite() {
        var pattern = ""
        for moment in 0 ..< 4 {
            for row in 0 ..< 16 { pattern += PowderEngine.sweepsRightward(row: row, moment: moment) ? "1" : "0" }
        }
        // Worked out by the website's own code. The two must agree bit for bit, or a world run in one diverges from
        // the same world run in the other on the very first moment.
        #expect(pattern == "1101010000011010111100111100010100000100110011000011000111100100")
        // Moments past what fits in 32 bits wrap exactly as the website's do.
        #expect(PowderEngine.sweepsRightward(row: 5000, moment: 2_147_483_647))
        #expect(PowderEngine.sweepsRightward(row: 7, moment: 4_294_967_299))
        #expect(PowderEngine.sweepsRightward(row: 123, moment: 99_999_999))

        var rightward = 0
        for moment in 0 ..< 200 {
            for row in 0 ..< 200 where PowderEngine.sweepsRightward(row: row, moment: moment) { rightward += 1 }
        }
        #expect(abs(rightward - 20000) < 400, "\(rightward) of 40000 sweeps went rightward")
        // And a single row does not settle into a rhythm: on alternate moments it goes both ways about equally.
        var evenRightward = 0
        for moment in stride(from: 0, to: 4000, by: 2) where PowderEngine.sweepsRightward(row: 40, moment: moment) {
            evenRightward += 1
        }
        #expect(abs(evenRightward - 1000) < 100)
    }

    @Test("Sand draining through a gap takes from both sides alike")
    func drainingDoesNotLean() {
        // A heap resting on a floor with a gap two cells wide in the middle, the setup that showed the lean.
        let engine = PowderEngine(width: 60, height: 80, seed: 9)
        for x in 0 ..< 60 where x != 29 && x != 30 { engine.setElement(x, 40, Element.bedrock) }
        for y in 10 ..< 40 {
            for x in 5 ..< 55 { engine.setElement(x, y, Element.sand) }
        }
        for _ in 0 ..< 400 { engine.step() }
        var left = 0
        var right = 0
        for y in 0 ..< 40 {
            for x in 0 ..< 60 where engine.type[engine.index(x, y)] == Element.sand {
                if x < 30 { left += 1 } else { right += 1 }
            }
        }
        #expect(left + right < 1400, "hardly anything drained")
        #expect(abs(left - right) < (left + right) / 8, "\(left) grains left against \(right) right")
    }

    @Test("The kaleidoscope copies a touch evenly round the middle, once each")
    func kaleidoscopeCells() {
        let engine = PowderEngine(width: 101, height: 101, seed: 1)
        let cells = engine.kaleidoscopeCells(x: 80, y: 50, folds: 6, mirrors: false)
        #expect(cells.count == 6)
        #expect(cells[0].x == 80 && cells[0].y == 50, "the touch itself was not first")
        for cell in cells {
            let distance = (Double(cell.x - 50) * Double(cell.x - 50) + Double(cell.y - 50) * Double(cell.y - 50))
                .squareRoot()
            #expect(abs(distance - 30) <= 1, "a copy is \(distance) from the middle, not 30")
        }
        // Straight opposite, since six folds include a half turn.
        #expect(cells.contains { $0.x == 20 && $0.y == 50 })

        // The middle itself is one place however many times it is copied.
        #expect(engine.kaleidoscopeCells(x: 50, y: 50, folds: 6, mirrors: true).count == 1)
        // One fold, or nonsense, is the touch alone.
        #expect(engine.kaleidoscopeCells(x: 10, y: 10, folds: 1, mirrors: false).count == 1)
        #expect(engine.kaleidoscopeCells(x: 10, y: 10, folds: -4, mirrors: false).count == 1)
        // Copies past the edge are dropped, not pushed against the wall.
        let wide = PowderEngine(width: 200, height: 40, seed: 1)
        let clipped = wide.kaleidoscopeCells(x: 190, y: 20, folds: 6, mirrors: false)
        #expect(clipped.allSatisfy { wide.isValid($0.x, $0.y) })
        #expect(clipped.count < 6)
    }

    @Test("A mirrored kaleidoscope differs from a plain one")
    func mirroredKaleidoscope() {
        let engine = PowderEngine(width: 101, height: 101, seed: 1)
        let cells = engine.kaleidoscopeCells(x: 60, y: 20, folds: 6, mirrors: true)
        #expect(cells.count == 6)
        let plain = engine.kaleidoscopeCells(x: 60, y: 20, folds: 6, mirrors: false)
        #expect(Set(cells.map { $0.x * 1000 + $0.y }) != Set(plain.map { $0.x * 1000 + $0.y }),
                "mirroring changed nothing")
    }
}
