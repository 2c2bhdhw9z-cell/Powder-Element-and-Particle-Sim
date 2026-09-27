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
    /// Every spring and muscle joined to one of the individual bodies, as two totals: what the springs are doing and
    /// what the muscles are doing, each worked out exactly as the moment does.
    func springPushes(on index: Int) -> [ParticleReading.Push] {
        guard index >= 0, index < particles.count, !springs.isEmpty else { return [] }
        let body = particles[index]
        guard !body.isFixed else { return [] }
        let moment = springMoment
        let inDepth = storedDepthEnabled
        var plain = (x: 0.0, y: 0.0, z: 0.0, count: 0)
        var muscle = (x: 0.0, y: 0.0, z: 0.0, count: 0)
        for spring in springs where spring.a == index || spring.b == index {
            guard spring.a >= 0, spring.a < particles.count, spring.b >= 0, spring.b < particles.count else { continue }
            let a = particles[spring.a]
            let b = particles[spring.b]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let dz = inDepth ? b.z - a.z : 0
            var distance = (dx * dx + dy * dy + dz * dz).squareRoot()
            if distance == 0 { distance = 0.001 }
            // Stretched past breaking, the moment ignores it, and so does this.
            if spring.rest > 0 && distance > spring.rest * 4.5 { continue }
            let rest = spring.isMuscle ? spring.length(atMoment: moment) : spring.rest
            let scale = ((distance - rest) / distance) * spring.k
            // Toward the other end when stretched, away from it when squashed, whichever end this body is.
            let sign = spring.a == index ? 1.0 : -1.0
            var fx = dx * scale * sign / body.mass
            var fy = dy * scale * sign / body.mass
            var fz = dz * scale * sign / body.mass
            if spring.jets {
                let rate = spring.lengthRate(atMoment: moment)
                if rate < 0 {
                    let push = -rate * spring.thrust * 0.5 / body.mass
                    fx += spring.thrustX * push
                    fy += spring.thrustY * push
                    if inDepth { fz += spring.thrustZ * push }
                }
            }
            if spring.isMuscle {
                muscle = (muscle.x + fx, muscle.y + fy, muscle.z + fz, muscle.count + 1)
            } else {
                plain = (plain.x + fx, plain.y + fy, plain.z + fz, plain.count + 1)
            }
        }
        var found: [ParticleReading.Push] = []
        if plain.count > 0 {
            found.append(ParticleReading.Push(
                name: plain.count == 1 ? "The spring joining it" : "The \(plain.count) springs joining it",
                x: plain.x, y: plain.y, z: plain.z
            ))
        }
        if muscle.count > 0 {
            found.append(ParticleReading.Push(
                name: muscle.count == 1 ? "Its muscle" : "Its \(muscle.count) muscles",
                x: muscle.x, y: muscle.y, z: muscle.z
            ))
        }
        return found
    }

    /// The pull and push of every other charged body on one of the individual bodies, when the moment works it out
    /// at all — which it does only for a few hundred bodies, and never where the charge is saying which kind a body is.
    func chargePush(on index: Int) -> ParticleReading.Push? {
        guard index >= 0, index < particles.count, particles.count <= 300, !storedChargeIsKind else { return nil }
        let body = particles[index]
        guard body.charge != 0, !body.isFixed else { return nil }
        var total = (x: 0.0, y: 0.0)
        let isWell = body.kind == .blackhole || body.kind == .repulsor
        for (other, neighbour) in particles.enumerated() where other != index {
            guard neighbour.charge != 0 else { continue }
            // Exactly the pairs the moment works out, which leaves a pair alone when the later of its two bodies in
            // the list is a well.
            let laterIsWell = other > index ? (neighbour.kind == .blackhole || neighbour.kind == .repulsor) : isWell
            if laterIsWell { continue }
            let dx = neighbour.x - body.x
            let dy = neighbour.y - body.y
            let distanceSquared = dx * dx + dy * dy + 10
            let distance = distanceSquared.squareRoot()
            let force = (body.charge * neighbour.charge * electrostaticFactor) / distanceSquared
            // Like charges apart, unlike together, as the moment has it.
            total.x -= (dx / distance) * force / body.mass
            total.y -= (dy / distance) * force / body.mass
        }
        guard total.x != 0 || total.y != 0 else { return nil }
        return ParticleReading.Push(name: "Charge", x: total.x, y: total.y)
    }

    /// The pull back toward the shape a jelly was drawn in, on one of its bodies.
    func jellyPush(on index: Int) -> ParticleReading.Push? {
        guard index >= 0, index < particles.count, !storedJellies.isEmpty else { return nil }
        let id = particles[index].id
        for jelly in storedJellies {
            guard let at = jelly.ids.firstIndex(of: id) else { continue }
            var where_: [Int: Int] = [:]
            for (place, body) in particles.enumerated() { where_[body.id] = place }
            var members: [(index: Int, restX: Double, restY: Double)] = []
            for (slot, member) in jelly.ids.enumerated() {
                if let place = where_[member] { members.append((place, jelly.restX[slot], jelly.restY[slot])) }
            }
            guard members.count >= 3 else { return nil }
            let count = Double(members.count)
            var centreX = 0.0, centreY = 0.0, restX = 0.0, restY = 0.0
            for member in members {
                centreX += particles[member.index].x
                centreY += particles[member.index].y
                restX += member.restX
                restY += member.restY
            }
            centreX /= count
            centreY /= count
            restX /= count
            restY /= count
            var along = 0.0, across = 0.0
            for member in members {
                let qx = member.restX - restX, qy = member.restY - restY
                let px = particles[member.index].x - centreX, py = particles[member.index].y - centreY
                along += qx * px + qy * py
                across += qx * py - qy * px
            }
            let turn = JS.atan2(across, along)
            let qx = jelly.restX[at] - restX
            let qy = jelly.restY[at] - restY
            let goalX = centreX + qx * jsCos(turn) - qy * jsSin(turn)
            let goalY = centreY + qx * jsSin(turn) + qy * jsCos(turn)
            return ParticleReading.Push(
                name: "Holding the jelly's shape",
                x: (goalX - particles[index].x) * jelly.firmness,
                y: (goalY - particles[index].y) * jelly.firmness
            )
        }
        return nil
    }

    /// What each recorded loop is doing at a place this moment, named by its tool.
    func loopPushes(atX x: Double, y: Double, z: Double) -> [ParticleReading.Push] {
        guard !storedForceLoops.isEmpty else { return [] }
        var found: [ParticleReading.Push] = []
        let unit = brushUnit
        for loop in storedForceLoops where !loop.points.isEmpty {
            let at = loop.playhead % loop.points.count
            let point = loop.points[at]
            let strength = ParticleBrush.defaultStrength * loop.strength
            let reach = loop.reach.isNaN ? 0 : loop.reach
            let push: (x: Double, y: Double, z: Double)
            if storedDepthEnabled {
                let ray = loop.rays.count == loop.points.count
                    ? loop.rays[at]
                    : ParticleFingerRay.straightIn(x: point.x, y: point.y, fromDepth: -halfDepth - 10)
                let effect = ParticleBrush.effect(
                    loop.mode, atX: x, y: y, z: z, ray: ray, reach: reach, strength: strength, unit: unit
                )
                guard effect.inReach, !effect.stops else { continue }
                push = (effect.velocityX, effect.velocityY, effect.velocityZ)
            } else {
                let effect = ParticleBrush.effect(
                    loop.mode, atX: x, y: y, fingerX: point.x, fingerY: point.y, reach: reach, strength: strength, unit: unit
                )
                guard effect.inReach, !effect.stops else { continue }
                push = (effect.velocityX, effect.velocityY, 0)
            }
            guard push.x != 0 || push.y != 0 || push.z != 0 else { continue }
            found.append(ParticleReading.Push(name: "Your recorded \(Self.toolName(loop.mode))", x: push.x, y: push.y, z: push.z))
        }
        return found
    }

    /// What a tool is called on the buttons, in lower case for the middle of a sentence.
    static func toolName(_ mode: ParticleMouseMode) -> String {
        switch mode {
        case .attract: return "pull"
        case .repel: return "push"
        case .vortex: return "swirl"
        case .gravityWell: return "well"
        case .freeze: return "freeze"
        case .painter: return "paint"
        case .hawk: return "hawk"
        case .hyperDrive: return "hyper"
        case .emitter: return "emit"
        case .current: return "wind"
        case .wall: return "wall"
        case .source: return "source"
        case .light: return "light"
        case .slingshot: return "throw"
        case .jelly: return "jelly"
        }
    }

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

        // The swirl about the middle of the world, exactly as the moment applies it.
        if vortexForce != 0 {
            let dx = width / 2 - x
            let dy = height / 2 - y
            let distanceSquared = dx * dx + dy * dy + 20
            let distance = distanceSquared.squareRoot()
            let strength = (vortexForce * 10) / distanceSquared
            pushes.append(ParticleReading.Push(
                name: "Swirl about the middle",
                x: (-dy / distance) * strength + (dx / distance) * (strength * 0.2),
                y: (dx / distance) * strength + (dy / distance) * (strength * 0.2)
            ))
        }

        if !found.isCrowd {
            pushes.append(contentsOf: springPushes(on: found.index))
            if let charge = chargePush(on: found.index) { pushes.append(charge) }
            if let shape = jellyPush(on: found.index) { pushes.append(shape) }
        } else if fluidEnabled {
            // What the liquid gave this body in its last pass: the figure it actually added, not an estimate.
            if storedDepthEnabled {
                if let push = depthFluid.lastPush(at: found.index) {
                    pushes.append(ParticleReading.Push(name: "The liquid", x: push.x, y: push.y, z: push.z))
                }
            } else if let push = fluid.lastPush(at: found.index) {
                pushes.append(ParticleReading.Push(name: "The liquid", x: push.x, y: push.y))
            }
        }

        // Recorded loops, which push when no finger is anywhere near and so are the easiest thing to forget.
        pushes.append(contentsOf: loopPushes(atX: x, y: y, z: z))

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
