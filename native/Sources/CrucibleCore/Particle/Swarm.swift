/// The high-count particle store: up to a million bodies, held as flat arrays.
///
/// Separate from the object particle list because the two have genuinely different
/// shapes. An object particle carries a dozen properties and can be a black hole or
/// part of a cloth; a swarm particle is a position, a velocity and a colour, and
/// there may be a million of them. Storing those as individual records would spend
/// most of the frame chasing memory.
///
/// ## Storage
///
/// Positions and velocities are interleaved pairs of **single-precision** floats,
/// matching the web implementation's typed arrays — so the same rounding happens on
/// the same writes. Arithmetic is done at double precision and narrowed on store.
///
/// Buffers are allocated manually and released in `deinit`, for the same reason the
/// powder grid does it: the physics needs raw pointers, and the collision pass wants
/// to hand them to worker threads later.
///
/// ## What this type deliberately does not do
///
/// It knows nothing about drawing or about the GPU. The web version reaches into a
/// WebGPU singleton from inside `clear()` and `spawn()`; here the renderer watches
/// ``generation`` instead and re-uploads when it changes. That keeps the simulation
/// runnable — and testable — with no graphics stack present at all.
public final class Swarm {
    /// Hard ceiling on the number of bodies.
    public static let maximumCount = 1_000_000

    /// How many bodies are live.
    public private(set) var count: Int = 0
    /// How many the buffers can currently hold.
    public private(set) var capacity: Int = 0

    /// Interleaved x, y pairs.
    public private(set) var positions: UnsafeMutablePointer<Float>
    /// Interleaved velocity pairs.
    public private(set) var velocities: UnsafeMutablePointer<Float>
    /// One packed colour per body.
    public private(set) var colors: UnsafeMutablePointer<UInt32>

    /// Bumped whenever the contents change in a way a renderer needs to notice.
    ///
    /// Replaces the web implementation's habit of poking a graphics singleton from
    /// inside the data structure.
    public private(set) var generation: Int = 0

    /// Spatial hash used by the collision pass. Allocated on demand.
    private var bucketHead: UnsafeMutablePointer<Int32>?
    private var bucketHeadCount: Int = 0
    private var nextInBucket: UnsafeMutablePointer<Int32>?
    private var nextInBucketCount: Int = 0

    /// The swarm deliberately owns no random stream of its own.
    ///
    /// Scattering a new swarm draws from the stream its owner passes in, so the whole
    /// field — object bodies and swarm alike — replays from a single seed. The web
    /// reference works this way by accident, because everything there calls one global
    /// `Math.random`; here it is the explicit contract, and it is what lets the two
    /// implementations be compared draw for draw.
    public init() {
        // One element rather than zero, so the pointers are always valid to hold.
        self.capacity = 0
        self.positions = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        self.velocities = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        self.colors = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        self.positions.initialize(repeating: 0, count: 1)
        self.velocities.initialize(repeating: 0, count: 1)
        self.colors.initialize(repeating: 0, count: 1)
    }

    deinit {
        let allocated = max(1, capacity)
        positions.deinitialize(count: allocated * 2)
        positions.deallocate()
        velocities.deinitialize(count: allocated * 2)
        velocities.deallocate()
        colors.deinitialize(count: allocated)
        colors.deallocate()
        if let bucketHead {
            bucketHead.deinitialize(count: bucketHeadCount)
            bucketHead.deallocate()
        }
        if let nextInBucket {
            nextInBucket.deinitialize(count: nextInBucketCount)
            nextInBucket.deallocate()
        }
    }

    // MARK: - Capacity

    /// Empties the swarm. The buffers are kept, so refilling does not reallocate.
    public func removeAll() {
        count = 0
        generation += 1
    }

    /// Drops the newest bodies so at most `limit` remain.
    public func trim(to limit: Int) {
        let next = max(0, min(count, limit))
        if next == count { return }
        count = next
        generation += 1
    }

    /// Grows the buffers to hold at least `needed` bodies.
    ///
    /// Doubles rather than growing exactly, so filling a swarm one batch at a time
    /// does not reallocate on every batch.
    private func reserve(_ needed: Int) {
        guard needed > capacity else { return }
        let target = min(Self.maximumCount, max(needed, capacity == 0 ? 8192 : capacity * 2))
        guard target > capacity else { return }

        let newPositions = UnsafeMutablePointer<Float>.allocate(capacity: target * 2)
        let newVelocities = UnsafeMutablePointer<Float>.allocate(capacity: target * 2)
        let newColors = UnsafeMutablePointer<UInt32>.allocate(capacity: target)
        newPositions.initialize(repeating: 0, count: target * 2)
        newVelocities.initialize(repeating: 0, count: target * 2)
        newColors.initialize(repeating: 0, count: target)

        if count > 0 {
            newPositions.update(from: positions, count: count * 2)
            newVelocities.update(from: velocities, count: count * 2)
            newColors.update(from: colors, count: count)
        }

        let previous = max(1, capacity)
        positions.deinitialize(count: previous * 2)
        positions.deallocate()
        velocities.deinitialize(count: previous * 2)
        velocities.deallocate()
        colors.deinitialize(count: previous)
        colors.deallocate()

        positions = newPositions
        velocities = newVelocities
        colors = newColors
        capacity = target
    }

    // MARK: - Spawning

    /// Scatters new bodies in a ring around the centre of the world.
    ///
    /// - Parameter budget: How many bodies may exist in total. The caller subtracts
    ///   whatever the object particle list is already using, because the limit covers
    ///   the whole field — the web version handed the swarm the full limit regardless,
    ///   so the two together exceeded it.
    /// - Parameter rng: The field's random stream, passed in rather than owned. See
    ///   ``init()``.
    public func spawn(
        count requested: Int,
        width: Double,
        height: Double,
        color: UInt32,
        budget: Int,
        rng: inout Mulberry32
    ) {
        let room = max(0, min(Self.maximumCount, budget) - count)
        let adding = min(requested, room)
        guard adding > 0 else { return }
        reserve(count + adding)
        // A capacity ceiling could still leave less room than asked for.
        let actual = min(adding, capacity - count)
        guard actual > 0 else { return }

        let centreX = width * 0.5
        let centreY = height * 0.5
        let span = min(width, height) * 0.42

        let start = count
        for i in start ..< (start + actual) {
            let angle = rng.next() * Double.pi * 2
            let distance = rng.next() * span + 20
            let pair = i * 2
            positions[pair] = JS.toFloat32(centreX + jsCos(angle) * distance)
            positions[pair + 1] = JS.toFloat32(centreY + jsSin(angle) * distance)
            velocities[pair] = JS.toFloat32((rng.next() - 0.5) * 6)
            velocities[pair + 1] = JS.toFloat32((rng.next() - 0.5) * 6)
            // `!= 0`, not truthiness: a deliberately black or transparent colour is a
            // legitimate request that the web version silently replaced.
            colors[i] = color != 0
                ? color
                : 0xFF00_0000 | UInt32((i * 97) & 255)
                    | (UInt32((i * 57) & 255) << 8)
                    | (UInt32((i * 13) & 255) << 16)
        }
        count = start + actual
        generation += 1
    }

    // MARK: - Stepping

    /// Everything the swarm needs to know about the world for one tick.
    public struct StepOptions: Sendable {
        public var width: Double
        public var height: Double
        public var gravityX: Double
        public var gravityY: Double
        public var damping: Double
        public var elasticity: Double
        public var collide: Bool
        /// The same global speed limit the object particles obey.
        public var maxSpeed: Double
        /// The same boundary rule the object particles obey.
        public var boundaryMode: ParticleBoundaryMode
        public var mouseX: Double
        public var mouseY: Double
        public var mouseActive: Bool
        public var mouseForce: Double
        public var mouseRadius: Double
        /// `true` pulls toward the finger, `false` pushes away.
        public var attract: Bool

        public init(
            width: Double,
            height: Double,
            gravityX: Double,
            gravityY: Double,
            damping: Double,
            elasticity: Double,
            collide: Bool,
            maxSpeed: Double,
            boundaryMode: ParticleBoundaryMode,
            mouseX: Double,
            mouseY: Double,
            mouseActive: Bool,
            mouseForce: Double,
            mouseRadius: Double,
            attract: Bool
        ) {
            self.width = width
            self.height = height
            self.gravityX = gravityX
            self.gravityY = gravityY
            self.damping = damping
            self.elasticity = elasticity
            self.collide = collide
            self.maxSpeed = maxSpeed
            self.boundaryMode = boundaryMode
            self.mouseX = mouseX
            self.mouseY = mouseY
            self.mouseActive = mouseActive
            self.mouseForce = mouseForce
            self.mouseRadius = mouseRadius
            self.attract = attract
        }
    }

    /// Advances every body one tick.
    public func step(_ options: StepOptions) {
        guard count > 0 else { return }

        let width = options.width
        let height = options.height
        let damping = options.damping
        let bounce = options.elasticity
        let radiusSquared = options.mouseRadius * options.mouseRadius
        let force = (options.attract ? 1.0 : -1.0) * options.mouseForce * 0.08
        let maxSpeed = options.maxSpeed > 0 ? options.maxSpeed : Double.infinity
        let maxSpeedSquared = maxSpeed * maxSpeed
        let wrapping = options.boundaryMode == .wrap

        for i in 0 ..< count {
            let pair = i * 2
            var velX = velocities[pair].asDouble * damping + options.gravityX
            var velY = velocities[pair + 1].asDouble * damping + options.gravityY

            if options.mouseActive {
                let dx = options.mouseX - positions[pair].asDouble
                let dy = options.mouseY - positions[pair + 1].asDouble
                let distanceSquared = dx * dx + dy * dy
                if distanceSquared < radiusSquared && distanceSquared > 0.5 {
                    let inverse = force / distanceSquared.squareRoot()
                    velX += dx * inverse
                    velY += dy * inverse
                }
            }

            // The same speed limit the object particles obey. The web swarm had none
            // at all, so the one slider the interface offers governed a few hundred
            // bodies and ignored the other million.
            let speedSquared = velX * velX + velY * velY
            if speedSquared > maxSpeedSquared && speedSquared > 0 {
                let scale = maxSpeed / speedSquared.squareRoot()
                velX *= scale
                velY *= scale
            }

            var posX = positions[pair].asDouble + velX
            var posY = positions[pair + 1].asDouble + velY

            if wrapping {
                if width > 0 { posX = ((posX.truncatingRemainder(dividingBy: width)) + width).truncatingRemainder(dividingBy: width) }
                if height > 0 { posY = ((posY.truncatingRemainder(dividingBy: height)) + height).truncatingRemainder(dividingBy: height) }
            } else {
                // Void has no meaning for a fixed buffer with no per-body lifetime, so
                // it falls back to bouncing rather than leaking bodies outside the
                // world where nothing would ever bring them back.
                if posX < 1 {
                    posX = 1
                    velX *= -bounce
                } else if posX > width - 1 {
                    posX = width - 1
                    velX *= -bounce
                }
                if posY < 1 {
                    posY = 1
                    velY *= -bounce
                } else if posY > height - 1 {
                    posY = height - 1
                    velY *= -bounce
                }
            }

            positions[pair] = JS.toFloat32(posX)
            positions[pair + 1] = JS.toFloat32(posY)
            velocities[pair] = JS.toFloat32(velX)
            velocities[pair + 1] = JS.toFloat32(velY)
        }

        if options.collide && count > 1 {
            // Twice, which firms up stacks that one pass leaves overlapping.
            resolveCollisions(width: width, height: height)
            resolveCollisions(width: width, height: height)
        }
    }

    /// Pushes overlapping bodies apart, using a uniform grid to find neighbours.
    private func resolveCollisions(width: Double, height: Double) {
        let bodies = count
        guard bodies > 1, width > 0, height > 0 else { return }

        // Coarser cells at higher counts: the point is to keep the number of bodies
        // per cell roughly constant rather than the cell size.
        let cell = Double(bodies > 120_000 ? 7 : bodies > 40_000 ? 5 : 4)
        let columns = max(1, Int((width / cell).rounded(.up)))
        let rows = max(1, Int((height / cell).rounded(.up)))
        let buckets = columns * rows

        if bucketHead == nil || bucketHeadCount != buckets {
            if let existing = bucketHead {
                existing.deinitialize(count: bucketHeadCount)
                existing.deallocate()
            }
            let fresh = UnsafeMutablePointer<Int32>.allocate(capacity: buckets)
            fresh.initialize(repeating: -1, count: buckets)
            bucketHead = fresh
            bucketHeadCount = buckets
        }
        if nextInBucket == nil || nextInBucketCount < bodies {
            if let existing = nextInBucket {
                existing.deinitialize(count: nextInBucketCount)
                existing.deallocate()
            }
            let size = max(bodies, 8192)
            let fresh = UnsafeMutablePointer<Int32>.allocate(capacity: size)
            fresh.initialize(repeating: -1, count: size)
            nextInBucket = fresh
            nextInBucketCount = size
        }
        guard let head = bucketHead, let next = nextInBucket else { return }

        head.update(repeating: -1, count: buckets)
        // Cleared over the live range. The web version left this holding the previous
        // frame's links, and because the striding loop below only writes the entries it
        // visits, traversal could follow a stale chain — or loop.
        next.update(repeating: -1, count: bodies)

        // At very high counts only every other body is resolved per pass, which halves
        // the cost and is invisible in a crowd that dense.
        let stride = bodies > 250_000 ? 2 : 1
        let diameter = max(3.2, cell * 0.88)
        let diameterSquared = diameter * diameter

        var i = 0
        while i < bodies {
            let pair = i * 2
            var column = Int(positions[pair].asDouble / cell)
            var row = Int(positions[pair + 1].asDouble / cell)
            column = max(0, min(columns - 1, column))
            row = max(0, min(rows - 1, row))
            let bucket = row * columns + column
            next[i] = head[bucket]
            head[bucket] = Int32(i)
            i += stride
        }

        i = 0
        while i < bodies {
            let pair = i * 2
            var posX = positions[pair].asDouble
            var posY = positions[pair + 1].asDouble
            var velX = velocities[pair].asDouble
            var velY = velocities[pair + 1].asDouble

            let column = max(0, min(columns - 1, Int(posX / cell)))
            let row = max(0, min(rows - 1, Int(posY / cell)))

            for rowOffset in -1 ... 1 {
                let neighbourRow = row + rowOffset
                if neighbourRow < 0 || neighbourRow >= rows { continue }
                for columnOffset in -1 ... 1 {
                    let neighbourColumn = column + columnOffset
                    if neighbourColumn < 0 || neighbourColumn >= columns { continue }

                    var other = Int(head[neighbourRow * columns + neighbourColumn])
                    var examined = 0
                    // Capped, so one very crowded cell cannot dominate the frame.
                    while other >= 0 && examined < 8 {
                        examined += 1
                        if other != i {
                            let otherPair = other * 2
                            let dx = posX - positions[otherPair].asDouble
                            let dy = posY - positions[otherPair + 1].asDouble
                            let distanceSquared = dx * dx + dy * dy
                            if distanceSquared < diameterSquared && distanceSquared > 0.0001 {
                                let distance = distanceSquared.squareRoot()
                                let normalX = dx / distance
                                let normalY = dy / distance
                                let overlap = diameter - distance
                                posX += normalX * overlap * 0.5
                                posY += normalY * overlap * 0.5

                                let otherVelX = velocities[otherPair].asDouble
                                let otherVelY = velocities[otherPair + 1].asDouble
                                let closing = (velX - otherVelX) * normalX + (velY - otherVelY) * normalY
                                if closing < 0 {
                                    velX -= normalX * closing * 0.92
                                    velY -= normalY * closing * 0.92
                                }
                                // Friction along the contact.
                                let relativeX = velX - otherVelX
                                let relativeY = velY - otherVelY
                                let alongNormal = relativeX * normalX + relativeY * normalY
                                let tangentX = relativeX - normalX * alongNormal
                                let tangentY = relativeY - normalY * alongNormal
                                velX -= tangentX * 0.18
                                velY -= tangentY * 0.18
                            }
                        }
                        other = Int(next[other])
                    }
                }
            }

            velX *= 0.996
            velY *= 0.996

            if posX < 1 {
                posX = 1
                velX *= -0.55
            } else if posX > width - 1 {
                posX = width - 1
                velX *= -0.55
            }
            if posY < 1 {
                posY = 1
                velY *= -0.55
            } else if posY > height - 1 {
                posY = height - 1
                velY *= -0.55
            }

            positions[pair] = JS.toFloat32(posX)
            positions[pair + 1] = JS.toFloat32(posY)
            velocities[pair] = JS.toFloat32(velX)
            velocities[pair + 1] = JS.toFloat32(velY)
            i += stride
        }
    }

    // MARK: - Snapshots

    /// A copy of the swarm, for undo and for sharing.
    public struct Snapshot: Sendable, Hashable {
        public var positions: [Float]
        public var velocities: [Float]
        public var colors: [UInt32]
        public var count: Int { colors.count }
    }

    /// Copies out at most `limit` bodies.
    public func snapshot(limit: Int = .max) -> Snapshot {
        let taken = max(0, min(count, limit))
        return Snapshot(
            positions: Array(UnsafeBufferPointer(start: positions, count: taken * 2)),
            velocities: Array(UnsafeBufferPointer(start: velocities, count: taken * 2)),
            colors: Array(UnsafeBufferPointer(start: colors, count: taken))
        )
    }

    /// Replaces the swarm's contents from a snapshot.
    ///
    /// Grows the buffers directly rather than going through `spawn`. The web version
    /// called spawn — which does trigonometry and two random draws per body to scatter
    /// them — and then overwrote everything it had just computed; worse, spawn clamps
    /// to the budget while the count assignment did not, so a snapshot larger than the
    /// cap left the count pointing past the allocation, and the writes that followed
    /// were silently dropped.
    public func restore(from snapshot: Snapshot, budget: Int) {
        let wanted = min(snapshot.count, Self.maximumCount, max(0, budget))
        removeAll()
        guard wanted > 0 else { return }
        reserve(wanted)
        let actual = min(wanted, capacity)
        guard actual > 0 else { return }

        snapshot.positions.withUnsafeBufferPointer { source in
            positions.update(from: source.baseAddress!, count: min(actual * 2, source.count))
        }
        snapshot.velocities.withUnsafeBufferPointer { source in
            velocities.update(from: source.baseAddress!, count: min(actual * 2, source.count))
        }
        snapshot.colors.withUnsafeBufferPointer { source in
            colors.update(from: source.baseAddress!, count: min(actual, source.count))
        }
        count = actual
        generation += 1
    }

    /// Whether any body holds an unusable number.
    public func corruptCount() -> Int {
        var corrupt = 0
        for i in 0 ..< count {
            let pair = i * 2
            if !positions[pair].isFinite || !positions[pair + 1].isFinite
                || !velocities[pair].isFinite || !velocities[pair + 1].isFinite
            {
                corrupt += 1
            }
        }
        return corrupt
    }

    /// The fastest body's speed, for diagnostics.
    public func fastestSpeed() -> Double {
        var fastest = 0.0
        for i in 0 ..< count {
            let pair = i * 2
            let vx = velocities[pair].asDouble
            let vy = velocities[pair + 1].asDouble
            guard vx.isFinite, vy.isFinite else { continue }
            let speed = (vx * vx + vy * vy).squareRoot()
            if speed > fastest { fastest = speed }
        }
        return fastest
    }
}
