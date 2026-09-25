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
    /// How heavy each body is.
    ///
    /// One for every body until something sets otherwise, and the arithmetic is arranged so that equal
    /// weights give exactly the answer the crowd gave before weights existed — which is what lets the
    /// recorded comparison against the reference implementation stay exact.
    public private(set) var masses: UnsafeMutablePointer<Float>
    /// How many moments each body has left. Negative means it never expires.
    public private(set) var lives: UnsafeMutablePointer<Float>
    /// How many it started with, for fading and for colouring by age.
    public private(set) var maxLives: UnsafeMutablePointer<Float>

    /// Whether any body will ever expire.
    ///
    /// Tracked rather than scanned for, because it decides whether three whole passes run at all — ageing,
    /// removing the dead, and sending the lifetimes to the graphics card. At a million bodies that last one
    /// alone is four megabytes a frame, and almost every scene is made of bodies that live forever.
    public private(set) var hasMortalBodies = false

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
        self.masses = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        self.lives = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        self.maxLives = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        self.positions.initialize(repeating: 0, count: 1)
        self.velocities.initialize(repeating: 0, count: 1)
        self.colors.initialize(repeating: 0, count: 1)
        self.masses.initialize(repeating: 1, count: 1)
        self.lives.initialize(repeating: -1, count: 1)
        self.maxLives.initialize(repeating: 1, count: 1)
    }

    deinit {
        let allocated = max(1, capacity)
        positions.deinitialize(count: allocated * 2)
        positions.deallocate()
        velocities.deinitialize(count: allocated * 2)
        velocities.deallocate()
        colors.deinitialize(count: allocated)
        colors.deallocate()
        masses.deinitialize(count: allocated)
        masses.deallocate()
        lives.deinitialize(count: allocated)
        lives.deallocate()
        maxLives.deinitialize(count: allocated)
        maxLives.deallocate()
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
        let newMasses = UnsafeMutablePointer<Float>.allocate(capacity: target)
        let newLives = UnsafeMutablePointer<Float>.allocate(capacity: target)
        let newMaxLives = UnsafeMutablePointer<Float>.allocate(capacity: target)
        newPositions.initialize(repeating: 0, count: target * 2)
        newVelocities.initialize(repeating: 0, count: target * 2)
        newColors.initialize(repeating: 0, count: target)
        // A body nobody has said anything about weighs one and lives forever, so that is what fresh room
        // holds — otherwise a body written without those set would weigh nothing and be dead on arrival.
        newMasses.initialize(repeating: 1, count: target)
        newLives.initialize(repeating: -1, count: target)
        newMaxLives.initialize(repeating: 1, count: target)

        if count > 0 {
            newPositions.update(from: positions, count: count * 2)
            newVelocities.update(from: velocities, count: count * 2)
            newColors.update(from: colors, count: count)
            newMasses.update(from: masses, count: count)
            newLives.update(from: lives, count: count)
            newMaxLives.update(from: maxLives, count: count)
        }

        let previous = max(1, capacity)
        positions.deinitialize(count: previous * 2)
        positions.deallocate()
        velocities.deinitialize(count: previous * 2)
        velocities.deallocate()
        colors.deinitialize(count: previous)
        colors.deallocate()
        masses.deinitialize(count: previous)
        masses.deallocate()
        lives.deinitialize(count: previous)
        lives.deallocate()
        maxLives.deinitialize(count: previous)
        maxLives.deallocate()

        positions = newPositions
        velocities = newVelocities
        colors = newColors
        masses = newMasses
        lives = newLives
        maxLives = newMaxLives
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
            masses[i] = 1
            lives[i] = -1
            maxLives[i] = 1
            colors[i] = color != 0
                ? color
                : 0xFF00_0000 | UInt32((i * 97) & 255)
                    | (UInt32((i * 57) & 255) << 8)
                    | (UInt32((i * 13) & 255) << 16)
        }
        count = start + actual
        generation += 1
    }

    /// Moves every body by the same amount.
    ///
    /// Used when the world is deliberately grown to make more room: everything shifts by half the growth so
    /// the scene stays in the middle and the new space appears evenly all round it. Velocities are left
    /// alone — the crowd keeps doing what it was doing, it is only somewhere else.
    public func translate(dx: Double, dy: Double) {
        guard dx.isFinite, dy.isFinite, dx != 0 || dy != 0, count > 0 else { return }
        let shiftX = Float(dx)
        let shiftY = Float(dy)
        for index in 0 ..< count {
            let pair = index * 2
            positions[pair] += shiftX
            positions[pair + 1] += shiftY
        }
        generation += 1
    }

    /// Adds one body at a chosen place, and reports whether there was room.
    ///
    /// ``spawn(count:width:height:color:budget:rng:)`` scatters bodies at random, which is what a crowd
    /// wants. The pattern scenes want the opposite: a sunflower's seeds, a snowflake's arms and a
    /// mandala's petals are entirely *about* being in exact places, and none of them can be had from a
    /// scatter.
    ///
    /// - Returns: `false` when the field is full, so a caller placing a shape can stop rather than
    ///   silently drawing part of it. A half-drawn snowflake is worse than a smaller one.
    @discardableResult
    public func append(
        x: Double,
        y: Double,
        velocityX: Double,
        velocityY: Double,
        color: UInt32,
        budget: Int,
        mass: Double = 1,
        life: Double = -1
    ) -> Bool {
        guard count < min(Self.maximumCount, budget) else { return false }
        reserve(count + 1)
        guard count < capacity else { return false }

        let index = count
        let pair = index * 2
        positions[pair] = JS.toFloat32(x)
        positions[pair + 1] = JS.toFloat32(y)
        velocities[pair] = JS.toFloat32(velocityX)
        velocities[pair + 1] = JS.toFloat32(velocityY)
        colors[index] = color
        masses[index] = JS.toFloat32(mass.isFinite ? max(0.01, mass) : 1)
        let usableLife = life.isFinite ? life : -1
        lives[index] = JS.toFloat32(usableLife)
        // Never nought: it divides the remaining life to work out how faded a body should be.
        maxLives[index] = JS.toFloat32(usableLife > 0 ? usableLife : 1)
        if usableLife > 0 { hasMortalBodies = true }
        count = index + 1
        generation += 1
        return true
    }

    /// Sets one body's weight.
    public func setMass(_ mass: Double, at index: Int) {
        guard index >= 0, index < count else { return }
        masses[index] = JS.toFloat32(mass.isFinite ? max(0.01, mass) : 1)
    }

    /// Sets how long one body has left.
    public func setLife(_ life: Double, at index: Int) {
        guard index >= 0, index < count else { return }
        let usable = life.isFinite ? life : -1
        lives[index] = JS.toFloat32(usable)
        maxLives[index] = JS.toFloat32(usable > 0 ? usable : 1)
        if usable > 0 { hasMortalBodies = true }
    }

    /// How faded a body should be drawn, from nought when it is about to go to one when it is new.
    ///
    /// A body that never expires is fully solid, which is the only sensible answer for something with no age
    /// to be part of the way through.
    public func fade(at index: Int) -> Double {
        guard index >= 0, index < count else { return 1 }
        let left = Double(lives[index])
        guard left >= 0 else { return 1 }
        let started = Double(maxLives[index])
        guard started > 0 else { return 0 }
        return max(0, min(1, left / started))
    }

    /// Ages every body, and removes the ones that have run out.
    ///
    /// - Returns: how many were removed.
    ///
    /// Does nothing at all when nothing can expire, which is almost every scene — so the cost of having
    /// lifetimes is nought until something uses one.
    @discardableResult
    public func age(by moments: Double = 1) -> Int {
        guard hasMortalBodies, count > 0 else { return 0 }
        let step = Float(moments.isFinite ? max(0, moments) : 0)
        guard step > 0 else { return 0 }

        var anyMortal = false
        for index in 0 ..< count where lives[index] >= 0 {
            lives[index] = max(0, lives[index] - step)
            if lives[index] > 0 { anyMortal = true }
        }
        hasMortalBodies = anyMortal
        return removeExpired()
    }

    /// Removes every body whose life has run out, and every one marked for removal.
    ///
    /// Swap-with-last, which is the only way to remove from the middle of a packed list without moving
    /// everything after it. The consequence is that the order changes, which nothing here depends on — the
    /// crowd carries no springs and nothing holds a position in it between ticks.
    @discardableResult
    public func removeExpired() -> Int {
        guard count > 0 else { return 0 }
        var removed = 0
        var index = 0
        while index < count {
            if lives[index] == 0 {
                let last = count - 1
                if index != last {
                    let here = index * 2
                    let there = last * 2
                    positions[here] = positions[there]
                    positions[here + 1] = positions[there + 1]
                    velocities[here] = velocities[there]
                    velocities[here + 1] = velocities[there + 1]
                    colors[index] = colors[last]
                    masses[index] = masses[last]
                    lives[index] = lives[last]
                    maxLives[index] = maxLives[last]
                }
                count = last
                removed += 1
                // Deliberately not advancing: whatever was moved into this place has not been looked at.
                continue
            }
            index += 1
        }
        if removed > 0 { generation += 1 }
        return removed
    }

    /// Marks a body to be removed by the next sweep.
    ///
    /// Marked rather than removed at once, because this is called from inside the loop that is walking the
    /// bodies — and removing one there would move an unvisited body into a place already passed.
    func markForRemoval(at index: Int) {
        guard index >= 0, index < count else { return }
        lives[index] = 0
        hasMortalBodies = true
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
        /// How bodies in the crowd meet one another.
        ///
        /// Given a default so that adding it did not have to change every caller — of which the tests are
        /// most, and they are testing the physics rather than the contact numbers.
        public var contact: ContactSettings = .default

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
            attract: Bool,
            contact: ContactSettings = .default
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
            self.contact = contact
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

        // Each stage below lands back in the buffers, which are single precision, so
        // each stage rounds. That is deliberate rather than incidental: the stored
        // velocity *is* the body's velocity, and the position update has to use the
        // value that was stored, not a more precise one carried alongside it. Holding
        // doubles across the whole update instead would be marginally more accurate,
        // would no longer match the reference implementation, and would model something
        // the buffers cannot actually represent.
        for i in 0 ..< count {
            let pair = i * 2

            velocities[pair] = JS.toFloat32(velocities[pair].asDouble * damping + options.gravityX)
            velocities[pair + 1] = JS.toFloat32(
                velocities[pair + 1].asDouble * damping + options.gravityY
            )

            if options.mouseActive {
                let dx = options.mouseX - positions[pair].asDouble
                let dy = options.mouseY - positions[pair + 1].asDouble
                let distanceSquared = dx * dx + dy * dy
                if distanceSquared < radiusSquared && distanceSquared > 0.5 {
                    let inverse = force / distanceSquared.squareRoot()
                    velocities[pair] = JS.toFloat32(velocities[pair].asDouble + dx * inverse)
                    velocities[pair + 1] = JS.toFloat32(velocities[pair + 1].asDouble + dy * inverse)
                }
            }

            // The same speed limit the object particles obey. The web swarm had none
            // at all, so the one slider the interface offers governed a few hundred
            // bodies and ignored the other million.
            let velX = velocities[pair].asDouble
            let velY = velocities[pair + 1].asDouble
            let speedSquared = velX * velX + velY * velY
            if speedSquared > maxSpeedSquared && speedSquared > 0 {
                let scale = maxSpeed / speedSquared.squareRoot()
                velocities[pair] = JS.toFloat32(velX * scale)
                velocities[pair + 1] = JS.toFloat32(velY * scale)
            }

            positions[pair] = JS.toFloat32(positions[pair].asDouble + velocities[pair].asDouble)
            positions[pair + 1] = JS.toFloat32(
                positions[pair + 1].asDouble + velocities[pair + 1].asDouble
            )

            if wrapping {
                if width > 0 {
                    let x = positions[pair].asDouble
                    positions[pair] = JS.toFloat32(
                        ((x.truncatingRemainder(dividingBy: width)) + width)
                            .truncatingRemainder(dividingBy: width)
                    )
                }
                if height > 0 {
                    let y = positions[pair + 1].asDouble
                    positions[pair + 1] = JS.toFloat32(
                        ((y.truncatingRemainder(dividingBy: height)) + height)
                            .truncatingRemainder(dividingBy: height)
                    )
                }
                continue
            }

            // Vanishing used to fall back to bouncing here, because there was no per-body lifetime and a
            // body left outside the world would never come back. There is one now, so it works: a body that
            // has left is marked, and the sweep after the loop removes it.
            if options.boundaryMode == .void {
                let x = positions[pair].asDouble
                let y = positions[pair + 1].asDouble
                if x < -10 || x > width + 10 || y < -10 || y > height + 10 {
                    markForRemoval(at: i)
                    continue
                }
            }

            if positions[pair].asDouble < 1 {
                positions[pair] = 1
                velocities[pair] = JS.toFloat32(velocities[pair].asDouble * -bounce)
            } else if positions[pair].asDouble > width - 1 {
                positions[pair] = JS.toFloat32(width - 1)
                velocities[pair] = JS.toFloat32(velocities[pair].asDouble * -bounce)
            }
            if positions[pair + 1].asDouble < 1 {
                positions[pair + 1] = 1
                velocities[pair + 1] = JS.toFloat32(velocities[pair + 1].asDouble * -bounce)
            } else if positions[pair + 1].asDouble > height - 1 {
                positions[pair + 1] = JS.toFloat32(height - 1)
                velocities[pair + 1] = JS.toFloat32(velocities[pair + 1].asDouble * -bounce)
            }
        }

        // Ageing before the contact pass, so a body that has expired is gone rather than spending its last
        // moment shoving its neighbours about.
        if hasMortalBodies { age(by: 1) } else { removeExpired() }

        if options.collide, count > 1 {
            // More than once, because moving one pair apart pushes each of them into somebody else — one
            // pass leaves stacks overlapping. Twice was the old fixed behaviour and is still the default.
            let contact = options.contact.sanitized
            for _ in 0 ..< contact.passes {
                resolveCollisions(width: width, height: height, contact: contact)
            }
        }
    }

    /// Pushes overlapping bodies apart, using a uniform grid to find neighbours.
    private func resolveCollisions(width: Double, height: Double, contact: ContactSettings) {
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
        // How wide a body counts as.
        //
        // Nought means work it out, which is what the field has always done: a little under the width of a
        // search square, and never below 3.2 so that a very coarse grid at a huge crowd does not make the
        // bodies enormous. Anything else is what somebody asked for — capped at the square's width, because
        // a body reaching beyond it would have neighbours the search never looks at, so it would pass
        // through some of them and not others depending only on which square each happened to fall in.
        let diameter = contact.size <= 0
            ? max(3.2, cell * 0.88)
            : max(1, min(contact.size, cell * 0.98))
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
                                // Shared by weight, so a heavy body barely moves and a light one is shoved.
                                // At equal weights this is exactly a half each, which is what the crowd did
                                // before weights existed — so the recorded comparison stays exact.
                                let ownMass = masses[i].asDouble
                                let otherMass = masses[other].asDouble
                                let totalMass = ownMass + otherMass
                                let ownShare = totalMass > 0 ? otherMass / totalMass : 0.5
                                posX += normalX * overlap * ownShare
                                posY += normalY * overlap * ownShare
                                // And the same for how much of the bounce this body takes. Twice the other
                                // body's share, so that equal weights give one — again, exactly the old
                                // behaviour.
                                let takenShare = totalMass > 0 ? 2 * otherMass / totalMass : 1

                                let otherVelX = velocities[otherPair].asDouble
                                let otherVelY = velocities[otherPair + 1].asDouble
                                let closing = (velX - otherVelX) * normalX + (velY - otherVelY) * normalY
                                if closing < 0 {
                                    velX -= normalX * closing * contact.bounciness * takenShare
                                    velY -= normalY * closing * contact.bounciness * takenShare
                                }
                                // Friction along the contact.
                                let relativeX = velX - otherVelX
                                let relativeY = velY - otherVelY
                                let alongNormal = relativeX * normalX + relativeY * normalY
                                let tangentX = relativeX - normalX * alongNormal
                                let tangentY = relativeY - normalY * alongNormal
                                velX -= tangentX * contact.friction * takenShare
                                velY -= tangentY * contact.friction * takenShare
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
        /// Weights, left empty when every body weighs one — which is almost always, and is four megabytes a
        /// save file at a million bodies.
        public var masses: [Float] = []
        /// Lifetimes, left empty when nothing expires.
        public var lives: [Float] = []
        public var count: Int { colors.count }
    }

    /// Copies out at most `limit` bodies.
    public func snapshot(limit: Int = .max) -> Snapshot {
        let taken = max(0, min(count, limit))
        var anyWeighted = false
        for index in 0 ..< taken where masses[index] != 1 {
            anyWeighted = true
            break
        }
        return Snapshot(
            positions: Array(UnsafeBufferPointer(start: positions, count: taken * 2)),
            velocities: Array(UnsafeBufferPointer(start: velocities, count: taken * 2)),
            colors: Array(UnsafeBufferPointer(start: colors, count: taken)),
            masses: anyWeighted ? Array(UnsafeBufferPointer(start: masses, count: taken)) : [],
            lives: hasMortalBodies ? Array(UnsafeBufferPointer(start: lives, count: taken)) : []
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
        // Absent means the plain answer — everything weighs one and lives forever — which is what the fresh
        // room was filled with, so there is nothing to do in that case.
        if !snapshot.masses.isEmpty {
            snapshot.masses.withUnsafeBufferPointer { source in
                masses.update(from: source.baseAddress!, count: min(actual, source.count))
            }
        } else {
            masses.update(repeating: 1, count: actual)
        }
        hasMortalBodies = false
        if !snapshot.lives.isEmpty {
            snapshot.lives.withUnsafeBufferPointer { source in
                lives.update(from: source.baseAddress!, count: min(actual, source.count))
            }
            for index in 0 ..< actual {
                maxLives[index] = max(1, lives[index])
                if lives[index] > 0 { hasMortalBodies = true }
            }
        } else {
            lives.update(repeating: -1, count: actual)
            maxLives.update(repeating: 1, count: actual)
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
