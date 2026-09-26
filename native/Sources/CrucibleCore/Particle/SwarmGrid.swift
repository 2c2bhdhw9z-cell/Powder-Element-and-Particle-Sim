/// Finding which bodies are near which, for the passes that need neighbours.
///
/// A uniform grid: the world is cut into squares, every body is filed under the square it sits in, and
/// looking for neighbours means looking in the nine squares around a point. That is the whole idea, and
/// it is the right one here because the bodies are spread fairly evenly — a tree would pay for its
/// cleverness in pointer-chasing and win nothing.
///
/// Kept separate from the grid inside ``Swarm`` rather than shared with it, deliberately. That one is
/// tuned for pushing overlapping bodies apart: its squares are a few pixels across and it looks at no
/// more than eight candidates in each, which is right for contact and far too few for a fluid, where
/// under-counting neighbours does not merely lose accuracy — it makes the fluid read as less dense than
/// it is, so the pressure that should hold it apart never appears and the whole body of it collapses
/// into a point. The two want different settings, and the collision one is compared against a recorded
/// reference, so it is left alone.
///
/// ## The one thing to understand about the limit
///
/// A square holds at most so many bodies. Past that, further ones are **not filed** — they are still
/// simulated, and still pushed about by their neighbours, but they are invisible to everybody else's
/// search. The reference implementation this was merged from does exactly the same thing at
/// thirty-two per square and says nothing about it, which is why its fluid collapses when it gets
/// genuinely dense.
///
/// The limit cannot simply be removed: it is what stops one badly clumped square costing as much as the
/// entire rest of the frame. So it is set generously, it is reported, and ``overflowed`` says when it
/// has been hit — so the interface can say that the fluid is past what it can represent instead of
/// quietly showing the wrong thing.
final class SwarmGrid {
    /// How many bodies one square may hold.
    ///
    /// Forty-eight. A fluid whose smoothing radius is set so that a square holds about the same number
    /// of bodies as the fluid has neighbours will sit comfortably under this; a clump several times
    /// denser than intended will hit it, and that is the point at which the answer stops being
    /// meaningful anyway.
    static let bodiesPerCell = 48

    private(set) var columns = 0
    private(set) var rows = 0
    private(set) var cellSize = 1.0
    /// Whether any square filled up and turned bodies away during the last build.
    private(set) var overflowed = false

    /// How many bodies are in each square.
    private var counts: UnsafeMutablePointer<Int32>?
    /// The bodies in each square, laid out as fixed-size runs.
    ///
    /// A flat block with a fixed stride rather than linked lists. Following a chain of indices means a
    /// jump to somewhere unpredictable in memory for every step, and this pass is already limited by how
    /// fast the memory can be read; a run of neighbours sitting next to one another is read at full
    /// speed.
    private var entries: UnsafeMutablePointer<Int32>?
    private var allocatedCells = 0

    deinit {
        if let counts {
            counts.deinitialize(count: allocatedCells)
            counts.deallocate()
        }
        if let entries {
            entries.deinitialize(count: allocatedCells * Self.bodiesPerCell)
            entries.deallocate()
        }
    }

    /// Files every body under the square it sits in.
    ///
    /// - Parameter cellSize: How wide a square is. Should be the distance the caller cares about, so
    ///   that the nine squares around a point are enough — any interaction reaching further than one
    ///   square would silently miss the bodies beyond it.
    func build(
        positions: UnsafeMutablePointer<Float>,
        count: Int,
        width: Double,
        height: Double,
        cellSize requested: Double
    ) {
        overflowed = false
        guard count > 0, width > 0, height > 0 else {
            columns = 0
            rows = 0
            return
        }

        let size = max(1, requested.isFinite ? requested : 1)
        // Capped, because a very small square over a large world asks for an enormous number of them.
        // Two hundred thousand squares is about eight hundred kilobytes of counts and thirty-eight
        // megabytes of entries, which is already more than the bodies themselves.
        let wantedColumns = max(1, Int((width / size).rounded(.up)))
        let wantedRows = max(1, Int((height / size).rounded(.up)))
        if wantedColumns * wantedRows > 200_000 {
            let scale = (Double(wantedColumns * wantedRows) / 200_000).squareRoot()
            cellSize = size * scale
            columns = max(1, Int((width / cellSize).rounded(.up)))
            rows = max(1, Int((height / cellSize).rounded(.up)))
        } else {
            cellSize = size
            columns = wantedColumns
            rows = wantedRows
        }

        let cells = columns * rows
        if counts == nil || allocatedCells < cells {
            if let existing = counts {
                existing.deinitialize(count: allocatedCells)
                existing.deallocate()
            }
            if let existing = entries {
                existing.deinitialize(count: allocatedCells * Self.bodiesPerCell)
                existing.deallocate()
            }
            let freshCounts = UnsafeMutablePointer<Int32>.allocate(capacity: cells)
            freshCounts.initialize(repeating: 0, count: cells)
            let freshEntries = UnsafeMutablePointer<Int32>.allocate(
                capacity: cells * Self.bodiesPerCell
            )
            freshEntries.initialize(repeating: 0, count: cells * Self.bodiesPerCell)
            counts = freshCounts
            entries = freshEntries
            allocatedCells = cells
        }

        guard let counts, let entries else { return }
        // Only the counts need clearing. Whatever is left in the entries beyond a square's count is
        // never read, so wiping it would be work for nothing — and at thirty-eight megabytes that
        // "nothing" would be most of a frame.
        counts.update(repeating: 0, count: cells)

        let lastColumn = columns - 1
        let lastRow = rows - 1
        let inverseCell = 1 / cellSize
        for index in 0 ..< count {
            let pair = index * 2
            let x = Double(positions[pair])
            let y = Double(positions[pair + 1])
            // A body whose position has gone wrong is left out rather than filed at nought. Filing it
            // there would make it a neighbour of everything in the top-left square, and it would then
            // push real bodies about with numbers that are not numbers.
            guard x.isFinite, y.isFinite else { continue }
            let column = JS.clampedInt(x * inverseCell, 0, lastColumn)
            let row = JS.clampedInt(y * inverseCell, 0, lastRow)
            let cell = row * columns + column
            let filled = Int(counts[cell])
            if filled < Self.bodiesPerCell {
                entries[cell * Self.bodiesPerCell + filled] = Int32(index)
                counts[cell] = Int32(filled + 1)
            } else {
                overflowed = true
            }
        }
    }

    /// What a caller needs to walk the grid itself.
    ///
    /// Handed out as raw pointers rather than wrapped in a "call me for each neighbour" method,
    /// because that method was the first version of this and it was the reason the fluid cost
    /// twenty-eight milliseconds at ten thousand bodies. A closure call for every candidate — and
    /// there are of the order of a hundred per body per pass, twice a tick — is not something the
    /// compiler can remove across a file boundary, so every neighbour was paying for a function call
    /// to do two multiplications. Walking the runs directly is the same arithmetic without that.
    struct Storage {
        let counts: UnsafePointer<Int32>
        let entries: UnsafePointer<Int32>
        let columns: Int
        let rows: Int
        let cellSize: Double
        /// How many slots each square's run occupies, whether or not they are used.
        let stride: Int

        /// Which square a point falls in, clamped to the grid.
        @inline(__always)
        func cell(atX x: Double, y: Double) -> (column: Int, row: Int) {
            let inverse = 1 / cellSize
            return (
                JS.clampedInt(x * inverse, 0, columns - 1),
                JS.clampedInt(y * inverse, 0, rows - 1)
            )
        }
    }

    /// The grid's storage, or nothing when it holds no squares.
    func storage() -> Storage? {
        guard let counts, let entries, columns > 0, rows > 0 else { return nil }
        return Storage(
            counts: UnsafePointer(counts),
            entries: UnsafePointer(entries),
            columns: columns,
            rows: rows,
            cellSize: cellSize,
            stride: Self.bodiesPerCell
        )
    }
}
