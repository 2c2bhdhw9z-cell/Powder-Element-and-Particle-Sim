// The particle field's physics: forces, integration, boundaries, flocking, springs.
//
// Ported from web/src/sim/particle/step.ts, with the bugs found in that file during
// the audit already corrected on both sides.
//
// The main loop takes a mutable pointer to the body list and works through it
// directly, rather than going through the array's subscript. That is not premature:
// the pairwise force pass writes to two different bodies in the same iteration, and
// the whole loop runs for every body on every frame. Copying the values the loop
// needs into locals first also keeps the compiler from having to prove that nothing
// inside the loop touches the engine's other properties.

extension ParticleEngine {
    /// The continuous spray produced by holding the emitter tool down.
    func spawnEmitter(at x: Double, y: Double) {
        for _ in 0 ..< 6 {
            let angle = rng.next() * Double.pi * 2
            let speed = rng.next() * 6 + 1
            // Size before shade, and each drawn into its own constant before the call.
            //
            // The order in which bodies take numbers from the random stream is part of
            // the behaviour, not an implementation detail. These two were once the other
            // way round, which gave every emitted body the other one's size — and since
            // a body's size decides where it meets a wall, and the charge forces couple
            // every body to every other while the count is still small, the whole scene
            // drifted. The draw *count* was unaffected, so only comparing the values
            // caught it.
            let radius = rng.next() * 3 + 1
            let hue = rng.next() * 360
            addParticle(
                x: x,
                y: y,
                velocityX: jsCos(angle) * speed,
                velocityY: jsSin(angle) * speed,
                radius: radius,
                color: PackedColor(hue: hue, saturation: 0.9, lightness: 0.65)
            )
        }
    }

    /// Runs one tick of the object bodies: lifetimes, forces, integration, boundaries.
    func stepParticles(mouseX: Double?, mouseY: Double?, mouseActive: Bool, now: Double) {
        // MARK: Lifetimes, trails and recycling

        let recordTrails = showTrails && particles.count <= 1000
        var anyExpired = false

        do {
            var localRNG = rng
            let worldHeight = height
            let localDecaySpeed = decaySpeed

            particles.withUnsafeMutableBufferPointer { bodies in
                for index in bodies.indices {
                    if bodies[index].isFixed {
                        bodies[index].velocityX = 0
                        bodies[index].velocityY = 0
                    }

                    if recordTrails && !bodies[index].isFixed {
                        bodies[index].trail.append(x: Float(bodies[index].x), y: Float(bodies[index].y))
                    } else if bodies[index].trail.count > 0 {
                        // Discarded the moment trails stop being recorded, whether the
                        // user switched them off or the count crossed the threshold.
                        // Left in place, every body drew a six-point streak from
                        // wherever it happened to be when recording stopped.
                        bodies[index].trail.removeAll()
                    }

                    if localDecaySpeed > 0 && bodies[index].lifespan == nil {
                        bodies[index].lifespan = Int((100 / localDecaySpeed).rounded(.down))
                    }

                    guard var remaining = bodies[index].lifespan else { continue }
                    remaining -= 1
                    bodies[index].lifespan = remaining
                    guard remaining <= 0 else { continue }

                    if let originX = bodies[index].originX, let originY = bodies[index].originY {
                        // Returned to its starting point rather than deleted.
                        //
                        // The lifetime is restored unconditionally. The web version only
                        // restored it when a maximum had been recorded, so without one
                        // the body was teleported home once and then frozen there for
                        // good — skipped by the force loop, never removed, but still
                        // drawn and still counted toward every detail threshold.
                        let restored = bodies[index].maxLife ?? 0
                        bodies[index].lifespan = restored > 0 ? restored : 100
                        // The trail has to go too, or the next frame draws a line from
                        // where it died all the way to where it has reappeared.
                        bodies[index].trail.removeAll()

                        let angle = localRNG.next() * Double.pi * 2
                        let speed = 2 + localRNG.next() * 7
                        bodies[index].x = originX + jsCos(angle) * 15
                        bodies[index].y = originY + jsSin(angle) * 15

                        if originY > worldHeight - 50 {
                            // A fountain at the floor sprays upward instead of outward.
                            let fountainAngle = -Double.pi / 2 + (localRNG.next() - 0.5) * 0.7
                            let fountainSpeed = localRNG.next() * 9 + 5
                            bodies[index].x = originX + (localRNG.next() - 0.5) * 30
                            bodies[index].y = originY
                            bodies[index].velocityX = jsCos(fountainAngle) * fountainSpeed
                            bodies[index].velocityY = jsSin(fountainAngle) * fountainSpeed
                        } else {
                            bodies[index].velocityX = jsCos(angle) * speed
                            bodies[index].velocityY = jsSin(angle) * speed
                        }
                    } else {
                        anyExpired = true
                    }
                }
            }
            rng = localRNG
        }

        if anyExpired {
            removeParticles { $0.hasExpired }
        }

        let count = particles.count
        guard count > 0 else { return }

        // Attractors are gathered by index, so the main loop can find them without
        // searching. There are only ever a handful.
        var attractorIndices: [Int] = []
        for index in 0 ..< count {
            let kind = particles[index].kind
            if kind == .blackhole || kind == .repulsor { attractorIndices.append(index) }
        }

        // MARK: Forces and integration

        let centreX = width / 2
        let centreY = height / 2
        // Pairwise charge interaction is quadratic, so it only runs for small fields.
        let doPairwise = count <= 300

        let worldWidth = width
        let worldHeight = height
        let localGravityX = gravityX
        let localGravityY = gravityY
        let localDamping = damping
        let localElasticity = elasticity
        let localElectrostatic = electrostaticFactor
        let localVortex = vortexForce
        let localMaxSpeed = maxSpeed
        let localBoundary = boundaryMode
        let localMouseMode = mouseMode
        let localMouseRadius = mouseRadius
        let localMouseMultiplier = mouseForceMultiplier
        let localParticleSize = particleSize
        var localRNG = rng
        var expiredByVoid = false

        particles.withUnsafeMutableBufferPointer { bodies in
            for i in 0 ..< bodies.count {
                if bodies[i].hasExpired { continue }

                // MARK: Black holes and repulsors

                for attractorIndex in attractorIndices {
                    if attractorIndex == i { continue }
                    if attractorIndex >= bodies.count { continue }

                    // Resolved once, with fallbacks. The web version guarded these in
                    // the event-horizon test but used them bare two lines later, and
                    // imported scenes assign unvalidated values — so a missing radius or
                    // mass wrote not-a-number straight into a position, which then
                    // spread to every other body through the distance terms.
                    let attractorRadius = bodies[attractorIndex].radius == 0 ? 12 : bodies[attractorIndex].radius
                    let attractorMass = bodies[attractorIndex].mass == 0 ? 80 : bodies[attractorIndex].mass
                    let attractorX = bodies[attractorIndex].x
                    let attractorY = bodies[attractorIndex].y
                    let attractorKind = bodies[attractorIndex].kind

                    let dx = attractorX - bodies[i].x
                    let dy = attractorY - bodies[i].y
                    // The added constant keeps the force finite at zero distance.
                    let distanceSquared = dx * dx + dy * dy + 10
                    let distance = distanceSquared.squareRoot()

                    if attractorKind == .blackhole {
                        let ownRadius = bodies[i].radius == 0 ? 2 : bodies[i].radius
                        if distance < attractorRadius + ownRadius + 2 {
                            // Crossed the event horizon: thrown back out, either into a
                            // wide orbit or along a polar jet.
                            let gravitationalConstant = attractorMass * 200
                            if localRNG.chance(0.15) {
                                let jetAngle = localRNG.next() * Double.pi * 2
                                let jetSpeed = (gravitationalConstant / 40).squareRoot() * 1.2
                                bodies[i].x = attractorX + jsCos(jetAngle) * (attractorRadius + 8)
                                bodies[i].y = attractorY + jsSin(jetAngle) * (attractorRadius + 8)
                                bodies[i].velocityX = jsCos(jetAngle) * jetSpeed
                                bodies[i].velocityY = jsSin(jetAngle) * jetSpeed
                            } else {
                                let orbitDistance = localRNG.next() * (min(worldWidth, worldHeight) * 0.4) + 40
                                let orbitAngle = localRNG.next() * Double.pi * 2
                                let orbitSpeed = (gravitationalConstant / orbitDistance).squareRoot()
                                bodies[i].x = attractorX + jsCos(orbitAngle) * orbitDistance
                                bodies[i].y = attractorY + jsSin(orbitAngle) * orbitDistance
                                bodies[i].velocityX = -jsSin(orbitAngle) * orbitSpeed
                                bodies[i].velocityY = jsCos(orbitAngle) * orbitSpeed
                            }
                            // Otherwise the trail stretches from the horizon to the new orbit.
                            bodies[i].trail.removeAll()
                            continue
                        }
                        let force = (attractorMass * 200) / distanceSquared
                        bodies[i].velocityX += (dx / distance) * force
                        bodies[i].velocityY += (dy / distance) * force
                    } else if attractorKind == .repulsor {
                        let force = (attractorMass * 150) / distanceSquared
                        bodies[i].velocityX -= (dx / distance) * force
                        bodies[i].velocityY -= (dy / distance) * force
                    }
                }

                // MARK: Vortex about the centre of the world

                if localVortex != 0 {
                    let dx = centreX - bodies[i].x
                    let dy = centreY - bodies[i].y
                    let distanceSquared = dx * dx + dy * dy + 20
                    let distance = distanceSquared.squareRoot()
                    let strength = (localVortex * 10) / distanceSquared
                    // A swirl, plus a weaker pull inward so bodies do not simply orbit
                    // forever at the radius they started at.
                    bodies[i].velocityX += (-dy / distance) * strength + (dx / distance) * (strength * 0.2)
                    bodies[i].velocityY += (dx / distance) * strength + (dy / distance) * (strength * 0.2)
                }

                // MARK: Charge

                if doPairwise {
                    for j in (i + 1) ..< bodies.count {
                        if bodies[j].kind == .blackhole || bodies[j].kind == .repulsor { continue }
                        // Zero charge is how a body opts out entirely.
                        if bodies[i].charge == 0 || bodies[j].charge == 0 { continue }

                        let dx = bodies[j].x - bodies[i].x
                        let dy = bodies[j].y - bodies[i].y
                        let distanceSquared = dx * dx + dy * dy + 10
                        let distance = distanceSquared.squareRoot()

                        let product = bodies[i].charge * bodies[j].charge
                        let force = (product * localElectrostatic) / distanceSquared
                        let forceX = (dx / distance) * force
                        let forceY = (dy / distance) * force

                        if !bodies[i].isFixed {
                            bodies[i].velocityX -= forceX / bodies[i].mass
                            bodies[i].velocityY -= forceY / bodies[i].mass
                        }
                        if !bodies[j].isFixed {
                            bodies[j].velocityX += forceX / bodies[j].mass
                            bodies[j].velocityY += forceY / bodies[j].mass
                        }
                    }
                }

                // MARK: The finger

                if mouseActive, let mouseX, let mouseY, !bodies[i].isFixed {
                    let dx = mouseX - bodies[i].x
                    let dy = mouseY - bodies[i].y
                    let distanceSquared = dx * dx + dy * dy + 30
                    let distance = distanceSquared.squareRoot()

                    // At the top of its range the reach is treated as unlimited.
                    let reach = localMouseRadius >= 800 ? Double.infinity : localMouseRadius
                    if distance <= reach {
                        let falloff = reach.isInfinite ? 1 : max(0, 1 - distance / reach)
                        let multiplier = localMouseMultiplier

                        switch localMouseMode {
                        case .attract:
                            let force = (1800 / distanceSquared) * (0.2 + 0.8 * falloff) * multiplier
                            bodies[i].velocityX += (dx / distance) * force
                            bodies[i].velocityY += (dy / distance) * force
                        case .repel, .hawk:
                            let force = (2000 / distanceSquared) * (0.2 + 0.8 * falloff) * multiplier
                            bodies[i].velocityX -= (dx / distance) * force
                            bodies[i].velocityY -= (dy / distance) * force
                        case .vortex:
                            let force = (1400 / distanceSquared) * (0.2 + 0.8 * falloff) * multiplier
                            bodies[i].velocityX += (-dy / distance) * force + (dx / distance) * (force * 0.1)
                            bodies[i].velocityY += (dx / distance) * force + (dy / distance) * (force * 0.1)
                        case .painter:
                            // Floored to a whole degree, as the web reference does
                            // before it builds its colour string.
                            let hue = (now / 10 + Double(i) * 5)
                                .truncatingRemainder(dividingBy: 360)
                                .rounded(.down)
                            bodies[i].color = PackedColor(hue: hue, saturation: 0.95, lightness: 0.65)
                        case .gravityWell:
                            let force = (3500 / distanceSquared) * (0.2 + 0.8 * falloff) * multiplier
                            bodies[i].velocityX += (dx / distance) * force - (dy / distance) * (force * 0.3)
                            bodies[i].velocityY += (dy / distance) * force + (dx / distance) * (force * 0.3)
                        case .freeze:
                            bodies[i].velocityX *= 0.7
                            bodies[i].velocityY *= 0.7
                        case .hyperDrive:
                            bodies[i].velocityX += (dx / distance) * (12 * multiplier)
                            bodies[i].velocityY += (dy / distance) * (12 * multiplier)
                            bodies[i].color = PackedColor(r: 0xF4, g: 0x3F, b: 0x5E)
                        case .emitter:
                            break
                        case .current, .wall, .source:
                            // These change the world rather than the bodies. Nothing happens under the
                            // finger; the bodies notice the wind, the walls and the sources next tick.
                            break
                        }
                    }
                }

                // MARK: Per-preset behaviour, gravity, and integration

                if !bodies[i].isFixed {
                    // Held to its origin by a spring. Gated on an explicit flag: the web
                    // version inferred it from "has an origin, ignores gravity and is
                    // charged", which also described seven orbital presets and crushed
                    // them inward with a force ten times stronger than their own physics.
                    if bodies[i].latticeBound, let originX = bodies[i].originX, let originY = bodies[i].originY {
                        bodies[i].velocityX += (originX - bodies[i].x) * 0.02
                        bodies[i].velocityY += (originY - bodies[i].y) * 0.02
                    }

                    // A waterfall pours from the top and is caught at the bottom.
                    if let originX = bodies[i].originX, bodies[i].originY == 20, bodies[i].y >= worldHeight - 10 {
                        bodies[i].x = originX + localRNG.next() * (worldWidth * 0.4)
                        bodies[i].y = 15
                        bodies[i].velocityY = localRNG.next() * 4 + 2
                        bodies[i].velocityX = (localRNG.next() - 0.5) * 1.5
                        bodies[i].trail.removeAll()
                    }

                    // The helix undulates and wraps around. Driven by an explicit strand
                    // marker: the web version compared the body's colour against two hex
                    // strings, so any tool that repainted it dropped it out of the helix
                    // permanently.
                    if let strand = bodies[i].helixStrand, bodies[i].velocityX > 0 {
                        if bodies[i].x > worldWidth - 10 {
                            bodies[i].x = 10
                            bodies[i].trail.removeAll()
                        }
                        let wavelength = 120.0
                        let angle = (bodies[i].x / wavelength) * Double.pi * 2
                        let targetY = worldHeight / 2 + jsSin(angle) * 50 * strand
                        bodies[i].velocityY += (targetY - bodies[i].y) * 0.2
                    }

                    // World gravity and air friction. Orbital bodies are exempt so their
                    // orbital energy is not continuously bled away.
                    if !bodies[i].ignoresGravity {
                        bodies[i].velocityX += localGravityX
                        bodies[i].velocityY += localGravityY
                        bodies[i].velocityX *= localDamping
                        bodies[i].velocityY *= localDamping
                    }

                    // The speed limit, applied to everything.
                    //
                    // This clamp used to sit inside the branch above, so it only reached
                    // orbital bodies: every ordinary one was uncapped despite the
                    // interface offering a single global slider, and that is also what
                    // let bodies outrun the wrapping boundary and leave the world.
                    let speedSquared = bodies[i].velocityX * bodies[i].velocityX
                        + bodies[i].velocityY * bodies[i].velocityY
                    let limitSquared = localMaxSpeed * localMaxSpeed
                    if speedSquared > limitSquared && speedSquared > 0 {
                        let scale = localMaxSpeed / speedSquared.squareRoot()
                        bodies[i].velocityX *= scale
                        bodies[i].velocityY *= scale
                    }

                    bodies[i].x += bodies[i].velocityX
                    bodies[i].y += bodies[i].velocityY
                }

                // MARK: The edge of the world

                // Pinned bodies are exempt. The web version ran this block for them too,
                // so a fixed black hole placed near an edge was shoved inward on its very
                // first step — and because their velocity is only zeroed at the top of
                // the tick, the bounce acted on whatever the force loop had accumulated
                // since.
                if bodies[i].isFixed {
                    bodies[i].velocityX = 0
                    bodies[i].velocityY = 0
                    continue
                }

                let radius = bodies[i].radius == 0 ? localParticleSize : bodies[i].radius

                switch localBoundary {
                case .bounce:
                    if bodies[i].x - radius < 0 {
                        bodies[i].x = radius
                        bodies[i].velocityX *= -localElasticity
                    } else if bodies[i].x + radius > worldWidth {
                        bodies[i].x = worldWidth - radius
                        bodies[i].velocityX *= -localElasticity
                    }
                    if bodies[i].y - radius < 0 {
                        bodies[i].y = radius
                        bodies[i].velocityY *= -localElasticity
                    } else if bodies[i].y + radius > worldHeight {
                        bodies[i].y = worldHeight - radius
                        bodies[i].velocityY *= -localElasticity
                    }

                case .wrap:
                    // True modulo. The web version corrected by a single add or subtract
                    // once per frame, so anything travelling more than a world-width per
                    // frame stayed outside the world permanently.
                    if worldWidth > 0 {
                        let wrapped = ((bodies[i].x.truncatingRemainder(dividingBy: worldWidth)) + worldWidth)
                            .truncatingRemainder(dividingBy: worldWidth)
                        if wrapped != bodies[i].x {
                            bodies[i].x = wrapped
                            bodies[i].trail.removeAll()
                        }
                    }
                    if worldHeight > 0 {
                        let wrapped = ((bodies[i].y.truncatingRemainder(dividingBy: worldHeight)) + worldHeight)
                            .truncatingRemainder(dividingBy: worldHeight)
                        if wrapped != bodies[i].y {
                            bodies[i].y = wrapped
                            bodies[i].trail.removeAll()
                        }
                    }

                case .void:
                    if bodies[i].x < -10 || bodies[i].x > worldWidth + 10
                        || bodies[i].y < -10 || bodies[i].y > worldHeight + 10
                    {
                        bodies[i].lifespan = 0
                        expiredByVoid = true
                    }
                }
            }
        }

        rng = localRNG

        if expiredByVoid {
            removeParticles { $0.hasExpired }
        }
    }

    /// Boids-style flocking: bodies steer toward their neighbours, match their
    /// heading, and keep their distance.
    func stepFlock() {
        // Capped, because this is quadratic in the number of bodies considered. The cap is a setting rather
        // than a constant: somebody with a hundred bodies can afford far more than somebody with a million,
        // and should not be held to a limit set for the second one.
        let tuned = flockSettings.sanitized
        let considered = min(particles.count, tuned.limit)
        guard considered > 1 else { return }

        let visionSquared = tuned.vision * tuned.vision
        let personalSquared = tuned.personalSpace * tuned.personalSpace
        let separationWeight = tuned.separation
        let alignmentWeight = tuned.alignment
        let cohesionWeight = tuned.cohesion

        particles.withUnsafeMutableBufferPointer { bodies in
            for i in 0 ..< considered {
                if bodies[i].isFixed { continue }

                var centreX = 0.0
                var centreY = 0.0
                var headingX = 0.0
                var headingY = 0.0
                var separationX = 0.0
                var separationY = 0.0
                var neighbours = 0.0

                for j in 0 ..< considered {
                    if i == j { continue }
                    // Pinned bodies are excluded. The web version averaged them into the
                    // flock's heading as though they were flying along with it.
                    if bodies[j].isFixed { continue }

                    let dx = bodies[j].x - bodies[i].x
                    let dy = bodies[j].y - bodies[i].y
                    let distanceSquared = dx * dx + dy * dy
                    // Out of sight, or so close the direction is meaningless.
                    if distanceSquared > visionSquared || distanceSquared < 0.01 { continue }

                    neighbours += 1
                    centreX += bodies[j].x
                    centreY += bodies[j].y
                    headingX += bodies[j].velocityX
                    headingY += bodies[j].velocityY

                    if distanceSquared < personalSquared {
                        // Divided by distance, so closer neighbours push harder. The web
                        // version accumulated the raw offset, which made separation
                        // *weaker* the closer two bodies came — backwards for collision
                        // avoidance, and why flocks clumped into a knot.
                        let distance = distanceSquared.squareRoot()
                        separationX -= dx / distance
                        separationY -= dy / distance
                    }
                }

                guard neighbours > 0 else { continue }
                // Separation is scaled up to compensate for being normalised.
                bodies[i].velocityX += (centreX / neighbours - bodies[i].x) * cohesionWeight
                    + (headingX / neighbours - bodies[i].velocityX) * alignmentWeight
                    + separationX * separationWeight
                bodies[i].velocityY += (centreY / neighbours - bodies[i].y) * cohesionWeight
                    + (headingY / neighbours - bodies[i].velocityY) * alignmentWeight
                    + separationY * separationWeight
            }
        }
    }

    /// Pulls sprung pairs toward their rest length. Cloth, rope and blobs.
    func stepSprings() {
        guard !springs.isEmpty else { return }
        let localSprings = springs

        particles.withUnsafeMutableBufferPointer { bodies in
            for spring in localSprings {
                guard spring.a >= 0, spring.a < bodies.count,
                      spring.b >= 0, spring.b < bodies.count
                else { continue }

                let dx = bodies[spring.b].x - bodies[spring.a].x
                let dy = bodies[spring.b].y - bodies[spring.a].y
                var distance = (dx * dx + dy * dy).squareRoot()
                if distance == 0 { distance = 0.001 }

                // A rest length of zero made the overstretch test true for every
                // distance, so a cloth spawned with no room to space itself out had no
                // working springs at all.
                if spring.rest > 0 && distance > spring.rest * 4.5 { continue }

                let scale = ((distance - spring.rest) / distance) * spring.k
                let forceX = dx * scale
                let forceY = dy * scale

                // Divided by mass, as the charge force is. Without it a heavy body
                // responded correctly to charge but far too strongly to a spring.
                if !bodies[spring.a].isFixed {
                    let mass = bodies[spring.a].mass
                    bodies[spring.a].velocityX += forceX / mass
                    bodies[spring.a].velocityY += forceY / mass
                }
                if !bodies[spring.b].isFixed {
                    let mass = bodies[spring.b].mass
                    bodies[spring.b].velocityX -= forceX / mass
                    bodies[spring.b].velocityY -= forceY / mass
                }
            }
        }
    }

    /// What the finger does to the swarm, and which way.
    ///
    /// The swarm only understands "pull toward" or "push away", so each mode has to map
    /// onto one of those or be left out. The web version treated everything except two
    /// modes as repulsion, so the painter, freeze and emitter tools — which mean
    /// something quite different for the object bodies — silently blew the swarm apart.
    private var swarmMouseEffect: (active: Bool, attract: Bool) {
        switch mouseMode {
        case .attract, .gravityWell, .hawk:
            return (true, true)
        case .repel, .hyperDrive:
            return (true, false)
        case .current, .wall, .source:
            // These change the world rather than the bodies. The bodies notice on the next tick, through the
            // painted wind, the walls and the sources — not through a force under the finger.
            return (false, false)
        case .vortex, .emitter, .painter, .freeze:
            // Nothing sensible to do to a million positions, so the swarm is left alone
            // rather than shoved by a tool that means something else.
            return (false, false)
        }
    }

    /// Runs one tick of the swarm.
    func stepSwarm(mouseX: Double?, mouseY: Double?, mouseActive: Bool) {
        guard swarm.count > 0 else { return }

        // Both of these change velocity and nothing else, and both run *before* the main pass, so that
        // everything it does afterwards — the speed limit, the walls, the finger — sees their
        // contribution and can moderate it. A pass that moved bodies itself could push one through a
        // wall with nothing left to notice.
        //
        // The liquid first. It is the one that resists being squashed, and running the pull first would
        // mean a tick where bodies were drawn together and the liquid only got to object the tick after.
        if fluidEnabled {
            fluid.step(swarm: swarm, settings: fluidSettings, width: width, height: height)
        }
        if nbodyEnabled {
            bodyGravity.step(
                swarm: swarm,
                settings: bodyGravitySettings,
                width: width,
                height: height
            )
        }
        if flowEnabled {
            flow.step(swarm: swarm, settings: flowSettings, time: elapsedSeconds)
        }
        if !storedCurrent.isEmpty {
            SwarmDrawnWorld.applyCurrent(
                storedCurrent,
                to: swarm,
                settings: currentSettings,
                width: width,
                height: height
            )
        }
        if !writtenForceAcross.isEmpty || !writtenForceDown.isEmpty {
            writtenForce.step(
                swarm: swarm,
                acrossward: writtenForceAcross,
                downward: writtenForceDown,
                strength: writtenForceStrength,
                width: width,
                height: height,
                time: elapsedSeconds
            )
        }

        let effect = swarmMouseEffect
        swarm.step(Swarm.StepOptions(
            width: width,
            height: height,
            gravityX: gravityX,
            gravityY: gravityY,
            damping: damping,
            elasticity: elasticity,
            collide: collisionsEnabled,
            maxSpeed: maxSpeed,
            boundaryMode: boundaryMode,
            mouseX: mouseX ?? lastMouseX,
            mouseY: mouseY ?? lastMouseY,
            mouseActive: mouseActive && effect.active,
            mouseForce: mouseForceMultiplier * (mouseMode == .hawk ? 2.4 : 1),
            mouseRadius: mouseRadius,
            attract: effect.attract,
            contact: contactSettings.sanitized
        ))

        // After the move, because a wall is about where something has got to rather than where it was
        // going — and after the crowd has pushed itself apart, so a body shoved into a wall by its
        // neighbours is put back rather than left inside it until the next tick.
        if !storedWalls.isEmpty {
            previousSwarmPositions.withUnsafeBufferPointer { previous in
                SwarmDrawnWorld.applyWalls(
                    storedWalls,
                    to: swarm,
                    previousPositions: previous.count >= swarm.count * 2 ? previous.baseAddress : nil,
                    settings: wallSettings,
                    width: width,
                    height: height
                )
            }
        }
    }

    /// Remembers where every swarm body is, so a wall can tell which side it came from.
    ///
    /// Only when there are walls. At a million bodies this is eight megabytes, and copying it every tick for
    /// a field with no walls in it would be eight megabytes of work for nothing.
    func rememberSwarmPositions() {
        guard !storedWalls.isEmpty, swarm.count > 0 else {
            if !previousSwarmPositions.isEmpty { previousSwarmPositions.removeAll(keepingCapacity: true) }
            return
        }
        let needed = swarm.count * 2
        if previousSwarmPositions.count < needed {
            previousSwarmPositions.append(
                contentsOf: repeatElement(0, count: needed - previousSwarmPositions.count)
            )
        }
        previousSwarmPositions.withUnsafeMutableBufferPointer { out in
            guard let base = out.baseAddress else { return }
            base.update(from: swarm.positions, count: needed)
        }
    }
}
