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
    /// What each body does beyond drifting under the world's forces. See ``Role``.
    ///
    /// Nought for every body until something says otherwise, and a body with no role takes exactly the path
    /// through the tick that every body took before roles existed — which is what keeps the recorded
    /// comparison against the reference implementation exact.
    public private(set) var roles: UnsafeMutablePointer<UInt8>
    /// Where a body that holds a shape belongs, six numbers a body. See ``Home``.
    ///
    /// Read only for bodies whose role says they hold a shape; for everything else it is left at nought.
    public private(set) var homes: UnsafeMutablePointer<Float>

    /// Whether any body has a role at all, so a crowd with none pays nothing for the feature.
    public private(set) var hasRoles = false

    /// How wide each body is, as a diameter in the world's pixels at the size slider's resting value.
    ///
    /// Nought means the body has no size of its own and is drawn at whatever the size slider says, which is
    /// every body until something sets otherwise. It exists so that bodies added to an arrangement can be
    /// the size of the arrangement's own — the stars joining a galaxy the size of its stars — rather than
    /// all being one size whatever they joined.
    public private(set) var sizes: UnsafeMutablePointer<Float>

    /// Whether any body has a size of its own, so a crowd with none sends no sizes to the screen.
    public private(set) var hasSizes = false

    /// How far into the screen each body is, for the field in 3D. Nought for every body in a flat field.
    ///
    /// Kept apart from ``positions`` rather than making those triples, so that a flat field — every recorded
    /// comparison, and everything built before there was depth — reads and writes exactly the numbers it
    /// always has. Positive is away from somebody looking at the field from the front; nought is the middle.
    public private(set) var depths: UnsafeMutablePointer<Float>
    /// How fast each body is moving into or out of the screen.
    public private(set) var depthVelocities: UnsafeMutablePointer<Float>
    /// How far into the screen the place a shape-holding body belongs is. See ``Home/anchorZ``.
    public private(set) var homeDepths: UnsafeMutablePointer<Float>
    /// Whether any body might be anywhere but the middle, so a flat crowd saves and copies no depths.
    public internal(set) var hasDepth = false

    /// What a body in the crowd does, as a set of flags.
    ///
    /// ## Why the crowd needed these
    ///
    /// The crowd used to be positions, speeds and colours and nothing else, so everything in it behaved
    /// identically: it fell, it bounced, it was pushed by a finger. That is why a sunflower laid out seed by
    /// seed collapsed onto the floor the moment it appeared, and why ten thousand bodies added to a galaxy
    /// ignored the black hole entirely and scattered. A body in the crowd can now *orbit* — it keeps its
    /// speed rather than being dragged down by the world's gravity and air — and it can *hold* a place in a
    /// shape, drawn back to it by a spring, so a finger can push the shape about and it reforms.
    public struct Role: OptionSet, Sendable, Hashable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        /// Keeps its speed: exempt from the world's gravity and air friction, as orbiting object bodies are.
        public static let orbits = Role(rawValue: 1)
        /// Drawn back to a place in a shape. See ``Home``.
        public static let holds = Role(rawValue: 2)
        /// Its place turns round a level circle rather than one in the plane of the screen, so a shape in 3D
        /// turns the way a globe turns on its stand. See ``Home``.
        ///
        /// In a flat field only the sideways half of that circle can be seen, so the body swings from side to
        /// side — which is exactly how a turning globe looks from the front when it is drawn flat.
        public static let upright = Role(rawValue: 4)
        /// Its place goes round a circle standing across the screen — up, down, and in and out of it — so the
        /// body rises and falls. Squashed to a line, it bobs straight up and down, which with each body a little
        /// behind its neighbour is a wave running over a surface.
        public static let bobs = Role(rawValue: 8)

        /// Every role this build understands. Anything else in a file from a later build is dropped.
        static let known: UInt8 = Role.orbits.rawValue | Role.holds.rawValue | Role.upright.rawValue
            | Role.bobs.rawValue
    }

    /// Where a shape-holding body belongs.
    ///
    /// Written as a point on a circle round an anchor, because that single description covers every way a
    /// shape here moves: a still point is a circle of radius nought; a sunflower or a mandala turning is a
    /// circle whose angle advances; a tornado seen from the side is a circle flattened to a line, so the body
    /// swings from side to side; an aurora's curtain is the same flattened circle with the angle staggered
    /// down its length, which is a wave.
    public struct Home: Sendable, Hashable {
        public var anchorX: Double
        public var anchorY: Double
        public var radius: Double
        public var angle: Double
        /// How far the angle advances each moment, in radians. Nought holds still.
        public var spin: Double
        /// How much of the circle's height survives: one is a circle, nought a line.
        public var squash: Double
        /// How hard the body is pulled back to its place.
        ///
        /// Per body, because a still shape and a spinning one want opposite things. A still shape wants a soft
        /// spring, so a finger can dent it visibly and it eases back. A tornado wants a stiff one: its bodies
        /// chase a place moving round a funnel several times a second, and a soft spring cannot keep up — it
        /// lags, then overshoots, and near its own natural rhythm it swings wider and wider.
        public var stiffness: Double
        /// How far into the screen the anchor is, for the field in 3D. Nought in a flat field.
        public var anchorZ: Double

        public init(
            anchorX: Double,
            anchorY: Double,
            radius: Double = 0,
            angle: Double = 0,
            spin: Double = 0,
            squash: Double = 1,
            stiffness: Double = Swarm.holdStiffness,
            anchorZ: Double = 0
        ) {
            self.anchorX = anchorX
            self.anchorY = anchorY
            self.radius = radius
            self.angle = angle
            self.spin = spin
            self.squash = squash
            self.stiffness = stiffness
            self.anchorZ = anchorZ
        }

        /// A place that does not move.
        public static func fixed(_ x: Double, _ y: Double) -> Home {
            Home(anchorX: x, anchorY: y)
        }

        /// A place that does not move, somewhere in depth.
        public static func fixed(_ x: Double, _ y: Double, _ z: Double) -> Home {
            Home(anchorX: x, anchorY: y, anchorZ: z)
        }

        /// Where the body belongs right now.
        public var point: (x: Double, y: Double) {
            (anchorX + jsCos(angle) * radius, anchorY + jsSin(angle) * radius * squash)
        }

        /// Where the body belongs right now, depth included.
        ///
        /// - Parameter role: which way its circle stands. A level circle — ``Role/upright`` — goes round
        ///   through depth and leaves the height alone; one standing across the screen — ``Role/bobs`` — rises
        ///   and falls. Otherwise the circle is in the plane of the screen, as it is in a flat field.
        public func point(for role: Role) -> (x: Double, y: Double, z: Double) {
            if role.contains(.upright) {
                return (anchorX + jsCos(angle) * radius, anchorY, anchorZ + jsSin(angle) * radius * squash)
            }
            if role.contains(.bobs) {
                return (anchorX, anchorY + jsSin(angle) * radius, anchorZ + jsCos(angle) * radius * squash)
            }
            let flat = point
            return (flat.x, flat.y, anchorZ)
        }

        /// Where the body belongs on a flat field: what can be seen of its circle from the front.
        public func flatPoint(for role: Role) -> (x: Double, y: Double) {
            if role.contains(.upright) { return (anchorX + jsCos(angle) * radius, anchorY) }
            if role.contains(.bobs) { return (anchorX, anchorY + jsSin(angle) * radius) }
            return point
        }
    }

    /// How many numbers each home takes.
    static let homeStride = 7

    /// How hard a shape pulls its bodies back, and how much of their speed a held body keeps each moment.
    ///
    /// The stiffness is the default for a still shape: soft enough that a finger visibly dents it, firm enough
    /// that it reforms within a couple of seconds. The friction is what stops the spring ringing forever —
    /// without it a pushed shape would oscillate about its outline indefinitely.
    public static let holdStiffness = 0.005
    public static let holdFriction = 0.94

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

    /// The cubes the collision pass files bodies under in a field with depth. Made the first time it is needed.
    lazy var depthHash = SwarmHash3D()

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
        self.sizes = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        self.sizes.initialize(repeating: 0, count: 1)
        self.depths = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        self.depths.initialize(repeating: 0, count: 1)
        self.depthVelocities = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        self.depthVelocities.initialize(repeating: 0, count: 1)
        self.homeDepths = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        self.homeDepths.initialize(repeating: 0, count: 1)
        self.roles = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        self.homes = UnsafeMutablePointer<Float>.allocate(capacity: Self.homeStride)
        self.roles.initialize(repeating: 0, count: 1)
        self.homes.initialize(repeating: 0, count: Self.homeStride)
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
        roles.deinitialize(count: allocated)
        roles.deallocate()
        homes.deinitialize(count: allocated * Self.homeStride)
        homes.deallocate()
        sizes.deinitialize(count: allocated)
        sizes.deallocate()
        depths.deinitialize(count: allocated)
        depths.deallocate()
        depthVelocities.deinitialize(count: allocated)
        depthVelocities.deallocate()
        homeDepths.deinitialize(count: allocated)
        homeDepths.deallocate()
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
        hasRoles = false
        hasSizes = false
        hasDepth = false
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
        let newSizes = UnsafeMutablePointer<Float>.allocate(capacity: target)
        newSizes.initialize(repeating: 0, count: target)
        let newDepths = UnsafeMutablePointer<Float>.allocate(capacity: target)
        newDepths.initialize(repeating: 0, count: target)
        let newDepthVelocities = UnsafeMutablePointer<Float>.allocate(capacity: target)
        newDepthVelocities.initialize(repeating: 0, count: target)
        let newHomeDepths = UnsafeMutablePointer<Float>.allocate(capacity: target)
        newHomeDepths.initialize(repeating: 0, count: target)
        let newRoles = UnsafeMutablePointer<UInt8>.allocate(capacity: target)
        let newHomes = UnsafeMutablePointer<Float>.allocate(capacity: target * Self.homeStride)
        newRoles.initialize(repeating: 0, count: target)
        newHomes.initialize(repeating: 0, count: target * Self.homeStride)
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
            newRoles.update(from: roles, count: count)
            newSizes.update(from: sizes, count: count)
            newHomes.update(from: homes, count: count * Self.homeStride)
            newDepths.update(from: depths, count: count)
            newDepthVelocities.update(from: depthVelocities, count: count)
            newHomeDepths.update(from: homeDepths, count: count)
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
        roles.deinitialize(count: previous)
        roles.deallocate()
        sizes.deinitialize(count: previous)
        sizes.deallocate()
        homes.deinitialize(count: previous * Self.homeStride)
        homes.deallocate()
        depths.deinitialize(count: previous)
        depths.deallocate()
        depthVelocities.deinitialize(count: previous)
        depthVelocities.deallocate()
        homeDepths.deinitialize(count: previous)
        homeDepths.deallocate()

        depths = newDepths
        depthVelocities = newDepthVelocities
        homeDepths = newHomeDepths
        positions = newPositions
        velocities = newVelocities
        colors = newColors
        masses = newMasses
        lives = newLives
        maxLives = newMaxLives
        roles = newRoles
        homes = newHomes
        sizes = newSizes
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
        rng: inout Mulberry32,
        span requestedSpan: Double? = nil,
        size: Double = 0,
        inDepth depth: Double = 0
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
        // How far out the ring reaches. The caller can say, so a crowd scattered after zooming out is the size
        // it would have been on the screen rather than filling the whole grown world.
        let span = requestedSpan.map { $0.isFinite ? max(0, $0) : 0 } ?? min(width, height) * 0.42
        let ownSize = Float(size.isFinite ? max(0, size) : 0)
        if ownSize > 0 { hasSizes = true }

        let start = count
        // In 3D the ring becomes a ball: the same spread from the middle, in every direction rather than only
        // across the screen, and kept inside however deep the world is.
        if depth > 0, depth.isFinite {
            let halfDepth = depth * 0.5 - 2
            for i in start ..< (start + actual) {
                let angle = rng.next() * Double.pi * 2
                let distance = rng.next() * span + 20
                // Evenly over the sphere: the height is even, and the circle at that height is as wide as the
                // sphere is there.
                let rise = rng.next() * 2 - 1
                let across = (1 - rise * rise).squareRoot()
                let pair = i * 2
                positions[pair] = JS.toFloat32(centreX + jsCos(angle) * across * distance)
                positions[pair + 1] = JS.toFloat32(centreY + rise * distance)
                depths[i] = JS.toFloat32(max(-halfDepth, min(halfDepth, jsSin(angle) * across * distance)))
                velocities[pair] = JS.toFloat32((rng.next() - 0.5) * 6)
                velocities[pair + 1] = JS.toFloat32((rng.next() - 0.5) * 6)
                depthVelocities[i] = JS.toFloat32((rng.next() - 0.5) * 6)
                homeDepths[i] = 0
                masses[i] = 1
                lives[i] = -1
                maxLives[i] = 1
                roles[i] = 0
                sizes[i] = ownSize
                colors[i] = color != 0
                    ? color
                    : 0xFF00_0000 | UInt32((i * 97) & 255)
                        | (UInt32((i * 57) & 255) << 8)
                        | (UInt32((i * 13) & 255) << 16)
            }
            hasDepth = true
            count = start + actual
            generation += 1
            return
        }

        for i in start ..< (start + actual) {
            let angle = rng.next() * Double.pi * 2
            let distance = rng.next() * span + 20
            let pair = i * 2
            positions[pair] = JS.toFloat32(centreX + jsCos(angle) * distance)
            positions[pair + 1] = JS.toFloat32(centreY + jsSin(angle) * distance)
            depths[i] = 0
            depthVelocities[i] = 0
            homeDepths[i] = 0
            velocities[pair] = JS.toFloat32((rng.next() - 0.5) * 6)
            velocities[pair + 1] = JS.toFloat32((rng.next() - 0.5) * 6)
            // `!= 0`, not truthiness: a deliberately black or transparent colour is a
            // legitimate request that the web version silently replaced.
            masses[i] = 1
            lives[i] = -1
            maxLives[i] = 1
            roles[i] = 0
            sizes[i] = ownSize
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
            // A held shape has to move with its bodies, or it snaps back to where the world used to be.
            if hasRoles, roles[index] & Role.holds.rawValue != 0 {
                let at = index * Self.homeStride
                homes[at] += shiftX
                homes[at + 1] += shiftY
            }
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
        life: Double = -1,
        role: Role = [],
        home: Home? = nil,
        size: Double = 0,
        z: Double = 0,
        velocityZ: Double = 0
    ) -> Bool {
        guard count < min(Self.maximumCount, budget) else { return false }
        reserve(count + 1)
        guard count < capacity else { return false }

        let index = count
        // A body that holds a shape with nowhere to hold it would be pulled toward the top-left corner, so
        // without a home it holds where it was put.
        let usableZ = z.isFinite ? z : 0
        let usableVelocityZ = velocityZ.isFinite ? velocityZ : 0
        let place = home ?? Home.fixed(x, y, usableZ)
        writeRole(role, home: place, at: index)
        let ownSize = size.isFinite ? max(0, min(400, size)) : 0
        sizes[index] = Float(ownSize)
        if ownSize > 0 { hasSizes = true }
        depths[index] = JS.toFloat32(usableZ)
        depthVelocities[index] = JS.toFloat32(usableVelocityZ)
        if usableZ != 0 || usableVelocityZ != 0 || homeDepths[index] != 0 { hasDepth = true }
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

    /// Stores a body's role and home.
    private func writeRole(_ role: Role, home: Home, at index: Int) {
        roles[index] = role.rawValue
        if !role.isEmpty { hasRoles = true }
        let at = index * Self.homeStride
        homeDepths[index] = role.contains(.holds) && home.anchorZ.isFinite ? JS.toFloat32(home.anchorZ) : 0
        if homeDepths[index] != 0 { hasDepth = true }
        if role.contains(.holds) {
            homes[at] = JS.toFloat32(home.anchorX.isFinite ? home.anchorX : 0)
            homes[at + 1] = JS.toFloat32(home.anchorY.isFinite ? home.anchorY : 0)
            homes[at + 2] = JS.toFloat32(home.radius.isFinite ? home.radius : 0)
            homes[at + 3] = JS.toFloat32(home.angle.isFinite ? home.angle : 0)
            homes[at + 4] = JS.toFloat32(home.spin.isFinite ? home.spin : 0)
            homes[at + 5] = JS.toFloat32(home.squash.isFinite ? home.squash : 1)
            homes[at + 6] = JS.toFloat32(
                home.stiffness.isFinite ? max(0, min(0.5, home.stiffness)) : Self.holdStiffness
            )
        } else {
            for k in 0 ..< Self.homeStride { homes[at + k] = 0 }
        }
    }

    /// Changes one body's role, and where it belongs if it now holds a shape.
    public func setRole(_ role: Role, home: Home? = nil, at index: Int) {
        guard index >= 0, index < count else { return }
        let pair = index * 2
        writeRole(
            role,
            home: home ?? Home.fixed(Double(positions[pair]), Double(positions[pair + 1]), Double(depths[index])),
            at: index
        )
    }

    /// One body's role.
    public func role(at index: Int) -> Role {
        guard index >= 0, index < count else { return [] }
        return Role(rawValue: roles[index])
    }

    /// Where one body belongs, if it holds a shape.
    public func home(at index: Int) -> Home? {
        guard index >= 0, index < count, Role(rawValue: roles[index]).contains(.holds) else { return nil }
        let at = index * Self.homeStride
        return Home(
            anchorX: Double(homes[at]),
            anchorY: Double(homes[at + 1]),
            radius: Double(homes[at + 2]),
            angle: Double(homes[at + 3]),
            spin: Double(homes[at + 4]),
            squash: Double(homes[at + 5]),
            stiffness: Double(homes[at + 6]),
            anchorZ: Double(homeDepths[index])
        )
    }

    /// Sets how far into the screen one body is, and how fast it is moving that way.
    public func setDepth(_ z: Double, velocity: Double = 0, at index: Int) {
        guard index >= 0, index < count else { return }
        let usable = z.isFinite ? z : 0
        let moving = velocity.isFinite ? velocity : 0
        depths[index] = JS.toFloat32(usable)
        depthVelocities[index] = JS.toFloat32(moving)
        if usable != 0 || moving != 0 { hasDepth = true }
    }

    /// Moves the place a shape-holding body belongs into or out of the screen.
    public func setHomeDepth(_ z: Double, at index: Int) {
        guard index >= 0, index < count, Role(rawValue: roles[index]).contains(.holds) else { return }
        homeDepths[index] = JS.toFloat32(z.isFinite ? z : 0)
        if homeDepths[index] != 0 { hasDepth = true }
    }

    /// Puts every body on the middle sheet, still in depth, as a flat field has them.
    ///
    /// What turning 3D off does to a crowd with nothing to be rebuilt as. Nothing else about a body changes:
    /// where it is across and down the screen, its speed there, its colour and its place in a shape all stay.
    public func flattenDepth() {
        guard hasDepth || count > 0 else { return }
        depths.update(repeating: 0, count: max(1, count))
        depthVelocities.update(repeating: 0, count: max(1, count))
        homeDepths.update(repeating: 0, count: max(1, count))
        hasDepth = false
        generation += 1
    }

    /// Notes that the bodies may now be off the middle sheet — the step in depth moves them there.
    func noteDepthInUse() {
        if count > 0 { hasDepth = true }
    }

    /// Sets one body's own size, as a diameter at the size slider's resting value. Nought means none.
    public func setSize(_ size: Double, at index: Int) {
        guard index >= 0, index < count else { return }
        let ownSize = size.isFinite ? max(0, min(400, size)) : 0
        sizes[index] = Float(ownSize)
        if ownSize > 0 { hasSizes = true }
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
        // Nought is "remove it", which the next sweep only does if it is told something may have expired.
        if usable >= 0 { hasMortalBodies = true }
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
                    roles[index] = roles[last]
                    sizes[index] = sizes[last]
                    depths[index] = depths[last]
                    depthVelocities[index] = depthVelocities[last]
                    homeDepths[index] = homeDepths[last]
                    let homeHere = index * Self.homeStride
                    let homeThere = last * Self.homeStride
                    for k in 0 ..< Self.homeStride { homes[homeHere + k] = homes[homeThere + k] }
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
        /// How bodies in the crowd meet one another.
        ///
        /// Given a default so that adding it did not have to change every caller — of which the tests are
        /// most, and they are testing the physics rather than the contact numbers.
        public var contact: ContactSettings = .default
        /// Leave removing the dead to the caller, after this moment's walls.
        ///
        /// Removing a body moves the last one into its place, and the walls read where each body was before
        /// the move by its place in the list — so a removal between the two made a wall read one body's
        /// history as another's, and push a body that had never touched it to the far side.
        public var deferAgeing: Bool = false
        /// Where a finger is freezing the crowd, and how far it reaches. A reach of nought means no finger is
        /// freezing anything; an infinite one means the whole field.
        ///
        /// Here rather than only in the brush, because the brush runs before this moment's gravity, a shape's
        /// hold and everything else — so a body it had stopped was set moving again straight away, and a frozen
        /// crowd crept downward and frozen seeds crept after their turning places. Stopped here, after all of
        /// that and just before anything moves, frozen means still.
        public var freezeX: Double = 0
        public var freezeY: Double = 0
        public var freezeReach: Double = 0
        /// How deep the world is, for the field in 3D. Nought is a flat field, which moves exactly as it always
        /// has; anything more moves every body through depth too, inside a box that deep.
        public var depth: Double = 0
        /// In 3D, the line from the eye through the finger that is freezing, if there is one. A frozen body is
        /// anything that appears inside the finger's circle, however far away — not only what is level with it.
        public var freezeRay: ParticleFingerRay?

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
            contact: ContactSettings = .default,
            deferAgeing: Bool = false,
            freezeX: Double = 0,
            freezeY: Double = 0,
            freezeReach: Double = 0,
            depth: Double = 0,
            freezeRay: ParticleFingerRay? = nil
        ) {
            self.depth = depth.isFinite ? max(0, depth) : 0
            self.freezeRay = freezeRay
            self.width = width
            self.height = height
            self.gravityX = gravityX
            self.gravityY = gravityY
            self.damping = damping
            self.elasticity = elasticity
            self.collide = collide
            self.maxSpeed = maxSpeed
            self.boundaryMode = boundaryMode
            self.contact = contact
            self.deferAgeing = deferAgeing
            self.freezeX = freezeX
            self.freezeY = freezeY
            self.freezeReach = freezeReach
        }
    }

    /// Advances every body one tick.
    public func step(_ options: StepOptions) {
        guard count > 0 else { return }
        // In 3D, a pass of its own. The flat pass below is left exactly as it was — rather than sharing one loop
        // full of "and in depth" — so that nothing about depth can change a flat field by so much as a rounding.
        if options.depth > 0 {
            moveInDepth(options)
            settle(options)
            return
        }

        let width = options.width
        let height = options.height
        let damping = options.damping
        let bounce = options.elasticity
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
        let anyRoles = hasRoles
        let holdsBit = Role.holds.rawValue
        let orbitsBit = Role.orbits.rawValue
        let uprightBit = Role.upright.rawValue
        let turnsInDepthBits = Role.upright.rawValue | Role.bobs.rawValue
        let freezeX = options.freezeX
        let freezeY = options.freezeY
        let freezing = options.freezeReach > 0 && freezeX.isFinite && freezeY.isFinite
        let freezesEverything = freezing && !options.freezeReach.isFinite
        let freezeReachSquared = freezing && !freezesEverything ? options.freezeReach * options.freezeReach : 0
        for i in 0 ..< count {
            let pair = i * 2

            let role = anyRoles ? roles[i] : 0
            if role == 0 {
                velocities[pair] = JS.toFloat32(velocities[pair].asDouble * damping + options.gravityX)
                velocities[pair + 1] = JS.toFloat32(
                    velocities[pair + 1].asDouble * damping + options.gravityY
                )
            } else {
                var velX = velocities[pair].asDouble
                var velY = velocities[pair + 1].asDouble
                if role & holdsBit != 0 {
                    // Where it belongs this moment, and then the angle moves on so a turning shape turns.
                    let at = i * Self.homeStride
                    let radius = homes[at + 2].asDouble
                    let angle = homes[at + 3].asDouble
                    let spin = homes[at + 4].asDouble
                    var homeX = homes[at].asDouble
                    var homeY = homes[at + 1].asDouble
                    if radius != 0 {
                        if role & turnsInDepthBits == 0 {
                            homeX += jsCos(angle) * radius
                            homeY += jsSin(angle) * radius * homes[at + 5].asDouble
                        } else if role & uprightBit != 0 {
                            // A level circle seen from the front: all of it is sideways.
                            homeX += jsCos(angle) * radius
                        } else {
                            // A circle standing across the screen, seen from the front: all of it is up and down.
                            homeY += jsSin(angle) * radius
                        }
                    }
                    if spin != 0 {
                        // Kept inside one turn, so a shape left spinning for an hour does not lose the
                        // precision a single-precision angle needs.
                        var next = angle + spin
                        if next > 6.283185307179586 { next -= 6.283185307179586 }
                        if next < -6.283185307179586 { next += 6.283185307179586 }
                        homes[at + 3] = JS.toFloat32(next)
                    }
                    let stiffness = homes[at + 6].asDouble
                    velX = (velX + (homeX - positions[pair].asDouble) * stiffness) * Self.holdFriction
                    velY = (velY + (homeY - positions[pair + 1].asDouble) * stiffness) * Self.holdFriction
                }
                if role & orbitsBit == 0 {
                    velX = velX * damping + options.gravityX
                    velY = velY * damping + options.gravityY
                }
                velocities[pair] = JS.toFloat32(velX)
                velocities[pair + 1] = JS.toFloat32(velY)
            }

            if freezing {
                let dx = positions[pair].asDouble - freezeX
                let dy = positions[pair + 1].asDouble - freezeY
                if freezesEverything || dx * dx + dy * dy < freezeReachSquared {
                    velocities[pair] = 0
                    velocities[pair + 1] = 0
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
                }
                // And nothing else. The edges below used to catch every body still within ten pixels of the
                // world and bounce it back, so anything moving slower than that never left — the edge that
                // makes things disappear was a wall for everything but the fastest.
                continue
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
        //
        // Only when something can expire. This used to sweep every body looking for the dead on every moment
        // even when nothing could die — a million-body scan a frame that never found anything, since marking
        // a body for removal already says that something might.
        settle(options)
    }

    /// What follows the move in either pass: ageing, then pushing overlapping bodies apart.
    private func settle(_ options: StepOptions) {
        if hasMortalBodies, !options.deferAgeing { age(by: 1) }

        if options.collide, count > 1 {
            // More than once, because moving one pair apart pushes each of them into somebody else — one
            // pass leaves stacks overlapping. Twice was the old fixed behaviour and is still the default.
            let contact = options.contact.sanitized
            // Where things disappear at the edge, pushing a body apart from its neighbours must not also put it
            // back inside the world — which is what kept slow bodies from ever leaving.
            let keepsInside = options.boundaryMode != .void
            for _ in 0 ..< contact.passes {
                if options.depth > 0 {
                    resolveCollisionsInDepth(
                        width: options.width,
                        height: options.height,
                        depth: options.depth,
                        contact: contact,
                        hash: depthHash,
                        keepsInside: keepsInside
                    )
                } else {
                    resolveCollisions(width: options.width, height: options.height, contact: contact, keepsInside: keepsInside)
                }
            }
        }
    }

    /// One moment for every body in a field with depth.
    ///
    /// The flat pass, with a third direction added throughout: held bodies are drawn back to their place in
    /// depth as well, the air slows movement into the screen as it slows movement across it, the speed limit
    /// counts all three directions, and the world is a box rather than a rectangle — so a body reaching its
    /// front or back bounces, wraps round or vanishes as it would at any other edge. Gravity stays downward.
    private func moveInDepth(_ options: StepOptions) {
        let width = options.width
        let height = options.height
        let halfDepth = options.depth * 0.5
        let damping = options.damping
        let bounce = options.elasticity
        let maxSpeed = options.maxSpeed > 0 ? options.maxSpeed : Double.infinity
        let maxSpeedSquared = maxSpeed * maxSpeed
        let wrapping = options.boundaryMode == .wrap
        let vanishing = options.boundaryMode == .void

        let anyRoles = hasRoles
        let holdsBit = Role.holds.rawValue
        let orbitsBit = Role.orbits.rawValue
        let uprightBit = Role.upright.rawValue
        let bobsBit = Role.bobs.rawValue

        let freezeRay = options.freezeRay
        let freezeReach = options.freezeReach
        let freezing = freezeReach > 0
        let freezesEverything = freezing && !freezeReach.isFinite
        let freezeReachSquared = freezing && !freezesEverything ? freezeReach * freezeReach : 0

        for i in 0 ..< count {
            let pair = i * 2
            var velX = velocities[pair].asDouble
            var velY = velocities[pair + 1].asDouble
            var velZ = depthVelocities[i].asDouble

            let role = anyRoles ? roles[i] : 0
            if role & holdsBit != 0 {
                let at = i * Self.homeStride
                let radius = homes[at + 2].asDouble
                let angle = homes[at + 3].asDouble
                let spin = homes[at + 4].asDouble
                var homeX = homes[at].asDouble
                var homeY = homes[at + 1].asDouble
                var homeZ = homeDepths[i].asDouble
                if radius != 0 {
                    let squash = homes[at + 5].asDouble
                    if role & uprightBit != 0 {
                        homeX += jsCos(angle) * radius
                        homeZ += jsSin(angle) * radius * squash
                    } else if role & bobsBit != 0 {
                        homeY += jsSin(angle) * radius
                        homeZ += jsCos(angle) * radius * squash
                    } else {
                        homeX += jsCos(angle) * radius
                        homeY += jsSin(angle) * radius * squash
                    }
                }
                if spin != 0 {
                    var next = angle + spin
                    if next > 6.283185307179586 { next -= 6.283185307179586 }
                    if next < -6.283185307179586 { next += 6.283185307179586 }
                    homes[at + 3] = JS.toFloat32(next)
                }
                let stiffness = homes[at + 6].asDouble
                velX = (velX + (homeX - positions[pair].asDouble) * stiffness) * Self.holdFriction
                velY = (velY + (homeY - positions[pair + 1].asDouble) * stiffness) * Self.holdFriction
                velZ = (velZ + (homeZ - depths[i].asDouble) * stiffness) * Self.holdFriction
            }
            if role & orbitsBit == 0 {
                velX = velX * damping + options.gravityX
                velY = velY * damping + options.gravityY
                velZ *= damping
            }

            if freezing {
                let x = positions[pair].asDouble
                let y = positions[pair + 1].asDouble
                let z = depths[i].asDouble
                var inside = freezesEverything
                if !inside {
                    if let ray = freezeRay {
                        inside = ray.reaches(x: x, y: y, z: z, within: freezeReach)
                    } else {
                        // No line was given, which is a field seen from the front: everything level with the
                        // finger's circle, whatever its depth.
                        let dx = x - options.freezeX
                        let dy = y - options.freezeY
                        inside = dx * dx + dy * dy < freezeReachSquared
                    }
                }
                if inside {
                    velX = 0
                    velY = 0
                    velZ = 0
                }
            }

            let speedSquared = velX * velX + velY * velY + velZ * velZ
            if speedSquared > maxSpeedSquared && speedSquared > 0 {
                let scale = maxSpeed / speedSquared.squareRoot()
                velX *= scale
                velY *= scale
                velZ *= scale
            }
            velocities[pair] = JS.toFloat32(velX)
            velocities[pair + 1] = JS.toFloat32(velY)
            depthVelocities[i] = JS.toFloat32(velZ)

            positions[pair] = JS.toFloat32(positions[pair].asDouble + velocities[pair].asDouble)
            positions[pair + 1] = JS.toFloat32(positions[pair + 1].asDouble + velocities[pair + 1].asDouble)
            depths[i] = JS.toFloat32(depths[i].asDouble + depthVelocities[i].asDouble)

            if wrapping {
                if width > 0 {
                    let x = positions[pair].asDouble
                    positions[pair] = JS.toFloat32(
                        ((x.truncatingRemainder(dividingBy: width)) + width).truncatingRemainder(dividingBy: width)
                    )
                }
                if height > 0 {
                    let y = positions[pair + 1].asDouble
                    positions[pair + 1] = JS.toFloat32(
                        ((y.truncatingRemainder(dividingBy: height)) + height)
                            .truncatingRemainder(dividingBy: height)
                    )
                }
                let span = halfDepth * 2
                let z = depths[i].asDouble + halfDepth
                depths[i] = JS.toFloat32(
                    ((z.truncatingRemainder(dividingBy: span)) + span).truncatingRemainder(dividingBy: span)
                        - halfDepth
                )
                continue
            }

            if vanishing {
                let x = positions[pair].asDouble
                let y = positions[pair + 1].asDouble
                let z = depths[i].asDouble
                if x < -10 || x > width + 10 || y < -10 || y > height + 10 || z < -halfDepth - 10
                    || z > halfDepth + 10
                {
                    markForRemoval(at: i)
                }
                // Not bounced: see the same line in the flat pass.
                continue
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
            if depths[i].asDouble < -halfDepth + 1 {
                depths[i] = JS.toFloat32(-halfDepth + 1)
                depthVelocities[i] = JS.toFloat32(depthVelocities[i].asDouble * -bounce)
            } else if depths[i].asDouble > halfDepth - 1 {
                depths[i] = JS.toFloat32(halfDepth - 1)
                depthVelocities[i] = JS.toFloat32(depthVelocities[i].asDouble * -bounce)
            }
        }
        hasDepth = true
    }

    /// Pushes overlapping bodies apart, using a uniform grid to find neighbours.
    private func resolveCollisions(width: Double, height: Double, contact: ContactSettings, keepsInside: Bool = true) {
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

            if keepsInside {
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
        /// How long each body started with. Left empty when nothing expires.
        ///
        /// Carried separately because a body's fade and its colour by age are its life left *as a share of*
        /// what it started with. Without this, a restored body started over at full strength — every fading
        /// ember jumped back to solid the moment somebody pressed undo.
        public var maxLives: [Float] = []
        /// Roles, left empty when no body has one.
        public var roles: [UInt8] = []
        /// Homes, left empty when no body has a role.
        public var homes: [Float] = []
        /// Sizes of their own, left empty when no body has one.
        public var sizes: [Float] = []
        /// How far into the screen each body is, how fast it is moving that way, and how far in its place in a
        /// shape is. All three left empty in a flat field.
        public var depths: [Float] = []
        public var depthVelocities: [Float] = []
        public var homeDepths: [Float] = []
        public var count: Int { colors.count }

        /// Moves every body in the copy by the same amount, and the places the held ones belong along with
        /// them — as ``Swarm/translate(dx:dy:)`` does for the live crowd, so a copy kept for undo stays where
        /// the crowd is when the world grows round it.
        public mutating func translate(dx: Double, dy: Double) {
            guard dx.isFinite, dy.isFinite, dx != 0 || dy != 0 else { return }
            let shiftX = Float(dx)
            let shiftY = Float(dy)
            var pair = 0
            while pair + 1 < positions.count {
                positions[pair] += shiftX
                positions[pair + 1] += shiftY
                pair += 2
            }
            guard !roles.isEmpty, !homes.isEmpty else { return }
            let holds = Role.holds.rawValue
            for index in 0 ..< roles.count where roles[index] & holds != 0 {
                let at = index * Swarm.homeStride
                guard at + 1 < homes.count else { break }
                homes[at] += shiftX
                homes[at + 1] += shiftY
            }
        }

        public init(
            positions: [Float],
            velocities: [Float],
            colors: [UInt32],
            masses: [Float] = [],
            lives: [Float] = [],
            maxLives: [Float] = [],
            roles: [UInt8] = [],
            homes: [Float] = [],
            sizes: [Float] = [],
            depths: [Float] = [],
            depthVelocities: [Float] = [],
            homeDepths: [Float] = []
        ) {
            self.positions = positions
            self.velocities = velocities
            self.colors = colors
            self.masses = masses
            self.lives = lives
            self.maxLives = maxLives
            self.roles = roles
            self.homes = homes
            self.sizes = sizes
            self.depths = depths
            self.depthVelocities = depthVelocities
            self.homeDepths = homeDepths
        }
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
            lives: hasMortalBodies ? Array(UnsafeBufferPointer(start: lives, count: taken)) : [],
            maxLives: hasMortalBodies ? Array(UnsafeBufferPointer(start: maxLives, count: taken)) : [],
            roles: hasRoles ? Array(UnsafeBufferPointer(start: roles, count: taken)) : [],
            homes: hasRoles ? Array(UnsafeBufferPointer(start: homes, count: taken * Self.homeStride)) : [],
            sizes: hasSizes ? Array(UnsafeBufferPointer(start: sizes, count: taken)) : [],
            depths: hasDepth ? Array(UnsafeBufferPointer(start: depths, count: taken)) : [],
            depthVelocities: hasDepth ? Array(UnsafeBufferPointer(start: depthVelocities, count: taken)) : [],
            homeDepths: hasDepth ? Array(UnsafeBufferPointer(start: homeDepths, count: taken)) : []
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
            if let base = source.baseAddress { positions.update(from: base, count: min(actual * 2, source.count)) }
        }
        snapshot.velocities.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { velocities.update(from: base, count: min(actual * 2, source.count)) }
        }
        snapshot.colors.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { colors.update(from: base, count: min(actual, source.count)) }
        }
        // Absent means the plain answer — everything weighs one and lives forever — which is what the fresh
        // room was filled with, so there is nothing to do in that case.
        if !snapshot.masses.isEmpty {
            snapshot.masses.withUnsafeBufferPointer { source in
                if let base = source.baseAddress { masses.update(from: base, count: min(actual, source.count)) }
            }
        } else {
            masses.update(repeating: 1, count: actual)
        }
        hasMortalBodies = false
        if !snapshot.lives.isEmpty {
            snapshot.lives.withUnsafeBufferPointer { source in
                if let base = source.baseAddress { lives.update(from: base, count: min(actual, source.count)) }
            }
            let started = snapshot.maxLives
            for index in 0 ..< actual {
                // What it started with when that was kept, and otherwise the best guess there is: what it has
                // left, which at least never draws a body fainter than it was.
                let saved = index < started.count && started[index].isFinite ? started[index] : 0
                maxLives[index] = max(1, max(saved, lives[index]))
                if lives[index] >= 0 { hasMortalBodies = true }
            }
        } else {
            lives.update(repeating: -1, count: actual)
            maxLives.update(repeating: 1, count: actual)
        }
        hasRoles = false
        if !snapshot.roles.isEmpty {
            let usable = min(actual, snapshot.roles.count)
            for index in 0 ..< actual {
                let raw = index < usable ? snapshot.roles[index] : 0
                // Only the roles this build understands, so a file from a later one cannot switch on
                // behaviour that does not exist here.
                roles[index] = raw & Role.known
                if roles[index] != 0 { hasRoles = true }
            }
            let homeCount = actual * Self.homeStride
            for k in 0 ..< homeCount {
                let value = k < snapshot.homes.count ? snapshot.homes[k] : 0
                homes[k] = value.isFinite ? value : 0
            }
            // A body told to hold a shape with no usable home holds where it is.
            for index in 0 ..< actual where roles[index] & Role.holds.rawValue != 0
                && index * Self.homeStride + Self.homeStride > snapshot.homes.count
            {
                let at = index * Self.homeStride
                homes[at] = positions[index * 2]
                homes[at + 1] = positions[index * 2 + 1]
                homes[at + 2] = 0
                homes[at + 3] = 0
                homes[at + 4] = 0
                homes[at + 5] = 1
                homes[at + 6] = Float(Self.holdStiffness)
            }
        } else {
            roles.update(repeating: 0, count: actual)
        }
        hasSizes = false
        if !snapshot.sizes.isEmpty {
            for index in 0 ..< actual {
                let value = index < snapshot.sizes.count ? snapshot.sizes[index] : 0
                sizes[index] = value.isFinite ? max(0, min(400, value)) : 0
                if sizes[index] > 0 { hasSizes = true }
            }
        } else {
            sizes.update(repeating: 0, count: actual)
        }
        hasDepth = false
        func fill(_ target: UnsafeMutablePointer<Float>, from source: [Float], limit: Float) {
            for index in 0 ..< actual {
                let value = index < source.count ? source[index] : 0
                target[index] = value.isFinite ? max(-limit, min(limit, value)) : 0
                if target[index] != 0 { hasDepth = true }
            }
        }
        // Kept within a generous margin, as positions are: nothing legitimate is anywhere near it, and an
        // enormous number would reach whole-number conversions downstream that cannot hold it.
        let depthLimit: Float = 1_000_000
        fill(depths, from: snapshot.depths, limit: depthLimit)
        fill(depthVelocities, from: snapshot.depthVelocities, limit: 10_000)
        fill(homeDepths, from: snapshot.homeDepths, limit: depthLimit)
        count = actual
        generation += 1
    }

    // MARK: - Black holes and repulsors

    /// Something in the object list that pulls on everything, or pushes everything away.
    public struct Attractor: Sendable, Hashable {
        public var x: Double
        public var y: Double
        public var mass: Double
        public var radius: Double
        /// Pushes rather than pulls.
        public var repels: Bool
        /// How far into the screen it is, in a field with depth.
        public var z: Double

        public init(x: Double, y: Double, mass: Double, radius: Double, repels: Bool, z: Double = 0) {
            self.x = x
            self.y = y
            self.mass = mass
            self.radius = radius
            self.repels = repels
            self.z = z.isFinite ? z : 0
        }
    }

    /// The black holes and repulsors, in a field with depth.
    ///
    /// The same law, measured in all three directions. What differs is where a body goes when it reaches a
    /// black hole's edge. In a flat field there is only one plane to throw it back out into. In depth there is
    /// a choice, and it is the level one: the discs of every arrangement built in 3D lie level, as a galaxy's
    /// does, so a body re-emitted into a level orbit rejoins the disc — and the jets, now and then, go straight
    /// up and down out of it, which is where a real black hole's go.
    public func applyAttractorsInDepth(_ attractors: [Attractor], span: Double, rng: inout Mulberry32) {
        guard !attractors.isEmpty, count > 0 else { return }
        for i in 0 ..< count {
            let pair = i * 2
            var x = positions[pair].asDouble
            var y = positions[pair + 1].asDouble
            var z = depths[i].asDouble
            var velX = velocities[pair].asDouble
            var velY = velocities[pair + 1].asDouble
            var velZ = depthVelocities[i].asDouble
            var moved = false

            for attractor in attractors {
                let dx = attractor.x - x
                let dy = attractor.y - y
                let dz = attractor.z - z
                let distanceSquared = dx * dx + dy * dy + dz * dz + 10
                let distance = distanceSquared.squareRoot()
                let mass = attractor.mass == 0 ? 80 : attractor.mass
                if attractor.repels {
                    let force = (mass * 150) / distanceSquared
                    velX -= (dx / distance) * force
                    velY -= (dy / distance) * force
                    velZ -= (dz / distance) * force
                    continue
                }
                let edge = (attractor.radius == 0 ? 12 : attractor.radius) + 4
                if distance < edge {
                    let pull = mass * 200
                    if rng.chance(0.15) {
                        // A jet: up or down, spreading a little.
                        let up: Double = rng.next() < 0.5 ? -1 : 1
                        let speed = (pull / 40).squareRoot() * 1.2
                        let lean = rng.next() * Double.pi * 2
                        let spread = 0.12 * rng.next()
                        x = attractor.x + jsCos(lean) * spread * edge
                        y = attractor.y + up * (edge + 4)
                        z = attractor.z + jsSin(lean) * spread * edge
                        velX = jsCos(lean) * spread * speed
                        velY = up * speed
                        velZ = jsSin(lean) * spread * speed
                    } else {
                        let orbit = rng.next() * (span * 0.4) + 40
                        let angle = rng.next() * Double.pi * 2
                        let speed = (pull / orbit).squareRoot()
                        x = attractor.x + jsCos(angle) * orbit
                        y = attractor.y
                        z = attractor.z + jsSin(angle) * orbit
                        velX = -jsSin(angle) * speed
                        velY = 0
                        velZ = jsCos(angle) * speed
                    }
                    moved = true
                    break
                }
                let force = (mass * 200) / distanceSquared
                velX += (dx / distance) * force
                velY += (dy / distance) * force
                velZ += (dz / distance) * force
            }

            if moved {
                positions[pair] = JS.toFloat32(x)
                positions[pair + 1] = JS.toFloat32(y)
                depths[i] = JS.toFloat32(z)
            }
            velocities[pair] = JS.toFloat32(velX)
            velocities[pair + 1] = JS.toFloat32(velY)
            depthVelocities[i] = JS.toFloat32(velZ)
        }
        hasDepth = true
    }

    /// Pulls every body in the crowd toward the black holes, and pushes it away from the repulsors.
    ///
    /// ## Why the crowd needed this
    ///
    /// Only the object list used to feel a black hole. So dropping a well into a field of a hundred thousand
    /// bodies did nothing at all, and adding ten thousand bodies to a galaxy scattered them across a black
    /// hole they could not see. The same law the object bodies obey, written the same way, so a body in the
    /// crowd and a body in the list at the same place move the same way.
    ///
    /// A body that reaches a black hole's edge is thrown back out — into a wide orbit, or now and then along
    /// a jet — exactly as an object body is. Without that the crowd would pile into a single point.
    ///
    /// - Parameter span: the shorter side of the world, which sets how wide a re-emitted orbit may be.
    public func applyAttractors(_ attractors: [Attractor], span: Double, rng: inout Mulberry32) {
        guard !attractors.isEmpty, count > 0 else { return }
        for i in 0 ..< count {
            let pair = i * 2
            var x = positions[pair].asDouble
            var y = positions[pair + 1].asDouble
            var velX = velocities[pair].asDouble
            var velY = velocities[pair + 1].asDouble
            var moved = false

            for attractor in attractors {
                let dx = attractor.x - x
                let dy = attractor.y - y
                let distanceSquared = dx * dx + dy * dy + 10
                let distance = distanceSquared.squareRoot()
                let mass = attractor.mass == 0 ? 80 : attractor.mass
                if attractor.repels {
                    let force = (mass * 150) / distanceSquared
                    velX -= (dx / distance) * force
                    velY -= (dy / distance) * force
                    continue
                }
                let edge = (attractor.radius == 0 ? 12 : attractor.radius) + 4
                if distance < edge {
                    let pull = mass * 200
                    if rng.chance(0.15) {
                        let angle = rng.next() * Double.pi * 2
                        let speed = (pull / 40).squareRoot() * 1.2
                        x = attractor.x + jsCos(angle) * (edge + 4)
                        y = attractor.y + jsSin(angle) * (edge + 4)
                        velX = jsCos(angle) * speed
                        velY = jsSin(angle) * speed
                    } else {
                        let orbit = rng.next() * (span * 0.4) + 40
                        let angle = rng.next() * Double.pi * 2
                        let speed = (pull / orbit).squareRoot()
                        x = attractor.x + jsCos(angle) * orbit
                        y = attractor.y + jsSin(angle) * orbit
                        velX = -jsSin(angle) * speed
                        velY = jsCos(angle) * speed
                    }
                    moved = true
                    break
                }
                let force = (mass * 200) / distanceSquared
                velX += (dx / distance) * force
                velY += (dy / distance) * force
            }

            if moved {
                positions[pair] = JS.toFloat32(x)
                positions[pair + 1] = JS.toFloat32(y)
            }
            velocities[pair] = JS.toFloat32(velX)
            velocities[pair + 1] = JS.toFloat32(velY)
        }
    }

    // MARK: - Health

    /// Whether any body holds an unusable number.
    public func corruptCount() -> Int {
        var corrupt = 0
        for i in 0 ..< count {
            let pair = i * 2
            if !positions[pair].isFinite || !positions[pair + 1].isFinite
                || !velocities[pair].isFinite || !velocities[pair + 1].isFinite
                || !depths[i].isFinite || !depthVelocities[i].isFinite
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
            let vz = hasDepth ? depthVelocities[i].asDouble : 0
            guard vx.isFinite, vy.isFinite, vz.isFinite else { continue }
            let speed = (vx * vx + vy * vy + vz * vz).squareRoot()
            if speed > fastest { fastest = speed }
        }
        return fastest
    }
}
