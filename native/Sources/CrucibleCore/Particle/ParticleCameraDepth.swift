/// Looking at the field in 3D.
///
/// ## What this is
///
/// A view that goes round the box. The box is turned about the upright through its middle — ``orbitYaw`` —
/// and then tipped toward or away from the viewer — ``orbitPitch`` — and then seen from an eye some way in
/// front of it, so what is nearer is drawn larger and further apart than what is further away. That last part
/// is the perspective, and it has a strength: at nought there is none, and the box is drawn as a plan.
///
/// Zoom and pan work exactly as they do on a flat field, and so does zooming out to add room: the world grows,
/// the box with it, and everything in it is drawn smaller.
///
/// ## Why it is written twice
///
/// The graphics card places every body with the same arithmetic in `FieldShaders.metal`, and the finger has to
/// land where the body is drawn — so the two must agree number for number. This is the copy that can be
/// tested: a place projected here and a finger put where it lands have to come back along the same line.
public struct ParticleDepthProjection: Sendable, Hashable {
    /// Across the screen, from minus one at the left edge to one at the right.
    public var x: Double
    /// Up the screen, from minus one at the bottom to one at the top.
    public var y: Double
    /// How much bigger or smaller the perspective draws something here. One at the middle of the box.
    public var scale: Double
    /// How far away it is, from nought for the nearest anything in the box can be to one for the furthest.
    public var depth: Double
    /// Whether it is in front of the eye at all. Something behind it is not drawn.
    public var isInFront: Bool
}

/// The extent of what is in a field with depth, for fitting the view round it.
public struct ParticleDepthFraming: Sendable, Hashable {
    public var minX: Double
    public var maxX: Double
    public var minY: Double
    public var maxY: Double
    public var minZ: Double
    public var maxZ: Double
    public var bodyCount: Int

    public init(minX: Double, maxX: Double, minY: Double, maxY: Double, minZ: Double, maxZ: Double, bodyCount: Int) {
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
        self.minZ = minZ
        self.maxZ = maxZ
        self.bodyCount = bodyCount
    }

    public var isEmpty: Bool { bodyCount == 0 }

    /// The eight corners.
    public var corners: [(x: Double, y: Double, z: Double)] {
        var all: [(x: Double, y: Double, z: Double)] = []
        for x in [minX, maxX] {
            for y in [minY, maxY] {
                for z in [minZ, maxZ] { all.append((x, y, z)) }
            }
        }
        return all
    }
}

extension ParticleCamera {
    /// How close to the eye something may be before it is not drawn, as a share of the eye's distance.
    public static let depthNearLimit = 0.15
    /// The largest and smallest the perspective may draw anything, so a body right at the eye does not fill the
    /// screen and one at the far end of a long box does not vanish.
    public static let depthScaleRange: ClosedRange<Double> = 0.2 ... 5

    /// The turn round the box actually applied: the setting plus however far the automatic spin has got.
    public var effectiveOrbitYaw: Double {
        Self.wrapDegrees(orbitYaw + autoOrbitAngle)
    }

    /// How far the eye is from the middle of the box, in the world's pixels, or nothing when there is no
    /// perspective.
    ///
    /// Measured against the world's height, so the perspective looks the same whatever the screen and however
    /// far the view has been pulled out. At full strength the eye is a world's height away; at a tenth, ten.
    public func eyeDistance(worldHeight: Double) -> Double? {
        guard perspective > 0.001, worldHeight > 0 else { return nil }
        return min(40, 2 / perspective) * worldHeight * 0.5
    }

    /// Half the diagonal of the box: nothing in it is further from its middle than this.
    public static func depthRadius(worldWidth: Double, worldHeight: Double, worldDepth: Double) -> Double {
        max(1, (worldWidth * worldWidth + worldHeight * worldHeight + worldDepth * worldDepth).squareRoot() * 0.5)
    }

    /// Where a place is once the box has been turned and tipped: across, up, and away from the viewer, each
    /// measured from the middle of the box.
    public func viewSpace(x: Double, y: Double, z: Double, worldWidth: Double, worldHeight: Double) -> (u: Double, v: Double, w: Double) {
        let u = Self.usable(x) - worldWidth * 0.5
        let v = worldHeight * 0.5 - Self.usable(y)
        let depth = Self.usable(z)
        let yaw = Self.radians(effectiveOrbitYaw)
        let pitch = Self.radians(orbitPitch)
        let cosYaw = jsCos(yaw), sinYaw = jsSin(yaw)
        let cosPitch = jsCos(pitch), sinPitch = jsSin(pitch)
        let u1 = u * cosYaw - depth * sinYaw
        let z1 = u * sinYaw + depth * cosYaw
        return (u1, v * cosPitch + z1 * sinPitch, -v * sinPitch + z1 * cosPitch)
    }

    /// Undoes the turn and the tip, for a direction or a place measured from the middle of the box.
    func worldSpace(u: Double, v: Double, w: Double) -> (x: Double, y: Double, z: Double) {
        let yaw = Self.radians(effectiveOrbitYaw)
        let pitch = Self.radians(orbitPitch)
        let cosYaw = jsCos(yaw), sinYaw = jsSin(yaw)
        let cosPitch = jsCos(pitch), sinPitch = jsSin(pitch)
        let v1 = v * cosPitch - w * sinPitch
        let z1 = v * sinPitch + w * cosPitch
        return (u * cosYaw + z1 * sinYaw, v1, -u * sinYaw + z1 * cosYaw)
    }

    /// Turns a place in a field with depth into a place on the screen.
    public func projectInDepth(
        x: Double,
        y: Double,
        z: Double,
        worldWidth: Double,
        worldHeight: Double,
        worldDepth: Double,
        viewWidth: Double,
        viewHeight: Double
    ) -> ParticleDepthProjection {
        let w = max(1e-6, worldWidth)
        let h = max(1e-6, worldHeight)
        let turned = viewSpace(x: x, y: y, z: z, worldWidth: w, worldHeight: h)
        var scale = 1.0
        var inFront = true
        if let eye = eyeDistance(worldHeight: h) {
            let distance = eye + turned.w
            inFront = distance > eye * Self.depthNearLimit
            scale = eye / max(eye * Self.depthNearLimit, distance)
        }
        let radius = Self.depthRadius(worldWidth: w, worldHeight: h, worldDepth: worldDepth)
        return ParticleDepthProjection(
            x: turned.u * scale / (w * 0.5) * pictureScale + Self.panToScreenFraction(panX, across: viewWidth),
            y: turned.v * scale / (h * 0.5) * pictureScale - Self.panToScreenFraction(panY, across: viewHeight),
            scale: max(Self.depthScaleRange.lowerBound, min(Self.depthScaleRange.upperBound, scale)),
            depth: max(0, min(1, (turned.w + radius) / (2 * radius))),
            isInFront: inFront
        )
    }

    /// The line from the eye through a place on the screen, into the box. What a finger there is touching.
    public func fingerRay(
        screenX: Double,
        screenY: Double,
        worldWidth: Double,
        worldHeight: Double,
        worldDepth: Double,
        viewWidth: Double,
        viewHeight: Double
    ) -> ParticleFingerRay {
        let w = max(1e-6, worldWidth)
        let h = max(1e-6, worldHeight)
        let vw = max(1e-6, viewWidth)
        let vh = max(1e-6, viewHeight)
        let scale = max(1e-6, pictureScale)
        let clipX = ((Self.usable(screenX) / vw) * 2 - 1 - Self.panToScreenFraction(panX, across: vw)) / scale
        let clipY = (1 - (Self.usable(screenY) / vh) * 2 + Self.panToScreenFraction(panY, across: vh)) / scale
        // Where on the plane through the middle of the box, square to the view, the finger is.
        let u = clipX * w * 0.5
        let v = clipY * h * 0.5
        let originView: (u: Double, v: Double, w: Double)
        let directionView: (u: Double, v: Double, w: Double)
        let focus: Double
        let widens: Bool
        if let eye = eyeDistance(worldHeight: h) {
            originView = (0, 0, -eye)
            directionView = (u, v, eye)
            focus = (u * u + v * v + eye * eye).squareRoot()
            widens = true
        } else {
            let back = Self.depthRadius(worldWidth: w, worldHeight: h, worldDepth: worldDepth) + 10
            originView = (u, v, -back)
            directionView = (0, 0, 1)
            focus = back
            widens = false
        }
        let origin = worldSpace(u: originView.u, v: originView.v, w: originView.w)
        let direction = worldSpace(u: directionView.u, v: directionView.v, w: directionView.w)
        return ParticleFingerRay(
            originX: origin.x + w * 0.5,
            originY: h * 0.5 - origin.y,
            originZ: origin.z,
            directionX: direction.x,
            directionY: -direction.y,
            directionZ: direction.z,
            focusDistance: focus,
            widens: widens
        )
    }

    // MARK: - Where to look from

    /// Turns the view to look from a place round the box.
    public mutating func look(yaw: Double, pitch: Double) {
        orbitYaw = Self.wrapDegrees(yaw)
        orbitPitch = Self.clampOrbitPitch(pitch)
        autoOrbitAngle = 0
    }

    /// Turns the view to where an arrangement is best seen from.
    public mutating func look(from view: ParticleArrangement.View) {
        switch view {
        case .angled: look(yaw: Self.restingOrbitYaw, pitch: Self.restingOrbitPitch)
        case .above: look(yaw: -20, pitch: 58)
        case .front: look(yaw: 0, pitch: 0)
        case .low: look(yaw: -28, pitch: 7)
        }
    }

    /// Turns round the box by a drag, in degrees: sideways turns about the upright, up and down tips it.
    public mutating func orbit(byYaw yawChange: Double, pitch pitchChange: Double) {
        orbitYaw = Self.wrapDegrees(orbitYaw + Self.usable(yawChange))
        orbitPitch = Self.clampOrbitPitch(orbitPitch + Self.usable(pitchChange))
    }

    /// Whether the view is anything but where a field in 3D starts.
    public var isAtRestInDepth: Bool {
        zoom == 1 && panX == 0 && panY == 0 && abs(effectiveOrbitYaw - Self.restingOrbitYaw) < 1e-9
            && abs(orbitPitch - Self.restingOrbitPitch) < 1e-9
    }

    // MARK: - Fitting the view to what is there

    /// Zooms and shifts the view so everything in `framing` is on the screen, keeping the angle it is seen from.
    ///
    /// The eight corners of what is there are put through the view, and the view is fitted round where they
    /// land. With zooming out set to add room, a box of things bigger than the screen grows the world to hold
    /// them, as it does on a flat field.
    public mutating func fitInDepth(
        to framing: ParticleDepthFraming,
        worldWidth: Double,
        worldHeight: Double,
        worldDepth: Double,
        viewWidth: Double,
        viewHeight: Double,
        margin: Double = fitMargin
    ) {
        guard !framing.isEmpty, worldWidth > 0, worldHeight > 0, viewWidth > 0, viewHeight > 0 else { return }
        var flat = self
        flat.zoom = 1
        flat.panX = 0
        flat.panY = 0
        var lowX = Double.infinity, highX = -Double.infinity
        var lowY = Double.infinity, highY = -Double.infinity
        for corner in framing.corners {
            let placed = flat.projectInDepth(
                x: corner.x, y: corner.y, z: corner.z,
                worldWidth: worldWidth, worldHeight: worldHeight, worldDepth: worldDepth,
                viewWidth: viewWidth, viewHeight: viewHeight
            )
            lowX = min(lowX, placed.x)
            highX = max(highX, placed.x)
            lowY = min(lowY, placed.y)
            highY = max(highY, placed.y)
        }
        guard lowX.isFinite, highX.isFinite, lowY.isFinite, highY.isFinite else { return }
        let middleX = (lowX + highX) * 0.5
        let middleY = (lowY + highY) * 0.5
        let half = max(1e-6, max(highX - middleX, highY - middleY))
        let usableRoom = 1 - (margin.isFinite ? max(0, min(0.4, margin)) : Self.fitMargin)
        let grown = worldScale

        if growsWorldWhenZoomedOut {
            // How many screens the world would have to be to hold it all.
            let screensNeeded = half * grown / usableRoom
            if screensNeeded > 1 {
                zoom = Self.clampZoom(1 / screensNeeded)
                let now = worldScale
                panX = -middleX * grown / now * viewWidth * 0.5
                panY = middleY * grown / now * viewHeight * 0.5
            } else {
                zoom = Self.clampZoom(max(1, usableRoom / (half * grown)))
                panX = -middleX * grown * zoom * viewWidth * 0.5
                panY = middleY * grown * zoom * viewHeight * 0.5
            }
            return
        }
        zoom = Self.clampZoom(usableRoom / half)
        panX = -middleX * zoom * viewWidth * 0.5
        panY = middleY * zoom * viewHeight * 0.5
    }
}

extension ParticleEngine {
    /// The extent of what is in a field with depth, ignoring the wildest few in each direction.
    public func framingInDepth(trim: Double = ParticleCamera.framingTrimFraction) -> ParticleDepthFraming {
        let half = max(1, halfDepth)
        var xs: [Float] = []
        var ys: [Float] = []
        var zs: [Float] = []
        let total = swarm.count + particles.count
        guard total > 0 else {
            return ParticleDepthFraming(minX: 0, maxX: 0, minY: 0, maxY: 0, minZ: 0, maxZ: 0, bodyCount: 0)
        }
        xs.reserveCapacity(total)
        ys.reserveCapacity(total)
        zs.reserveCapacity(total)
        for index in 0 ..< swarm.count {
            let x = swarm.positions[index * 2]
            let y = swarm.positions[index * 2 + 1]
            let z = swarm.depths[index]
            guard x.isFinite, y.isFinite, z.isFinite else { continue }
            xs.append(x)
            ys.append(y)
            zs.append(z)
        }
        for body in particles where body.isFinite {
            xs.append(Float(body.x))
            ys.append(Float(body.y))
            zs.append(Float(body.z))
        }
        guard !xs.isEmpty else {
            return ParticleDepthFraming(minX: 0, maxX: 0, minY: 0, maxY: 0, minZ: 0, maxZ: 0, bodyCount: 0)
        }
        let rangeX = Self.trimmedRange(xs, low: 0, high: width, trim: trim)
        let rangeY = Self.trimmedRange(ys, low: 0, high: height, trim: trim)
        let rangeZ = Self.trimmedRange(zs, low: -half, high: half, trim: trim)
        return ParticleDepthFraming(
            minX: rangeX.low, maxX: rangeX.high,
            minY: rangeY.low, maxY: rangeY.high,
            minZ: rangeZ.low, maxZ: rangeZ.high,
            bodyCount: xs.count
        )
    }

    /// Where most of a list of numbers lies, leaving out the furthest few at each end — by a count in bins, so
    /// it is one pass whatever the size of the list.
    static func trimmedRange(_ values: [Float], low: Double, high: Double, trim: Double) -> (low: Double, high: Double) {
        let bins = ParticleCamera.framingBins
        let span = max(1e-6, high - low)
        var counts = [Int](repeating: 0, count: bins)
        for value in values {
            counts[JS.clampedInt((Double(value) - low) / span * Double(bins), 0, bins - 1)] += 1
        }
        let skip = Int(Double(values.count) * max(0, min(0.25, trim.isFinite ? trim : 0)))
        let range = ParticleCamera.occupiedRange(bins: counts.map { Int32($0) }, total: values.count, skip: skip)
        let width = span / Double(bins)
        return (low + Double(range.low) * width, low + Double(range.high + 1) * width)
    }
}
