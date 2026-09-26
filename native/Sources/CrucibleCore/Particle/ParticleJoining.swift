/// Adding bodies that take part in what the field is doing.
///
/// ## What was wrong
///
/// Adding bodies always did the same thing whatever was on screen: it scattered them in a ring round the
/// middle with random speeds. Ten thousand bodies added to a galaxy ignored the black hole and flew about
/// through the disc; bodies added to a sunflower were a fog over it; bodies added to a fire did not burn.
/// The one exception was a small batch dropped into a galaxy, which quietly went into orbit — and nothing
/// said so, and it stopped working past four thousand.
///
/// ## What joining means
///
/// It depends on what the arrangement is, and ``ParticleArrangement/Joining`` names the four kinds:
///
///   - **Orbit.** New bodies go into orbit round the black holes, at the distances the arrangement's own
///     bodies orbit at. Each one is a copy of a body already orbiting, turned to a random place round the
///     same centre — which puts it on an orbit that is known to work, rather than on one worked out afresh
///     that might not suit a pair of wells.
///   - **Crowd.** New bodies copy a body of the crowd: its speed, colour, weight and how long it has left,
///     and its place in a shape if it holds one. A sunflower gets denser, a fire gets hotter, a pour gets
///     deeper.
///   - **Objects.** The same, for arrangements whose behaviour belongs to the object list — a flare's
///     recycling, a helix's strands, a flock's steering. The object list is the expensive one, so there is
///     a ceiling on how many can join, and the caller is told how many did.
///   - **Structure.** A cloth or a rope is a built thing, so adding to it builds another.
///
/// Turned off, adding scatters bodies exactly as it always has — somebody who wants to see what a galaxy
/// does to a crowd dropped into it can still have that.
extension ParticleEngine {
    /// The most object bodies joining may bring the field to.
    ///
    /// The object list carries a dozen properties a body and is copied whole for every undo point, so it is
    /// kept to a size where both stay quick. The crowd has no such limit, which is why most arrangements
    /// join through it.
    public static let joinedObjectLimit = 8_000

    /// Whether new sources should pour bodies that join the arrangement.
    ///
    /// Set by the interface from the same switch as adding bodies, so a source placed in a galaxy pours a
    /// stream that goes into orbit rather than one that falls through the disc.
    public var joinsArrangement: Bool {
        get { storedJoinsArrangement }
        set { storedJoinsArrangement = newValue }
    }

    /// Whether bodies added to an arrangement are made the size of the arrangement's own bodies.
    ///
    /// On unless somebody turns it off. The stars added to a galaxy used to be drawn at one size whatever the
    /// galaxy's stars were — the size slider's — so the new ones stood out as a different kind of thing. With
    /// this on, each copies the size of the body it copies; with it off, they are the size slider's, as before.
    public var matchesArrangementSize: Bool {
        get { storedMatchesArrangementSize }
        set { storedMatchesArrangementSize = newValue }
    }

    /// How big the arrangement's own bodies are, as a diameter at the size slider's resting value.
    ///
    /// The average of the individual bodies when the arrangement has them — the stars of a galaxy, not its
    /// black hole — and otherwise of the crowd's own sizes. Nought when nothing has a size of its own, which is
    /// every arrangement made of the crowd, and means "the size slider's", which is what those are drawn at.
    /// Nought too once the field has been cleared, since then there is no arrangement to match.
    public var arrangementBodySize: Double {
        // With no arrangement there is nothing to match. Whatever happens to be lying about — a burst's big
        // charged bodies, say — is not a size anybody chose for what they add next.
        guard storedArrangement != nil else { return 0 }
        var total = 0.0
        var counted = 0
        for body in particles where body.kind == .standard && !body.isFixed {
            guard body.radius.isFinite, body.radius > 0 else { continue }
            total += body.radius * 2
            counted += 1
        }
        if counted > 0 { return total / Double(counted) }
        guard swarm.hasSizes, swarm.count > 0 else { return 0 }
        // A sample, evenly spaced, so a crowd of a million is not walked end to end to answer this.
        let step = max(1, swarm.count / 4_096)
        var index = 0
        while index < swarm.count {
            let own = Double(swarm.sizes[index])
            if own > 0 {
                total += own
                counted += 1
            }
            index += step
        }
        return counted > 0 ? total / Double(counted) : 0
    }

    /// Adds bodies that take part in the arrangement, or scatters them if there is nothing to join.
    ///
    /// - Returns: how many bodies were added. For a structure, that is the size of the one built — the
    ///   count asked for is not meaningful for "another rope".
    @discardableResult
    public func spawnJoining(count requested: Int) -> Int {
        let before = bodyCount
        guard let details = arrangementDetails, canJoinArrangement else {
            spawnBatch(count: requested, size: storedMatchesArrangementSize ? arrangementBodySize : 0)
            return bodyCount - before
        }
        pushUndo()
        switch details.joining {
        case .orbit:
            joinOrbit(count: requested)
        case .crowd:
            joinCrowd(count: requested)
        case .objects:
            joinObjects(count: requested, flock: details.id == "flock")
        case .structure:
            joinStructure(details.id)
        case .none:
            break
        }
        return max(0, bodyCount - before)
    }

    // MARK: - Orbit

    private func joinOrbit(count requested: Int) {
        let room = max(0, maxParticles - particles.count - swarm.count)
        let total = min(requested, room)
        guard total > 0 else { return }

        let holes = particles.filter { $0.kind == .blackhole && $0.x.isFinite && $0.y.isFinite }
        guard !holes.isEmpty else {
            // The black holes have gone — somebody undid them, or loaded something odd. Nothing to orbit.
            joinCrowd(count: total)
            return
        }

        // Bodies already orbiting, to copy. Object bodies first, since those are the arrangement's own.
        let members = particles.indices.filter { index in
            let body = particles[index]
            return body.kind == .standard && !body.isFixed && body.ignoresGravity && body.isFinite
        }
        let budget = maxParticles - particles.count
        let fallbackSize = storedMatchesArrangementSize ? arrangementBodySize : 0

        func nearestHole(toX x: Double, y: Double) -> ParticleObject {
            var best = holes[0]
            var bestDistance = Double.infinity
            for hole in holes {
                let dx = hole.x - x
                let dy = hole.y - y
                let distance = dx * dx + dy * dy
                if distance < bestDistance {
                    bestDistance = distance
                    best = hole
                }
            }
            return best
        }

        for _ in 0 ..< total {
            var x: Double
            var y: Double
            var velX: Double
            var velY: Double
            var z = 0.0
            var velZ = 0.0
            var colour: UInt32
            var ownSize = 0.0

            if !members.isEmpty {
                let member = particles[members[Int(rng.next() * Double(members.count)) % members.count]]
                // Turned about whatever it orbits: its own recorded centre when it has one — which is how a
                // synchrotron's bodies circle the midpoint between its wells — and otherwise the nearest hole.
                let centreX: Double
                let centreY: Double
                let centreZ: Double
                if let originX = member.originX, let originY = member.originY {
                    centreX = originX
                    centreY = originY
                    centreZ = member.originZ
                } else {
                    let hole = nearestHole(toX: member.x, y: member.y)
                    centreX = hole.x
                    centreY = hole.y
                    centreZ = hole.z
                }
                let turn = rng.next() * Double.pi * 2
                let c = jsCos(turn)
                let s = jsSin(turn)
                // A little further in or out, with the speed adjusted to match, so the new bodies fill the
                // disc rather than landing exactly on the orbits that already exist.
                let stretch = 0.92 + rng.next() * 0.16
                let slow = 1 / stretch.squareRoot()
                if storedDepthEnabled {
                    // In depth every disc lies level, so the copy is turned round the upright through its centre.
                    let offsetX = (member.x - centreX) * stretch
                    let offsetZ = (member.z - centreZ) * stretch
                    x = centreX + offsetX * c - offsetZ * s
                    z = centreZ + offsetX * s + offsetZ * c
                    y = centreY + (member.y - centreY) * stretch
                    velX = (member.velocityX * c - member.velocityZ * s) * slow
                    velZ = (member.velocityX * s + member.velocityZ * c) * slow
                    velY = member.velocityY * slow
                } else {
                    let offsetX = (member.x - centreX) * stretch
                    let offsetY = (member.y - centreY) * stretch
                    x = centreX + offsetX * c - offsetY * s
                    y = centreY + offsetX * s + offsetY * c
                    velX = (member.velocityX * c - member.velocityY * s) * slow
                    velY = (member.velocityX * s + member.velocityY * c) * slow
                }
                colour = member.color.packedRGBA
                if storedMatchesArrangementSize, member.radius.isFinite, member.radius > 0 {
                    ownSize = member.radius * 2
                }
            } else {
                let hole = holes[Int(rng.next() * Double(holes.count)) % holes.count]
                let distance = rng.next() * (patternSpan * 0.4) + 30 * sceneScale
                let angle = rng.next() * Double.pi * 2
                let speed = (hole.mass * 200 / distance).squareRoot()
                if storedDepthEnabled {
                    x = hole.x + jsCos(angle) * distance
                    y = hole.y
                    z = hole.z + jsSin(angle) * distance
                    velX = -jsSin(angle) * speed
                    velY = 0
                    velZ = jsCos(angle) * speed
                } else {
                    x = hole.x + jsCos(angle) * distance
                    y = hole.y + jsSin(angle) * distance
                    velX = -jsSin(angle) * speed
                    velY = jsCos(angle) * speed
                }
                colour = PackedColor(hue: (distance * 2.8).truncatingRemainder(dividingBy: 360), saturation: 0.95, lightness: 0.7)
                    .packedRGBA
                if storedMatchesArrangementSize { ownSize = fallbackSize }
            }

            guard swarm.append(
                x: x,
                y: y,
                velocityX: velX,
                velocityY: velY,
                color: colour,
                budget: budget,
                role: .orbits,
                size: ownSize,
                z: z,
                velocityZ: velZ
            ) else { return }
        }
    }

    // MARK: - Crowd

    private func joinCrowd(count requested: Int) {
        let room = max(0, maxParticles - particles.count - swarm.count)
        let total = min(requested, room)
        guard total > 0 else { return }

        let existing = swarm.count
        guard existing > 0 else {
            // Between shells, or after a storm's last bolt has faded, there is nobody to copy. Scatter them
            // rather than refusing, so the button never silently does nothing.
            swarm.spawn(
                count: total,
                width: width,
                height: height,
                color: 0,
                budget: maxParticles - particles.count,
                rng: &rng,
                span: patternSpan * 0.42,
                size: storedMatchesArrangementSize ? arrangementBodySize : 0,
                inDepth: worldDepth
            )
            return
        }

        let budget = maxParticles - particles.count
        let nudge = 0.004 * patternSpan
        for _ in 0 ..< total {
            // Copied from the bodies there were before this press, so a large addition copies the
            // arrangement rather than copies of copies of one unlucky body.
            let source = Int(rng.next() * Double(existing)) % existing
            let pair = source * 2
            var velX = Double(swarm.velocities[pair]) + (rng.next() - 0.5) * 0.2
            var velY = Double(swarm.velocities[pair + 1]) + (rng.next() - 0.5) * 0.2
            let mass = Double(swarm.masses[source])
            let left = Double(swarm.lives[source])
            // A body that will expire gets a fresh share of what its original started with, so a thousand
            // embers added at once do not all go out on the same moment.
            let life = left < 0 ? -1 : max(1, Double(swarm.maxLives[source]) * (0.5 + rng.next() * 0.5))
            let role = swarm.role(at: source)
            var home = swarm.home(at: source)
            let ownSize = storedMatchesArrangementSize ? Double(swarm.sizes[source]) : 0
            var x: Double
            var y: Double
            var z = 0.0
            var velZ = 0.0
            if var place = home {
                if place.radius > 0 {
                    place.radius *= 0.98 + rng.next() * 0.04
                    place.angle += (rng.next() - 0.5) * 0.04
                } else {
                    place.anchorX += (rng.next() - 0.5) * 2 * nudge
                    place.anchorY += (rng.next() - 0.5) * 2 * nudge
                    if storedDepthEnabled { place.anchorZ += (rng.next() - 0.5) * 2 * nudge }
                }
                home = place
                if storedDepthEnabled {
                    let point = place.point(for: role)
                    x = point.x
                    y = point.y
                    z = point.z
                } else {
                    let point = place.flatPoint(for: role)
                    x = point.x
                    y = point.y
                }
            } else {
                x = Double(swarm.positions[pair]) + (rng.next() - 0.5) * 2 * nudge
                y = Double(swarm.positions[pair + 1]) + (rng.next() - 0.5) * 2 * nudge
                if storedDepthEnabled { z = Double(swarm.depths[source]) + (rng.next() - 0.5) * 2 * nudge }
            }
            if storedDepthEnabled {
                velZ = Double(swarm.depthVelocities[source]) + (rng.next() - 0.5) * 0.2
            }
            if !x.isFinite || !y.isFinite || !z.isFinite {
                x = width * 0.5
                y = height * 0.5
                z = 0
                velX = 0
                velY = 0
                velZ = 0
            }
            guard swarm.append(
                x: x,
                y: y,
                velocityX: velX,
                velocityY: velY,
                color: swarm.colors[source],
                budget: budget,
                mass: mass,
                life: life,
                role: role,
                home: home,
                size: ownSize,
                z: z,
                velocityZ: velZ
            ) else { return }
        }
    }

    // MARK: - Objects

    private func joinObjects(count requested: Int, flock: Bool) {
        var ceiling = Self.joinedObjectLimit
        // Only the first so many bodies flock at all, so bodies past that would sit among the flock ignoring
        // it — which is exactly what joining is meant to stop.
        if flock { ceiling = min(ceiling, flockSettings.sanitized.limit) }
        let room = max(0, min(ceiling - particles.count, maxParticles - particles.count - swarm.count))
        let total = min(requested, room)
        guard total > 0 else { return }

        let members = particles.indices.filter { index in
            let body = particles[index]
            return body.kind == .standard && !body.isFixed && body.isFinite
        }
        guard !members.isEmpty else { return }
        let nudge = 3 * sceneScale

        for _ in 0 ..< total {
            let member = particles[members[Int(rng.next() * Double(members.count)) % members.count]]
            // A share of what it started with, so the new ones do not all recycle on the same moment.
            let life: Int? = member.lifespan.map { _ in
                let longest = max(1, member.maxLife ?? 100)
                return max(1, Int((rng.next() * Double(longest)).rounded(.down)))
            }
            let x = member.x + (rng.next() - 0.5) * 2 * nudge
            let y = member.y + (rng.next() - 0.5) * 2 * nudge
            let velX = member.velocityX + (rng.next() - 0.5) * 0.3
            let velY = member.velocityY + (rng.next() - 0.5) * 0.3
            var z = 0.0
            var velZ = 0.0
            if storedDepthEnabled {
                z = member.z + (rng.next() - 0.5) * 2 * nudge
                velZ = member.velocityZ + (rng.next() - 0.5) * 0.3
            }
            addParticle(
                x: x,
                y: y,
                velocityX: velX,
                velocityY: velY,
                // The size of the body it copies, or with matching off, one drawn at the size slider's size.
                radius: storedMatchesArrangementSize ? member.radius : 1,
                mass: member.mass,
                charge: member.charge,
                color: member.color,
                lifespan: life,
                maxLife: member.maxLife,
                ignoresGravity: member.ignoresGravity,
                originX: member.originX,
                originY: member.originY,
                latticeBound: member.latticeBound,
                helixStrand: member.helixStrand,
                kind: .standard,
                z: z,
                velocityZ: velZ,
                originZ: member.originZ
            )
        }
    }

    // MARK: - Structures

    private func joinStructure(_ id: String) {
        if storedDepthEnabled {
            switch id {
            case "rope":
                addRopeInDepth(length: 32, atX: across(0.12 + rng.next() * 0.76))
            case "blob":
                addBlobInDepth(
                    nodes: 42,
                    centreX: across(0.2 + rng.next() * 0.6),
                    centreY: down(0.15 + rng.next() * 0.3),
                    centreZ: (rng.next() - 0.5) * halfDepth
                )
            case "cloth":
                addClothInDepth(cols: 10, rows: 8, centreX: across(0.25 + rng.next() * 0.5), top: down(0.05 + rng.next() * 0.35))
            case "molecules":
                addMoleculesInDepth(count: 60, laidOut: false)
            default:
                break
            }
            return
        }
        switch id {
        case "rope":
            addRope(length: 32, atX: across(0.12 + rng.next() * 0.76))
        case "blob":
            addBlob(nodes: 24, centreX: across(0.2 + rng.next() * 0.6), centreY: down(0.15 + rng.next() * 0.3))
        case "cloth":
            addCloth(
                cols: 10,
                rows: 8,
                centreX: across(0.25 + rng.next() * 0.5),
                top: down(0.05 + rng.next() * 0.35)
            )
        case "molecules":
            addMolecules(count: 60, laidOut: false)
        default:
            break
        }
    }
}
