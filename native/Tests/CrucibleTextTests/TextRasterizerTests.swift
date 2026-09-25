import Testing

#if canImport(CoreText)

@testable import CrucibleCore
@testable import CrucibleText

/// Drawing a word into a picture.
///
/// These only run where there is text machinery to run them against, which in this project's checks means the
/// macOS half. That is the point of them: the questions here — which way up, which way round, what shape —
/// are ones that reading the code cannot settle, and that nothing else in the project would notice getting
/// wrong. A word rendered upside down is perfectly reasonable code producing a ruined picture.
///
/// The letters chosen are the ones whose ink is lopsided in a way no font can reverse. A T is heavier at the
/// top than the bottom in every typeface there has ever been; an L is heavier at the bottom, and its top half
/// sits to the left. Between them they pin down both directions.
struct TextRasterizerTests {
    /// How much ink there is in a part of the picture, as a share of all of it.
    private func ink(
        _ picture: TextRasterizer.Picture,
        columns: Range<Double>,
        rows: Range<Double>
    ) -> Double {
        var inside = 0.0
        var all = 0.0
        for row in 0 ..< picture.height {
            let downThrough = (Double(row) + 0.5) / Double(picture.height)
            for column in 0 ..< picture.width {
                let value = picture.coverage[row * picture.width + column]
                guard value > 0.35 else { continue }
                all += 1
                let acrossThrough = (Double(column) + 0.5) / Double(picture.width)
                if columns.contains(acrossThrough), rows.contains(downThrough) { inside += 1 }
            }
        }
        guard all > 0 else { return 0 }
        return inside / all
    }

    /// The box the ink sits in, in fractions of the picture.
    private func inkBox(
        _ picture: TextRasterizer.Picture
    ) -> (left: Double, right: Double, top: Double, bottom: Double)? {
        var left = 1.0
        var right = 0.0
        var top = 1.0
        var bottom = 0.0
        var found = false
        for row in 0 ..< picture.height {
            for column in 0 ..< picture.width where picture.coverage[row * picture.width + column] > 0.35 {
                found = true
                let x = (Double(column) + 0.5) / Double(picture.width)
                let y = (Double(row) + 0.5) / Double(picture.height)
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
            }
        }
        return found ? (left, right, top, bottom) : nil
    }

    // MARK: - Which way up

    @Test("A T comes out heavier at the top, so the picture is not upside down")
    func rightWayUp() throws {
        let picture = try #require(TextRasterizer.picture(of: "T"))
        let box = try #require(inkBox(picture))
        let middle = (box.top + box.bottom) / 2
        let upper = ink(picture, columns: 0 ..< 1, rows: 0 ..< middle)
        #expect(
            upper > 0.62,
            "only \(Int(upper * 100))% of a T's ink is in its top half — the picture is upside down"
        )
    }

    @Test("An L comes out heavier at the bottom")
    func lIsBottomHeavy() throws {
        let picture = try #require(TextRasterizer.picture(of: "L"))
        let box = try #require(inkBox(picture))
        let middle = (box.top + box.bottom) / 2
        let lower = ink(picture, columns: 0 ..< 1, rows: middle ..< 1)
        #expect(
            lower > 0.55,
            "only \(Int(lower * 100))% of an L's ink is in its bottom half — the picture is upside down"
        )
    }

    // MARK: - Which way round

    @Test("The top of an L sits to the left, so the picture is not mirrored")
    func notMirrored() throws {
        let picture = try #require(TextRasterizer.picture(of: "L"))
        let box = try #require(inkBox(picture))
        let middle = (box.left + box.right) / 2
        let topThird = box.top ..< (box.top + (box.bottom - box.top) / 3)
        let onTheLeft = ink(picture, columns: 0 ..< middle, rows: topThird)
        #expect(
            onTheLeft > 0.8,
            "only \(Int(onTheLeft * 100))% of the top of an L is on its left — the picture is mirrored"
        )
    }

    @Test("Two words in a row read left to right, not right to left")
    func readsLeftToRight() throws {
        // A full stop is a small mark at one end. Put at the end of the word it must come out on the right.
        let picture = try #require(TextRasterizer.picture(of: "I."))
        let box = try #require(inkBox(picture))
        let stem = ink(picture, columns: 0 ..< ((box.left + box.right) / 2), rows: 0 ..< 1)
        #expect(stem > 0.7, "the upright of ‘I.’ is not on the left — the word is back to front")
    }

    // MARK: - Shape and size

    @Test("A word is fitted to the sheet without being squashed")
    func fittedWithoutSquashing() throws {
        let wide = try #require(TextRasterizer.picture(of: "CRUCIBLE"))
        let wideBox = try #require(inkBox(wide))
        // In pixels, because the sheet is far wider than it is tall and fractions of it are not distances.
        let wideAcross = (wideBox.right - wideBox.left) * Double(wide.width)
        let wideDown = (wideBox.bottom - wideBox.top) * Double(wide.height)
        #expect(wideAcross > wideDown * 2, "a long word came out \(wideAcross) by \(wideDown)")

        let narrow = try #require(TextRasterizer.picture(of: "I"))
        let narrowBox = try #require(inkBox(narrow))
        let narrowAcross = (narrowBox.right - narrowBox.left) * Double(narrow.width)
        let narrowDown = (narrowBox.bottom - narrowBox.top) * Double(narrow.height)
        #expect(narrowDown > narrowAcross, "a single upright came out \(narrowAcross) by \(narrowDown)")
    }

    @Test("A word fills the sheet rather than sitting in a corner of it")
    func fillsTheSheet() throws {
        let picture = try #require(TextRasterizer.picture(of: "CRUCIBLE"))
        let box = try #require(inkBox(picture))
        #expect(box.right - box.left > 0.8, "the word spans only \(box.right - box.left) of the sheet")
        // Centred: the gaps at the two ends should match.
        #expect(abs(box.left - (1 - box.right)) < 0.06, "the word is off to one side")
        #expect(abs(box.top - (1 - box.bottom)) < 0.12, "the word rides high or low")
    }

    @Test("Nothing is clipped off at the edges")
    func nothingClipped() throws {
        for word in ["CRUCIBLE", "gjpqy", "W", "A very long sentence indeed, quite a lot of it"] {
            let picture = try #require(TextRasterizer.picture(of: word), "‘\(word)’ drew nothing at all")
            let box = try #require(inkBox(picture))
            #expect(box.left > 0.001, "‘\(word)’ touches the left edge")
            #expect(box.right < 0.999, "‘\(word)’ touches the right edge")
            #expect(box.top > 0.001, "‘\(word)’ touches the top edge")
            #expect(box.bottom < 0.999, "‘\(word)’ touches the bottom edge")
        }
    }

    // MARK: - What comes back

    @Test("The picture is the size it says it is, and the numbers are usable")
    func pictureIsWellFormed() throws {
        let picture = try #require(TextRasterizer.picture(of: "Crucible"))
        #expect(picture.width == TextRasterizer.pictureWidth)
        #expect(picture.height == TextRasterizer.pictureHeight)
        #expect(picture.coverage.count == picture.width * picture.height)
        for value in picture.coverage {
            #expect(value.isFinite && value >= 0 && value <= 1)
        }
        #expect(picture.darkness(column: -1, row: 0) == 0, "asking outside the sheet should be blank")
        #expect(picture.darkness(column: 0, row: picture.height) == 0)
    }

    @Test("Letters have soft edges rather than jagged ones")
    func edgesAreSmoothed() throws {
        let picture = try #require(TextRasterizer.picture(of: "S"))
        // Part-dark pixels are the smoothed edge. Without them the strokes would be stepped, and the cloud
        // would be sampled from a staircase.
        let partial = picture.coverage.filter { $0 > 0.05 && $0 < 0.95 }.count
        #expect(partial > 200, "only \(partial) part-dark pixels — the letters are not being smoothed")
    }

    @Test("A custom sheet size is honoured")
    func customSize() throws {
        let picture = try #require(TextRasterizer.picture(of: "Hi", width: 128, height: 128))
        #expect(picture.width == 128)
        #expect(picture.height == 128)
        #expect(picture.coverage.count == 128 * 128)
        #expect(inkBox(picture) != nil)
    }

    @Test("The same word drawn twice gives the same picture")
    func drawingIsRepeatable() throws {
        let first = try #require(TextRasterizer.picture(of: "Crucible"))
        let second = try #require(TextRasterizer.picture(of: "Crucible"))
        #expect(first == second)
    }

    // MARK: - Nothing to draw

    @Test("No word means no picture")
    func nothingToDraw() {
        #expect(TextRasterizer.picture(of: "") == nil)
        #expect(TextRasterizer.picture(of: "   ") == nil)
        #expect(TextRasterizer.picture(of: "\n\t ") == nil)
        #expect(TextRasterizer.picture(of: "A", width: 0, height: 100) == nil)
        #expect(TextRasterizer.picture(of: "A", width: 100, height: 0) == nil)
    }

    @Test("Odd input is drawn or refused, never crashed on")
    func oddInput() {
        let awkward = [
            "🔥🔥🔥",
            "日本語",
            "الشمس",
            String(repeating: "M", count: 400),
            "\u{200B}\u{200B}",
            "i̴̶̷̸̡̢̛̖̗̘",
            "-",
        ]
        for word in awkward {
            // Either a usable picture or nothing. Both are answers; a crash or a wrongly sized list is not.
            if let picture = TextRasterizer.picture(of: word) {
                #expect(picture.coverage.count == picture.width * picture.height, "‘\(word)’")
                for value in picture.coverage { #expect(value.isFinite, "‘\(word)’") }
            }
        }
    }

    // MARK: - The whole way through

    @Test("A drawn word becomes a cloud of particles")
    func wordBecomesACloud() throws {
        // The join between the two halves, which is the thing neither half's own tests can check.
        let picture = try #require(TextRasterizer.picture(of: "CRUCIBLE"))
        let engine = ParticleEngine(width: 400, height: 700, seed: 5)
        engine.setMaxParticles(50_000)
        let placed = engine.spawnTextCloud(
            coverage: picture.coverage,
            width: picture.width,
            height: picture.height,
            count: 4_000
        )
        #expect(placed > 1_000, "placed only \(placed)")

        var left = Double.greatestFiniteMagnitude
        var right = -Double.greatestFiniteMagnitude
        var top = Double.greatestFiniteMagnitude
        var bottom = -Double.greatestFiniteMagnitude
        for index in 0 ..< engine.swarm.count {
            let x = Double(engine.swarm.positions[index * 2])
            let y = Double(engine.swarm.positions[index * 2 + 1])
            left = min(left, x)
            right = max(right, x)
            top = min(top, y)
            bottom = max(bottom, y)
        }
        // Across most of the field, and a band rather than a blob — which is what a word looks like.
        #expect(right - left > engine.width * 0.6, "the word is \(right - left) wide")
        #expect(bottom - top < (right - left) * 0.5, "the word is \(bottom - top) tall, which is not a line")
    }

    @Test("A word made of particles is still the right way up")
    func cloudIsTheRightWayUp() throws {
        // The same T test, but after the whole journey: drawn, sampled, placed in the world. The engine's
        // world counts downward from the top like the picture does, so a T's bodies must be mostly high up.
        let picture = try #require(TextRasterizer.picture(of: "T"))
        let engine = ParticleEngine(width: 400, height: 700, seed: 5)
        engine.setMaxParticles(50_000)
        engine.spawnTextCloud(
            coverage: picture.coverage, width: picture.width, height: picture.height, count: 3_000
        )
        #expect(engine.swarm.count > 400)

        var heights: [Double] = []
        for index in 0 ..< engine.swarm.count {
            heights.append(Double(engine.swarm.positions[index * 2 + 1]))
        }
        let highest = heights.min() ?? 0
        let lowest = heights.max() ?? 0
        let middle = (highest + lowest) / 2
        let above = Double(heights.filter { $0 < middle }.count) / Double(heights.count)
        #expect(above > 0.62, "only \(Int(above * 100))% of a T's bodies are in its top half")
    }
}

#endif
