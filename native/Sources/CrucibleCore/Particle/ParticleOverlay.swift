// The trails behind bodies, and the ring round your finger.
//
// Ported from the drawing half of web/src/sim/particle/render.ts.
//
// ## Why the decisions are here and the drawing is not
//
// These cannot be compared pixel for pixel the way every other renderer in this port has been. The
// web version draws them with the browser's 2D canvas, whose antialiasing, line joins and end caps
// are not specified anywhere and differ between browsers — so a recorded picture would prove
// nothing except that one rasteriser agrees with itself.
//
// What *can* be pinned down is every decision that goes into them: which colour, how transparent,
// how wide, how long a trail is allowed to get, and the rule that decides how big the ring is. Those
// are the things a porting error would get wrong. They live here, with tests; the app turns them
// into geometry and Metal draws it.

extension ParticleEngine {
    /// Above this many bodies the web version stops drawing shapes and writes single pixels, which
    /// means no trails and no springs.
    ///
    /// Recorded because it is where the reference implementation's appearance changes, not because
    /// the native renderer needs it — Metal draws geometry at any count.
    public static let trailDrawingLimit = 1000
}

/// How the extras over the field are drawn.
///
/// Every figure is the reference implementation's.
public enum ParticleOverlayStyle {
    // MARK: Trails

    /// How transparent a trail is.
    ///
    /// One flat value along the whole length, not a taper. A taper would look better and would not
    /// be what the reference does.
    public static let trailOpacity = 0.3

    /// A trail's thickness, as a share of the body's own width.
    public static let trailWidthScale = 0.8

    /// The most positions a body remembers.
    ///
    /// Six is short — a trail is a hint of direction rather than a streak. The reference gets its
    /// longer smear from fading the previous frame instead of from a longer history.
    public static let trailLength = 6

    /// How much of the previous frame survives when trails are on.
    ///
    /// This is the part that actually makes a trail look like motion: rather than clearing the
    /// picture, the reference paints the background over it at a quarter opacity, so what was there
    /// fades out over several frames. A trail is therefore longer than the six positions a body
    /// remembers.
    public static let frameFadeOpacity = 0.25

    /// A body's thickness for trail purposes.
    ///
    /// Bodies with no size of their own fall back to the field's default, which is what the
    /// reference's `p.radius || e.particleSize` does — and note that a radius of exactly zero takes
    /// the fallback there too, because zero is falsy in JavaScript. Reproduced deliberately.
    public static func trailWidth(bodyRadius: Double, defaultSize: Double) -> Double {
        let radius = bodyRadius != 0 ? bodyRadius : defaultSize
        return radius * trailWidthScale
    }

    // MARK: The touch ring

    /// The ring's colour. A cyan that appears nowhere else, so it reads as your own doing rather
    /// than as part of the simulation.
    public static let ringColor = PackedColor(r: 34, g: 211, b: 238)
    /// How solid the outline is.
    public static let ringStrokeOpacity = 0.85
    /// How solid the wash inside it is.
    public static let ringFillOpacity = 0.12
    /// The outline's thickness, in pixels.
    public static let ringStrokeWidth = 2.0
    /// The dot marking the exact centre.
    public static let ringCentreDotRadius = 3.0

    /// How big the ring should be drawn.
    ///
    /// The point of this is honesty. With the reach set to the whole field every body is pulled, however far
    /// away, and drawing any circle would say the opposite — that there is a boundary and things outside it
    /// are safe. So then the ring is drawn large enough to cover the whole world.
    ///
    /// The whole field is an infinite reach, stated outright. It used to be any reach of eight hundred pixels
    /// or more, which on a phone's screen is only a third of the way across — so a reach that merely looked
    /// large quietly became the whole field.
    ///
    /// - Parameters:
    ///   - reach: the finger's reach the physics is using.
    ///   - worldWidth: the field's width.
    ///   - worldHeight: the field's height.
    public static func ringRadius(reach: Double, worldWidth: Double, worldHeight: Double) -> Double {
        guard isUnlimited(reach: reach) else { return max(0, reach) }
        // The diagonal, so the circle covers every corner from wherever the finger is.
        return (worldWidth * worldWidth + worldHeight * worldHeight).squareRoot()
    }

    /// Whether the reach is unlimited, for anything that wants to say so in words.
    public static func isUnlimited(reach: Double) -> Bool {
        reach == .infinity
    }
}
