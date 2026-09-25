import Testing

@testable import CrucibleCore

/// Words made of particles.
///
/// The drawing of the letters is the app's job and cannot be reached from here, so these tests draw their
/// own: a filled block, a ring, a letter H. Crude, but they have the two properties that matter — a known
/// shape and a known extent — which is exactly what is needed to ask whether the cloud keeps the shape.
struct ParticleTextShapeTests {
    private func field(seed: UInt32 = 11) -> ParticleEngine {
        let engine = ParticleEngine(width: 400, height: 700, seed: seed)
        engine.setMaxParticles(200_000)
        return engine
    }

    // MARK: - Pictures to sample

    /// A picture of the given size with a solid rectangle in it, measured in pixels from the top left.
    private func block(
        width: Int,
        height: Int,
        left: Int,
        top: Int,
        across: Int,
        down: Int
    ) -> [Double] {
        var out = [Double](repeating: 0, count: width * height)
        for row in top ..< min(height, top + down) {
            for column in left ..< min(width, left + across) {
                out[row * width + column] = 1
            }
        }
        return out
    }

    /// A picture of a filled disc, which is the shape a stretch shows up in most plainly.
    private func disc(width: Int, height: Int, centreX: Int, centreY: Int, radius: Int) -> [Double] {
        var out = [Double](repeating: 0, count: width * height)
        for row in 0 ..< height {
            for column in 0 ..< width {
                let dx = Double(column - centreX)
                let dy = Double(row - centreY)
                if (dx * dx + dy * dy).squareRoot() <= Double(radius) { out[row * width + column] = 1 }
            }
        }
        return out
    }

    /// A letter H: two uprights and a bar between them.
    private func letterH(width: Int, height: Int) -> [Double] {
        var out = [Double](repeating: 0, count: width * height)
        let stroke = max(1, width / 8)
        let top = height / 8
        let bottom = height - height / 8
        let left = width / 4
        let right = width - width / 4 - stroke
        for row in top ..< bottom {
            for column in left ..< (left + stroke) { out[row * width + column] = 1 }
            for column in right ..< min(width, right + stroke) { out[row * width + column] = 1 }
        }
        let barTop = height / 2 - stroke / 2
        for row in barTop ..< min(height, barTop + max(1, stroke)) {
            for column in left ..< min(width, right + stroke) { out[row * width + column] = 1 }
        }
        return out
    }

    /// Every body's place in the swarm.
    private func points(_ engine: ParticleEngine) -> [(x: Double, y: Double)] {
        (0 ..< engine.swarm.count).map { index in
            (Double(engine.swarm.positions[index * 2]), Double(engine.swarm.positions[index * 2 + 1]))
        }
    }

    // MARK: - Choosing which pixels become bodies

    @Test("Only pixels that are part of a letter become bodies")
    func samplesLandOnInk() {
        let width = 120
        let height = 80
        let coverage = letterH(width: width, height: height)
        var rng = Mulberry32(seed: 3)
        let picked = ParticleTextShape.samples(
            coverage: coverage, width: width, height: height, wanted: 400, random: &rng
        )
        #expect(!picked.isEmpty)
        for sample in picked {
            let column = min(width - 1, Int(sample.x * Double(width)))
            let row = min(height - 1, Int(sample.y * Double(height)))
            #expect(
                coverage[row * width + column] >= ParticleTextShape.defaultThreshold,
                "a body landed on blank paper at \(column), \(row)"
            )
        }
    }

    @Test("A picture with nothing in it makes no bodies")
    func blankPictureMakesNothing() {
        var rng = Mulberry32(seed: 3)
        let blank = [Double](repeating: 0, count: 64 * 64)
        #expect(ParticleTextShape.samples(
            coverage: blank, width: 64, height: 64, wanted: 500, random: &rng
        ).isEmpty)
    }

    @Test("Nonsense in, nothing out")
    func nonsenseMakesNothing() {
        var rng = Mulberry32(seed: 3)
        let solid = [Double](repeating: 1, count: 16 * 16)
        // Sizes that cannot describe the list handed over, and counts that ask for nothing.
        #expect(ParticleTextShape.samples(
            coverage: solid, width: 0, height: 16, wanted: 100, random: &rng
        ).isEmpty)
        #expect(ParticleTextShape.samples(
            coverage: solid, width: 16, height: 0, wanted: 100, random: &rng
        ).isEmpty)
        #expect(ParticleTextShape.samples(
            coverage: solid, width: 64, height: 64, wanted: 100, random: &rng
        ).isEmpty, "claimed a picture four thousand pixels bigger than the one handed over")
        #expect(ParticleTextShape.samples(
            coverage: solid, width: 16, height: 16, wanted: 0, random: &rng
        ).isEmpty)
        // Unusable darkness readings are not ink.
        let broken = [Double](repeating: .nan, count: 16 * 16)
        #expect(ParticleTextShape.samples(
            coverage: broken, width: 16, height: 16, wanted: 100, random: &rng
        ).isEmpty)
        // An unusable threshold falls back rather than refusing.
        #expect(!ParticleTextShape.samples(
            coverage: solid, width: 16, height: 16, wanted: 100, threshold: .nan, random: &rng
        ).isEmpty)
    }

    @Test("Roughly the number asked for, and never more")
    func countIsNearWhatWasAsked() {
        let width = 200
        let height = 200
        let coverage = block(width: width, height: height, left: 0, top: 0, across: 200, down: 200)
        for wanted in [200, 1_000, 4_000] {
            var rng = Mulberry32(seed: 5)
            let picked = ParticleTextShape.samples(
                coverage: coverage, width: width, height: height, wanted: wanted, random: &rng
            )
            #expect(picked.count <= wanted, "asked for \(wanted) and got \(picked.count)")
            #expect(
                Double(picked.count) > Double(wanted) * 0.45,
                "asked for \(wanted) and got only \(picked.count)"
            )
        }
    }

    @Test("Asking for more bodies than there are pixels does not loop or repeat")
    func morewantedThanPixels() {
        let coverage = [Double](repeating: 1, count: 20 * 20)
        var rng = Mulberry32(seed: 5)
        let picked = ParticleTextShape.samples(
            coverage: coverage, width: 20, height: 20, wanted: 10_000, random: &rng
        )
        #expect(picked.count == 400, "got \(picked.count) from a four hundred pixel picture")
    }

    // MARK: - Evenness

    @Test("The cloud is spread evenly over the letters, not clumped")
    func spreadIsEven() {
        // A solid square, so every part of it deserves the same share and any unevenness is the sampling's.
        let side = 160
        let coverage = block(width: side, height: side, left: 0, top: 0, across: side, down: side)
        var rng = Mulberry32(seed: 9)
        let picked = ParticleTextShape.samples(
            coverage: coverage, width: side, height: side, wanted: 4_000, random: &rng
        )
        #expect(picked.count > 1_500)

        // Counted in an eight by eight grid over the square. Sixty-four boxes, so each should hold about a
        // sixty-fourth. A free scatter of this many points would routinely leave a box at half or double.
        var boxes = [Int](repeating: 0, count: 64)
        for sample in picked {
            let column = min(7, Int(sample.x * 8))
            let row = min(7, Int(sample.y * 8))
            boxes[row * 8 + column] += 1
        }
        let average = Double(picked.count) / 64
        for (index, held) in boxes.enumerated() {
            #expect(
                Double(held) > average * 0.7 && Double(held) < average * 1.3,
                "box \(index) holds \(held) where the average is \(average)"
            )
        }
    }

    @Test("Thinning takes from everywhere, not off the bottom")
    func thinningKeepsTheWholeWord() {
        // The picture is read from the top down, so an overshoot trimmed by dropping the tail would cut the
        // bottom off the word. Asking for far fewer than the lattice naturally finds forces the trim.
        let side = 160
        let coverage = block(width: side, height: side, left: 0, top: 0, across: side, down: side)
        var rng = Mulberry32(seed: 9)
        let picked = ParticleTextShape.samples(
            coverage: coverage, width: side, height: side, wanted: 300, random: &rng
        )
        #expect(!picked.isEmpty)
        let lowest = picked.map(\.y).max() ?? 0
        let highest = picked.map(\.y).min() ?? 1
        #expect(lowest > 0.9, "the bottom of the word is missing: it stops at \(lowest)")
        #expect(highest < 0.1, "the top of the word is missing: it starts at \(highest)")
    }

    // MARK: - Repeatability

    @Test("The same word from the same seed gives the same cloud")
    func sameSeedSameCloud() {
        let coverage = letterH(width: 120, height: 80)
        var first = Mulberry32(seed: 21)
        var second = Mulberry32(seed: 21)
        let a = ParticleTextShape.samples(
            coverage: coverage, width: 120, height: 80, wanted: 600, random: &first
        )
        let b = ParticleTextShape.samples(
            coverage: coverage, width: 120, height: 80, wanted: 600, random: &second
        )
        #expect(a == b)
    }

    @Test("A different seed gives a different cloud of the same word")
    func differentSeedDifferentCloud() {
        let coverage = letterH(width: 120, height: 80)
        var first = Mulberry32(seed: 21)
        var second = Mulberry32(seed: 22)
        let a = ParticleTextShape.samples(
            coverage: coverage, width: 120, height: 80, wanted: 600, random: &first
        )
        let b = ParticleTextShape.samples(
            coverage: coverage, width: 120, height: 80, wanted: 600, random: &second
        )
        #expect(a != b)
        // Same word though, so the two should be about the same size.
        #expect(abs(a.count - b.count) < max(20, a.count / 5))
    }

    @Test("Where the ink is does not change how far the random stream moves")
    func streamUseDoesNotDependOnWhereTheInkIs() {
        // Two pictures holding the same amount of ink in quite different places. Every lattice cell is
        // visited and drawn for whether or not it finds anything, so the stream must end up in the same
        // place — which is what lets a field draw a word and then carry on reproducibly. If some early exit
        // ever skipped blank areas, this is the test that would say so.
        let left = block(width: 120, height: 80, left: 0, top: 0, across: 40, down: 40)
        let right = block(width: 120, height: 80, left: 80, top: 40, across: 40, down: 40)
        var a = Mulberry32(seed: 4)
        var b = Mulberry32(seed: 4)
        let first = ParticleTextShape.samples(
            coverage: left, width: 120, height: 80, wanted: 600, random: &a
        )
        let second = ParticleTextShape.samples(
            coverage: right, width: 120, height: 80, wanted: 600, random: &b
        )
        #expect(!first.isEmpty && !second.isEmpty)
        #expect(a.next() == b.next())
    }

    // MARK: - Fitting it into the world

    @Test("A word lands in the field and fills most of it")
    func wordFillsTheField() {
        let engine = field()
        let placed = engine.spawnTextCloud(
            coverage: letterH(width: 512, height: 192),
            width: 512,
            height: 192,
            count: 3_000
        )
        #expect(placed > 800, "placed only \(placed)")
        let cloud = points(engine)
        for point in cloud {
            #expect(point.x.isFinite && point.y.isFinite)
            #expect(point.x >= 0 && point.x <= engine.width)
            #expect(point.y >= 0 && point.y <= engine.height)
        }
        // The letter H is wider than it is tall once drawn wide, so it should be fitted across.
        let widest = (cloud.map(\.x).max() ?? 0) - (cloud.map(\.x).min() ?? 0)
        #expect(widest > engine.width * 0.6, "the word spans only \(widest) of \(engine.width)")
    }

    @Test("A small mark in a big empty picture is still drawn full size")
    func fittedByItsOwnInkNotThePicture() {
        // The picture is what the drawing machinery happened to hand over; a short word sits in the middle of
        // a mostly empty one. Fitting the picture would draw it as a speck.
        let engine = field()
        engine.spawnTextCloud(
            coverage: block(width: 512, height: 192, left: 200, top: 80, across: 90, down: 34),
            width: 512,
            height: 192,
            count: 2_000
        )
        let cloud = points(engine)
        #expect(cloud.count > 400)
        let widest = (cloud.map(\.x).max() ?? 0) - (cloud.map(\.x).min() ?? 0)
        #expect(widest > engine.width * 0.6, "the mark was drawn \(widest) wide in a \(engine.width) field")
    }

    @Test("A round mark comes out round, not stretched sideways")
    func shapeIsNotStretched() {
        // The strongest test in the file. The picture is two and two thirds times as wide as it is tall; a
        // fit done in fractions of the picture rather than in real distances stretches this disc into a
        // flattened oval, and nothing else here would notice.
        let engine = field()
        engine.spawnTextCloud(
            coverage: disc(width: 512, height: 192, centreX: 256, centreY: 96, radius: 80),
            width: 512,
            height: 192,
            count: 3_000
        )
        let cloud = points(engine)
        #expect(cloud.count > 600)
        let across = (cloud.map(\.x).max() ?? 0) - (cloud.map(\.x).min() ?? 0)
        let down = (cloud.map(\.y).max() ?? 0) - (cloud.map(\.y).min() ?? 0)
        #expect(
            abs(across - down) < max(across, down) * 0.12,
            "a circle came out \(across) across and \(down) down"
        )
    }

    @Test("A word arrives still, so it can be read before anything moves it")
    func wordArrivesStill() {
        let engine = field()
        engine.spawnTextCloud(
            coverage: letterH(width: 256, height: 96), width: 256, height: 96, count: 800
        )
        #expect(engine.swarm.count > 100)
        for index in 0 ..< engine.swarm.count {
            #expect(engine.swarm.velocities[index * 2] == 0)
            #expect(engine.swarm.velocities[index * 2 + 1] == 0)
        }
    }

    @Test("A word can be undone")
    func wordCanBeUndone() {
        let engine = field()
        engine.spawnTextCloud(
            coverage: letterH(width: 256, height: 96), width: 256, height: 96, count: 800
        )
        #expect(engine.swarm.count > 0)
        engine.undo()
        #expect(engine.swarm.count == 0)
    }

    @Test("A full field refuses a word rather than overfilling")
    func fullFieldRefuses() {
        let engine = ParticleEngine(width: 400, height: 700, seed: 3)
        engine.setMaxParticles(1_000)
        engine.spawnBatch(count: 1_000)
        let before = engine.swarm.count
        let placed = engine.spawnTextCloud(
            coverage: letterH(width: 256, height: 96), width: 256, height: 96, count: 2_000
        )
        #expect(placed == 0)
        #expect(engine.swarm.count == before)
    }

    @Test("Blank paper leaves the field as it was")
    func blankPaperChangesNothing() {
        let engine = field()
        let placed = engine.spawnTextCloud(
            coverage: [Double](repeating: 0, count: 256 * 96), width: 256, height: 96, count: 800
        )
        #expect(placed == 0)
        #expect(engine.swarm.count == 0)
    }

    @Test("How much of the field a word fills can be turned down")
    func fillIsAdjustable() {
        func spanOf(fill: Double) -> Double {
            let engine = field()
            engine.spawnTextCloud(
                coverage: letterH(width: 512, height: 192),
                width: 512,
                height: 192,
                count: 2_000,
                fill: fill
            )
            let cloud = points(engine)
            return (cloud.map(\.x).max() ?? 0) - (cloud.map(\.x).min() ?? 0)
        }
        let small = spanOf(fill: 0.35)
        let large = spanOf(fill: 0.95)
        #expect(large > small * 1.8, "turning the size up went from \(small) to \(large)")
        // Nonsense falls back rather than collapsing the word to a point.
        #expect(spanOf(fill: .nan) > engine_minimumUsefulSpan)
    }

    private var engine_minimumUsefulSpan: Double { 40 }
}
