import Testing

@testable import CrucibleCore

/// The tide, the rewind, the lasso and the plotter drawing.
@Suite("Tide, rewind, lasso and the plotter drawing")
struct PowderLabToolsTests {
    private func world(width: Int = 60, height: Int = 40, seed: UInt32 = 3) -> PowderEngine {
        let engine = PowderEngine(width: width, height: height, seed: seed)
        for x in 0 ..< width { engine.setElement(x, height - 1, Element.bedrock) }
        return engine
    }

    private func count(_ id: ElementID, in engine: PowderEngine) -> Int {
        var found = 0
        for i in 0 ..< engine.cellCount where engine.type[i] == id { found += 1 }
        return found
    }

    @Test("The tide comes in across the whole sea, and goes out again")
    func tideRisesAndFalls() {
        let engine = world()
        engine.tide = PowderTide(side: .left, period: 600, strength: 8)
        var highest = 0
        for _ in 0 ..< 300 {
            engine.step()
            highest = max(highest, count(Element.water, in: engine))
        }
        // The flood fills the lowest third of the world, as far as the sea may rise.
        #expect(highest > 400, "the flood brought in only \(highest) grains of water")
        var reached = 0
        var topRow = engine.height
        for y in 0 ..< engine.height {
            for x in 0 ..< engine.width where engine.type[engine.index(x, y)] == Element.water {
                reached = max(reached, x)
                topRow = min(topRow, y)
            }
        }
        #expect(reached > 50, "the sea did not reach across the world")
        #expect(topRow >= engine.tideHighestRow - 1, "the sea rose past the highest it may")
        for _ in 0 ..< 300 { engine.step() }
        let atLowTide = count(Element.water, in: engine)
        #expect(atLowTide < highest / 4, "the ebb left \(atLowTide) of \(highest) grains behind")
    }

    @Test("A lake the sea has not reached is left alone, and nothing happens without gravity")
    func tideLeavesLakesAlone() {
        let engine = world()
        // A dam of bedrock across the middle, with a lake on the far side of it.
        for y in 10 ..< 39 { engine.setElement(30, y, Element.bedrock) }
        for y in 32 ..< 39 {
            for x in 40 ..< 50 { engine.setElement(x, y, Element.water) }
        }
        let lake = 70
        engine.tide = PowderTide(side: .left, period: 600, strength: 8)
        for _ in 0 ..< 290 { engine.step() }
        var farSide = 0
        for y in 0 ..< engine.height {
            for x in 31 ..< engine.width where engine.type[engine.index(x, y)] == Element.water { farSide += 1 }
        }
        #expect(farSide == lake, "the tide reached a lake it was not joined to: \(farSide) of \(lake)")

        let weightless = world()
        weightless.gravityY = 0
        weightless.tide = PowderTide(side: .right, period: 600, strength: 8)
        for _ in 0 ..< 100 { weightless.step() }
        #expect(count(Element.water, in: weightless) == 0)
    }

    @Test("A tide is saved with its world")
    func tideIsSaved() {
        let engine = world()
        engine.tide = PowderTide(side: .right, period: 2_400, strength: 3)
        let other = PowderEngine(width: 60, height: 40, seed: 1)
        #expect(other.apply(engine.captureState()))
        #expect(other.tide == PowderTide(side: .right, period: 2_400, strength: 3))
        engine.tide = nil
        #expect(other.apply(engine.captureState()))
        #expect(other.tide == nil, "loading a world with no tide left the last one's tide running")
    }

    @Test("Scrubbing back shows the past, going forward again puts the present back exactly")
    func rewindScrubs() {
        let engine = world()
        let rewind = PowderRewind(spacing: 10, capacity: 5)
        engine.drawBrush(centerX: 30, centerY: 5, radius: 3, elementID: Element.sand, shape: .circle)
        var moments: [[ElementID]] = []
        for moment in 1 ... 50 {
            engine.step()
            rewind.noteMoment(engine)
            if moment % 10 == 0 { moments.append(Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount))) }
        }
        for _ in 0 ..< 7 { engine.step() }
        let present = Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount))
        #expect(rewind.count == 5)
        rewind.beginScrub(engine)
        #expect(rewind.isScrubbing)
        // While scrubbing, nothing new is kept.
        rewind.noteMoment(engine)
        #expect(rewind.count == 5)
        for back in 1 ... 5 {
            #expect(rewind.show(engine, stepsBack: back))
            #expect(Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount)) == moments[5 - back])
        }
        #expect(rewind.show(engine, stepsBack: 0))
        #expect(Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount)) == present)
        // Changing its mind: back to the present exactly, and everything still kept.
        #expect(rewind.show(engine, stepsBack: 3))
        rewind.endScrub(engine, keepingStepsBack: nil)
        #expect(Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount)) == present)
        #expect(rewind.count == 5 && !rewind.isScrubbing)
        // Keeping a past moment lets go of everything after it.
        rewind.beginScrub(engine)
        rewind.endScrub(engine, keepingStepsBack: 3)
        #expect(Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount)) == moments[2])
        #expect(rewind.count == 3)
        // A world of another size cannot be shown moments of the old one.
        engine.resize(width: 30, height: 20)
        rewind.beginScrub(engine)
        #expect(!rewind.show(engine, stepsBack: 1))
        rewind.endScrub(engine, keepingStepsBack: nil)
        #expect(engine.width == 30, "going back to the present resized the world")
        rewind.noteMoment(engine)
        #expect(rewind.count == 0, "moments of the old size were kept")
        // With nothing kept there is nothing to go back to.
        #expect(!PowderRewind().rewind(engine, stepsBack: 0))
    }

    @Test("How many moments are kept follows how much memory they may use")
    func rewindFitsItsMemory() {
        let rewind = PowderRewind()
        rewind.fit(budgetBytes: 40_000_000, cellCount: 150_000)
        #expect(rewind.capacity == 33)
        rewind.fit(budgetBytes: 40_000_000, cellCount: 600_000)
        #expect(rewind.capacity == 8)
        rewind.fit(budgetBytes: 40_000_000, cellCount: 10)
        #expect(rewind.capacity == 90)
    }

    @Test("Moments of a world in its own colours cost more, and the memory is still kept to")
    func rewindCountsColouredMoments() {
        let engine = world(width: 50, height: 40)
        // Enough for ten plain moments.
        let rewind = PowderRewind(spacing: 1, capacity: 90)
        rewind.fit(budgetBytes: engine.cellCount * 8 * 10, cellCount: engine.cellCount)
        #expect(rewind.capacity == 10)
        for _ in 0 ..< 30 { rewind.noteMoment(engine) }
        #expect(rewind.count == 10)
        #expect(rewind.keptBytes == engine.cellCount * 8 * 10)
        // A coloured grain makes every moment after it half as dear again, so fewer fit in the same memory.
        engine.setElement(5, 5, Element.sand)
        engine.setTint(5, 5, PowderEngine.tintWord(red: 250, green: 20, blue: 90))
        for _ in 0 ..< 30 { rewind.noteMoment(engine) }
        #expect(rewind.keptBytes <= engine.cellCount * 8 * 10, "kept \(rewind.keptBytes) bytes")
        #expect(rewind.count == 6)
        // However tight, a few are always kept.
        rewind.fit(budgetBytes: 1, cellCount: engine.cellCount)
        #expect(rewind.count == PowderRewind.fewestKept)
    }

    @Test("The rewind says how long ago each moment was, and keeping one takes time back with it")
    func rewindKnowsWhen() {
        let engine = world()
        let rewind = PowderRewind(spacing: 10, capacity: 5)
        for moment in 1 ... 50 {
            engine.step()
            // Half a second a moment, by the caller's clock.
            rewind.noteMoment(engine, time: Double(moment) * 0.5)
        }
        #expect(rewind.time(stepsBack: 0) == nil, "the present has no time before scrubbing begins")
        rewind.beginScrub(engine, time: 26)
        #expect(rewind.time(stepsBack: 0) == 26)
        #expect(rewind.time(stepsBack: 1) == 25)
        #expect(rewind.timeBack(stepsBack: 1) == 1)
        #expect(rewind.timeBack(stepsBack: 5) == 21)
        #expect(rewind.timeBack(stepsBack: 9) == 21, "further back than anything kept is the oldest")
        #expect(rewind.timeBack(stepsBack: 0) == 0)
        #expect(rewind.endScrub(engine, keepingStepsBack: 2))
        #expect(rewind.count == 4)
        rewind.beginScrub(engine, time: 20)
        #expect(!rewind.endScrub(engine, keepingStepsBack: nil), "going back to the present kept a past moment")
    }

    @Test("A thermometer reads the heat where it was put, and remembers")
    func thermometerReads() {
        let engine = world()
        for x in 20 ..< 40 { engine.setElement(x, 38, Element.lava) }
        for x in 20 ..< 40 { engine.setElement(x, 37, Element.stone, temp: 20) }
        var probe = PowderThermometer(x: 30, y: 37)
        for _ in 0 ..< 200 {
            engine.step()
            probe.read(engine)
        }
        #expect(probe.readings.count == 200)
        #expect((probe.current ?? 0) > 60, "the stone over the lava never warmed")
        #expect(probe.lowest < probe.highest)
        probe.move(toX: 5, y: 5)
        #expect(probe.readings.isEmpty)
        probe.move(toX: 500, y: 5)
        probe.read(engine)
        #expect(probe.readings.isEmpty, "a thermometer outside the world read something")
    }

    @Test("Measurements come out as a spreadsheet with a column for every material that appeared")
    func measurementsAsNumbers() {
        let engine = world()
        let measurements = PowderMeasurements(limit: 3)
        engine.setElement(5, 5, Element.lava, temp: 1_000)
        measurements.sample(engine, seconds: 0, thermometer: 20)
        engine.setElement(6, 6, Element.water)
        for second in 1 ... 3 { measurements.sample(engine, seconds: Double(second)) }
        #expect(measurements.rows.count == 3, "the oldest rows were not let go")
        let csv = measurements.csv(name: { $0 == Element.water ? "Water, fresh" : "id \($0)" })
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 4)
        #expect(lines[0].hasPrefix("seconds,cells filled,hottest °C,coldest °C,average °C,thermometer °C"))
        #expect(lines[0].contains("\"Water, fresh\""), "a heading with a comma in it was not quoted")
        #expect(lines[1].hasPrefix("1,62,"), "\(lines[1])")
        let fahrenheit = measurements.csv(name: { "\($0)" }, temperature: { $0 * 9 / 5 + 32 }, unit: "°F")
        #expect(fahrenheit.contains("hottest °F"))
        #expect(PowderMeasurements.number(2.5) == "2.5" && PowderMeasurements.number(3) == "3")
        // Rewound to a moment, what was measured after it did not happen.
        measurements.forget(after: 1.5)
        let left = measurements.rows.map { $0.seconds }
        #expect(left == [1])
        measurements.forget(after: .nan)
        #expect(measurements.rows.count == 1)
    }

    @Test("A lasso takes exactly the cells inside it, and a stamp puts them down again")
    func lassoAndStamp() {
        let engine = world()
        engine.drawBrush(centerX: 10, centerY: 10, radius: 2, elementID: Element.stone, shape: .square)
        engine.setTint(10, 10, PowderEngine.tintWord(red: 200, green: 0, blue: 0))
        // A square loop round the stone, with room to spare.
        let loop: [(x: Double, y: Double)] = [(6, 6), (15, 6), (15, 15), (6, 15)]
        let inside = engine.cells(insideLoop: loop)
        #expect(inside.count == 81)
        let stamp = engine.stamp(of: inside)
        #expect(stamp.count == 25, "the stamp should be the stone and none of the air")
        // It remembers where it came from, so it can be put back exactly there.
        #expect(stamp.originX == 10 && stamp.originY == 10)
        #expect(engine.place(stamp, atX: 40, y: 20) == 25)
        #expect(engine.type[engine.index(40, 20)] == Element.stone)
        #expect(engine.tintAt(40, 20) == PowderEngine.tintWord(red: 200, green: 0, blue: 0))
        engine.clear(cells: inside)
        #expect(engine.type[engine.index(10, 10)] == Element.empty)
        #expect(count(Element.stone, in: engine) == 25)
        // A loop too small to hold a cell, and nonsense, hold nothing.
        #expect(engine.cells(insideLoop: [(1, 1), (1.2, 1), (1.1, 1.2)]).isEmpty)
        #expect(engine.cells(insideLoop: [(.nan, 1), (2, 2)]).isEmpty)
        // And putting a stamp down off the edge keeps only what lands inside.
        #expect(engine.place(stamp, atX: -1, y: -1) < 25)
    }

    @Test("Warming what the lasso holds warms only that")
    func lassoWarms() {
        let engine = world()
        engine.setElement(5, 5, Element.stone, temp: 20)
        engine.setElement(30, 30, Element.stone, temp: 20)
        engine.warm(cells: engine.cells(insideLoop: [(3, 3), (8, 3), (8, 8), (3, 8)]), by: 500)
        #expect(engine.temperature[engine.index(5, 5)] == 520)
        #expect(engine.temperature[engine.index(30, 30)] == 20)
    }

    @Test("Recolouring what the lasso holds colours the grains in it and leaves the air")
    func lassoRecolours() {
        let engine = world()
        engine.setElement(5, 5, Element.sand)
        engine.setElement(30, 30, Element.sand)
        let loop: [(x: Double, y: Double)] = [(3, 3), (8, 3), (8, 8), (3, 8)]
        let pink = PowderEngine.tintWord(red: 240, green: 90, blue: 160)
        engine.tint(cells: engine.cells(insideLoop: loop), with: pink)
        #expect(engine.tintAt(5, 5) == pink)
        #expect(engine.tintAt(6, 6) == 0, "air was given a colour")
        #expect(engine.tintAt(30, 30) == 0, "a grain outside the loop was recoloured")
        engine.tint(cells: engine.cells(insideLoop: loop), with: 0)
        #expect(engine.tintAt(5, 5) == 0, "nought did not give the grain its own colour back")
    }

    @Test("The plotter drawing outlines what is there in long straight lines")
    func plotterDrawing() {
        let empty = PowderEngine(width: 10, height: 10, seed: 1)
        #expect(empty.outlineLineCount() == 0, "an empty world should draw nothing")
        let single = PowderEngine(width: 10, height: 10, seed: 1)
        single.setElement(4, 4, Element.stone)
        #expect(single.outlineLineCount() == 4, "one grain is a square")
        let block = PowderEngine(width: 10, height: 10, seed: 1)
        block.drawBrush(centerX: 5, centerY: 5, radius: 2, elementID: Element.stone, shape: .square)
        // A five by five block is still four lines, not twenty.
        #expect(block.outlineLineCount() == 4)
        let svg = block.outlineSVG(cellMillimetres: 2)
        #expect(svg.hasPrefix("<svg"))
        #expect(svg.contains("width=\"20mm\""))
        #expect(svg.contains("M6 6H16"), "the top of the block was not one line: \(svg)")
        // Drawn from a copy of the cells it is the same drawing, and a copy that does not describe the world draws
        // an empty page rather than reading past its end.
        let copy = Array(UnsafeBufferPointer(start: block.type, count: block.cellCount))
        #expect(PowderEngine.outlineSVG(types: copy, width: 10, height: 10, cellMillimetres: 2) == svg)
        #expect(PowderEngine.outlineSVG(types: copy, width: 20, height: 20).contains("width=\"0mm\""))
    }
}
