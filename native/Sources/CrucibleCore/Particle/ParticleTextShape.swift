/// Turning a picture of some letters into a cloud of particles.
///
/// The last of the reference implementation's twenty-six arrangements, and the only one that could not be
/// done in the engine alone: somebody has to draw the letters first, and drawing letters needs fonts, which
/// needs the system's drawing machinery, which this engine deliberately cannot reach.
///
/// So the job is split where the seam actually is. Drawing the word into a small picture belongs to the app.
/// Deciding *which* of those pixels become bodies, and where they land in the world, is arithmetic — and it
/// is the half with all the decisions in it, so it lives here where it can be tested.
///
/// ## The decision that matters
///
/// A word rasterised at a useful size is tens of thousands of dark pixels. Turning each one into a body gives
/// a solid slab with no texture, uses the whole field on one word, and looks nothing like particles. So the
/// picture is sampled rather than copied: how many bodies are wanted decides how coarsely, and they are taken
/// on a lattice with a little jitter rather than at random.
///
/// A lattice with jitter rather than a free scatter, because a free scatter of ten thousand points over a
/// letter leaves visible clumps and holes — the eye finds them immediately and they read as the letters being
/// damaged. An even lattice alone reads as a printed halftone. Jittering a lattice gives neither.
public enum ParticleTextShape {
    /// One place a body should go, in fractions of the picture it came from.
    public struct Sample: Sendable, Hashable {
        /// Across, from nought at the left to one at the right.
        public var x: Double
        /// Down, from nought at the top to one at the bottom.
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// How dark a pixel has to be to count as part of a letter.
    ///
    /// A third. Letters drawn with smoothed edges fade out over two or three pixels, and a threshold near the
    /// top would keep only the solid middles — which thins every stroke and breaks the thin ones. A third
    /// keeps most of the smoothed edge, so the strokes come out the width they look.
    public static let defaultThreshold = 0.34

    /// Picks the places in a picture that should become bodies.
    ///
    /// - Parameters:
    ///   - coverage: How dark each pixel is, nought to one, row by row from the top left.
    ///   - width: How many pixels across.
    ///   - height: How many down.
    ///   - wanted: Roughly how many bodies to produce. The result will be close to this rather than exact,
    ///     because it comes from a lattice and a lattice cannot have any arbitrary number of points in it.
    ///   - threshold: How dark counts as part of a letter.
    ///   - random: The field's own stream, so the same word from the same seed gives the same cloud.
    public static func samples(
        coverage: [Double],
        width: Int,
        height: Int,
        wanted: Int,
        threshold: Double = defaultThreshold,
        random: inout Mulberry32
    ) -> [Sample] {
        guard width > 0, height > 0, wanted > 0, coverage.count >= width * height else { return [] }
        let cut = threshold.isFinite ? max(0.01, min(0.99, threshold)) : defaultThreshold

        // How many pixels are part of a letter at all. Needed before choosing how coarsely to sample, because
        // the answer depends entirely on how much of the picture the word actually covers — a short word in a
        // wide picture is mostly empty.
        var covered = 0
        for index in 0 ..< (width * height) {
            let value = coverage[index]
            if value.isFinite, value >= cut { covered += 1 }
        }
        guard covered > 0 else { return [] }

        // The lattice spacing that would give about the number asked for. Never below one — a lattice finer
        // than the pixels cannot find more of them, it just visits the same ones repeatedly.
        let spacing = max(1, Int((Double(covered) / Double(wanted)).squareRoot().rounded()))

        var out: [Sample] = []
        out.reserveCapacity(min(wanted * 2, covered))

        let acrossScale = 1 / Double(width)
        let downScale = 1 / Double(height)

        var row = 0
        while row < height {
            var column = 0
            while column < width {
                // Jittered within its own lattice cell, so the cloud is even without being a printed
                // halftone.
                //
                // Two draws per cell, every cell, whether or not anything is found there. Nothing about
                // *which* pixels are inked changes how far the stream moves — only how many are, through the
                // spacing worked out above. That is what lets a word be drawn and the field then carry on
                // reproducibly: no hidden early exit makes the stream position depend on the shape.
                let jitterX = random.next()
                let jitterY = random.next()
                let sampleColumn = min(width - 1, column + Int(jitterX * Double(spacing)))
                let sampleRow = min(height - 1, row + Int(jitterY * Double(spacing)))
                let value = coverage[sampleRow * width + sampleColumn]
                if value.isFinite, value >= cut {
                    out.append(Sample(
                        x: (Double(sampleColumn) + 0.5) * acrossScale,
                        y: (Double(sampleRow) + 0.5) * downScale
                    ))
                }
                column += spacing
            }
            row += spacing
        }

        // The lattice cannot land on exactly the number asked for, and it usually overshoots a little. The
        // extra have to go, and *which* extra matters: the list was built row by row from the top, so
        // dropping the tail would cut the bottom off the word. Thinned evenly across the whole list
        // instead, so what goes is a scattering from everywhere and the word stays whole.
        guard out.count > wanted else { return out }
        var thinned: [Sample] = []
        thinned.reserveCapacity(wanted)
        var carried = 0
        for sample in out {
            carried += wanted
            if carried >= out.count {
                carried -= out.count
                thinned.append(sample)
            }
        }
        return thinned
    }
}

extension ParticleEngine {
    /// Places a cloud of bodies in the shape of an already-drawn word.
    ///
    /// - Parameters:
    ///   - coverage: How dark each pixel of the drawn word is, row by row.
    ///   - width: How many pixels across the drawing is.
    ///   - height: How many down.
    ///   - count: Roughly how many bodies to place.
    ///   - fill: How much of the shorter side of the world the word should span.
    ///
    /// The word is fitted to the world by its *own* shape rather than the picture's, so a short word is not
    /// drawn tiny inside a wide empty picture. The picture is what the drawing machinery happened to produce;
    /// where the ink actually is is what somebody means by "the word".
    @discardableResult
    public func spawnTextCloud(
        coverage: [Double],
        width pictureWidth: Int,
        height pictureHeight: Int,
        count: Int = 4_000,
        fill: Double = 0.78
    ) -> Int {
        pushUndo()
        let room = max(0, maxParticles - particles.count - swarm.count)
        let wanted = min(count, room)
        guard wanted > 0 else { return 0 }

        let picked = ParticleTextShape.samples(
            coverage: coverage,
            width: pictureWidth,
            height: pictureHeight,
            wanted: wanted,
            random: &rng
        )
        guard !picked.isEmpty else { return 0 }

        // Where the ink actually is, within the picture.
        var minX = 1.0
        var maxX = 0.0
        var minY = 1.0
        var maxY = 0.0
        for sample in picked {
            minX = min(minX, sample.x)
            maxX = max(maxX, sample.x)
            minY = min(minY, sample.y)
            maxY = max(maxY, sample.y)
        }

        // In pixels, not in fractions of the picture. The picture a word is drawn into is much wider than it
        // is tall, so a fraction across and the same fraction down are nothing like the same distance —
        // fitting the fractions directly would stretch every letter sideways into the shape of the picture.
        let inkWidth = max(1e-6, (maxX - minX) * Double(pictureWidth))
        let inkHeight = max(1e-6, (maxY - minY) * Double(pictureHeight))

        // Fitted by whichever way round is tighter, so a long word fits across and a tall one fits down.
        let span = patternSpan * max(0.05, min(1, fill.isFinite ? fill : 0.78))
        let scale = min(span / inkWidth, span / inkHeight)
        let drawnWidth = inkWidth * scale
        let drawnHeight = inkHeight * scale
        let leftEdge = width * 0.5 - drawnWidth * 0.5
        let topEdge = height * 0.5 - drawnHeight * 0.5

        var placed = 0
        for sample in picked {
            let x = leftEdge + (sample.x - minX) * Double(pictureWidth) * scale
            let y = topEdge + (sample.y - minY) * Double(pictureHeight) * scale
            let acrossWord = (sample.x - minX) * Double(pictureWidth) / inkWidth
            let placedOne = swarm.append(
                x: x,
                y: y,
                // Still, so the word is readable the moment it appears. Whatever force is switched on takes
                // it apart from there, which is the point — but it has to be legible first.
                velocityX: 0,
                velocityY: 0,
                color: PackedColor(
                    hue: 190 + acrossWord * 120,
                    saturation: 0.78,
                    lightness: 0.66
                ).packedRGBA,
                budget: maxParticles - particles.count
            )
            guard placedOne else { break }
            placed += 1
        }
        return placed
    }
}
