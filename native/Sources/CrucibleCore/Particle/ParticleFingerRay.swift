/// Where a finger points, in a field with depth.
///
/// ## Why a line rather than a point
///
/// On a flat field a finger is at a place: the world under the screen is a sheet, and the finger touches one
/// spot on it. In depth there is no one spot. A finger on the glass is over a whole line of places, from the
/// front of the box to the back, and every body anywhere along that line is drawn under the finger. So a tool
/// in 3D acts on everything that *appears* inside the finger's circle — the body right at the front and the
/// one far behind it alike — which is what somebody means when they put a finger on something they can see.
///
/// The line starts at the eye, runs through the finger on the glass, and goes on into the world. The camera
/// works it out (see `ParticleCamera.fingerRay`), since only the camera knows where the eye is.
public struct ParticleFingerRay: Sendable, Hashable {
    /// Where the line starts, in the world's pixels.
    public var originX: Double
    public var originY: Double
    public var originZ: Double
    /// Which way it goes, as a direction of length one.
    public var directionX: Double
    public var directionY: Double
    public var directionZ: Double
    /// How far along the line the middle of what is being looked at is — where the line crosses the plane
    /// through the middle of the box, square to the view. The finger's circle is drawn at its true size there,
    /// and that is the place under the finger that tools which put something somewhere use.
    public var focusDistance: Double
    /// Whether the circle widens with distance, as everything seen in perspective does: something twice as far
    /// away looks half the size, so twice as much of the world fits inside the same circle on the glass.
    /// Without perspective the circle is the same size all the way along.
    public var widens: Bool

    public init(
        originX: Double,
        originY: Double,
        originZ: Double,
        directionX: Double,
        directionY: Double,
        directionZ: Double,
        focusDistance: Double = 0,
        widens: Bool = false
    ) {
        self.focusDistance = focusDistance.isFinite ? max(0, focusDistance) : 0
        self.widens = widens && self.focusDistance > 0
        self.originX = originX.isFinite ? originX : 0
        self.originY = originY.isFinite ? originY : 0
        self.originZ = originZ.isFinite ? originZ : 0
        let length = (directionX * directionX + directionY * directionY + directionZ * directionZ).squareRoot()
        if length.isFinite, length > 1e-12 {
            self.directionX = directionX / length
            self.directionY = directionY / length
            self.directionZ = directionZ / length
        } else {
            // Nowhere to point, which only a broken camera could produce. Straight into the screen.
            self.directionX = 0
            self.directionY = 0
            self.directionZ = 1
        }
    }

    /// A line straight into the screen through a place — a field seen from the front, with no perspective.
    public static func straightIn(x: Double, y: Double, fromDepth z: Double) -> ParticleFingerRay {
        ParticleFingerRay(
            originX: x, originY: y, originZ: z,
            directionX: 0, directionY: 0, directionZ: 1,
            focusDistance: max(0, -z)
        )
    }

    /// The place under the finger at the middle of what is being looked at.
    public var cursor: (x: Double, y: Double, z: Double) {
        (
            originX + directionX * focusDistance,
            originY + directionY * focusDistance,
            originZ + directionZ * focusDistance
        )
    }

    /// How wide the finger's circle is at a distance along the line, for a circle of the given width at the
    /// focus.
    @inline(__always)
    public func reach(_ reach: Double, at along: Double) -> Double {
        guard widens, reach.isFinite else { return reach }
        // Never narrower than a twentieth, so something right at the eye can still be touched.
        return reach * max(0.05, along / focusDistance)
    }

    /// The point on the line nearest a body, how far along the line that is, and the gap from the body to it.
    ///
    /// The gap is what decides whether a body is under the finger; the point is where the finger's forces are
    /// aimed from, so a pull draws a body toward the line — toward the finger as it appears — rather than
    /// toward the front of the box.
    @inline(__always)
    public func nearest(toX x: Double, y: Double, z: Double) -> (x: Double, y: Double, z: Double, along: Double) {
        let offsetX = x - originX
        let offsetY = y - originY
        let offsetZ = z - originZ
        let along = offsetX * directionX + offsetY * directionY + offsetZ * directionZ
        return (
            originX + directionX * along,
            originY + directionY * along,
            originZ + directionZ * along,
            along
        )
    }

    /// Whether a body is inside a cylinder of the given radius round the line.
    @inline(__always)
    public func reaches(x: Double, y: Double, z: Double, within reach: Double) -> Bool {
        guard reach > 0 else { return false }
        guard reach.isFinite else { return true }
        let near = nearest(toX: x, y: y, z: z)
        guard near.along > 0 else { return false }
        let dx = x - near.x
        let dy = y - near.y
        let dz = z - near.z
        let here = self.reach(reach, at: near.along)
        return dx * dx + dy * dy + dz * dz < here * here
    }

    /// Where the line crosses the level plane at a height, if it does — for placing things on a floor or a
    /// shelf in depth.
    public func crossing(height: Double) -> (x: Double, z: Double)? {
        guard abs(directionY) > 1e-9 else { return nil }
        let along = (height - originY) / directionY
        guard along > 0, along.isFinite else { return nil }
        return (originX + directionX * along, originZ + directionZ * along)
    }

    /// Where the line crosses the upright plane at a depth — the middle sheet of the box, say.
    public func crossing(depth: Double) -> (x: Double, y: Double)? {
        guard abs(directionZ) > 1e-9 else { return nil }
        let along = (depth - originZ) / directionZ
        guard along > 0, along.isFinite else { return nil }
        return (originX + directionX * along, originY + directionY * along)
    }
}

extension ParticleBrush {
    /// What the finger does to a body in a field with depth.
    ///
    /// The flat rule, measured from the nearest point on the finger's line rather than from a spot on a sheet:
    /// the circle becomes a tube along the line, a pull draws a body in toward the line, a push drives it out
    /// from it, and a swirl turns it round the line — so from where somebody is looking, a swirl turns the
    /// crowd round the finger exactly as it does on a flat field, whatever angle the field is seen from.
    @inline(__always)
    public static func effect(
        _ mode: ParticleMouseMode,
        atX x: Double,
        y: Double,
        z: Double,
        ray: ParticleFingerRay,
        reach: Double,
        strength: Double,
        unit: Double
    ) -> (inReach: Bool, velocityX: Double, velocityY: Double, velocityZ: Double, stops: Bool) {
        let none = (false, 0.0, 0.0, 0.0, false)
        let near = ray.nearest(toX: x, y: y, z: z)
        // Behind the eye is never under the finger.
        guard near.along > 0 else { return none }
        let dx = near.x - x
        let dy = near.y - y
        let dz = near.z - z
        let distanceSquared = dx * dx + dy * dy + dz * dz
        let unlimited = !reach.isFinite
        guard distanceSquared.isFinite else { return none }
        let here = ray.reach(reach, at: near.along)
        if !unlimited {
            guard here > 0, distanceSquared < here * here else { return none }
        }
        if mode == .freeze { return (true, 0, 0, 0, true) }
        if mode == .painter { return (true, 0, 0, 0, false) }

        let distance = distanceSquared.squareRoot() + 1e-6
        let fall = unlimited ? 1 : max(0, 1 - distance / here)
        let share = strength * fall
        // Toward the line.
        let towardX = dx / distance
        let towardY = dy / distance
        let towardZ = dz / distance
        // Round the line: the direction along it crossed with the way in, which turns a body about the line
        // the same way the flat swirl turns it about the finger when the field is seen from the front.
        let aroundX = ray.directionY * towardZ - ray.directionZ * towardY
        let aroundY = ray.directionZ * towardX - ray.directionX * towardZ
        let aroundZ = ray.directionX * towardY - ray.directionY * towardX

        var ax = 0.0
        var ay = 0.0
        var az = 0.0
        switch mode {
        case .attract:
            ax = towardX * share * pullRate
            ay = towardY * share * pullRate
            az = towardZ * share * pullRate
        case .repel:
            ax = -towardX * share * pushRate
            ay = -towardY * share * pushRate
            az = -towardZ * share * pushRate
        case .vortex:
            ax = aroundX * share * swirlRate
            ay = aroundY * share * swirlRate
            az = aroundZ * share * swirlRate
        case .gravityWell:
            ax = towardX * share * wellPullRate + aroundX * share * wellSwirlRate
            ay = towardY * share * wellPullRate + aroundY * share * wellSwirlRate
            az = towardZ * share * wellPullRate + aroundZ * share * wellSwirlRate
        case .hawk:
            let scale = max(1e-6, unit)
            let offsetX = dx / scale
            let offsetY = dy / scale
            let offsetZ = dz / scale
            let k = share * scatterRate / (offsetX * offsetX + offsetY * offsetY + offsetZ * offsetZ + 0.0004)
            ax = -offsetX * k
            ay = -offsetY * k
            az = -offsetZ * k
        case .hyperDrive:
            ax = towardX * strength * rushRate
            ay = towardY * strength * rushRate
            az = towardZ * strength * rushRate
        case .freeze, .painter, .emitter, .current, .wall, .source:
            return none
        }

        ax = max(-accelerationLimit, min(accelerationLimit, ax))
        ay = max(-accelerationLimit, min(accelerationLimit, ay))
        az = max(-accelerationLimit, min(accelerationLimit, az))
        let toPixels = max(0, unit) / momentsSquared
        return (true, ax * toPixels, ay * toPixels, az * toPixels, false)
    }
}

extension Swarm {
    /// What the finger does to the crowd for one moment, in a field with depth.
    public func applyBrushInDepth(
        _ mode: ParticleMouseMode,
        ray: ParticleFingerRay,
        reach: Double,
        strength: Double,
        unit: Double,
        now: Double
    ) {
        guard count > 0, ParticleBrush.touchesBodies(mode) else { return }
        let rush = ParticleBrush.rushColor.packedRGBA
        for i in 0 ..< count {
            let pair = i * 2
            let x = Double(positions[pair])
            let y = Double(positions[pair + 1])
            let z = Double(depths[i])
            guard x.isFinite, y.isFinite, z.isFinite else { continue }
            let effect = ParticleBrush.effect(
                mode, atX: x, y: y, z: z, ray: ray, reach: reach, strength: strength, unit: unit
            )
            guard effect.inReach else { continue }
            if effect.stops {
                velocities[pair] = 0
                velocities[pair + 1] = 0
                depthVelocities[i] = 0
                continue
            }
            if mode == .painter {
                colors[i] = ParticleBrush.paintColor(now: now, index: i).packedRGBA
                continue
            }
            velocities[pair] = JS.toFloat32(Double(velocities[pair]) + effect.velocityX)
            velocities[pair + 1] = JS.toFloat32(Double(velocities[pair + 1]) + effect.velocityY)
            depthVelocities[i] = JS.toFloat32(Double(depthVelocities[i]) + effect.velocityZ)
            if mode == .hyperDrive { colors[i] = rush }
        }
        hasDepth = true
    }
}
