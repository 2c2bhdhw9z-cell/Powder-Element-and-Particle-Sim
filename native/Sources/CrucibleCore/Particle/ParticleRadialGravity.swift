/// Gravity that points at the middle of the world instead of down it.
///
/// ## What it is for
///
/// A little round world. With ordinary gravity, loose matter falls to the floor and lies in a heap; with gravity
/// that points inward, it falls toward one place from every direction and settles into a ball with a surface all
/// the way round. Everything else then follows without being asked: dig a hole and it fills from the sides, fling
/// a handful off and it arcs back down, and a liquid finds a level that is a circle.
///
/// ## Why it is its own pass
///
/// Every other force in the field is applied inside loops that are compared, number for number, against
/// recordings of what the field used to do. Reaching into those loops to add a case that is switched off almost
/// all the time would put the whole of that agreement at risk for a feature most scenes never use. This is a
/// separate sweep instead, run only while it is switched on — so with it off, not one number anywhere changes.
///
/// ## Why the pull is the same everywhere rather than weaker further out
///
/// Because this is a world to stand on, not a solar system. Real gravity falls away with distance, which for a
/// ball of loose matter a few hundred pixels across would mean the outside barely being held at all while the
/// middle was crushed. A steady pull is what a surface feels like, and it is what makes a pile of sand on a small
/// world behave the way a pile of sand does.
extension ParticleEngine {
    /// How hard everything is pulled toward the middle of the world. Nought is off, and off is the default.
    ///
    /// Measured the same way ordinary gravity is, so a strength of nought point three five pulls about as hard as
    /// the gravity slider does at that number.
    public var gravityToCentre: Double {
        get { storedGravityToCentre }
        set { storedGravityToCentre = newValue.isFinite ? max(0, min(4, newValue)) : 0 }
    }

    /// How close to the middle the pull stops growing, so nothing is flung about by dividing by almost nothing.
    static let radialGravityCore = 6.0

    /// Pulls everything one step toward the middle.
    func stepGravityToCentre() {
        let strength = storedGravityToCentre
        guard strength > 0 else { return }
        let centreX = width * 0.5
        let centreY = height * 0.5
        let softening = Self.radialGravityCore

        particles.withUnsafeMutableBufferPointer { bodies in
            for index in 0 ..< bodies.count {
                guard !bodies[index].isFixed, !bodies[index].ignoresGravity else { continue }
                let dx = centreX - bodies[index].x
                let dy = centreY - bodies[index].y
                let dz = storedDepthEnabled ? -bodies[index].z : 0
                let distance = (dx * dx + dy * dy + dz * dz).squareRoot()
                guard distance > softening else { continue }
                let share = strength / distance
                bodies[index].velocityX += dx * share
                bodies[index].velocityY += dy * share
                if storedDepthEnabled { bodies[index].velocityZ += dz * share }
            }
        }

        let count = swarm.count
        guard count > 0 else { return }
        let inDepth = storedDepthEnabled && swarm.hasDepth
        let positions = swarm.positions
        let velocities = swarm.velocities
        let depths = swarm.depths
        let depthVelocities = swarm.depthVelocities
        for index in 0 ..< count {
            let pair = index * 2
            let dx = centreX - positions[pair].asDouble
            let dy = centreY - positions[pair + 1].asDouble
            let dz = inDepth ? -depths[index].asDouble : 0
            let distance = (dx * dx + dy * dy + dz * dz).squareRoot()
            guard distance > softening else { continue }
            let share = strength / distance
            velocities[pair] = JS.toFloat32(velocities[pair].asDouble + dx * share)
            velocities[pair + 1] = JS.toFloat32(velocities[pair + 1].asDouble + dy * share)
            if inDepth {
                depthVelocities[index] = JS.toFloat32(depthVelocities[index].asDouble + dz * share)
            }
        }
    }
}
