// The particle field's physics in 3D.
//
// Every pass here is its flat counterpart in `ParticleStep.swift` with depth added throughout, and is used
// only while the field is in 3D. They are separate passes rather than one pass with "and in depth" threaded
// through it, so that nothing about depth can change a flat field by so much as a rounding: the flat passes
// are exactly what they were, and every recorded comparison against the web version still holds them to it.

extension ParticleEngine {
    // MARK: - The emitter tool

    /// The emitter tool's spray, in depth: out in every direction from the place under the finger.
    func spawnEmitterInDepth(at x: Double, y: Double, z: Double) {
        for _ in 0 ..< 6 {
            let radius = rng.next() * 3 + 1
            let hue = rng.next() * 360
            let speed = rng.next() * 6 + 1
            let direction = randomDirection()
            addParticle(
                x: x,
                y: y,
                velocityX: direction.x * speed,
                velocityY: direction.y * speed,
                radius: radius,
                color: PackedColor(hue: hue, saturation: 0.9, lightness: 0.65),
                z: z,
                velocityZ: direction.z * speed
            )
        }
    }

    /// A direction chosen evenly over every way there is to go.
    func randomDirection() -> (x: Double, y: Double, z: Double) {
        let rise = rng.next() * 2 - 1
        let turn = rng.next() * Double.pi * 2
        let across = (1 - rise * rise).squareRoot()
        return (jsCos(turn) * across, rise, jsSin(turn) * across)
    }

    // MARK: - The individual bodies

    /// One moment of the individual bodies in a field with depth: lifetimes, forces, moving, the box's walls.
    func stepParticlesInDepth(mouseActive: Bool, now: Double) {
        let halfDepth = self.halfDepth
        let recordTrails = showTrails && particles.count <= 1000
        var anyExpired = false

        // MARK: Lifetimes, trails and recycling

        do {
            var localRNG = rng
            let worldHeight = height
            let localDecaySpeed = decaySpeed
            particles.withUnsafeMutableBufferPointer { bodies in
                for index in bodies.indices {
                    if bodies[index].isFixed {
                        bodies[index].velocityX = 0
                        bodies[index].velocityY = 0
                        bodies[index].velocityZ = 0
                    }
                    if recordTrails && !bodies[index].isFixed {
                        bodies[index].trail.append(
                            x: Float(bodies[index].x),
                            y: Float(bodies[index].y),
                            z: Float(bodies[index].z)
                        )
                    } else if bodies[index].trail.count > 0 {
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
                        let originZ = bodies[index].originZ
                        let restored = bodies[index].maxLife ?? 0
                        bodies[index].lifespan = restored > 0 ? restored : 100
                        bodies[index].trail.removeAll()
                        // Out in any direction from where it began.
                        let rise = localRNG.next() * 2 - 1
                        let turn = localRNG.next() * Double.pi * 2
                        let across = (1 - rise * rise).squareRoot()
                        let speed = 2 + localRNG.next() * 7
                        if originY > worldHeight - 50 {
                            // A fountain at the floor sprays upward in a cone.
                            let lean = localRNG.next() * 0.35
                            let fountainSpeed = localRNG.next() * 9 + 5
                            bodies[index].x = originX + (localRNG.next() - 0.5) * 30
                            bodies[index].y = originY
                            bodies[index].z = originZ + (localRNG.next() - 0.5) * 30
                            bodies[index].velocityX = jsCos(turn) * jsSin(lean) * fountainSpeed
                            bodies[index].velocityY = -jsCos(lean) * fountainSpeed
                            bodies[index].velocityZ = jsSin(turn) * jsSin(lean) * fountainSpeed
                        } else {
                            bodies[index].x = originX + jsCos(turn) * across * 15
                            bodies[index].y = originY + rise * 15
                            bodies[index].z = originZ + jsSin(turn) * across * 15
                            bodies[index].velocityX = jsCos(turn) * across * speed
                            bodies[index].velocityY = rise * speed
                            bodies[index].velocityZ = jsSin(turn) * across * speed
                        }
                    } else {
                        anyExpired = true
                    }
                }
            }
            rng = localRNG
        }
        if anyExpired { removeParticles { $0.hasExpired } }

        let count = particles.count
        guard count > 0 else { return }

        var attractorIndices: [Int] = []
        for index in 0 ..< count {
            let kind = particles[index].kind
            if kind == .blackhole || kind == .repulsor { attractorIndices.append(index) }
        }

        // MARK: Forces and moving

        let centreX = width / 2
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
        let ray = mouseActive ? activeFingerRay : nil
        var localRNG = rng
        var expiredByVoid = false

        particles.withUnsafeMutableBufferPointer { bodies in
            for i in 0 ..< bodies.count {
                if bodies[i].hasExpired { continue }

                // MARK: Black holes and repulsors

                for attractorIndex in attractorIndices {
                    if attractorIndex == i || attractorIndex >= bodies.count { continue }
                    let attractorRadius = bodies[attractorIndex].radius == 0 ? 12 : bodies[attractorIndex].radius
                    let attractorMass = bodies[attractorIndex].mass == 0 ? 80 : bodies[attractorIndex].mass
                    let attractorX = bodies[attractorIndex].x
                    let attractorY = bodies[attractorIndex].y
                    let attractorZ = bodies[attractorIndex].z
                    let dx = attractorX - bodies[i].x
                    let dy = attractorY - bodies[i].y
                    let dz = attractorZ - bodies[i].z
                    let distanceSquared = dx * dx + dy * dy + dz * dz + 10
                    let distance = distanceSquared.squareRoot()

                    if bodies[attractorIndex].kind == .blackhole {
                        let ownRadius = bodies[i].radius == 0 ? 2 : bodies[i].radius
                        if distance < attractorRadius + ownRadius + 2 {
                            let gravitationalConstant = attractorMass * 200
                            if localRNG.chance(0.15) {
                                // A jet, straight up or down out of the disc.
                                let up: Double = localRNG.next() < 0.5 ? -1 : 1
                                let jetSpeed = (gravitationalConstant / 40).squareRoot() * 1.2
                                let lean = localRNG.next() * Double.pi * 2
                                let spread = 0.12 * localRNG.next()
                                bodies[i].x = attractorX + jsCos(lean) * spread * attractorRadius
                                bodies[i].y = attractorY + up * (attractorRadius + 8)
                                bodies[i].z = attractorZ + jsSin(lean) * spread * attractorRadius
                                bodies[i].velocityX = jsCos(lean) * spread * jetSpeed
                                bodies[i].velocityY = up * jetSpeed
                                bodies[i].velocityZ = jsSin(lean) * spread * jetSpeed
                            } else {
                                // Back out into a level orbit, which is where every disc in depth lies.
                                let orbitDistance = localRNG.next() * (localSpan * 0.4) + 40
                                let orbitAngle = localRNG.next() * Double.pi * 2
                                let orbitSpeed = (gravitationalConstant / orbitDistance).squareRoot()
                                bodies[i].x = attractorX + jsCos(orbitAngle) * orbitDistance
                                bodies[i].y = attractorY
                                bodies[i].z = attractorZ + jsSin(orbitAngle) * orbitDistance
                                bodies[i].velocityX = -jsSin(orbitAngle) * orbitSpeed
                                bodies[i].velocityY = 0
                                bodies[i].velocityZ = jsCos(orbitAngle) * orbitSpeed
                            }
                            bodies[i].trail.removeAll()
                            continue
                        }
                        let force = (attractorMass * 200) / distanceSquared
                        bodies[i].velocityX += (dx / distance) * force
                        bodies[i].velocityY += (dy / distance) * force
                        bodies[i].velocityZ += (dz / distance) * force
                    } else if bodies[attractorIndex].kind == .repulsor {
                        let force = (attractorMass * 150) / distanceSquared
                        bodies[i].velocityX -= (dx / distance) * force
                        bodies[i].velocityY -= (dy / distance) * force
                        bodies[i].velocityZ -= (dz / distance) * force
                    }
                }

                // MARK: The swirl, round the upright through the middle

                // Level, like water going down a plughole: in depth the swirl turns everything round the
                // upright line through the middle of the box, with a weaker pull in toward it.
                if localVortex != 0 {
                    let dx = centreX - bodies[i].x
                    let dz = -bodies[i].z
                    let distanceSquared = dx * dx + dz * dz + 20
                    let distance = distanceSquared.squareRoot()
                    let strength = (localVortex * 10) / distanceSquared
                    bodies[i].velocityX += (-dz / distance) * strength + (dx / distance) * (strength * 0.2)
                    bodies[i].velocityZ += (dx / distance) * strength + (dz / distance) * (strength * 0.2)
                }

                // MARK: Charge

                if doPairwise {
                    for j in (i + 1) ..< bodies.count {
                        if bodies[j].kind == .blackhole || bodies[j].kind == .repulsor { continue }
                        if bodies[i].charge == 0 || bodies[j].charge == 0 { continue }
                        let dx = bodies[j].x - bodies[i].x
                        let dy = bodies[j].y - bodies[i].y
                        let dz = bodies[j].z - bodies[i].z
                        let distanceSquared = dx * dx + dy * dy + dz * dz + 10
                        let distance = distanceSquared.squareRoot()
                        let force = (bodies[i].charge * bodies[j].charge * localElectrostatic) / distanceSquared
                        let forceX = (dx / distance) * force
                        let forceY = (dy / distance) * force
                        let forceZ = (dz / distance) * force
                        if !bodies[i].isFixed {
                            bodies[i].velocityX -= forceX / bodies[i].mass
                            bodies[i].velocityY -= forceY / bodies[i].mass
                            bodies[i].velocityZ -= forceZ / bodies[i].mass
                        }
                        if !bodies[j].isFixed {
                            bodies[j].velocityX += forceX / bodies[j].mass
                            bodies[j].velocityY += forceY / bodies[j].mass
                            bodies[j].velocityZ += forceZ / bodies[j].mass
                        }
                    }
                }

                // MARK: The finger

                var frozen = false
                if let ray, !bodies[i].isFixed, ParticleBrush.touchesBodies(localMouseMode) {
                    let effect = ParticleBrush.effect(
                        localMouseMode,
                        atX: bodies[i].x,
                        y: bodies[i].y,
                        z: bodies[i].z,
                        ray: ray,
                        reach: localMouseRadius,
                        strength: localBrushStrength,
                        unit: localBrushUnit
                    )
                    if effect.inReach {
                        if effect.stops {
                            bodies[i].velocityX = 0
                            bodies[i].velocityY = 0
                            bodies[i].velocityZ = 0
                            frozen = true
                        } else if localMouseMode == .painter {
                            bodies[i].color = ParticleBrush.paintColor(now: now, index: i)
                        } else {
                            bodies[i].velocityX += effect.velocityX
                            bodies[i].velocityY += effect.velocityY
                            bodies[i].velocityZ += effect.velocityZ
                            if localMouseMode == .hyperDrive { bodies[i].color = ParticleBrush.rushColor }
                        }
                    }
                }

                // MARK: Painted wind — painted on the screen, so the same at every depth

                if hasCurrent, !bodies[i].isFixed, worldWidth > 0, worldHeight > 0 {
                    let push = localCurrent.sample(atFractionX: bodies[i].x / worldWidth, y: bodies[i].y / worldHeight)
                    bodies[i].velocityX += push.x * localCurrentStrength
                    bodies[i].velocityY += push.y * localCurrentStrength
                }

                // MARK: Per-arrangement behaviour, gravity, and moving

                if !bodies[i].isFixed {
                    if bodies[i].latticeBound, let originX = bodies[i].originX, let originY = bodies[i].originY {
                        bodies[i].velocityX += (originX - bodies[i].x) * 0.02
                        bodies[i].velocityY += (originY - bodies[i].y) * 0.02
                        bodies[i].velocityZ += (bodies[i].originZ - bodies[i].z) * 0.02
                    }

                    // A waterfall pours from the top across its whole depth and is caught at the bottom.
                    if let originX = bodies[i].originX, bodies[i].originY == 20, bodies[i].y >= worldHeight - 10 {
                        bodies[i].x = originX + localRNG.next() * (localLayoutWidth * 0.4)
                        bodies[i].y = 15
                        bodies[i].z = bodies[i].originZ + (localRNG.next() - 0.5) * localSpan * 0.4
                        bodies[i].velocityY = localRNG.next() * 4 + 2
                        bodies[i].velocityX = (localRNG.next() - 0.5) * 1.5
                        bodies[i].velocityZ = (localRNG.next() - 0.5) * 1.5
                        bodies[i].trail.removeAll()
                    }

                    // The helix, as a real one: each strand winds round the line through the middle, the two
                    // half a turn apart, so from the side it is the flat helix and from the end a circle.
                    if let strand = bodies[i].helixStrand, bodies[i].velocityX > 0 {
                        if bodies[i].x > worldWidth - 10 {
                            bodies[i].x = 10
                            bodies[i].trail.removeAll()
                        }
                        let wavelength = 120.0 * max(1, abs(strand))
                        let angle = (bodies[i].x / wavelength) * Double.pi * 2
                        let targetY = worldHeight / 2 + jsSin(angle) * 50 * strand
                        let targetZ = jsCos(angle) * 50 * strand
                        bodies[i].velocityY += (targetY - bodies[i].y) * 0.2
                        bodies[i].velocityZ += (targetZ - bodies[i].z) * 0.2
                    }

                    if !bodies[i].ignoresGravity {
                        bodies[i].velocityX += localGravityX
                        bodies[i].velocityY += localGravityY
                        bodies[i].velocityX *= localDamping
                        bodies[i].velocityY *= localDamping
                        bodies[i].velocityZ *= localDamping
                    }

                    let speedSquared = bodies[i].velocityX * bodies[i].velocityX
                        + bodies[i].velocityY * bodies[i].velocityY
                        + bodies[i].velocityZ * bodies[i].velocityZ
                    let limitSquared = localMaxSpeed * localMaxSpeed
                    if speedSquared > limitSquared && speedSquared > 0 {
                        let scale = localMaxSpeed / speedSquared.squareRoot()
                        bodies[i].velocityX *= scale
                        bodies[i].velocityY *= scale
                        bodies[i].velocityZ *= scale
                    }

                    if frozen {
                        bodies[i].velocityX = 0
                        bodies[i].velocityY = 0
                        bodies[i].velocityZ = 0
                    }

                    let cameFromX = bodies[i].x
                    let cameFromY = bodies[i].y
                    bodies[i].x += bodies[i].velocityX
                    bodies[i].y += bodies[i].velocityY
                    bodies[i].z += bodies[i].velocityZ

                    // Walls reach all the way through the box, so only where a body is across and down matters.
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

                // MARK: The walls of the box

                if bodies[i].isFixed {
                    bodies[i].velocityX = 0
                    bodies[i].velocityY = 0
                    bodies[i].velocityZ = 0
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
                    if bodies[i].z - radius < -halfDepth {
                        bodies[i].z = -halfDepth + radius
                        bodies[i].velocityZ *= -localElasticity
                    } else if bodies[i].z + radius > halfDepth {
                        bodies[i].z = halfDepth - radius
                        bodies[i].velocityZ *= -localElasticity
                    }

                case .wrap:
                    func wrap(_ value: Double, _ low: Double, _ span: Double) -> Double {
                        guard span > 0 else { return value }
                        let shifted = value - low
                        return ((shifted.truncatingRemainder(dividingBy: span)) + span)
                            .truncatingRemainder(dividingBy: span) + low
                    }
                    let x = wrap(bodies[i].x, 0, worldWidth)
                    let y = wrap(bodies[i].y, 0, worldHeight)
                    let z = wrap(bodies[i].z, -halfDepth, halfDepth * 2)
                    if x != bodies[i].x || y != bodies[i].y || z != bodies[i].z {
                        bodies[i].x = x
                        bodies[i].y = y
                        bodies[i].z = z
                        bodies[i].trail.removeAll()
                    }

                case .void:
                    if bodies[i].x < -10 || bodies[i].x > worldWidth + 10
                        || bodies[i].y < -10 || bodies[i].y > worldHeight + 10
                        || bodies[i].z < -halfDepth - 10 || bodies[i].z > halfDepth + 10
                    {
                        bodies[i].lifespan = 0
                        expiredByVoid = true
                    }
                }
            }
        }

        rng = localRNG
        if expiredByVoid { removeParticles { $0.hasExpired } }
    }

    /// Flocking in depth: the flat rules, with neighbours and headings measured in all three directions.
    func stepFlockInDepth() {
        let tuned = flockSettings.sanitized
        let considered = min(particles.count, tuned.limit)
        guard considered > 1 else { return }
        let visionSquared = tuned.vision * tuned.vision
        let personalSquared = tuned.personalSpace * tuned.personalSpace

        particles.withUnsafeMutableBufferPointer { bodies in
            for i in 0 ..< considered {
                if bodies[i].isFixed { continue }
                var centreX = 0.0, centreY = 0.0, centreZ = 0.0
                var headingX = 0.0, headingY = 0.0, headingZ = 0.0
                var separationX = 0.0, separationY = 0.0, separationZ = 0.0
                var neighbours = 0.0
                for j in 0 ..< considered {
                    if i == j || bodies[j].isFixed { continue }
                    let dx = bodies[j].x - bodies[i].x
                    let dy = bodies[j].y - bodies[i].y
                    let dz = bodies[j].z - bodies[i].z
                    let distanceSquared = dx * dx + dy * dy + dz * dz
                    if distanceSquared > visionSquared || distanceSquared < 0.01 { continue }
                    neighbours += 1
                    centreX += bodies[j].x
                    centreY += bodies[j].y
                    centreZ += bodies[j].z
                    headingX += bodies[j].velocityX
                    headingY += bodies[j].velocityY
                    headingZ += bodies[j].velocityZ
                    if distanceSquared < personalSquared {
                        let distance = distanceSquared.squareRoot()
                        separationX -= dx / distance
                        separationY -= dy / distance
                        separationZ -= dz / distance
                    }
                }
                guard neighbours > 0 else { continue }
                bodies[i].velocityX += (centreX / neighbours - bodies[i].x) * tuned.cohesion
                    + (headingX / neighbours - bodies[i].velocityX) * tuned.alignment
                    + separationX * tuned.separation
                bodies[i].velocityY += (centreY / neighbours - bodies[i].y) * tuned.cohesion
                    + (headingY / neighbours - bodies[i].velocityY) * tuned.alignment
                    + separationY * tuned.separation
                bodies[i].velocityZ += (centreZ / neighbours - bodies[i].z) * tuned.cohesion
                    + (headingZ / neighbours - bodies[i].velocityZ) * tuned.alignment
                    + separationZ * tuned.separation
            }
        }
    }

    /// Springs in depth: the flat rule, with the length measured in all three directions.
    func stepSpringsInDepth() {
        guard !springs.isEmpty else { return }
        let localSprings = springs
        particles.withUnsafeMutableBufferPointer { bodies in
            for spring in localSprings {
                guard spring.a >= 0, spring.a < bodies.count, spring.b >= 0, spring.b < bodies.count else { continue }
                let dx = bodies[spring.b].x - bodies[spring.a].x
                let dy = bodies[spring.b].y - bodies[spring.a].y
                let dz = bodies[spring.b].z - bodies[spring.a].z
                var distance = (dx * dx + dy * dy + dz * dz).squareRoot()
                if distance == 0 { distance = 0.001 }
                if spring.rest > 0 && distance > spring.rest * 4.5 { continue }
                let scale = ((distance - spring.rest) / distance) * spring.k
                if !bodies[spring.a].isFixed {
                    let mass = bodies[spring.a].mass
                    bodies[spring.a].velocityX += dx * scale / mass
                    bodies[spring.a].velocityY += dy * scale / mass
                    bodies[spring.a].velocityZ += dz * scale / mass
                }
                if !bodies[spring.b].isFixed {
                    let mass = bodies[spring.b].mass
                    bodies[spring.b].velocityX -= dx * scale / mass
                    bodies[spring.b].velocityY -= dy * scale / mass
                    bodies[spring.b].velocityZ -= dz * scale / mass
                }
            }
        }
    }

    // MARK: - The crowd

    /// One moment of the crowd in a field with depth.
    func stepSwarmInDepth(mouseActive: Bool, now: Double) {
        guard swarm.count > 0 else { return }
        let depth = worldDepth

        if fluidEnabled {
            depthFluid.step(swarm: swarm, settings: fluidSettings, width: width, height: height)
        }
        if nbodyEnabled {
            depthGravity.step(swarm: swarm, settings: bodyGravitySettings, width: width, height: height, depth: depth)
        }
        if flowEnabled {
            flow.stepInDepth(swarm: swarm, settings: flowSettings, time: elapsedSeconds)
        }
        if !storedCurrent.isEmpty {
            // Painted on the screen, so the same at every depth.
            SwarmDrawnWorld.applyCurrent(storedCurrent, to: swarm, settings: currentSettings, width: width, height: height)
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

        var attractors: [Swarm.Attractor] = []
        for body in particles where body.kind == .blackhole || body.kind == .repulsor {
            guard body.x.isFinite, body.y.isFinite, body.z.isFinite else { continue }
            attractors.append(Swarm.Attractor(
                x: body.x, y: body.y, mass: body.mass, radius: body.radius,
                repels: body.kind == .repulsor, z: body.z
            ))
        }
        if !attractors.isEmpty {
            swarm.applyAttractorsInDepth(attractors, span: patternSpan, rng: &rng)
        }

        // Whatever the arrangement itself does to the crowd in depth: a strange attractor's flow, and so on.
        stepArrangementInDepth()

        let reach = mouseRadius.isNaN ? 0 : mouseRadius
        let ray = mouseActive ? activeFingerRay : nil
        if let ray {
            swarm.applyBrushInDepth(
                mouseMode,
                ray: ray,
                reach: reach,
                strength: ParticleBrush.defaultStrength * (mouseForceMultiplier.isFinite ? mouseForceMultiplier : 1),
                unit: brushUnit,
                now: now
            )
        }
        let freezing = ray != nil && mouseMode == .freeze

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
            freezeReach: freezing ? reach : 0,
            depth: depth,
            freezeRay: freezing ? ray : nil
        ))

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

    // MARK: - Sources

    /// Sources pouring in depth: from the middle of the box, spreading a little into and out of it as well as
    /// across, so a stream has a thickness rather than being a sheet a single body thick.
    func stepEmittersInDepth() {
        guard !storedEmitters.isEmpty, width > 0, height > 0 else { return }
        let budget = maxParticles - particles.count
        guard budget > swarm.count else { return }
        let pouredRole: Swarm.Role = storedJoinsArrangement && arrangementDetails?.joining == .orbit ? .orbits : []
        let pouredSize = storedMatchesArrangementSize && storedArrangement != nil ? arrangementBodySize : 0
        for index in storedEmitters.indices {
            var emitter = storedEmitters[index].sanitized
            defer { storedEmitters[index] = emitter }
            guard emitter.isRunning, emitter.rate > 0 else { continue }
            emitter.owed += emitter.rate / 60
            var toEmit = Int(emitter.owed)
            guard toEmit > 0 else { continue }
            emitter.owed -= Double(toEmit)
            toEmit = min(toEmit, 400)
            let atX = emitter.atFractionX * width
            let atY = emitter.atFractionY * height
            for _ in 0 ..< toEmit {
                let angle = emitter.direction + (rng.next() - 0.5) * 2 * emitter.spread
                let lean = (rng.next() - 0.5) * 2 * emitter.spread
                let speed = emitter.speed * (1 + (rng.next() - 0.5) * 2 * emitter.speedVariation)
                let weight = emitter.weight * (1 + (rng.next() - 0.5) * 2 * emitter.weightVariation)
                let hue = emitter.hue >= 0 ? emitter.hue : rng.next() * 360
                let flat = jsCos(lean)
                let placed = swarm.append(
                    x: atX,
                    y: atY,
                    velocityX: jsCos(angle) * speed * flat,
                    velocityY: jsSin(angle) * speed * flat,
                    color: PackedColor(hue: hue, saturation: 0.85, lightness: 0.62).packedRGBA,
                    budget: budget,
                    mass: weight,
                    life: emitter.lifespan > 0 ? emitter.lifespan : -1,
                    role: pouredRole,
                    size: pouredSize,
                    z: 0,
                    velocityZ: jsSin(lean) * speed
                )
                guard placed else {
                    emitter.owed = 0
                    break
                }
            }
        }
    }
}
