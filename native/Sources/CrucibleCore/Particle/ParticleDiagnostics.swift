/// Inspecting the particle field's health, and putting it right.
///
/// The same idea as the powder side, but the field has two halves that need different
/// treatment: the object bodies are a list and a broken one can simply be removed, while
/// the swarm is a flat pair of buffers with no per-body identity, so a broken entry is
/// reset where it lies. Counting them together but repairing only one half is how the web
/// reference ended up reporting a fault it could never clear.

/// What an inspection of the particle field found.
public struct ParticleDiagnostics: Sendable {
    /// Object bodies plus swarm bodies.
    public var bodyCount: Int
    public var maxParticles: Int
    /// Bodies whose position or velocity is not a real number, across both halves.
    public var corruptCount: Int
    /// How much of `corruptCount` belongs to the swarm.
    ///
    /// Reported separately because the two halves are repaired differently. Without it,
    /// the automatic pass could only reach the object half, so it announced that it had
    /// purged nothing and left the issue on the list permanently.
    public var swarmCorruptCount: Int
    public var outOfBoundsCount: Int
    public var overSpeedCount: Int
    public var fastestSpeed: Int
    public var trailPoints: Int
    public var isHealthy: Bool { issues.isEmpty }
    public var issues: [String]
}

extension ParticleEngine {
    /// How far outside the world a body may drift before it counts as escaped.
    static let outOfBoundsMargin = 100.0

    /// Looks over the whole field without changing it.
    public func inspect() -> ParticleDiagnostics {
        var corruptCount = 0
        var outOfBoundsCount = 0
        var overSpeedCount = 0
        var fastest = 0.0
        // Accumulated in the same pass rather than in a second walk of the same list.
        // Counting trail points used to be its own loop over every body, which on a large
        // field is a second million-element traversal for one addition each.
        var trailPoints = 0

        // The world's own limit, not a fixed number. With the two out of step, bodies well
        // past the limit were called healthy while the repair clamped them anyway.
        let speedLimit = maxSpeed > 0 ? maxSpeed : .infinity
        // Judged against the limit plus a hair.
        //
        // Bringing a body down to the limit means scaling its two components by
        // `limit / speed`, and the speed recomputed from the scaled components can land a
        // fraction above the limit — the arithmetic simply cannot always represent
        // "exactly at the limit". Compared strictly, such a body is reported as over the
        // limit on every inspection for ever, so the automatic pass clamps it, re-inspects,
        // still sees it, and finishes by announcing an issue it just failed to fix. The
        // physics applies the same clamp every frame, so this affects ordinary fast-moving
        // worlds, not just repaired ones.
        let overLimit = speedLimit.isFinite ? speedLimit * (1 + 1e-9) : .infinity

        for body in particles {
            trailPoints += body.trail.count
            // Checked for being finite, not merely for being a number: an infinite
            // coordinate is just as broken and used to pass straight through as healthy.
            guard body.isFinite else {
                corruptCount += 1
                continue
            }
            if body.x < -Self.outOfBoundsMargin || body.x > width + Self.outOfBoundsMargin
                || body.y < -Self.outOfBoundsMargin || body.y > height + Self.outOfBoundsMargin {
                outOfBoundsCount += 1
            }
            let speed = (body.velocityX * body.velocityX + body.velocityY * body.velocityY).squareRoot()
            if speed > fastest { fastest = speed }
            if speed > overLimit { overSpeedCount += 1 }
        }

        // The swarm is inspected too. Every count above covered only the object bodies
        // while the headline total included the swarm, so a corrupt swarm — entirely
        // possible, since its gravity comes from the device's motion sensors — reported a
        // perfectly healthy field.
        var swarmCorruptCount = 0
        for i in 0 ..< swarm.count {
            let pair = i * 2
            let x = swarm.positions[pair]
            let y = swarm.positions[pair + 1]
            let vx = swarm.velocities[pair]
            let vy = swarm.velocities[pair + 1]
            guard x.isFinite, y.isFinite, vx.isFinite, vy.isFinite else {
                swarmCorruptCount += 1
                continue
            }
            let speed = (Double(vx) * Double(vx) + Double(vy) * Double(vy)).squareRoot()
            if speed > fastest { fastest = speed }
            // Counted, like the object bodies. The swarm only fed the headline top speed,
            // so the report could show a top speed of nine hundred beside a count of zero
            // over the limit, and an escaped swarm was invisible to the automatic pass.
            if speed > overLimit { overSpeedCount += 1 }
        }
        corruptCount += swarmCorruptCount

        var issues: [String] = []
        if corruptCount > 0 {
            issues.append("Detected \(corruptCount) particles with unusable coordinates or velocities")
        }
        if outOfBoundsCount > 0 {
            issues.append("Detected \(outOfBoundsCount) particles drifted outside the world")
        }
        if overSpeedCount > 0 {
            issues.append("Detected \(overSpeedCount) particles past the \(JS.clampedInt(JS.round(speedLimit), 0, 1_000_000_000)) speed limit")
        }

        return ParticleDiagnostics(
            bodyCount: bodyCount,
            maxParticles: maxParticles,
            corruptCount: corruptCount,
            swarmCorruptCount: swarmCorruptCount,
            outOfBoundsCount: outOfBoundsCount,
            overSpeedCount: overSpeedCount,
            // Held to a number an integer can carry. A runaway body's speed can be infinite, and the report
            // that exists to find runaway bodies used to crash on exactly that.
            fastestSpeed: JS.clampedInt(JS.round(fastest), 0, 1_000_000_000, fallback: 1_000_000_000),
            trailPoints: trailPoints,
            issues: issues
        )
    }

    // MARK: - Individual repairs

    /// Removes every object body whose position or velocity is unusable.
    @discardableResult
    public func purgeCorruptParticles() -> Int {
        // Through the removal path that keeps springs valid — see `removeParticles`.
        removeParticles { !$0.isFinite }
    }

    /// Brings every object body back under the speed limit.
    @discardableResult
    public func clampVelocities() -> Int {
        // The same reading of the limit the inspection uses: zero or less means "no
        // limit", not "freeze everything". Taken literally, and the limit is a plain
        // property so anything could set it to zero, every body was multiplied by a factor
        // of zero and stopped dead — while the inspection that triggered the repair had
        // treated the same value as no limit and reported nothing wrong.
        let limit = maxSpeed > 0 ? maxSpeed : .infinity
        var clamped = 0
        for i in particles.indices {
            let vx = particles[i].velocityX
            let vy = particles[i].velocityY
            // A velocity that is not finite is reset rather than scaled. Dividing the limit
            // by infinity gives zero, and infinity times zero is not a number — so this
            // repair used to manufacture exactly the corruption it exists to remove.
            if !vx.isFinite || !vy.isFinite {
                particles[i].velocityX = 0
                particles[i].velocityY = 0
                clamped += 1
                continue
            }
            guard limit.isFinite else { continue }
            let speed = (vx * vx + vy * vy).squareRoot()
            if speed > limit, speed > 0 {
                let scale = limit / speed
                particles[i].velocityX = vx * scale
                particles[i].velocityY = vy * scale
                clamped += 1
            }
        }
        return clamped
    }

    /// Resets swarm entries that hold unusable values, and reins in any that are too fast.
    ///
    /// Entries are reset rather than removed: the swarm has no per-body identity, so
    /// removing one would mean compacting a million entries for no visible gain.
    @discardableResult
    public func repairSwarm() -> Int {
        let limit = maxSpeed > 0 ? maxSpeed : .infinity
        var repaired = 0
        for i in 0 ..< swarm.count {
            let pair = i * 2
            var touched = false
            if !swarm.positions[pair].isFinite || !swarm.positions[pair + 1].isFinite {
                // Back to the middle, the only position guaranteed to be inside the world.
                swarm.positions[pair] = Float(width / 2)
                swarm.positions[pair + 1] = Float(height / 2)
                touched = true
            }
            let vx = swarm.velocities[pair]
            let vy = swarm.velocities[pair + 1]
            if !vx.isFinite || !vy.isFinite {
                swarm.velocities[pair] = 0
                swarm.velocities[pair + 1] = 0
                touched = true
            } else if limit.isFinite {
                let speed = (Double(vx) * Double(vx) + Double(vy) * Double(vy)).squareRoot()
                if speed > limit, speed > 0 {
                    let scale = limit / speed
                    swarm.velocities[pair] = JS.toFloat32(Double(vx) * scale)
                    swarm.velocities[pair + 1] = JS.toFloat32(Double(vy) * scale)
                    touched = true
                }
            }
            if touched { repaired += 1 }
        }
        return repaired
    }

    /// Brings escaped bodies back inside the world.
    ///
    /// Clamped to the body's own radius, and the outward part of its velocity zeroed —
    /// without that, a "repaired" body was pushed straight back out and re-clamped every
    /// frame, leaving it pinned to the wall rather than recovered.
    @discardableResult
    public func recentreOutOfBounds() -> Int {
        var moved = 0
        for i in particles.indices {
            // A radius of exactly zero is a legitimate value that `addParticle` goes out of
            // its way to preserve, so it is tested for being absent rather than for being
            // falsy. A truthiness test silently substituted the default size, resizing a
            // body inside a repair that is only supposed to move it.
            let radius = particles[i].radius.isFinite ? particles[i].radius : particleSize
            let minX = min(radius, width / 2)
            let maxX = max(minX, width - radius)
            let minY = min(radius, height / 2)
            let maxY = max(minY, height - radius)
            let body = particles[i]
            guard body.x < minX || body.x > maxX || body.y < minY || body.y > maxY else { continue }

            if body.x < minX {
                particles[i].x = minX
                if particles[i].velocityX < 0 { particles[i].velocityX = 0 }
            } else if body.x > maxX {
                particles[i].x = maxX
                if particles[i].velocityX > 0 { particles[i].velocityX = 0 }
            }
            if body.y < minY {
                particles[i].y = minY
                if particles[i].velocityY < 0 { particles[i].velocityY = 0 }
            } else if body.y > maxY {
                particles[i].y = maxY
                if particles[i].velocityY > 0 { particles[i].velocityY = 0 }
            }
            moved += 1
        }
        return moved
    }

    /// Brings every unpinned body to rest.
    @discardableResult
    public func haltAllMotion() -> Int {
        var stopped = 0
        for i in particles.indices {
            // Pinned bodies and attractors are left alone — stopping a black hole was never
            // the intent — and only the bodies actually changed are counted.
            guard !particles[i].isFixed else { continue }
            guard particles[i].velocityX != 0 || particles[i].velocityY != 0 else { continue }
            particles[i].velocityX = 0
            particles[i].velocityY = 0
            stopped += 1
        }
        return stopped
    }

    /// Spreads charge evenly over the bodies that carry one.
    ///
    /// Only touches bodies that are already charged, and leaves attractors alone: a charge
    /// of zero is how a body opts out of the electrostatic force entirely, and giving every
    /// body a charge destroyed that.
    @discardableResult
    public func resetCharges() -> Int {
        var charged: [Int] = []
        for i in particles.indices {
            guard particles[i].charge != 0 else { continue }
            guard particles[i].kind != .blackhole, particles[i].kind != .repulsor else { continue }
            charged.append(i)
        }
        // Alternating plus and minus over an even number, and the odd one out made neutral
        // so the total really does come to zero. It used to be skipped entirely, leaving it
        // holding whatever it had — possibly a charge of five — while the function reported
        // a balanced field it had not produced.
        let paired = charged.count - (charged.count % 2)
        for k in 0 ..< paired {
            particles[charged[k]].charge = k % 2 == 0 ? 1 : -1
        }
        if paired != charged.count, let last = charged.last {
            particles[last].charge = 0
        }
        return charged.count
    }

    // MARK: - Injectors, for exercising the repairs

    /// Adds bodies with unusable coordinates and velocities.
    public func injectCorruptParticles() {
        for _ in 0 ..< 15 {
            addParticle(
                x: .nan,
                y: .nan,
                velocityX: 1000,
                velocityY: .nan,
                radius: 4,
                color: PackedColor(r: 0xFF, g: 0x00, b: 0x55)
            )
        }
    }

    /// Fires a burst outward far faster than the speed limit allows.
    public func injectHyperVelocityExplosion() {
        let cx = width / 2
        let cy = height / 2
        for _ in 0 ..< 50 {
            let angle = rng.next() * Double.pi * 2
            addParticle(
                x: cx,
                y: cy,
                velocityX: jsCos(angle) * 250,
                velocityY: jsSin(angle) * 250,
                radius: 5,
                color: PackedColor(r: 0xF9, g: 0x73, b: 0x16)
            )
        }
    }

    // MARK: - The automatic pass

    /// Runs whichever repairs the field's condition calls for.
    @discardableResult
    public func runAutoFix() -> [String] {
        var logs = ["Initiating particle diagnostics pass..."]

        if inspect().isHealthy {
            logs.append("✓ All particle vectors and velocities verified normal.")
            logs.append("✓ No anomalies detected.")
            return logs
        }

        var steps: [String] = []

        // Each stage re-inspects rather than all of them deciding from one snapshot taken
        // before any repair. Combined with clamping running last, a clamp that produced
        // fresh corruption was never purged — and the report then called it a recovery.
        //
        // Clamping comes before the purge for the same reason: it is the stage that can
        // introduce a bad value, so the purge has to follow it.
        if inspect().overSpeedCount > 0 {
            steps.append("Clamped \(clampVelocities()) over-fast particles.")
        }

        let beforePurge = inspect()
        // The two halves are counted together but repaired differently, so each is checked
        // against its own figure.
        if beforePurge.corruptCount - beforePurge.swarmCorruptCount > 0 {
            steps.append("Purged \(purgeCorruptParticles()) corrupt particles.")
        }
        if inspect().swarmCorruptCount > 0 {
            steps.append("Repaired \(repairSwarm()) corrupt swarm particles.")
        }
        if inspect().outOfBoundsCount > 0 {
            steps.append("Brought \(recentreOutOfBounds()) escaped particles back inside the world.")
        }

        for (i, message) in steps.enumerated() {
            logs.append("✓ Step \(i + 1)/\(steps.count): \(message)")
        }

        let after = inspect()
        if after.isHealthy {
            logs.append("Diagnostics pass complete. Field health: fully operational.")
        } else {
            logs.append("Diagnostics pass complete, but \(after.issues.count) issue(s) remain:")
            for issue in after.issues { logs.append("  • \(issue)") }
        }
        return logs
    }
}
