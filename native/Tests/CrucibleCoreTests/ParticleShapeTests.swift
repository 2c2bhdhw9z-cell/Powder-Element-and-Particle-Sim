import Foundation
import Testing

@testable import CrucibleCore

/// The silhouettes bodies are drawn as.
///
/// A shape fault is invisible in the numbers and obvious on the screen, and the app layer has no
/// tests at all — which is why the arithmetic lives in the engine and is checked here. Three of the
/// ten shapes were wrong when first written and all three were found by drawing them out as text and
/// looking: the star came out as a filled square with a star-shaped hole, the hexagon overran its box
/// and arrived with its top and bottom sliced off, and the spark was a plain diamond with an invisible
/// cross inside it. These tests are what that exercise turned into.
struct ParticleShapeTests {
    /// Renders a shape as a grid of "is this pixel inside", the way the probe did.
    private func grid(_ shape: ParticleShape, size: Int = 33) -> [[Bool]] {
        (0 ..< size).map { row in
            let y = 1 - Double(row) * (2 / Double(size - 1))
            return (0 ..< size).map { column in
                let x = -1 + Double(column) * (2 / Double(size - 1))
                return shape.coverage(x: x, y: y) > 0.5
            }
        }
    }

    private func filledCount(_ shape: ParticleShape) -> Int {
        grid(shape).reduce(0) { $0 + $1.filter { $0 }.count }
    }

    // MARK: - The basics every shape must satisfy

    /// The one shape that is meant to be empty in the middle.
    ///
    /// Named rather than skipped in passing, so that the exception has to be justified each time it is
    /// used and a second hollow shape cannot creep in unnoticed.
    private let hollowShapes: Set<ParticleShape> = [.ring]

    /// The one shape that is meant to fill its whole box, corners included.
    private let boxFillingShapes: Set<ParticleShape> = [.square]

    @Test("Every shape is solid at its centre, except the ring")
    func centresAreFilled() {
        // The star failed this, and it is the cheapest possible check: a shape whose middle is empty
        // is its own negative.
        for shape in ParticleShape.allCases where !hollowShapes.contains(shape) {
            #expect(shape.coverage(x: 0, y: 0) == 1, "\(shape.rawValue) is hollow at the centre")
        }
        #expect(ParticleShape.ring.coverage(x: 0, y: 0) == 0, "the ring is supposed to be hollow")
    }

    @Test("Every shape is empty outside its box")
    func outsideIsEmpty() {
        for shape in ParticleShape.allCases {
            for point in [(-3.0, 0.0), (3.0, 0.0), (0.0, 3.0), (0.0, -3.0), (2.0, 2.0)] {
                #expect(
                    shape.coverage(x: point.0, y: point.1) == 0,
                    "\(shape.rawValue) draws something at \(point)"
                )
            }
        }
    }

    @Test("Every shape reaches the edge of its box somewhere")
    func shapesFillTheirBox() {
        // A shape drawn well inside its box arrives smaller than every other shape at the same
        // setting, so choosing it silently shrinks the bodies. Every one of these should touch the
        // boundary on at least one axis.
        for shape in ParticleShape.allCases {
            let reaches = [
                shape.coverage(x: 0, y: 0.96) > 0,
                shape.coverage(x: 0, y: -0.96) > 0,
                shape.coverage(x: 0.96, y: 0) > 0,
                shape.coverage(x: -0.96, y: 0) > 0,
            ]
            #expect(reaches.contains(true), "\(shape.rawValue) never reaches the edge of its box")
        }
    }

    @Test("Only the square fills its corners")
    func cornersAreCutExceptOnTheSquare() {
        // This is what catches a shape that has overrun its box and been sliced flat: whatever it was
        // meant to be, it ends up filling the corners like a square. The hexagon did exactly that
        // before it was fixed, and the reference implementation's own notes describe its snowflakes
        // overshooting their radius for the same reason.
        for shape in ParticleShape.allCases {
            let corners = [(0.88, 0.88), (-0.88, 0.88), (0.88, -0.88), (-0.88, -0.88)]
            for corner in corners {
                let filled = shape.coverage(x: corner.0, y: corner.1) > 0.5
                if boxFillingShapes.contains(shape) {
                    #expect(filled, "the square should reach \(corner)")
                } else {
                    #expect(!filled, "\(shape.rawValue) fills the corner \(corner) like a square")
                }
            }
        }
    }

    @Test("Every shape covers a sensible amount of its box")
    func shapesAreNeitherEmptyNorFull() {
        // A shape that fills almost nothing is a dot, and one that fills almost everything is a
        // square by another name. Either way the choice in the interface would do nothing.
        let total = 33 * 33
        for shape in ParticleShape.allCases {
            let filled = filledCount(shape)
            #expect(filled > total / 12, "\(shape.rawValue) covers almost nothing (\(filled))")
            if shape != .square {
                #expect(filled < total * 9 / 10, "\(shape.rawValue) covers almost everything (\(filled))")
            }
        }
    }

    @Test("No two shapes are the same")
    func shapesAreDistinct() {
        // Ten entries in a picker have to be ten shapes. The spark was a second diamond before this
        // test existed, which is exactly the kind of choice-that-does-nothing this project has
        // shipped before.
        var seen: [String: String] = [:]
        for shape in ParticleShape.allCases {
            let signature = grid(shape, size: 49)
                .map { row in String(row.map { $0 ? "#" : "." }) }
                .joined(separator: "/")
            if let twin = seen[signature] {
                Issue.record("\(shape.rawValue) draws exactly the same as \(twin)")
            }
            seen[signature] = shape.rawValue
        }
    }

    @Test("A point that is not a number does not draw and does not crash")
    func unusableCoordinatesAreSafe() {
        for shape in ParticleShape.allCases {
            for point in [(Double.nan, 0.0), (0.0, Double.nan), (.infinity, .infinity)] {
                let coverage = shape.coverage(x: point.0, y: point.1, softness: 0.1)
                #expect(coverage.isFinite, "\(shape.rawValue) at \(point) gave \(coverage)")
                #expect(coverage >= 0 && coverage <= 1)
            }
        }
    }

    @Test("Shader numbers are fixed and unique")
    func shaderIdentifiersAreStable() {
        // Written out by hand rather than taken from the order of the cases, so that adding a shape
        // cannot silently renumber the rest and start drawing hearts where the squares were.
        let numbers = ParticleShape.allCases.map(\.shaderIdentifier)
        #expect(Set(numbers).count == numbers.count, "two shapes share a number")
        #expect(ParticleShape.circle.shaderIdentifier == 0, "the circle must stay nought")
        for number in numbers {
            #expect(number >= 0 && number < Int32(ParticleShape.allCases.count))
        }
    }

    // MARK: - Each shape actually being that shape

    @Test("The circle is round")
    func circleIsRound() {
        for step in 0 ..< 32 {
            let angle = Double(step) * 2 * .pi / 32
            #expect(ParticleShape.circle.coverage(x: jsCos(angle) * 0.9, y: jsSin(angle) * 0.9) == 1)
            #expect(ParticleShape.circle.coverage(x: jsCos(angle) * 1.1, y: jsSin(angle) * 1.1) == 0)
        }
        #expect(ParticleShape.circle.coverage(x: 0.8, y: 0.8) == 0, "the corners must be empty")
    }

    @Test("The square has corners and the diamond has them turned")
    func squareAndDiamondDiffer() {
        #expect(ParticleShape.square.coverage(x: 0.9, y: 0.9) == 1, "a square reaches its corners")
        #expect(ParticleShape.diamond.coverage(x: 0.9, y: 0.9) == 0, "a diamond does not")
        #expect(ParticleShape.diamond.coverage(x: 0, y: 0.9) == 1, "a diamond reaches its points")
        #expect(ParticleShape.diamond.coverage(x: 0.9, y: 0) == 1)
    }

    @Test("The ring is hollow, and hollow all the way round")
    func ringIsHollow() {
        #expect(ParticleShape.ring.coverage(x: 0, y: 0) == 0)
        for step in 0 ..< 24 {
            let angle = Double(step) * 2 * .pi / 24
            #expect(
                ParticleShape.ring.coverage(x: jsCos(angle) * 0.7, y: jsSin(angle) * 0.7) == 1,
                "the band is broken at \(angle)"
            )
            #expect(
                ParticleShape.ring.coverage(x: jsCos(angle) * 0.3, y: jsSin(angle) * 0.3) == 0,
                "the hole is filled at \(angle)"
            )
        }
    }

    @Test("The triangle points upward and widens toward its base")
    func triangleWidensDownward() {
        // The reference implementation states this in terms of whichever end its coordinates put
        // first, which is why its two drawing paths disagree about which way its triangles point.
        let rows = grid(.triangle, size: 49)
        let widths = rows.map { $0.filter { $0 }.count }
        let filledRows = widths.enumerated().filter { $0.element > 0 }
        let first = try? #require(filledRows.first)
        let last = try? #require(filledRows.last)
        #expect((first?.element ?? 99) < (last?.element ?? 0), "the top is not narrower than the base")
        #expect((first?.offset ?? 99) < 4, "the apex should be near the top of the box")

        // And monotonically, so it is a triangle rather than an hourglass.
        var previous = 0
        for (index, width) in widths.enumerated() where width > 0 && index <= (last?.offset ?? 0) {
            #expect(width >= previous, "row \(index) is narrower than the one above it")
            previous = width
        }
    }

    @Test("The star has five points, one of them at the top")
    func starHasFivePoints() {
        // Counted by walking a circle just inside the tips and seeing how many separate stretches of
        // the shape it crosses.
        let radius = 0.88
        var inside: [Bool] = []
        for step in 0 ..< 360 {
            let angle = Double(step) * .pi / 180
            inside.append(ParticleShape.star.coverage(x: jsCos(angle) * radius, y: jsSin(angle) * radius) > 0.5)
        }
        var runs = 0
        for step in 0 ..< 360 where inside[step] && !inside[(step + 359) % 360] {
            runs += 1
        }
        #expect(runs == 5, "found \(runs) points rather than five")
        #expect(ParticleShape.star.coverage(x: 0, y: 0.95) == 1, "there must be a point at the top")
        #expect(ParticleShape.star.coverage(x: 0, y: -0.95) == 0, "and a valley at the bottom")
    }

    @Test("The hexagon has six sides and fits its box exactly")
    func hexagonFitsAndHasSixSides() {
        #expect(ParticleShape.hexagon.coverage(x: 0, y: 0.99) == 1, "points must reach the top")
        #expect(ParticleShape.hexagon.coverage(x: 0.99, y: 0) == 0, "and the flats must not reach the side")
        #expect(ParticleShape.hexagon.coverage(x: 0.85, y: 0) == 1)
        // Corners cut, which is what makes it a hexagon and not a square.
        #expect(ParticleShape.hexagon.coverage(x: 0.8, y: 0.8) == 0)
    }

    @Test("The cross has four arms and a hollow between each pair")
    func plusHasFourArms() {
        #expect(ParticleShape.plus.coverage(x: 0, y: 0.95) == 1)
        #expect(ParticleShape.plus.coverage(x: 0, y: -0.95) == 1)
        #expect(ParticleShape.plus.coverage(x: 0.95, y: 0) == 1)
        #expect(ParticleShape.plus.coverage(x: -0.95, y: 0) == 1)
        for corner in [(0.6, 0.6), (-0.6, 0.6), (0.6, -0.6), (-0.6, -0.6)] {
            #expect(
                ParticleShape.plus.coverage(x: corner.0, y: corner.1) == 0,
                "the corner \(corner) should be empty"
            )
        }
    }

    @Test("The spark has four points with sides curving inward")
    func sparkIsPinched() {
        // The difference between a spark and a cross: a cross has straight sides, so halfway out
        // along the diagonal it is empty either way — but a spark is pinched much closer to the
        // centre. This is the check the reference implementation's version fails, because what it
        // actually draws is a diamond.
        #expect(ParticleShape.spark.coverage(x: 0, y: 0.95) == 1, "there must be a point upward")
        #expect(ParticleShape.spark.coverage(x: 0.95, y: 0) == 1, "and sideways")

        // The waist along the diagonal.
        let waist = (0 ..< 40).first { step in
            let r = Double(step) * 0.025
            return ParticleShape.spark.coverage(x: r * 0.7071, y: r * 0.7071) <= 0.5
        }
        let waistRadius = Double(waist ?? 40) * 0.025
        #expect(waistRadius < 0.45, "the diagonal reaches \(waistRadius), which is not pinched")

        // And a diamond would not be pinched at all, which is the shape it must not be.
        #expect(
            ParticleShape.diamond.coverage(x: 0.45, y: 0.45) == 1,
            "a diamond does reach here, so the two really are different"
        )
        #expect(ParticleShape.spark.coverage(x: 0.45, y: 0.45) == 0)
    }

    @Test("The heart has two lobes at the top and a point at the bottom")
    func heartHasLobesAndAPoint() {
        // The notch between the lobes is the whole difference between a heart and a rounded blob with
        // a point on it, which is what the reference implementation's coefficient actually produces.
        let rows = grid(.heart, size: 65)
        let notchRow = rows.enumerated().first { entry in
            let row = entry.element
            guard row.contains(true) else { return false }
            // A row with a gap in the middle: filled, then empty, then filled again.
            var transitions = 0
            for index in 1 ..< row.count where row[index] != row[index - 1] { transitions += 1 }
            return transitions >= 4
        }
        #expect(notchRow != nil, "no row of the heart has a notch in it")
        if let notchRow {
            #expect(notchRow.offset < 32, "the notch should be in the top half, not the bottom")
        }

        // And a single point at the bottom.
        let widths = rows.map { $0.filter { $0 }.count }
        let lastFilled = widths.lastIndex(where: { $0 > 0 }) ?? 0
        #expect(widths[lastFilled] <= 3, "the bottom of the heart should come to a point")
        #expect(lastFilled > 48, "and it should reach well down the box")
    }

    // MARK: - The faded edge

    @Test("Softening fades the edge and leaves the inside alone")
    func softnessOnlyAffectsTheEdge() {
        for shape in ParticleShape.allCases where !hollowShapes.contains(shape) {
            #expect(
                shape.coverage(x: 0, y: 0, softness: 0.3) == 1,
                "\(shape.rawValue) faded at its centre"
            )
        }
        #expect(
            ParticleShape.ring.coverage(x: 0, y: 0.7, softness: 0.3) == 1,
            "the middle of the ring's band should be solid"
        )

        // A circle is the one whose edge position is known exactly, so the ramp can be checked
        // against a specific place.
        let hard = ParticleShape.circle.coverage(x: 0.97, y: 0, softness: 0)
        let soft = ParticleShape.circle.coverage(x: 0.97, y: 0, softness: 0.1)
        #expect(hard == 1, "with no softening the edge is a step")
        #expect(soft > 0 && soft < 1, "with softening it is part-way, not \(soft)")
    }

    @Test("Coverage falls steadily as a point leaves the shape")
    func coverageIsMonotonic() {
        // A shape whose coverage went up again on the way out would have a bright halo round it.
        //
        // Measured outward from wherever the shape is solid rather than from the centre, because the
        // ring's centre is deliberately empty — starting there would measure the coverage climbing
        // into the band, which is the shape working correctly.
        for shape in ParticleShape.allCases {
            let start = shape == .ring ? 0.7 : 0.0
            var previous = 1.0
            for step in 0 ..< 80 {
                let radius = start + Double(step) * 0.025
                let coverage = shape.coverage(x: 0, y: radius, softness: 0.12)
                #expect(
                    coverage <= previous + 1e-9,
                    "\(shape.rawValue) brightens again at \(radius): \(previous) then \(coverage)"
                )
                previous = coverage
            }
        }
    }

    @Test("A given softening looks the same width on every shape")
    func softnessIsScaledPerShape() {
        // The shapes do not share a scale — a ring's measurement moves more than three times as fast
        // as a circle's, and a heart's is a squared distance. Without the per-shape correction the
        // fade would be the right width on a circle and either invisible or a smear elsewhere. This
        // checks the faded band is a similar physical width on all of them.
        for shape in ParticleShape.allCases {
            var partial = 0
            for step in 0 ..< 400 {
                let radius = Double(step) * 0.005
                let coverage = shape.coverage(x: 0, y: radius, softness: 0.1)
                if coverage > 0.02, coverage < 0.98 { partial += 1 }
            }
            let bandWidth = Double(partial) * 0.005
            #expect(
                bandWidth > 0.02 && bandWidth < 0.4,
                "\(shape.rawValue) fades over \(bandWidth), which is not in step with the others"
            )
        }
    }

    @Test("The fade width comes from the drawn size, so it is one pixel at any size")
    func softnessFollowsPixelSize() {
        // The reference implementation uses a fixed width in shape units, which makes the fade a
        // constant fraction of the body — invisible on a small one and a blur several pixels wide on
        // a large one.
        #expect(ParticleShape.softness(forPixelSize: 2) == 0.5, "a two-pixel body is nearly all edge")
        #expect(ParticleShape.softness(forPixelSize: 8) == 0.25)
        #expect(ParticleShape.softness(forPixelSize: 40) == 0.05)
        #expect(ParticleShape.softness(forPixelSize: 200) == 0.01)
        // Capped, so a one-pixel body does not ask for a fade wider than the shape.
        #expect(ParticleShape.softness(forPixelSize: 1) == 0.5)
        #expect(ParticleShape.softness(forPixelSize: 0) == 0)
        #expect(ParticleShape.softness(forPixelSize: .nan) == 0)
        #expect(ParticleShape.softness(forPixelSize: -4) == 0)
    }

    // MARK: - Saving

    @Test("A shape survives being written down and read back")
    func shapeRoundTrips() throws {
        for shape in ParticleShape.allCases {
            let bytes = try JSONEncoder().encode(shape)
            #expect(try JSONDecoder().decode(ParticleShape.self, from: bytes) == shape)
        }
    }
}
