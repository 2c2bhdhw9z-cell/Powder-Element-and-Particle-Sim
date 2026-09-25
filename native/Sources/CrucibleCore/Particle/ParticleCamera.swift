/// Where the field is being looked at from.
///
/// Until now there was nowhere to look from: world coordinates went straight to screen coordinates
/// with a flip, and the world *was* the screen. So a galaxy could only ever be the size of the phone,
/// and there was no way to lean in on a single knot of bodies or to tip the plane over and see it as
/// a disc rather than a circle.
///
/// This is a camera over a flat plane. Five numbers — zoom, two of pan, and two angles — plus an
/// automatic spin. The projection is taken from the reference particle sandbox (`HELION-MERGE.md`,
/// slice A) and is worth describing properly, because it is not what it first looks like:
///
///   - It is **not** a rotation of the picture. The plane the bodies live on is genuinely turned in
///     space and then divided through by depth, so a body on the near side of the plane draws bigger
///     than one on the far side, and a ring of bodies becomes a proper ellipse rather than a squashed
///     circle.
///   - It is **not** a full three-dimensional pipeline either. There is one plane, at depth nought,
///     and no depth buffer — so nothing occludes anything. That is deliberate: tens of thousands of
///     translucent points look better added together than sorted.
///   - At no rotation it is **exactly** the identity, by an explicit early exit, so leaving the
///     camera alone leaves the picture bit-for-bit as it was before this existed.
///
/// Everything here is arithmetic. It compiles and is tested on any machine, and the drawing code and
/// the touch handling both go through it, so the place a finger lands is the place a body is drawn.
public struct ParticleCamera: Sendable, Hashable, Codable {
    // MARK: - Limits

    /// How far out the view can be pulled.
    ///
    /// A quarter, rather than the reference implementation's four tenths. Its world was a fixed shape
    /// on a desktop monitor; here the world is the phone's own screen, so pulling out further is the
    /// only way to see a scene whole.
    public static let minimumZoom = 0.25
    /// How far in the view can be pushed.
    ///
    /// Twelve, rather than the reference implementation's eight, for the matching reason: bodies here
    /// are drawn a couple of points across, and looking at one closely means more than eight times.
    public static let maximumZoom = 12.0
    /// How far the plane can be tipped, in degrees. Level, up to just past a very shallow angle.
    ///
    /// Stopping at seventy-two rather than ninety because at ninety the plane is edge-on: every body
    /// collapses onto one line and the field vanishes. Seventy-two still reads as nearly edge-on
    /// without ever reaching the degenerate case.
    public static let maximumPitch = 72.0

    /// How far the eye sits from the plane, in the same units the projection works in.
    ///
    /// This is the only number that decides how strong the perspective is. Larger would flatten it
    /// toward a plain squash; smaller would exaggerate it until the near edge ballooned.
    public static let eyeDistance = 2.4

    /// How close to the eye the maths is allowed to get before it stops dividing.
    ///
    /// Without this, a body that lands exactly at the eye divides by nothing and the whole frame
    /// fills with one enormous quad. With it the worst case is a body drawn twelve times its size,
    /// which looks odd for a moment and then passes.
    public static let nearLimit = 0.2

    /// How much bigger or smaller depth is allowed to make a body.
    ///
    /// The reference implementation clamped this on the graphics card and not on the processor, so
    /// its own two drawing paths disagreed about how big a tilted body was. One rule, here.
    public static let minimumDepthScale = 0.35
    /// See ``minimumDepthScale``.
    public static let maximumDepthScale = 2.8

    /// How fast the automatic spin turns, in degrees a second.
    public static let autoOrbitDegreesPerSecond = 18.0

    // MARK: - State

    /// How far in the view is pushed. One is the whole world filling the screen.
    public var zoom: Double
    /// Sideways shift, in screen points.
    public var panX: Double
    /// Vertical shift, in screen points.
    public var panY: Double
    /// Turn about the upright axis, in degrees.
    public var yaw: Double
    /// Tip toward the viewer, in degrees. Nought is looking straight down at the plane.
    public var pitch: Double
    /// Whether zooming out makes the world larger instead of making the picture smaller.
    ///
    /// On by default, because it is what somebody means by zooming out. With it off, pulling back shrinks
    /// the whole field into the middle of the screen and leaves black all round it — which is technically a
    /// zoom and is useless: the same scene, smaller, with nothing gained. With it on, the screen stays
    /// full and the freed room becomes *real simulation space*, so the crowd has somewhere to go and the
    /// scene can grow into it.
    ///
    /// Only below one. Zooming *in* is always a magnification — there is no sense in which looking closely
    /// at something should shrink the world it lives in.
    public var growsWorldWhenZoomedOut: Bool = true
    /// Whether the view turns by itself.
    public var autoOrbit: Bool
    /// How far the automatic spin has turned so far, in degrees.
    ///
    /// Held apart from ``yaw`` on purpose. The reference implementation wrote the spin straight into
    /// the same field the slider used, so turning the spin on made the slider jump and then fight it —
    /// dragging the slider did nothing, because the next frame overwrote it. Kept separate, the spin
    /// adds to whatever the slider says and both work.
    public var autoOrbitAngle: Double

    public init(
        zoom: Double = 1,
        panX: Double = 0,
        panY: Double = 0,
        yaw: Double = 0,
        pitch: Double = 0,
        growsWorldWhenZoomedOut: Bool = true,
        autoOrbit: Bool = false,
        autoOrbitAngle: Double = 0
    ) {
        self.growsWorldWhenZoomedOut = growsWorldWhenZoomedOut
        self.zoom = Self.clampZoom(zoom)
        self.panX = Self.usable(panX)
        self.panY = Self.usable(panY)
        self.yaw = Self.wrapDegrees(yaw)
        self.pitch = Self.clampPitch(pitch)
        self.autoOrbit = autoOrbit
        self.autoOrbitAngle = Self.wrapDegrees(autoOrbitAngle)
    }

    /// Looking straight down at the whole world, centred.
    public static let identity = ParticleCamera()

    /// Whether the camera is doing nothing at all, so the drawing path can take its fast route.
    public var isIdentity: Bool {
        zoom == 1 && panX == 0 && panY == 0 && !isRotated
    }

    /// How many times larger the world is than the view.
    ///
    /// One at rest and when zoomed in. Zoomed out with world growth on, it is one over the zoom — so at a
    /// quarter zoom the world is four times as wide and four times as tall, which is sixteen times the room.
    public var worldScale: Double {
        guard growsWorldWhenZoomedOut, zoom < 1 else { return 1 }
        return 1 / max(Self.minimumZoom, zoom)
    }

    /// How much the picture itself is scaled.
    ///
    /// This is what the drawing uses, and it is *not* the zoom. When zooming out grows the world instead,
    /// the picture stays at its true size — the bodies do not get smaller, there are simply more of the
    /// world's units on screen. Pinned to one in that case; equal to the zoom otherwise.
    public var pictureScale: Double {
        guard growsWorldWhenZoomedOut, zoom < 1 else { return zoom }
        return 1
    }

    /// Whether the plane is turned or tipped.
    public var isRotated: Bool {
        abs(effectiveYaw) > 1e-9 || abs(pitch) > 1e-9
    }

    /// The turn actually applied: the slider plus however far the automatic spin has got.
    public var effectiveYaw: Double {
        Self.wrapDegrees(yaw + autoOrbitAngle)
    }

    // MARK: - Keeping the numbers sane

    static func usable(_ value: Double) -> Double { value.isFinite ? value : 0 }

    static func clampZoom(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return max(minimumZoom, min(maximumZoom, value))
    }

    /// Public because the tilt slider hands over whatever the finger produced, and the same rule has to
    /// apply there as everywhere else — a limit enforced in some places and not others is not a limit.
    public static func clampPitch(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return max(0, min(maximumPitch, value))
    }

    /// Brings an angle into the half-open range from minus one hundred and eighty.
    ///
    /// Wrapped rather than clamped, because turning is endless: a spin that stopped dead at a
    /// boundary would be a camera that jams after half a revolution.
    static func wrapDegrees(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let wrapped = (value + 180).truncatingRemainder(dividingBy: 360)
        return (wrapped < 0 ? wrapped + 360 : wrapped) - 180
    }

    /// Degrees into radians. Public because the drawing code needs the same conversion.
    public static func radians(_ degrees: Double) -> Double { degrees * 3.141592653589793 / 180 }

    // MARK: - Moving it

    /// Multiplies the zoom, the way a pinch does. Clamped, never wrapped.
    public mutating func zoom(by factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        zoom = Self.clampZoom(zoom * factor)
    }

    /// Shifts the view by a distance in screen points.
    public mutating func pan(byX dx: Double, y dy: Double) {
        guard dx.isFinite, dy.isFinite else { return }
        panX += dx
        panY += dy
    }

    /// Turns and tips the view by an amount in degrees.
    public mutating func rotate(byYaw dyaw: Double, pitch dpitch: Double) {
        yaw = Self.wrapDegrees(yaw + Self.usable(dyaw))
        pitch = Self.clampPitch(pitch + Self.usable(dpitch))
    }

    /// Advances the automatic spin.
    ///
    /// - Parameter seconds: Time since the last frame. Clamped, so a frame that took a quarter of a
    ///   second after the app came back from the background does not jump the view a long way round.
    public mutating func advance(bySeconds seconds: Double) {
        guard autoOrbit, seconds.isFinite, seconds > 0 else { return }
        let step = min(0.1, seconds) * Self.autoOrbitDegreesPerSecond
        autoOrbitAngle = Self.wrapDegrees(autoOrbitAngle + step)
    }

    /// Back to looking straight down at the whole world.
    ///
    /// The automatic spin is left switched on if it was on, but its accumulated angle is cleared —
    /// otherwise "reset the view" would leave the field at whatever angle the spin happened to have
    /// reached, which is not a reset.
    public mutating func reset() {
        // The growth setting is left alone. It is a choice about what zooming out *means*, not a position
        // the view happens to be in, so resetting the view should not silently change it back.
        zoom = 1
        panX = 0
        panY = 0
        yaw = 0
        pitch = 0
        autoOrbitAngle = 0
    }

    // MARK: - The projection

    /// A point on the plane, after being turned, tipped and divided through by depth.
    public struct Projected: Sendable, Hashable {
        /// Sideways, from minus one at the left edge to one at the right.
        public var x: Double
        /// Upward, from minus one at the bottom to one at the top.
        public var y: Double
        /// How much depth changes the size of anything drawn here. One is unchanged.
        public var depthScale: Double

        public init(x: Double, y: Double, depthScale: Double) {
            self.x = x
            self.y = y
            self.depthScale = depthScale
        }
    }

    /// Turns a position in the world into a position on the screen.
    ///
    /// The world is measured in the same units the field uses — the top left corner is nought,
    /// nought, and y increases downward. The result runs from minus one to one on both axes, with y
    /// increasing upward, which is what the drawing code wants.
    ///
    /// Zoom and pan are applied after the turn, not before. Before, and zooming in would also swing
    /// the view round, because the turn happens about the middle of the world rather than about the
    /// middle of what is on screen.
    public func project(
        x: Double,
        y: Double,
        worldWidth: Double,
        worldHeight: Double,
        viewWidth: Double,
        viewHeight: Double
    ) -> Projected {
        let w = max(1e-6, worldWidth)
        let h = max(1e-6, worldHeight)
        let plain = Projected(
            x: (Self.usable(x) / w) * 2 - 1,
            y: 1 - (Self.usable(y) / h) * 2,
            depthScale: 1
        )

        let turned = Self.turn(plain, yaw: effectiveYaw, pitch: pitch)
        // The picture scale, not the zoom. When zooming out grows the world instead of shrinking the
        // picture, the two are different numbers and using the wrong one would shrink the bodies *and*
        // enlarge the world, which cancels out into no visible change at all.
        let scale = pictureScale
        return Projected(
            x: turned.x * scale + Self.panToScreenFraction(panX, across: viewWidth),
            // Pan down the screen has to become pan down the *picture*, and the picture's y runs the
            // other way — so this subtracts where the x above adds.
            y: turned.y * scale - Self.panToScreenFraction(panY, across: viewHeight),
            depthScale: turned.depthScale
        )
    }

    /// Turns and tips a point already in screen-fraction coordinates.
    ///
    /// Split out because the corners of a box are projected the same way when working out how far to
    /// zoom to fit something, and because it is the part worth reading on its own.
    static func turn(_ point: Projected, yaw: Double, pitch: Double) -> Projected {
        // Exactly the identity when nothing is turned. Not an optimisation — a guarantee, so that a
        // field with the camera untouched draws precisely as it did before the camera existed.
        guard abs(yaw) > 1e-9 || abs(pitch) > 1e-9 else { return point }

        let yawRadians = radians(yaw)
        let pitchRadians = radians(pitch)
        let cosYaw = jsCos(yawRadians)
        let sinYaw = jsSin(yawRadians)
        let cosPitch = jsCos(pitchRadians)
        let sinPitch = jsSin(pitchRadians)

        // Turn about the upright axis. The plane sits at depth nought, so only sideways position
        // feeds depth.
        let x1 = point.x * cosYaw
        let z1 = -point.x * sinYaw

        // Then tip about the sideways axis.
        let y2 = point.y * cosPitch - z1 * sinPitch
        let z2 = point.y * sinPitch + z1 * cosPitch

        // And divide through by how far away it ended up.
        let depth = max(nearLimit, eyeDistance - z2)
        let perspective = eyeDistance / depth
        return Projected(x: x1 * perspective, y: y2 * perspective, depthScale: perspective)
    }

    /// Converts a pan in screen points into the fraction of the screen it represents.
    ///
    /// Half the view, because the coordinates the drawing works in run from minus one to one — two
    /// units across a whole screen.
    static func panToScreenFraction(_ points: Double, across view: Double) -> Double {
        guard view > 1e-6 else { return 0 }
        return usable(points) / (view * 0.5)
    }

    /// How much bigger or smaller to draw something at a given depth.
    public func drawScale(depthScale: Double) -> Double {
        let clamped = depthScale.isFinite
            ? max(Self.minimumDepthScale, min(Self.maximumDepthScale, depthScale))
            : 1
        return pictureScale * clamped
    }

    // MARK: - Going back the other way

    /// Turns a place on the screen back into a place in the world.
    ///
    /// This is what a finger needs. Without it, tilting the view would mean the brush no longer
    /// appeared under the touch — and a tool that lands somewhere other than where it was aimed is
    /// worse than one that cannot be aimed at all.
    ///
    /// Untilted this is exact. Tilted it is very close but not exact: undoing the turn needs a term
    /// that the forward direction folds away, and recovering it would mean solving a quadratic for
    /// every touch. The error is a fraction of a point on screen, far below what a fingertip
    /// resolves, and it is stated here rather than left to be discovered.
    public func unproject(
        screenX: Double,
        screenY: Double,
        worldWidth: Double,
        worldHeight: Double,
        viewWidth: Double,
        viewHeight: Double
    ) -> (x: Double, y: Double) {
        let w = max(1e-6, worldWidth)
        let h = max(1e-6, worldHeight)
        let vw = max(1e-6, viewWidth)
        let vh = max(1e-6, viewHeight)

        // Screen points to the range minus one through one, y upward.
        var nx = (Self.usable(screenX) / vw) * 2 - 1
        var ny = 1 - (Self.usable(screenY) / vh) * 2

        // Undo the pan and the zoom, in the reverse of the order they were applied.
        let scale = max(1e-6, pictureScale)
        nx = (nx - Self.panToScreenFraction(panX, across: vw)) / scale
        ny = (ny + Self.panToScreenFraction(panY, across: vh)) / scale

        let flat = Self.untilt(x: nx, y: ny, yaw: effectiveYaw, pitch: pitch)

        return (
            x: ((flat.x + 1) * 0.5) * w,
            y: ((1 - flat.y) * 0.5) * h
        )
    }

    /// Undoes the turn and the tip.
    static func untilt(x: Double, y: Double, yaw: Double, pitch: Double) -> (x: Double, y: Double) {
        guard abs(yaw) > 1e-9 || abs(pitch) > 1e-9 else { return (x, y) }

        let yawRadians = radians(yaw)
        let pitchRadians = radians(pitch)
        let cosYaw = jsCos(yawRadians)
        let sinYaw = jsSin(yawRadians)
        let cosPitch = jsCos(pitchRadians)
        let sinPitch = jsSin(pitchRadians)

        // Find how far along the ray from the eye the plane was hit, then walk back up the same
        // rotations in reverse.
        let denominator = eyeDistance * cosPitch * cosYaw - x * sinYaw + y * sinPitch * cosYaw
        let safe = abs(denominator) < 1e-6 ? (denominator < 0 ? -1e-6 : 1e-6) : denominator
        let along = (eyeDistance * cosPitch * cosYaw) / safe

        let x2 = along * x
        let y2 = along * y
        let z2 = eyeDistance * (1 - along)

        let y1 = y2 * cosPitch + z2 * sinPitch
        let z1 = -y2 * sinPitch + z2 * cosPitch

        return (x: x2 * cosYaw - z1 * sinYaw, y: y1)
    }
}

// MARK: - Framing what is there

/// The extent of what is actually in the field, for fitting the view around it.
public struct ParticleFraming: Sendable, Hashable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double
    /// How many bodies were counted. Nought means there was nothing to frame.
    public var bodyCount: Int

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double, bodyCount: Int) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
        self.bodyCount = bodyCount
    }

    public var isEmpty: Bool { bodyCount == 0 }
    public var centreX: Double { (minX + maxX) * 0.5 }
    public var centreY: Double { (minY + maxY) * 0.5 }
    public var width: Double { max(0, maxX - minX) }
    public var height: Double { max(0, maxY - minY) }
}

extension ParticleCamera {
    /// How many bins the framing histogram uses on each axis.
    ///
    /// Two hundred and fifty-six, so the answer is accurate to a few tenths of a percent of the
    /// world — well under what anybody notices in a framing — and so the whole thing is one pass over
    /// the bodies with no sorting and no allocation that depends on how many there are.
    static let framingBins = 256

    /// How much of the crowd, at each end, a framing is allowed to leave outside.
    ///
    /// Half a percent from each end. Without this, one body flung out of a supernova frames the whole
    /// scene around itself and everything else becomes a dot in the middle — which is exactly what
    /// "fit to what is there" must not do. The reference implementation has no fitting at all, so
    /// this is not a port; it is the thing its absence was the reason for.
    public static let framingTrimFraction = 0.005

    /// Works out the extent of the bodies in the field, ignoring the wildest few.
    ///
    /// Positions come in as pairs, the way both stores hold them. Anything that is not a usable
    /// number is skipped rather than counted at zero: a corrupt body would otherwise drag the frame
    /// out to the corner of the world and the picture would appear to be nowhere.
    public static func framing(
        positions: UnsafePointer<Float>,
        count: Int,
        worldWidth: Double,
        worldHeight: Double,
        trim: Double = framingTrimFraction
    ) -> ParticleFraming {
        guard count > 0, worldWidth > 0, worldHeight > 0 else {
            return ParticleFraming(minX: 0, minY: 0, maxX: 0, maxY: 0, bodyCount: 0)
        }

        var columns = [Int32](repeating: 0, count: framingBins)
        var rows = [Int32](repeating: 0, count: framingBins)
        var counted = 0
        let lastBin = framingBins - 1
        let xScale = Double(framingBins) / worldWidth
        let yScale = Double(framingBins) / worldHeight

        for index in 0 ..< count {
            let pair = index * 2
            let x = Double(positions[pair])
            let y = Double(positions[pair + 1])
            guard x.isFinite, y.isFinite else { continue }
            columns[max(0, min(lastBin, Int(x * xScale)))] += 1
            rows[max(0, min(lastBin, Int(y * yScale)))] += 1
            counted += 1
        }

        guard counted > 0 else {
            return ParticleFraming(minX: 0, minY: 0, maxX: 0, maxY: 0, bodyCount: 0)
        }

        // How many to leave outside at each end. At least none, and never so many that the two ends
        // meet in the middle and the frame collapses.
        let trimFraction = trim.isFinite ? max(0, min(0.25, trim)) : framingTrimFraction
        let skip = Int(Double(counted) * trimFraction)

        let xRange = Self.occupiedRange(bins: columns, total: counted, skip: skip)
        let yRange = Self.occupiedRange(bins: rows, total: counted, skip: skip)

        // Bins are ranges, so the low end takes the bin's start and the high end its finish.
        let binWidth = worldWidth / Double(framingBins)
        let binHeight = worldHeight / Double(framingBins)
        return ParticleFraming(
            minX: Double(xRange.low) * binWidth,
            minY: Double(yRange.low) * binHeight,
            maxX: Double(xRange.high + 1) * binWidth,
            maxY: Double(yRange.high + 1) * binHeight,
            bodyCount: counted
        )
    }

    /// Finds the first and last bin worth including, having discarded `skip` from each end.
    static func occupiedRange(bins: [Int32], total: Int, skip: Int) -> (low: Int, high: Int) {
        var low = 0
        var running = 0
        for index in 0 ..< bins.count {
            running += Int(bins[index])
            if running > skip {
                low = index
                break
            }
        }

        var high = bins.count - 1
        running = 0
        for index in stride(from: bins.count - 1, through: 0, by: -1) {
            running += Int(bins[index])
            if running > skip {
                high = index
                break
            }
        }

        // Discarding from both ends of a small crowd can cross the two over. One bin is the honest
        // answer there: everything is in nearly the same place.
        if high < low { return (low: low, high: low) }
        return (low: low, high: high)
    }

    /// How much of the screen a fitted frame leaves as a margin.
    ///
    /// Eight percent. A frame drawn exactly to the edges has bodies half-clipped all the way round
    /// and reads as though the view is slightly too small, which is the opposite of what fitting is
    /// supposed to feel like.
    public static let fitMargin = 0.08

    /// Zooms and shifts the view so that everything in `framing` is on screen.
    ///
    /// The turn and the tip are left as they are, and the fit is computed *through* them — the four
    /// corners of the frame are projected and the view is fitted around where they land. That works
    /// because the projection maps a flat quadrilateral to a flat quadrilateral, so its corners are
    /// enough. Resetting the angles instead would be easier and would also mean "fit" quietly
    /// destroyed a tilt somebody had set up.
    public mutating func fit(
        to framing: ParticleFraming,
        worldWidth: Double,
        worldHeight: Double,
        viewWidth: Double,
        viewHeight: Double,
        margin: Double = fitMargin
    ) {
        guard !framing.isEmpty, worldWidth > 0, worldHeight > 0, viewWidth > 0, viewHeight > 0 else {
            return
        }

        // Projected with the zoom and pan taken out, so what comes back is the shape of the content
        // in the turned view rather than the shape of the view we already have.
        var flat = self
        flat.zoom = 1
        flat.panX = 0
        flat.panY = 0

        let corners = [
            (framing.minX, framing.minY),
            (framing.maxX, framing.minY),
            (framing.minX, framing.maxY),
            (framing.maxX, framing.maxY),
        ].map { corner in
            flat.project(
                x: corner.0,
                y: corner.1,
                worldWidth: worldWidth,
                worldHeight: worldHeight,
                viewWidth: viewWidth,
                viewHeight: viewHeight
            )
        }

        let lowX = corners.map(\.x).min() ?? -1
        let highX = corners.map(\.x).max() ?? 1
        let lowY = corners.map(\.y).min() ?? -1
        let highY = corners.map(\.y).max() ?? 1

        let spanX = max(1e-6, highX - lowX)
        let spanY = max(1e-6, highY - lowY)
        let usableMargin = margin.isFinite ? max(0, min(0.4, margin)) : Self.fitMargin
        let room = 1 - usableMargin

        // The screen is two units across and two tall, so fitting a span means dividing two by it.
        // The smaller of the two, so both axes fit rather than one overflowing.
        zoom = Self.clampZoom(min(2 / spanX, 2 / spanY) * room)

        // And centre it. The middle of the projected content, moved to the middle of the screen, in
        // screen points — which is the reverse of what `project` does with the pan.
        let middleX = (lowX + highX) * 0.5
        let middleY = (lowY + highY) * 0.5
        panX = -middleX * zoom * (viewWidth * 0.5)
        panY = middleY * zoom * (viewHeight * 0.5)
    }
}
