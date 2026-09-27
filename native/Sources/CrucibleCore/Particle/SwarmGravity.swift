/// Making every body in the swarm pull on every other.
///
/// The other switch that was wired to nothing. The field has offered **Gravity between bodies** since
/// the port, saved it with scenes, and never read it.
///
/// ## Why this cannot be done the obvious way
///
/// Every body pulling on every other means, for a hundred thousand bodies, ten thousand million pairs a
/// tick. That is not a large number to be clever about; it is a number that cannot be computed at all.
///
/// So the world is divided into a coarse grid and the mass of each square is added up. A body then feels
/// the eight squares around it one body at a time — near things matter individually — and everything
/// beyond that as a single lump sitting at its square's centre of mass. That turns ten thousand million
/// into roughly a thousand sums per body, which is affordable.
///
/// ## What that approximation actually costs
///
/// Stated plainly, because the honest version is more useful than the flattering one:
///
///   - **A distant clump is treated as a point.** For a clump whose width is a tenth of its distance the
///     error is around a percent; for one right at the edge of the near ring it is tens of percent.
///   - **That error changes suddenly** as a body crosses from one square to the next, because the near
///     ring moves with it and a clump that was being felt one body at a time becomes a lump, or the
///     reverse. The visible result is a slight shimmer in the motion. Making the squares' influence
///     fade in and out instead would smooth it, at the cost of doing both calculations in the
///     transition; the shimmer is small enough that it is not worth twice the work.
///   - **Nothing is done about the very long range.** There is one grid, not a hierarchy, so a body
///     feels the far side of the world at full one-square resolution. For a field the size of a phone
///     screen that is fine; it would not be for a simulation of a galaxy cluster.
///
/// ## Two things the reference implementation gets wrong here
///
///   - **It multiplies by the pulled body's own mass and never divides it out again**, so in its version
///     a heavy body accelerates *faster* than a light one in the same field. That is not how gravity
///     works — heavy and light fall alike, which is the single most famous fact about it. Here mass
///     appears once, on the body doing the pulling.
///   - **It lets a body be pulled by its own square's centre of mass, including its own mass**, so
///     every body is attracted to itself. The softening keeps that from exploding, but it adds a
///     spurious pull toward wherever the body already is. Here a body's own square is always felt one
///     body at a time, with itself left out.
public final class SwarmGravity {
    /// How many squares across and down the grid is.
    ///
    /// Forty by forty. Fine enough that the near ring is a small part of the world — so most pairs are
    /// approximated, which is where the saving comes from — and coarse enough that the sweep over every
    /// square is a thousand-odd sums rather than a hundred thousand.
    public static let gridColumns = 40
    /// See ``gridColumns``.
    public static let gridRows = 40

    /// Below this many bodies, every pair is worked out exactly.
    ///
    /// A thousand. The grid has a fixed cost that does not depend on the crowd — it compares every square
    /// with every other, which is about a million sums — so for a small crowd the shortcut costs more
    /// than the thing it is avoiding. A thousand bodies is a million pairs, which is the crossover.
    ///
    /// This also means every scene the field ships with, all of which place a few hundred bodies, gets
    /// the exact answer with no approximation at all.
    public static let exactBelow = 1_000

    /// Total mass in each square.
    private var cellMass: [Double] = []
    /// Where that mass is, on average.
    private var cellX: [Double] = []
    private var cellY: [Double] = []
    /// The pull each square feels from every square outside its own eight neighbours.
    ///
    /// Worked out once per square rather than once per body, which is the whole reason this is
    /// affordable. The first version of this swept all sixteen hundred squares for every single body: at
    /// ten thousand bodies that is sixteen million sums a tick, and it measured thirty-one milliseconds —
    /// three frames a second short of unusable, for a crowd the field considers small.
    ///
    /// Working it out per square instead costs about a million sums *however many bodies there are*, so
    /// the cost stops growing with the crowd. The price is that every body in a square feels the same
    /// distant pull, which is discussed under the approximation above.
    private var farX: [Double] = []
    private var farY: [Double] = []
    /// Where each square's bodies begin in ``order``, and where they end — the next square's beginning.
    private var cellStart: [Int32] = []
    /// Every body, sorted by the square it is in.
    private var order: [Int32] = []
    /// Which square each body is in, while sorting.
    private var bodyCell: [Int32] = []

    public init() {}

    /// The settings, in the field's own pixels and ticks.
    public struct Settings: Sendable, Hashable, Codable {
        /// How strong the pull is.
        public var strength: Double = 1.5
        /// How close two bodies may get before the pull stops growing, in pixels.
        ///
        /// Without this, two bodies that touch feel an unbounded pull and are flung apart at a speed
        /// that has nothing to do with anything. Eight pixels, which is a few body widths.
        public var softening: Double = 8

        public init(strength: Double = 1.5, softening: Double = 8) {
            self.strength = strength
            self.softening = softening
        }

        public static let `default` = Settings()

        var sanitized: Settings {
            Settings(
                strength: strength.isFinite ? max(0, min(40, strength)) : 1.5,
                softening: softening.isFinite ? max(1, min(200, softening)) : 8
            )
        }
    }

    /// Runs one step of the pull over a swarm, changing velocities only.
    public func step(
        swarm: Swarm,
        settings: Settings,
        width: Double,
        height: Double
    ) {
        let bodies = swarm.count
        guard bodies > 1, width > 0, height > 0 else { return }
        let tuned = settings.sanitized
        guard tuned.strength > 0 else { return }

        if bodies < Self.exactBelow {
            stepExactly(swarm: swarm, settings: tuned)
        } else {
            stepApproximately(swarm: swarm, settings: tuned, width: width, height: height)
        }
    }

    /// Every pair, worked out properly. Used for small crowds, where it is also the cheaper option.
    private func stepExactly(swarm: Swarm, settings: Settings) {
        let bodies = swarm.count
        let positions = swarm.positions
        let velocities = swarm.velocities
        let masses = swarm.masses
        let strength = settings.strength
        let softeningSquared = settings.softening * settings.softening

        for index in 0 ..< bodies {
            let pair = index * 2
            let x = Double(positions[pair])
            let y = Double(positions[pair + 1])
            guard x.isFinite, y.isFinite else { continue }

            var pullX = 0.0
            var pullY = 0.0
            for other in 0 ..< bodies where other != index {
                let otherPair = other * 2
                let dx = Double(positions[otherPair]) - x
                let dy = Double(positions[otherPair + 1]) - y
                guard dx.isFinite, dy.isFinite else { continue }
                let distanceSquared = dx * dx + dy * dy + softeningSquared
                // The weight of the body doing the pulling, and only that one. The body being pulled does
                // not enter into it, which is why heavy and light fall alike.
                let scale = strength * Double(masses[other])
                    / (distanceSquared * distanceSquared.squareRoot())
                pullX += dx * scale
                pullY += dy * scale
            }

            apply(pullX: pullX, pullY: pullY, to: velocities, at: pair)
        }
    }

    /// Near bodies one at a time, everything else as one lump per square.
    private func stepApproximately(
        swarm: Swarm,
        settings: Settings,
        width: Double,
        height: Double
    ) {
        let bodies = swarm.count
        let columns = Self.gridColumns
        let rows = Self.gridRows
        let cells = columns * rows
        let cellWidth = width / Double(columns)
        let cellHeight = height / Double(rows)

        if cellMass.count < cells {
            let extra = cells - cellMass.count
            cellMass.append(contentsOf: repeatElement(0, count: extra))
            cellX.append(contentsOf: repeatElement(0, count: extra))
            cellY.append(contentsOf: repeatElement(0, count: extra))
            farX.append(contentsOf: repeatElement(0, count: extra))
            farY.append(contentsOf: repeatElement(0, count: extra))
        }

        // The near ring is found with the general-purpose grid, sized so that one of its squares is one
        // of the mass grid's — so "the eight around me" means the same thing to both.
        // Which bodies are in each square, sorted by square, on exactly the grid the lumps are made on.
        //
        // This used to be a separate grid of *square* cells as wide as the narrower side of these. On any
        // world that is not square — which is every phone — the two did not line up: the near part looked
        // one small square either way while the far part left out one tall rectangle either way, so a band
        // above and below every body was counted by neither, and a heavy body twenty pixels away could
        // pull on nothing at all. It also silently dropped anything past the forty-eighth body in a square,
        // which gravity, pulling everything together, makes common.
        if cellStart.count < cells + 1 { cellStart = [Int32](repeating: 0, count: cells + 1) }
        if order.count < bodies { order = [Int32](repeating: 0, count: bodies) }
        if bodyCell.count < bodies { bodyCell = [Int32](repeating: 0, count: bodies) }

        let positions = swarm.positions
        let velocities = swarm.velocities
        let masses = swarm.masses
        let strength = settings.strength
        let softeningSquared = settings.softening * settings.softening
        let lastColumn = columns - 1
        let lastRow = rows - 1

        cellMass.withUnsafeMutableBufferPointer { mass in
        cellX.withUnsafeMutableBufferPointer { centreX in
        cellY.withUnsafeMutableBufferPointer { centreY in
        farX.withUnsafeMutableBufferPointer { distantX in
        farY.withUnsafeMutableBufferPointer { distantY in

            // MARK: Where the mass is

            for cell in 0 ..< cells {
                mass[cell] = 0
                centreX[cell] = 0
                centreY[cell] = 0
            }

            for index in 0 ..< bodies {
                let pair = index * 2
                let x = Double(positions[pair])
                let y = Double(positions[pair + 1])
                guard x.isFinite, y.isFinite else { continue }
                let column = JS.clampedInt(x / cellWidth, 0, lastColumn)
                let row = JS.clampedInt(y / cellHeight, 0, lastRow)
                let cell = row * columns + column
                // Weighted, so a cell holding one heavy body pulls as hard as one holding several light
                // ones — and its centre of mass sits where the weight is rather than where the count is.
                let weight = Double(masses[index])
                mass[cell] += weight
                centreX[cell] += x * weight
                centreY[cell] += y * weight
            }

            for cell in 0 ..< cells where mass[cell] > 0 {
                centreX[cell] /= mass[cell]
                centreY[cell] /= mass[cell]
            }

            cellStart.withUnsafeMutableBufferPointer { start in
            order.withUnsafeMutableBufferPointer { sorted in
            bodyCell.withUnsafeMutableBufferPointer { home in
                for cell in 0 ... cells { start[cell] = 0 }
                for index in 0 ..< bodies {
                    let pair = index * 2
                    let x = Double(positions[pair])
                    let y = Double(positions[pair + 1])
                    guard x.isFinite, y.isFinite else {
                        home[index] = -1
                        continue
                    }
                    let cell = JS.clampedInt(y / cellHeight, 0, lastRow) * columns
                        + JS.clampedInt(x / cellWidth, 0, lastColumn)
                    home[index] = Int32(cell)
                    start[cell + 1] += 1
                }
                for cell in 0 ..< cells { start[cell + 1] += start[cell] }
                var fill = [Int32](start[0 ..< cells])
                for index in 0 ..< bodies where home[index] >= 0 {
                    let cell = Int(home[index])
                    sorted[Int(fill[cell])] = Int32(index)
                    fill[cell] += 1
                }
            }
            }
            }

            // MARK: What each square feels from every distant square
            //
            // Once per square rather than once per body. This is the step that makes the whole thing
            // affordable: its cost does not depend on how many bodies there are.

            for cell in 0 ..< cells {
                distantX[cell] = 0
                distantY[cell] = 0
            }

            for row in 0 ..< rows {
                for column in 0 ..< columns {
                    let cell = row * columns + column
                    // An empty square still needs its far pull worked out — a body can sit in a square
                    // holding nothing else. Its own position for the purpose is its centre.
                    let fromX = mass[cell] > 0 ? centreX[cell] : (Double(column) + 0.5) * cellWidth
                    let fromY = mass[cell] > 0 ? centreY[cell] : (Double(row) + 0.5) * cellHeight

                    var pullX = 0.0
                    var pullY = 0.0
                    for otherRow in 0 ..< rows {
                        let rowIsNear = otherRow >= row - 1 && otherRow <= row + 1
                        let otherRowStart = otherRow * columns
                        for otherColumn in 0 ..< columns {
                            if rowIsNear, otherColumn >= column - 1, otherColumn <= column + 1 {
                                continue
                            }
                            let other = otherRowStart + otherColumn
                            let lump = mass[other]
                            guard lump > 0 else { continue }
                            let dx = centreX[other] - fromX
                            let dy = centreY[other] - fromY
                            let distanceSquared = dx * dx + dy * dy + softeningSquared
                            // Divided by the distance once for the strength and once more to turn the
                            // offset into a direction, hence the power of three halves.
                            let scale = strength * lump
                                / (distanceSquared * distanceSquared.squareRoot())
                            pullX += dx * scale
                            pullY += dy * scale
                        }
                    }
                    distantX[cell] = pullX
                    distantY[cell] = pullY
                }
            }

            // MARK: And what each body feels

            for index in 0 ..< bodies {
                let pair = index * 2
                let x = Double(positions[pair])
                let y = Double(positions[pair + 1])
                guard x.isFinite, y.isFinite else { continue }

                let column = JS.clampedInt(x / cellWidth, 0, lastColumn)
                let row = JS.clampedInt(y / cellHeight, 0, lastRow)
                var pullX = distantX[row * columns + column]
                var pullY = distantY[row * columns + column]

                // Everything close by, one body at a time. Itself left out — the reference
                // implementation leaves a body's own mass in its own square's lump, so every body there
                // is pulled toward where it already is.
                var scanRow = max(0, row - 1)
                let nearLastRow = min(lastRow, row + 1)
                let nearFirstColumn = max(0, column - 1)
                let nearLastColumn = min(lastColumn, column + 1)
                while scanRow <= nearLastRow {
                    let rowStart = scanRow * columns
                    var scanColumn = nearFirstColumn
                    while scanColumn <= nearLastColumn {
                        let cell = rowStart + scanColumn
                        var slot = Int(cellStart[cell])
                        let end = Int(cellStart[cell + 1])
                        while slot < end {
                            let other = Int(order[slot])
                            slot += 1
                            guard other != index else { continue }
                            let otherPair = other * 2
                            let dx = Double(positions[otherPair]) - x
                            let dy = Double(positions[otherPair + 1]) - y
                            let distanceSquared = dx * dx + dy * dy + softeningSquared
                            let scale = strength * Double(masses[other])
                                / (distanceSquared * distanceSquared.squareRoot())
                            pullX += dx * scale
                            pullY += dy * scale
                        }
                        scanColumn += 1
                    }
                    scanRow += 1
                }

                apply(pullX: pullX, pullY: pullY, to: velocities, at: pair)
            }
        }
        }
        }
        }
        }
    }

    /// Adds a pull to a body's velocity.
    ///
    /// Mass appears once, on the body doing the pulling, and not at all on the body being pulled — which
    /// is why heavy and light fall alike. The reference implementation multiplies by the pulled body's
    /// own mass and never divides it out, so in its version a heavy body accelerates faster in the same
    /// field.
    @inline(__always)
    private func apply(
        pullX: Double,
        pullY: Double,
        to velocities: UnsafeMutablePointer<Float>,
        at pair: Int
    ) {
        guard pullX.isFinite, pullY.isFinite else { return }
        let velX = Double(velocities[pair])
        let velY = Double(velocities[pair + 1])
        guard velX.isFinite, velY.isFinite else { return }
        velocities[pair] = JS.toFloat32(velX + pullX)
        velocities[pair + 1] = JS.toFloat32(velY + pullY)
    }
}
