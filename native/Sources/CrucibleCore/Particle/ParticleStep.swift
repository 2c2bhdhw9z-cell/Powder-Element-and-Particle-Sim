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
        let localMouseRadius = mouseRadius.isNaN ? 0 : mouseRadius
        let localBrushStrength = ParticleBrush.defaultStrength * (mouseForceMultiplier.isFinite ? mouseForceMultiplier : 1)
        let localBrushUnit = brushUnit
        let localLayoutWidth = layoutWidth
        let localSpan = patternSpan
        let localCurrent = storedCurrent
        let hasCurrent = !storedCurrent.isEmpty
        let localCurrentStrength = storedCurrentSettings.sanitized.strength
        let wallSegments = SwarmDrawnWorld.segments(for: storedWalls, width: width, height: height)
        let localWallSettings = storedWallSettings.sanitized
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
                                // The screen's span rather than the world's, so a black hole in a world grown by
                                // zooming out throws bodies into the orbits it was laid out with.
                                let orbitDistance = localRNG.next() * (localSpan * 0.4) + 40
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

                // Whether the finger is freezing this body. It is stopped again just before it moves, after
                // gravity, a lattice's springs and a helix's pull have all acted — stopped only here, a frozen
                // body crept downward at the pace of this moment's gravity.
                var frozen = false
                if mouseActive, let mouseX, let mouseY, !bodies[i].isFixed {
                    if localMouseMode == .painter {
                        // Unchanged, including how far it reaches: painting moves nothing, so there was nothing
                        // wrong with it, and the recorded comparison of a repainted helix still holds it exactly.
                        let dx = mouseX - bodies[i].x
                        let dy = mouseY - bodies[i].y
                        let distance = (dx * dx + dy * dy + 30).squareRoot()
                        if distance <= localMouseRadius {
                            bodies[i].color = ParticleBrush.paintColor(now: now, index: i)
                        }
                    } else if ParticleBrush.touchesBodies(localMouseMode) {
                        // Built-Helion's brush, the same one the crowd feels. See `ParticleBrush`.
                        let effect = ParticleBrush.effect(
                            localMouseMode,
                            atX: bodies[i].x,
                            y: bodies[i].y,
                            fingerX: mouseX,
                            fingerY: mouseY,
                            reach: localMouseRadius,
                            strength: localBrushStrength,
                            unit: localBrushUnit
                        )
                        if effect.inReach {
                            if effect.stops {
                                bodies[i].velocityX = 0
                                bodies[i].velocityY = 0
                                frozen = true
                            } else {
                                bodies[i].velocityX += effect.velocityX
                                bodies[i].velocityY += effect.velocityY
                                if localMouseMode == .hyperDrive { bodies[i].color = ParticleBrush.rushColor }
                            }
                        }
                    }
                }

                // MARK: Painted wind

                // The object bodies feel it as the crowd does. They used to ignore it entirely, so painting wind
                // across a galaxy or a black hole did nothing to it at all.
                if hasCurrent, !bodies[i].isFixed, worldWidth > 0, worldHeight > 0 {
                    let push = localCurrent.sample(
                        atFractionX: bodies[i].x / worldWidth,
                        y: bodies[i].y / worldHeight
                    )
                    bodies[i].velocityX += push.x * localCurrentStrength
                    bodies[i].velocityY += push.y * localCurrentStrength
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
                        bodies[i].x = originX + localRNG.next() * (localLayoutWidth * 0.4)
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
                        // The strand's size is its scale: one for the original, larger on a larger field.
                        let wavelength = 120.0 * max(1, abs(strand))
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

                    if frozen {
                        bodies[i].velocityX = 0
                        bodies[i].velocityY = 0
                    }

                    let cameFromX = bodies[i].x
                    let cameFromY = bodies[i].y
                    bodies[i].x += bodies[i].velocityX
                    bodies[i].y += bodies[i].velocityY

                    // Walls stop the object bodies as they stop the crowd. They used to pass straight through, so
                    // a wall drawn across a galaxy was a line drawn on top of it and nothing more.
                    if !wallSegments.isEmpty {
                        var x = bodies[i].x
                        var y = bodies[i].y
                        var velX = bodies[i].velocityX
                        var velY = bodies[i].velocityY
                        SwarmDrawnWorld.collide(
                            x: &x,
                            y: &y,
                            velocityX: &velX,
                            velocityY: &velY,
                            cameFromX: cameFromX,
                            cameFromY: cameFromY,
                            segments: wallSegments,
                            thickness: localWallSettings.thickness + max(0, bodies[i].radius.isFinite ? bodies[i].radius : 0),
                            bounciness: localWallSettings.bounciness,
                            friction: localWallSettings.friction
                        )
                        bodies[i].x = x
                        bodies[i].y = y
                        bodies[i].velocityX = velX
                        bodies[i].velocityY = velY
                    }
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

    /// Runs one tick of the swarm.
    func stepSwarm(mouseX: Double?, mouseY: Double?, mouseActive: Bool, now: Double = 0) {
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

        // Black holes and repulsors reach the crowd as well as the object bodies. See
        // `Swarm.applyAttractors` for why.
        var attractors: [Swarm.Attractor] = []
        for body in particles where body.kind == .blackhole || body.kind == .repulsor {
            guard body.x.isFinite, body.y.isFinite else { continue }
            attractors.append(Swarm.Attractor(
                x: body.x,
                y: body.y,
                mass: body.mass,
                radius: body.radius,
                repels: body.kind == .repulsor
            ))
        }
        if !attractors.isEmpty {
            swarm.applyAttractors(attractors, span: patternSpan, rng: &rng)
        }

        // The finger. The same rule, and the same numbers, as for the object bodies — Built-Helion's brush.
        // The crowd used to have one of its own that pushed with eight hundredths of a pixel a moment and knew
        // nothing of swirling, freezing or painting, so on every arrangement made of the crowd the tools
        // looked broken. See `ParticleBrush`.
        let fingerX = mouseX ?? lastMouseX
        let fingerY = mouseY ?? lastMouseY
        let reach = mouseRadius.isNaN ? 0 : mouseRadius
        if mouseActive {
            swarm.applyBrush(
                mouseMode,
                fingerX: fingerX,
                fingerY: fingerY,
                reach: reach,
                strength: ParticleBrush.defaultStrength * (mouseForceMultiplier.isFinite ? mouseForceMultiplier : 1),
                unit: brushUnit,
                now: now
            )
        }
        // Freezing is finished inside the step, after gravity and the shapes' hold have had their say, so that
        // what it stops stays stopped. See `Swarm.StepOptions.freezeReach`.
        let freezing = mouseActive && mouseMode == .freeze

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
            contact: contactSettings.sanitized,
            deferAgeing: !storedWalls.isEmpty,
            freezeX: freezing ? fingerX : 0,
            freezeY: freezing ? fingerY : 0,
            freezeReach: freezing ? reach : 0
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
            if swarm.hasMortalBodies { swarm.age(by: 1) }
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
