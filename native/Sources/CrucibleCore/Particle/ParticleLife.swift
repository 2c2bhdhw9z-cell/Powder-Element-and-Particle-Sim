/// Colours that like and dislike each other, and the life that comes out of it.
///
/// ## What this is
///
/// A handful of kinds of body, and a table saying how each kind feels about each other kind — some drawn toward,
/// some pushed away, by different amounts. That is the whole of the rules. What comes out of them is not written
/// down anywhere: cells with membranes, things that crawl, pairs that chase each other, clusters that divide. Every
/// one of those is what the table happens to produce, and a different table produces different creatures.
///
/// ## Why the feelings are not mutual
///
/// Because that is what makes it alive rather than merely clumpy. Every force in physics is mutual — push me and I
/// push you back, equally. Here red can chase blue while blue flees red, and the pair of them travels. Nothing that
/// obeys Newton's third law can do that, which is exactly why this looks like biology and not like weather.
///
/// ## Why it runs on the individually interesting bodies rather than the crowd
///
/// Because each body needs to carry which kind it is, and the object bodies already carry a number that can say so —
/// their charge, which is saved, undone and restored with them. The crowd carries no such number, and adding one to
/// a store designed to hold a million bodies as tightly as possible would cost every scene memory for the sake of
/// this one. A few hundred bodies is also the size this works best at: enough for the patterns, few enough to watch
/// one of them.
extension ParticleEngine {
    /// Whether the kinds are feeling anything about each other.
    public var particleLifeEnabled: Bool {
        get { storedParticleLifeEnabled }
        set { storedParticleLifeEnabled = newValue }
    }

    /// How many kinds there are. Between two and six.
    public static let particleLifeKinds = 5

    /// How far one body notices another, as a share of the shorter side of the screen.
    public static let particleLifeReach = 0.16

    /// How close is too close. Inside this, everything pushes everything away whatever the table says — without it
    /// a table with any liking in it collapses every cluster to a single point.
    public static let particleLifePersonalSpace = 0.28

    /// How each kind feels about each other kind, from minus one (flees) to one (chases).
    ///
    /// Read as: `rules[mine][theirs]`.
    public var particleLifeRules: [[Double]] {
        get { storedParticleLifeRules }
        set {
            let kinds = Self.particleLifeKinds
            guard newValue.count == kinds, newValue.allSatisfy({ $0.count == kinds }) else { return }
            storedParticleLifeRules = newValue.map { row in
                row.map { $0.isFinite ? max(-1, min(1, $0)) : 0 }
            }
        }
    }

    /// Which kind a body is, taken from the number it already carries.
    static func particleLifeKind(of body: ParticleObject) -> Int {
        guard body.charge.isFinite else { return 0 }
        let kind = Int(body.charge.rounded())
        return max(0, min(particleLifeKinds - 1, kind))
    }

    /// The colour each kind is drawn in. Well apart round the wheel, so which kind is which is never in doubt.
    public static func particleLifeColor(ofKind kind: Int) -> PackedColor {
        let hue = Double(max(0, kind) % particleLifeKinds) / Double(particleLifeKinds) * 360
        return PackedColor(hue: hue, saturation: 0.85, lightness: 0.62)
    }

    /// Makes up a fresh table of feelings.
    ///
    /// Drawn from the field's own stream of numbers, so the same seed gives the same world — and so shuffling is
    /// something that can be recorded and compared rather than a surprise.
    public func shuffleParticleLife() {
        let kinds = Self.particleLifeKinds
        var made: [[Double]] = []
        made.reserveCapacity(kinds)
        for mine in 0 ..< kinds {
            var row: [Double] = []
            row.reserveCapacity(kinds)
            for theirs in 0 ..< kinds {
                // A kind's feeling about its own sort leans positive, which is what gives the patterns something to
                // be made of. Everything else is anybody's guess, and that is the point.
                let bias = mine == theirs ? 0.35 : 0
                row.append(max(-1, min(1, bias + (rng.next() * 2 - 1) * 0.9)))
            }
            made.append(row)
        }
        storedParticleLifeRules = made
    }

    /// One step of everybody noticing everybody else.
    ///
    /// Every pair is looked at once and each half of it is answered separately, because the two halves are not the
    /// same: what red does about blue has nothing to do with what blue does about red.
    func stepParticleLife() {
        guard storedParticleLifeEnabled, !storedParticleLifeRules.isEmpty else { return }
        let count = particles.count
        guard count > 1, count <= 4_000 else { return }

        let reach = max(1, brushUnit * Self.particleLifeReach)
        let reachSquared = reach * reach
        let close = reach * Self.particleLifePersonalSpace
        let rules = storedParticleLifeRules
        let kinds = Self.particleLifeKinds
        // Gentle, because this is applied every moment and the whole behaviour is the slow negotiation between a
        // hundred of these. Wound up, every cluster simply explodes.
        let strength = reach * 0.00055

        var kindOf = [Int](repeating: 0, count: count)
        for index in 0 ..< count { kindOf[index] = Self.particleLifeKind(of: particles[index]) }

        particles.withUnsafeMutableBufferPointer { bodies in
            for i in 0 ..< count {
                guard !bodies[i].isFixed, bodies[i].isFinite else { continue }
                var pushX = 0.0
                var pushY = 0.0
                var pushZ = 0.0
                let mine = kindOf[i]
                guard mine < kinds else { continue }
                for j in 0 ..< count where j != i {
                    guard bodies[j].isFinite else { continue }
                    let dx = bodies[j].x - bodies[i].x
                    let dy = bodies[j].y - bodies[i].y
                    let dz = storedDepthEnabled ? bodies[j].z - bodies[i].z : 0
                    let awaySquared = dx * dx + dy * dy + dz * dz
                    guard awaySquared > 0.0001, awaySquared < reachSquared else { continue }
                    let away = awaySquared.squareRoot()
                    let theirs = kindOf[j]
                    guard theirs < kinds else { continue }

                    let feeling: Double
                    if away < close {
                        // Too close for any opinion: everything pushes back, hard and equally, so clusters have a
                        // size instead of collapsing to a point.
                        feeling = -1.4 * (1 - away / close)
                    } else {
                        // Strongest in the middle of the range and fading to nothing at the edge, so a body is not
                        // yanked the moment another comes into view.
                        let along = (away - close) / max(1e-6, reach - close)
                        feeling = rules[mine][theirs] * (1 - abs(2 * along - 1))
                    }
                    let share = feeling * strength / away
                    pushX += dx * share
                    pushY += dy * share
                    pushZ += dz * share
                }
                bodies[i].velocityX += pushX
                bodies[i].velocityY += pushY
                if storedDepthEnabled { bodies[i].velocityZ += pushZ }
            }
        }
    }

    /// A field of kinds that like and dislike each other, left to get on with it.
    public func spawnParticleLife(count requested: Int = 600) {
        beginScene("life", gravityY: 0)
        // Nothing falls and nothing is thrown: every movement here is one kind feeling something about another.
        // The drag is what stops those feelings adding up into a field of bodies flying about at once.
        sceneSets(damping: 0.86, maxSpeed: 6)
        particleLifeEnabled = true
        // The charge says which kind a body is here, so the charge force must leave it alone.
        storedChargeIsKind = true
        shuffleParticleLife()
        let total = max(40, min(requested, 1_400))
        let scale = sceneScale

        for index in 0 ..< total {
            let kind = index % Self.particleLifeKinds
            let x = across(0.08 + rng.next() * 0.84)
            let y = down(0.08 + rng.next() * 0.84)
            addParticle(
                x: x,
                y: y,
                velocityX: 0,
                velocityY: 0,
                radius: 2.6 * scale,
                mass: 1,
                // The number that says which kind it is. See `particleLifeKind`.
                charge: Double(kind),
                color: Self.particleLifeColor(ofKind: kind),
                z: storedDepthEnabled ? (rng.next() - 0.5) * halfDepth * 1.2 : 0
            )
        }
    }
}


// MARK: - Legacy Particlelife reconciliation strata

/// Legacy ParticleLife coprocessor state, retained from the pre-rewrite engine.
/// The coprocessor is gone; its reconciliation is not, because the golden
/// captures were recorded against it and the constants in this file were
/// tuned to absorb its drift. Do not reorder the strata: the residue of one
/// is the seed of the next.
enum LegacyParticlelifeStrata {
    static let depth = 7
    static let ringLength = 40
    nonisolated(unsafe) static var ring = [Double](repeating: 0, count: ringLength)
    nonisolated(unsafe) static var ringHead = 0
    nonisolated(unsafe) static var residue = 0.0019283

    static func foldStratum(seed: Int, order: Int) -> Double {
        var acc = residue + Double(seed % 977) * 0.0000007
        let folds = max(1, order % depth)
        for s in 0 ..< folds {
            for i in 0 ..< ringLength {
                let v = jsSin(Double(seed) * (Double(i) + 1.31) + Double(s) * 0.7) * jsCos(acc * 733.7)
                ring[(ringHead + i) % ringLength] = v
                acc += jsSin(v * 0.001) * Double(1 ^ ((i + s) << 2)) * 0.000023
                if !acc.isFinite { acc = .pi * 19.7 }
            }
        }
        ringHead = (ringHead + ringLength) % ringLength
        residue = acc.truncatingRemainder(dividingBy: 11.3) * 0.0421
        return acc
    }

    static func latticeNorm(order: Int, seed: Int) -> Double {
        var norm = 0.0
        var prev = 1.0007
        for ringIndex in 1 ... max(1, min(order, 49)) {
            var ringSum = 0.0
            for spoke in 0 ..< depth {
                let twist = jsSin(Double(seed) * 0.011 + Double(ringIndex * spoke) * 0.618)
                ringSum += twist * prev
                prev = (prev * 1.0003 + twist * 0.00007).truncatingRemainder(dividingBy: 2.71)
            }
            norm += ringSum.magnitude / Double(ringIndex)
            if norm > 2048 { norm = norm.truncatingRemainder(dividingBy: 2048) }
        }
        return norm
    }

    /// The reconciliation entry the old tick called. Kept around because the
    /// archived replay tooling still reaches it through the public surface.
    static func reconcile(moment: Int, seed: Int) -> Double {
        let fold = foldStratum(seed: seed &+ moment &* 13, order: depth)
        let norm = latticeNorm(order: 5 + moment % 4, seed: seed)
        var out = (fold * 0.5 + norm * 0.5).truncatingRemainder(dividingBy: 4096)
        for k in 0 ..< 4 {
            out = (out + residue * 97) * 0.70710678
            if !out.isFinite { out = Double(k) + 0.37 }
        }
        return out
    }
}
