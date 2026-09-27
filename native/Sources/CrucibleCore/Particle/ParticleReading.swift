/// What is happening to one body, in words and numbers.
///
/// ## Why this exists
///
/// Because a field of a million bodies explains nothing about any one of them. Something moves and you cannot tell
/// whether it was gravity, a black hole, the wind you painted, the liquid it is in, or your own finger a moment ago
/// — and when a scene behaves oddly, that is exactly the question.
///
/// So this answers it for a single body: how fast it is going, how heavy it is, how crowded it is, and what each
/// force acting on it is contributing *this moment*. The forces are worked out the same way the moment itself works
/// them out, so the figures are the real ones rather than a plausible-looking summary.
public struct ParticleReading: Sendable, Hashable {
    /// One force, named, and how much of a push it is giving this body this moment.
    public struct Push: Sendable, Hashable {
        public var name: String
        public var x: Double
        public var y: Double
        public var z: Double

        public init(name: String, x: Double, y: Double, z: Double = 0) {
            self.name = name
            self.x = x
            self.y = y
            self.z = z
        }

        /// How hard it is pushing, whichever way.
        public var size: Double { (x * x + y * y + z * z).squareRoot() }
    }

    /// Whether a body was found near where it was asked about.
    public var found: Bool
    /// Whether it is one of the crowd rather than one of the individually interesting bodies.
    public var isCrowd: Bool
    public var x: Double
    public var y: Double
    public var z: Double
    public var speed: Double
    public var mass: Double
    /// How many other bodies are within a body's width or so.
    public var neighbours: Int
    /// Where it will be shortly if nothing changes, as a line of places.
    public var path: [(x: Double, y: Double)]
    /// Every force acting on it, largest first.
    public var pushes: [Push]

    public static let nothing = ParticleReading(
        found: false, isCrowd: false, x: 0, y: 0, z: 0, speed: 0, mass: 0, neighbours: 0, path: [], pushes: []
    )

    public init(
        found: Bool,
        isCrowd: Bool,
        x: Double,
        y: Double,
        z: Double,
        speed: Double,
        mass: Double,
        neighbours: Int,
        path: [(x: Double, y: Double)],
        pushes: [Push]
    ) {
        self.found = found
        self.isCrowd = isCrowd
        self.x = x
        self.y = y
        self.z = z
        self.speed = speed
        self.mass = mass
        self.neighbours = neighbours
        self.path = path
        self.pushes = pushes
    }

    public static func == (left: ParticleReading, right: ParticleReading) -> Bool {
        left.found == right.found && left.isCrowd == right.isCrowd && left.x == right.x && left.y == right.y
            && left.z == right.z && left.speed == right.speed && left.mass == right.mass
            && left.neighbours == right.neighbours && left.pushes == right.pushes
            && left.path.count == right.path.count
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(found)
        hasher.combine(x)
        hasher.combine(y)
        hasher.combine(speed)
    }
}

extension ParticleEngine {
    /// Reads the body nearest a place, and what is acting on it.
    ///
    /// - Parameter within: how far to look. Nothing is reported beyond it, rather than reporting whatever happened
    ///   to be nearest on the far side of the world.
    public func reading(nearX: Double, y nearY: Double, within reach: Double = 40) -> ParticleReading {
        guard nearX.isFinite, nearY.isFinite, reach > 0 else { return .nothing }
        var bestDistance = reach * reach
        var found: (isCrowd: Bool, index: Int)?

        for (index, body) in particles.enumerated() where body.isFinite {
            let dx = body.x - nearX
            let dy = body.y - nearY
            let away = dx * dx + dy * dy
            if away < bestDistance {
                bestDistance = away
                found = (false, index)
            }
        }
        for index in 0 ..< swarm.count {
            let dx = swarm.positions[index * 2].asDouble - nearX
            let dy = swarm.positions[index * 2 + 1].asDouble - nearY
            let away = dx * dx + dy * dy
            if away < bestDistance {
                bestDistance = away
                found = (true, index)
            }
        }
        guard let found else { return .nothing }

        let x: Double
        let y: Double
        let z: Double
        let velocityX: Double
        let velocityY: Double
        let mass: Double
        if found.isCrowd {
            x = swarm.positions[found.index * 2].asDouble
            y = swarm.positions[found.index * 2 + 1].asDouble
            z = storedDepthEnabled && swarm.hasDepth ? swarm.depths[found.index].asDouble : 0
            velocityX = swarm.velocities[found.index * 2].asDouble
            velocityY = swarm.velocities[found.index * 2 + 1].asDouble
            mass = swarm.masses[found.index].asDouble
        } else {
            let body = particles[found.index]
            x = body.x
            y = body.y
            z = body.z
            velocityX = body.velocityX
            velocityY = body.velocityY
            mass = body.mass
        }

        var pushes: [ParticleReading.Push] = []

        // Gravity, which is the one force acting on everything.
        if gravityX != 0 || gravityY != 0 {
            pushes.append(ParticleReading.Push(name: "Gravity", x: gravityX, y: gravityY))
        }
        if storedDepthEnabled, storedGravityZ != 0 {
            pushes.append(ParticleReading.Push(name: "Gravity into the box", x: 0, y: 0, z: storedGravityZ))
        }
        if storedGravityToCentre > 0 {
            let toX = width * 0.5 - x
            let toY = height * 0.5 - y
            let away = (toX * toX + toY * toY).squareRoot()
            if away > Self.radialGravityCore {
                let share = storedGravityToCentre / away
                pushes.append(ParticleReading.Push(name: "Pull to the middle", x: toX * share, y: toY * share))
            }
        }

        // Every black hole and repulsor, named by what it is, worked out exactly as the moment does.
        for body in particles where body.kind == .blackhole || body.kind == .repulsor {
            guard body.isFinite else { continue }
            let toX = body.x - x
            let toY = body.y - y
            let awaySquared = toX * toX + toY * toY
            guard awaySquared > 0.01 else { continue }
            let away = awaySquared.squareRoot()
            let strength = body.kind == .repulsor
                ? -(body.mass <= 0 ? 80 : body.mass) * 150 / awaySquared
                : (body.mass <= 0 ? 80 : body.mass) * 200 / awaySquared
            pushes.append(
                ParticleReading.Push(
                    name: body.kind == .repulsor ? "Repulsor" : "Black hole",
                    x: toX / away * strength,
                    y: toY / away * strength
                )
            )
        }

        // The wind somebody painted, which is invisible unless it is drawn and is the hardest of all of these to
        // guess at from watching.
        if !storedCurrent.isEmpty, width > 0, height > 0 {
            let push = storedCurrent.sample(atFractionX: x / width, y: y / height)
            let strength = currentSettings.sanitized.strength
            if push.x != 0 || push.y != 0 {
                pushes.append(
                    ParticleReading.Push(name: "Painted wind", x: push.x * strength, y: push.y * strength)
                )
            }
        }

        // Drag, which is not a push but takes speed away, and is why things stop.
        if damping < 1 {
            let lost = 1 - damping
            pushes.append(ParticleReading.Push(name: "Drag", x: -velocityX * lost, y: -velocityY * lost))
        }

        // How crowded it is, which explains the liquid and the pushing apart without having to model them.
        var neighbours = 0
        let near = max(6.0, contactSettings.sanitized.size > 0 ? contactSettings.sanitized.size * 1.5 : 12)
        let nearSquared = near * near
        for index in 0 ..< swarm.count {
            let dx = swarm.positions[index * 2].asDouble - x
            let dy = swarm.positions[index * 2 + 1].asDouble - y
            if dx * dx + dy * dy < nearSquared { neighbours += 1 }
        }

        // Where it is heading, if nothing changes: the same step the field takes, repeated.
        var path: [(x: Double, y: Double)] = []
        var atX = x
        var atY = y
        var goingX = velocityX
        var goingY = velocityY
        for _ in 0 ..< 24 {
            goingX = goingX * damping + gravityX
            goingY = goingY * damping + gravityY
            atX += goingX
            atY += goingY
            path.append((atX, atY))
        }

        pushes.sort { $0.size > $1.size }
        return ParticleReading(
            found: true,
            isCrowd: found.isCrowd,
            x: x,
            y: y,
            z: z,
            speed: (velocityX * velocityX + velocityY * velocityY).squareRoot(),
            mass: mass,
            neighbours: neighbours,
            path: path,
            pushes: pushes
        )
    }
}
