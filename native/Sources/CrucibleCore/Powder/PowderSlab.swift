/// The powder world as a slab of cubes, for looking at through the box's camera.
///
/// ## What this is, and what it is not
///
/// It is the *same world*, drawn differently. Not a second simulation, not powder with depth: every grain is where it
/// always was, on its flat grid, and this only says where each one sits in the box and what colour to draw it. Turn the
/// box and a castle somebody built can be walked round; nothing about how it falls changes, and nothing can be built
/// from this side.
///
/// Said plainly here because the alternative reading — a 3D powder world — is the thing people will assume, and it is a
/// far larger piece of work that the notes already describe as its own (`docs/lab-ideas.md`, "Powder in 3D").
///
/// ## Why the surface only
///
/// A full grid is up to six hundred thousand cells, and the crowd the box draws has a ceiling of a million bodies — so
/// a world could be drawn whole, at a cost. But it would look like nothing: a solid block, every inside grain hidden
/// behind the ones in front of it, at the price of drawing them all. So what is offered is the shell: every grain that
/// has air on at least one side. On an ordinary world that is a tenth or so of what is there, it looks identical from
/// outside, and it is what makes turning it smooth rather than a slideshow.
///
/// The thickness is what gives it the look of a slab rather than a sheet of paper: each grain is placed at a depth
/// worked out from the grid, so the surface has a little relief and the whole thing reads as carved.
public enum PowderSlab {
    /// How the world should be laid out in the box.
    public struct Shape: Sendable, Hashable {
        /// How wide the slab is in the box's own units, taken from the world's shorter side.
        public var width: Double
        public var height: Double
        /// How thick, as a share of the width. A tenth reads as carved; nought is a sheet.
        public var thickness: Double

        public init(width: Double, height: Double, thickness: Double = 0.1) {
            self.width = max(1, width.isFinite ? width : 1)
            self.height = max(1, height.isFinite ? height : 1)
            self.thickness = max(0, min(1, thickness.isFinite ? thickness : 0.1))
        }
    }

    /// One grain to draw: where it is in the box, and what colour.
    public struct Cube: Sendable, Hashable {
        public var x: Double
        public var y: Double
        public var z: Double
        public var color: UInt32
    }

    /// How many grains a slab may hold at most. Past this the world is thinned evenly rather than partly drawn, so what
    /// is shown is the whole world at a coarser grain instead of one corner of it in full.
    public static let mostCubes = 400_000
}

extension PowderEngine {
    /// Whether a cell is on the world's surface: it holds something, and at least one of its four neighbours is air.
    ///
    /// The edges of the world count as air, so a world that reaches its own edge has a surface there too — otherwise a
    /// grid filled to the brim would have no surface at all and would be drawn as nothing.
    @inline(__always)
    func isOnSurface(_ x: Int, _ y: Int) -> Bool {
        let here = index(x, y)
        guard type[here] != Element.empty else { return false }
        if x == 0 || y == 0 || x == width - 1 || y == height - 1 { return true }
        return type[here - 1] == Element.empty
            || type[here + 1] == Element.empty
            || type[here - width] == Element.empty
            || type[here + width] == Element.empty
    }

    /// How many grains are on the surface, which is what a slab of this world would cost to draw.
    public func surfaceCellCount() -> Int {
        guard width > 2, height > 2 else { return activeParticleCount }
        var found = 0
        for y in 0 ..< height {
            for x in 0 ..< width where isOnSurface(x, y) { found += 1 }
        }
        return found
    }

    /// The world as a slab of cubes in the box: every grain with air beside it, placed and coloured.
    ///
    /// - Parameters:
    ///   - shape: how big the slab is in the box, and how thick.
    ///   - overlay: which colours to use — the same choice the flat picture offers, so a heat view carries across.
    ///   - every: draw one grain in every so many. One is all of them; two is every other, in both directions, which is
    ///     a quarter of the grains. Worked out by ``slabStride(shape:)`` unless a caller wants otherwise.
    /// - Returns: the cubes, oldest corner first, in the order the grid is walked.
    public func slabCubes(
        shape: PowderSlab.Shape,
        overlay: PowderOverlayMode = .normal,
        every stride: Int = 1
    ) -> [PowderSlab.Cube] {
        var cubes: [PowderSlab.Cube] = []
        var colours: [UInt32] = []
        let written = fillSlab(into: &cubes, shape: shape, overlay: overlay, every: stride, colours: &colours)
        return Array(cubes.prefix(written))
    }

    /// The same, written into lists the caller keeps, so that turning the box does not allocate two megabytes a frame.
    ///
    /// - Parameter colours: scratch space for the whole grid's colours, kept between frames. Grown as needed.
    /// - Returns: how many cubes were written into `cubes`. Anything past that is left over from a previous frame.
    @discardableResult
    public func fillSlab(
        into cubes: inout [PowderSlab.Cube],
        shape: PowderSlab.Shape,
        overlay: PowderOverlayMode = .normal,
        every stride: Int = 1,
        colours: inout [UInt32]
    ) -> Int {
        guard width > 0, height > 0, cellCount > 0 else { return 0 }
        let step = max(1, stride)

        // The colours come from the one renderer the flat picture uses, rather than from a second copy of the rules
        // here: a heat view, a heaviness view and a grain painted in somebody's own colour all carry across exactly,
        // and there is only ever one place where a material's colour is decided.
        if colours.count < cellCount {
            colours.append(contentsOf: repeatElement(0, count: cellCount - colours.count))
        }
        colours.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            render(into: base, overlay: overlay)
        }

        var written = 0
        func put(_ cube: PowderSlab.Cube) {
            if written < cubes.count {
                cubes[written] = cube
            } else {
                cubes.append(cube)
            }
            written += 1
        }

        // The grid laid over the slab: a cell's middle, in the box's units, with the world's shape kept.
        let acrossStep = shape.width / Double(width)
        let downStep = shape.height / Double(height)
        let deep = shape.width * shape.thickness

        var y = 0
        while y < height {
            var x = 0
            while x < width {
                if isOnSurface(x, y) {
                    let colour = colours[index(x, y)]
                    // Where in the slab's thickness this grain sits. Taken from the grid rather than from chance, so
                    // turning the box shows the same relief every time rather than a surface that crawls.
                    let ripple = Double((x &* 73 &+ y &* 149) & 7) / 7 - 0.5
                    put(PowderSlab.Cube(
                        x: (Double(x) + 0.5) * acrossStep - shape.width / 2,
                        y: (Double(y) + 0.5) * downStep - shape.height / 2,
                        z: ripple * deep,
                        color: colour
                    ))
                    if written >= PowderSlab.mostCubes { return written }
                }
                x += step
            }
            y += step
        }
        return written
    }

    /// How coarse a slab of this world has to be drawn to stay within what the box can carry.
    ///
    /// One means every grain. Two means every other grain in both directions, and so on. Worked out from how much of
    /// the world is actually on the surface rather than from its size, because a world holding a single tower and a
    /// world filled to the brim are the same size and nothing like the same cost.
    public func slabStride(limit: Int = PowderSlab.mostCubes) -> Int {
        let surface = surfaceCellCount()
        guard surface > limit, limit > 0 else { return 1 }
        // Each step of coarseness quarters what is drawn.
        var step = 1
        while surface / (step * step) > limit, step < 8 { step += 1 }
        return step
    }
}
