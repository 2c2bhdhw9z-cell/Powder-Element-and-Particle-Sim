/// Pull back and let go to throw a body, with its path drawn before it is thrown.
///
/// ## Why the path can be trusted
///
/// It is not a guess drawn to look right. It is the body's own future, worked out by running the same forces the
/// field will run on it — the black holes and pushers where they are now, gravity and drag, the swirl, painted wind,
/// the speed limit, the walls somebody drew and the edges of the world — one moment at a time, for a couple of
/// seconds ahead. So aiming past a black hole to swing round it works the way the dots say it will.
///
/// What it cannot know is the future of everything else. It takes the wells as standing still where they are, and
/// the thrown body as alone, so near a well that is itself orbiting, or through a crowd, the real path parts company
/// with the dotted one after a while. That is why it is drawn only a little way ahead: far enough to aim with, not so
/// far that it promises more than it knows.
extension ParticleEngine {
    /// How much speed pulling back gives, in pixels a moment for every pixel of pull.
    public static let slingshotPower = 0.08
    /// The fastest anything can be thrown, however far the pull.
    public static let slingshotFastest = 24.0
    /// How far ahead the path is drawn, in moments. Two and a half seconds.
    public static let slingshotLookahead = 150

    /// The speed a pull gives: away from where the finger has pulled to, back through where the pull started.
    public static func slingshotVelocity(
        anchorX: Double, anchorY: Double, pullX: Double, pullY: Double
    ) -> (x: Double, y: Double) {
        guard anchorX.isFinite, anchorY.isFinite, pullX.isFinite, pullY.isFinite else { return (0, 0) }
        var vx = (anchorX - pullX) * slingshotPower
        var vy = (anchorY - pullY) * slingshotPower
        let speed = (vx * vx + vy * vy).squareRoot()
        if speed > slingshotFastest {
            vx *= slingshotFastest / speed
            vy *= slingshotFastest / speed
        }
        return (vx, vy)
    }

    /// Where a body thrown from a place at a speed would be, one point a moment.
    ///
    /// Stops early where the body would fall into a black hole, which throws what reaches it somewhere nobody can
    /// say in advance, or leave the world through an open edge.
    public func predictedPath(
        fromX startX: Double,
        y startY: Double,
        velocityX: Double,
        velocityY: Double,
        moments: Int = ParticleEngine.slingshotLookahead
    ) -> [ParticleFingerPoint] {
        guard startX.isFinite, startY.isFinite, velocityX.isFinite, velocityY.isFinite, moments > 0 else { return [] }
        let wells = particles.filter { $0.kind == .blackhole || $0.kind == .repulsor }
        let walls = SwarmDrawnWorld.segments(for: storedWalls, width: width, height: height)
        let wallSettings = storedWallSettings.sanitized
        let currentStrength = storedCurrentSettings.sanitized.strength
        let radius = slingshotRadius
        var x = startX
        var y = startY
        var vx = velocityX
        var vy = velocityY
        var path: [ParticleFingerPoint] = [ParticleFingerPoint(x: x, y: y)]
        path.reserveCapacity(moments + 1)

        for _ in 0 ..< moments {
            // The wells, exactly as the step applies them.
            for well in wells {
                let wellRadius = well.radius == 0 ? 12 : well.radius
                let wellMass = well.mass == 0 ? 80 : well.mass
                let dx = well.x - x
                let dy = well.y - y
                let distanceSquared = dx * dx + dy * dy + 10
                let distance = distanceSquared.squareRoot()
                if well.kind == .blackhole {
                    if distance < wellRadius + radius + 2 { return path }
                    let force = (wellMass * 200) / distanceSquared
                    vx += (dx / distance) * force
                    vy += (dy / distance) * force
                } else {
                    let force = (wellMass * 150) / distanceSquared
                    vx -= (dx / distance) * force
                    vy -= (dy / distance) * force
                }
            }
            if vortexForce != 0 {
                let dx = width / 2 - x
                let dy = height / 2 - y
                let distanceSquared = dx * dx + dy * dy + 20
                let distance = distanceSquared.squareRoot()
                let strength = (vortexForce * 10) / distanceSquared
                vx += (-dy / distance) * strength + (dx / distance) * (strength * 0.2)
                vy += (dx / distance) * strength + (dy / distance) * (strength * 0.2)
            }
            if !storedCurrent.isEmpty, width > 0, height > 0 {
                let push = storedCurrent.sample(atFractionX: x / width, y: y / height)
                vx += push.x * currentStrength
                vy += push.y * currentStrength
            }
            vx += gravityX
            vy += gravityY
            vx *= damping
            vy *= damping
            let speedSquared = vx * vx + vy * vy
            if speedSquared > maxSpeed * maxSpeed, speedSquared > 0 {
                let scale = maxSpeed / speedSquared.squareRoot()
                vx *= scale
                vy *= scale
            }
            let cameFromX = x
            let cameFromY = y
            x += vx
            y += vy
            if !walls.isEmpty {
                SwarmDrawnWorld.collide(
                    x: &x, y: &y, velocityX: &vx, velocityY: &vy,
                    cameFromX: cameFromX, cameFromY: cameFromY,
                    segments: walls,
                    thickness: wallSettings.thickness + radius,
                    bounciness: wallSettings.bounciness,
                    friction: wallSettings.friction
                )
            }
            switch boundaryMode {
            case .bounce:
                if x - radius < 0 {
                    x = radius
                    vx *= -elasticity
                } else if x + radius > width {
                    x = width - radius
                    vx *= -elasticity
                }
                if y - radius < 0 {
                    y = radius
                    vy *= -elasticity
                } else if y + radius > height {
                    y = height - radius
                    vy *= -elasticity
                }
            case .wrap:
                // A path that wraps would draw a line straight across the world, so it stops at the edge instead.
                if x < 0 || x > width || y < 0 || y > height { return path }
            case .void:
                if x < -10 || x > width + 10 || y < -10 || y > height + 10 { return path }
            }
            guard x.isFinite, y.isFinite else { return path }
            path.append(ParticleFingerPoint(x: x, y: y))
        }
        return path
    }

    /// How big a thrown body is.
    var slingshotRadius: Double { 4 * sceneScale }

    /// Throws a body from a place at a speed.
    ///
    /// - Returns: its identifier.
    @discardableResult
    public func launch(fromX x: Double, y: Double, velocityX: Double, velocityY: Double) -> Int {
        pushUndo()
        return addParticle(
            x: x.isFinite ? x : width / 2,
            y: y.isFinite ? y : height / 2,
            velocityX: velocityX.isFinite ? velocityX : 0,
            velocityY: velocityY.isFinite ? velocityY : 0,
            radius: slingshotRadius,
            mass: 1,
            // No charge, so it is not tugged by every other charged body, and belongs to no kind in the scenes that
            // use charge to say which kind a body is.
            charge: 0,
            color: PackedColor(r: 0xFD, g: 0xE6, b: 0x8A)
        )
    }
}
