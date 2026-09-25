/// What shape a body is drawn as.
///
/// The field drew one shape: a hard-edged disc, clipped by throwing away anything more than half a
/// unit from the centre. That is a reasonable default and a poor only option — a field of sparks, of
/// snowflakes, of confetti or of soft rings all read completely differently, and none of them can be
/// had from a circle.
///
/// ## Why the silhouettes live here and not only in the shader
///
/// Each shape is a small piece of arithmetic that answers "how far outside the shape is this point".
/// That arithmetic has to exist in the fragment shader, because that is where the pixels are. It also
/// exists here, in ordinary Swift, for two reasons that have both bitten this project before:
///
///   - Nothing in the app layer is tested, and every interface fault this project has had was found
///     by somebody looking at the screen. A silhouette is exactly the sort of thing a test can pin —
///     a ring must be hollow, a triangle must be wider at the bottom than the top, no two shapes may
///     be the same — and none of that is checkable in a shader.
///   - The reference implementation kept two copies of these functions, one per graphics backend, and
///     they drifted: its triangle and heart come out upside down on one path and the right way up on
///     the other, and one path clips every shape to a circle so its squares have rounded corners. Two
///     copies with no test between them is how that happens.
///
/// The shader mirrors what is written here, formula for formula, and says so. This file is the one to
/// change first.
///
/// ## Coordinates
///
/// A shape is described inside a square running from minus one to one on both axes, with **y pointing
/// up**. The centre of the body is the origin. Y up rather than down because two of the shapes have a
/// top and a bottom and the reference implementation gets them inverted — see above.
public enum ParticleShape: String, Sendable, Hashable, CaseIterable, Codable {
    /// A filled disc. What the field has always drawn.
    case circle
    /// A filled square.
    case square
    /// A hollow circle.
    case ring
    /// A square stood on its corner.
    case diamond
    /// A triangle with its point upward.
    case triangle
    /// A five-pointed star.
    case star
    /// A six-sided figure.
    case hexagon
    /// A cross with four equal arms.
    case plus
    /// A four-pointed sparkle: thinner arms than a cross, tapered.
    case spark
    /// A heart.
    case heart

    /// A name for the interface.
    public var displayName: String {
        switch self {
        case .circle: return "Circle"
        case .square: return "Square"
        case .ring: return "Ring"
        case .diamond: return "Diamond"
        case .triangle: return "Triangle"
        case .star: return "Star"
        case .hexagon: return "Hexagon"
        case .plus: return "Cross"
        case .spark: return "Spark"
        case .heart: return "Heart"
        }
    }

    /// The number the shader switches on.
    ///
    /// Written out rather than taken from the order of the cases, so that adding a shape or moving one
    /// cannot silently renumber the rest and start drawing hearts where the squares were.
    public var shaderIdentifier: Int32 {
        switch self {
        case .circle: return 0
        case .square: return 1
        case .ring: return 2
        case .diamond: return 3
        case .triangle: return 4
        case .star: return 5
        case .hexagon: return 6
        case .plus: return 7
        case .spark: return 8
        case .heart: return 9
        }
    }

    /// How far outside the shape a point is, and where the boundary sits.
    ///
    /// Everything is reduced to one number and one threshold, so that all ten shapes share a single
    /// piece of edge-softening rather than each inventing its own. Below the threshold is inside,
    /// above is outside, and the gap between them is what gets faded.
    public struct Metric: Sendable, Hashable {
        /// The measurement, in whatever units the shape works in.
        public var distance: Double
        /// The value of ``distance`` at the shape's edge.
        public var edge: Double
        /// How much a step of one unit in the square is worth in this shape's units.
        ///
        /// Needed because the shapes do not share a scale. A ring's measurement is multiplied by
        /// three and a third so its thin band fills the range; a heart's is a squared distance, so
        /// moving a given amount changes it by more when further from the centre. Without this, the
        /// edge softening would be the right width on a circle and either invisible or a smear on
        /// everything else.
        public var gradient: Double

        public init(distance: Double, edge: Double, gradient: Double = 1) {
            self.distance = distance
            self.edge = edge
            self.gradient = gradient
        }
    }

    /// Measures a point against the shape.
    ///
    /// - Parameters:
    ///   - x: Sideways, from minus one to one.
    ///   - y: Upward, from minus one to one.
    public func metric(x: Double, y: Double) -> Metric {
        let px = x.isFinite ? x : 0
        let py = y.isFinite ? y : 0

        switch self {
        case .circle:
            return Metric(distance: (px * px + py * py).squareRoot(), edge: 1)

        case .square:
            // The furthest of the two axes, which is a square rather than a circle because it does
            // not add them.
            return Metric(distance: max(abs(px), abs(py)), edge: 1)

        case .ring:
            // Distance from a circle of radius seven tenths, scaled so that a band three tenths wide
            // fills the whole range. The scaling is what lets one piece of edge softening serve a
            // shape whose measurement moves three and a third times as fast as the others.
            let radius = (px * px + py * py).squareRoot()
            return Metric(distance: abs(radius - 0.7) * (1 / 0.3), edge: 1, gradient: 1 / 0.3)

        case .diamond:
            // The two axes added instead of compared, which turns the square onto its corner.
            return Metric(distance: abs(px) + abs(py), edge: 1)

        case .triangle:
            // Point upward. The half-width grows from nothing at the apex to eighty-five hundredths
            // at the base, and the base is cut off flat a little above the bottom of the square so
            // the shape sits visually centred rather than hanging low.
            //
            // The reference implementation writes this with the apex at whichever end its
            // coordinates happen to put first, which is why its two drawing paths disagree about
            // which way its triangles point. Here it is stated in terms of up.
            let halfWidth = 0.85 * (1 - py) / 1.7
            return Metric(distance: max(-py - 0.72, abs(px) - halfWidth), edge: 0)

        case .star:
            // Five points, with a point at the top.
            //
            // The reference implementation does this by taking the angle of the point and folding it
            // into a fifth of a turn. That needs an inverse tangent, and this engine imports nothing —
            // not even the C maths library — so there is no inverse tangent to call. Reflections give
            // the same fold using only multiplication and addition, which is both available and
            // faster: mirroring left to right halves the circle, and two reflections about lines a
            // fifth of a turn apart fold the five points onto one another.
            //
            // What is left is a single half-spike with its tip straight up, and the answer is the
            // distance to the one straight edge running from that tip down to the neighbouring
            // valley. That makes this a true distance rather than a ratio, so the edge softening
            // needs no correction — hence a gradient of one.
            let cos36 = 0.8090169943749475
            let sin36 = 0.5877852522924731

            var qx = abs(px)
            var qy = py

            // First reflection, about the line a fifth of a turn round from upright.
            let first = qx * cos36 - qy * sin36
            if first > 0 {
                qx -= 2 * first * cos36
                qy += 2 * first * sin36
            }
            // Second reflection, about its mirror, which completes the fold.
            let second = -qx * cos36 - qy * sin36
            if second > 0 {
                qx += 2 * second * cos36
                qy += 2 * second * sin36
            }
            qx = abs(qx)

            // Measured from the tip, which sits at the top of the square.
            qy -= 1

            // The edge runs from the tip to the valley. The valley sits at thirty-eight hundredths of
            // the way out, a tenth of a turn round — the same proportion the reference uses, so the
            // star has the same stoutness.
            let edgeX = 0.38 * sin36
            let edgeY = 0.38 * cos36 - 1
            let lengthSquared = edgeX * edgeX + edgeY * edgeY
            let along = max(0, min(1, (qx * edgeX + qy * edgeY) / lengthSquared))
            let offX = qx - edgeX * along
            let offY = qy - edgeY * along
            let gap = (offX * offX + offY * offY).squareRoot()

            // Which side of the edge the point fell on. Inside is negative, so the threshold is zero.
            //
            // The sense of this was the wrong way round when first written, and the star came out as
            // its own negative — a filled square with a star-shaped hole. Worth recording because it
            // is not something reasoning catches: the fix was to draw the shape out as text and look
            // at it, which is the same way every interface fault in this project has been found.
            let side = qx * edgeY - qy * edgeX
            return Metric(distance: side > 0 ? -gap : gap, edge: 0)

        case .hexagon:
            // Two of the three axes of a hexagon; the third is the mirror of the second and comes
            // out of taking the absolute value.
            //
            // The threshold is the sine of a sixth of a turn, which is what makes the figure fit the
            // square exactly: points touching the top and bottom, flat sides just inside the left and
            // right. The reference implementation uses a round number here instead, and its hexagons
            // consequently overrun their own bounds by about two thirds and arrive with the top and
            // bottom sliced off — which is why its snowflakes are described in its own notes as
            // overshooting their nominal radius.
            let value = max(abs(px), abs(px) * 0.5 + abs(py) * 0.8660254037844386)
            return Metric(distance: value, edge: 0.8660254037844386)

        case .plus:
            // Two crossed bars. Each bar is a long thin box; taking the nearer of the two is their
            // union. Three and a fifth gives arms a little under a third of the width thick.
            let horizontal = max(3.2 * abs(px), abs(py))
            let vertical = max(3.2 * abs(py), abs(px))
            return Metric(distance: min(horizontal, vertical), edge: 1, gradient: 3.2)

        case .spark:
            // Four points with curved-in sides — the twinkle a bright thing makes, rather than a
            // cross. Adding the square roots of the two axes instead of the axes themselves is what
            // bends the sides inward: at the tips one term is everything and the other nothing, and
            // halfway between them both terms are large, so the outline is pulled in toward the
            // centre.
            //
            // The reference implementation builds this as a thin cross combined with a diamond, but
            // combines them the wrong way round — it takes the nearer of the two, which is their
            // union rather than their overlap, so what it actually draws is a plain diamond with the
            // cross entirely inside it and invisible. Reproducing that faithfully would mean shipping
            // a second diamond under a different name.
            let value = abs(px).squareRoot() + abs(py).squareRoot()
            return Metric(distance: value, edge: 1, gradient: 1.4)

        case .heart:
            // Shifted down a fifth of the square so the whole figure is centred, then the standard
            // cheap heart: a circle whose centre is pushed upward the further from the middle it is,
            // which opens the two lobes at the top and pulls the bottom into a point.
            //
            // The measurement is a squared distance rather than a distance, so its gradient is
            // reported as larger — otherwise the edge softening, tuned on a plain radius, comes out
            // about twice as wide here as everywhere else.
            //
            // The lift is half, not the reference implementation's eighteen hundredths. At that
            // value the notch between the two lobes is about two percent of the shape — invisible at
            // any size a particle is actually drawn — so what it renders is a rounded blob with a
            // point on it. Half gives a notch you can see.
            let shifted = py + 0.28
            let across = abs(px)
            let lift = shifted - 0.5 * across.squareRoot()
            return Metric(distance: across * across + lift * lift, edge: 0.62, gradient: 1.6)
        }
    }

    /// How much of a pixel the shape covers, from nought outside to one inside.
    ///
    /// - Parameters:
    ///   - x: Sideways, from minus one to one.
    ///   - y: Upward, from minus one to one.
    ///   - softness: How wide the faded edge is, in units of the square. Nought gives a hard edge.
    ///
    /// The softening is a straight ramp rather than a curve. A curve would be marginally smoother and
    /// would also need to be reproduced exactly in the shader for the two to agree; a ramp is one
    /// subtraction and a division, and at the two or three pixels a body is usually drawn the
    /// difference is not visible.
    public func coverage(x: Double, y: Double, softness: Double = 0) -> Double {
        let measured = metric(x: x, y: y)
        guard measured.distance.isFinite else { return 0 }

        // Converted from units of the square into this shape's own units, so a given softness looks
        // the same on a ring as on a circle.
        let width = softness.isFinite
            ? max(0, softness) * max(1e-6, measured.gradient)
            : 0
        guard width > 1e-9 else { return measured.distance <= measured.edge ? 1 : 0 }

        let inner = measured.edge - width
        if measured.distance <= inner { return 1 }
        if measured.distance >= measured.edge { return 0 }
        return (measured.edge - measured.distance) / width
    }

    /// How wide the faded edge should be for a body drawn this many pixels across.
    ///
    /// The square runs two units across whatever the body's size, so one pixel is two divided by that
    /// size. One pixel of fade, which is the least that removes the staircase without making a small
    /// body look like a smudge.
    ///
    /// The reference implementation uses a fixed width in shape units instead, which means the fade is
    /// a constant *fraction* of the body — so it is invisible on a small one and a soft blur several
    /// pixels wide on a large one. Getting this from the size is both simpler and right at every size.
    public static func softness(forPixelSize size: Double) -> Double {
        guard size.isFinite, size > 0 else { return 0 }
        return min(0.5, 2 / size)
    }
}
