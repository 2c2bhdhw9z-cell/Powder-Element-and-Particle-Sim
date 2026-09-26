/// What kind of thing a particle is, which decides whether other particles are
/// drawn toward it or pushed away.
public enum ParticleKind: String, Sendable, Hashable, CaseIterable, Codable {
    /// An ordinary particle.
    case standard
    /// Pulls everything toward it, and re-emits anything that reaches its centre.
    case blackhole
    /// Pushes everything away.
    case repulsor
    /// A bright core, used by the solar-flare preset.
    case glow
}

/// How a particle's colour is chosen when drawing.
public enum ParticleColorMode: String, Sendable, Hashable, CaseIterable, Codable {
    /// The particle's own colour.
    ///
    /// Spelled `element` on the wire, matching the web implementation, so a saved preference
    /// means the same thing in both.
    case native = "element"
    /// Hue from speed.
    case velocity
    /// Blue for positive, red for negative, white for neutral.
    case charge
    /// Hue from position.
    case rainbow
    /// Hue from how crowded the particle's surroundings are.
    case density
    /// Hue from how much life it has left.
    case lifespan
    /// Hue from how heavy it is.
    ///
    /// The one mode here that the reference implementation has and this field did not, because until the
    /// crowd carried weights there was nothing to colour by. It is also the only way to *see* a mixture of
    /// heavy and light bodies, which is most of what makes gravity between them interesting.
    case mass
}

/// What happens when a particle reaches the edge of the world.
public enum ParticleBoundaryMode: String, Sendable, Hashable, CaseIterable, Codable {
    /// Rebounds, losing energy according to elasticity.
    case bounce
    /// Reappears on the opposite side.
    case wrap
    /// Ceases to exist.
    case void
}

/// What dragging a finger across the world does.
public enum ParticleMouseMode: String, Sendable, Hashable, CaseIterable, Codable {
    case attract
    case repel
    case vortex
    case emitter
    case painter
    case gravityWell = "gravity_well"
    case freeze
    case hawk
    case hyperDrive = "hyper_drive"
    /// Paints wind into the world.
    ///
    /// Unlike every mode above it, this one does not touch the bodies at all — it changes the *world*, and
    /// the bodies notice on the next tick. That is the whole reason it is worth having: everything else in
    /// the field applies everywhere at once, and this makes one part of it behave differently from another.
    case current
    /// Draws a wall the crowd cannot pass through.
    case wall
    /// Places a source that keeps pouring after the finger is lifted.
    case source

    /// Whether this mode alters the world rather than pushing the bodies.
    ///
    /// The two are handled quite differently — a force is applied every tick for as long as a finger is
    /// down, where a stroke is recorded as it is drawn and then stays — so the distinction is worth naming
    /// rather than leaving as two cases somebody has to remember.
    public var drawsIntoTheWorld: Bool {
        switch self {
        case .current, .wall, .source: return true
        default: return false
        }
    }
}

/// A short history of where a particle has been, for drawing motion trails.
///
/// Six points, stored inline. This is deliberately not a Swift array: an array
/// would put a heap reference inside every particle, and the particle list is
/// copied wholesale for undo snapshots and iterated every frame — so that
/// reference would mean reference-counting traffic on work that is otherwise pure
/// arithmetic. Inline storage keeps a particle trivially copyable.
public struct TrailBuffer: Sendable, Hashable {
    /// Longest history kept, matching the web implementation.
    public static let capacity = 6

    /// How many points are currently held.
    public private(set) var count: Int = 0

    /// Six interleaved x/y pairs. A homogeneous tuple so it can be addressed as a
    /// contiguous run of floats without boxing.
    private var storage: (
        Float, Float, Float, Float, Float, Float,
        Float, Float, Float, Float, Float, Float
    ) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    /// How far into the screen each point was, for a field with depth. Nought on a flat field.
    private var depthStorage: (Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0)

    public init() {}

    /// Adds a point, discarding the oldest once full.
    public mutating func append(x: Float, y: Float, z: Float = 0) {
        let wasFull = count >= Self.capacity
        withUnsafeMutablePointer(to: &storage) { tuple in
            let slots = UnsafeMutableRawPointer(tuple).assumingMemoryBound(to: Float.self)
            if count < Self.capacity {
                slots[count * 2] = x
                slots[count * 2 + 1] = y
                count += 1
            } else {
                // Shift everything down one and write the newest at the end.
                for i in 0 ..< (Self.capacity - 1) {
                    slots[i * 2] = slots[(i + 1) * 2]
                    slots[i * 2 + 1] = slots[(i + 1) * 2 + 1]
                }
                slots[(Self.capacity - 1) * 2] = x
                slots[(Self.capacity - 1) * 2 + 1] = y
            }
        }
        withUnsafeMutablePointer(to: &depthStorage) { tuple in
            let slots = UnsafeMutableRawPointer(tuple).assumingMemoryBound(to: Float.self)
            if wasFull {
                for i in 0 ..< (Self.capacity - 1) { slots[i] = slots[i + 1] }
                slots[Self.capacity - 1] = z
            } else {
                slots[count - 1] = z
            }
        }
    }

    /// How far into the screen the point at an index was. Nought on a flat field.
    public func depth(at index: Int) -> Float {
        guard index >= 0, index < count else { return 0 }
        return withUnsafePointer(to: depthStorage) { tuple in
            UnsafeRawPointer(tuple).assumingMemoryBound(to: Float.self)[index]
        }
    }

    /// Forgets the history.
    ///
    /// Called whenever a particle is teleported — recycled to its origin, re-emitted
    /// from a black hole, or wrapped across the world — because otherwise the next
    /// frame draws a line from where it used to be all the way to where it now is.
    public mutating func removeAll() {
        count = 0
    }

    /// The point at an index, or `nil` if there is nothing there.
    public func point(at index: Int) -> (x: Float, y: Float)? {
        guard index >= 0, index < count else { return nil }
        return withUnsafePointer(to: storage) { tuple in
            let slots = UnsafeRawPointer(tuple).assumingMemoryBound(to: Float.self)
            return (slots[index * 2], slots[index * 2 + 1])
        }
    }

    // Equality and hashing are written out rather than synthesized: Swift will not
    // derive them for a struct holding a twelve-element tuple. Only the live points
    // are considered, so two buffers holding the same history compare equal whatever
    // stale values sit in the unused slots behind them.

    public static func == (lhs: TrailBuffer, rhs: TrailBuffer) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for index in 0 ..< lhs.count {
            guard let left = lhs.point(at: index), let right = rhs.point(at: index) else { return false }
            if left.x != right.x || left.y != right.y { return false }
            if lhs.depth(at: index) != rhs.depth(at: index) { return false }
        }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(count)
        for index in 0 ..< count {
            if let point = point(at: index) {
                hasher.combine(point.x)
                hasher.combine(point.y)
            }
        }
    }
}

/// One free-moving body in the particle field.
///
/// A value type with no references in it, so the whole list can be copied for an
/// undo snapshot with a single memory copy and iterated without touching the
/// reference counter.
///
/// ## Why several properties are explicit flags rather than inferred
///
/// The web implementation decided some behaviour by inspecting a particle's
/// incidental properties — whether it had an origin and a charge, or what colour it
/// was. Both turned out to catch particles that were never meant to be caught:
/// the lattice restoring force was crushing seven orbital presets, and repainting a
/// particle silently dropped it out of the DNA helix forever. ``latticeBound`` and
/// ``helixStrand`` replace those inferences.
public struct ParticleObject: Sendable, Hashable {
    /// Unique, monotonically assigned. Never reused.
    public var id: Int

    public var x: Double
    public var y: Double
    public var velocityX: Double
    public var velocityY: Double
    /// How far into the screen it is, for a field with depth. Nought — the middle — on a flat field.
    public var z: Double = 0
    /// How fast it is moving into or out of the screen.
    public var velocityZ: Double = 0

    /// Drawn size, and the distance kept from a wall when bouncing.
    public var radius: Double
    /// Resistance to force. Never zero.
    public var mass: Double
    /// Electric charge: positive, negative, or zero to opt out of the Coulomb force
    /// entirely.
    public var charge: Double

    /// Drawn colour, already packed.
    public var color: PackedColor

    /// Ticks remaining before it expires. `nil` means it never does.
    public var lifespan: Int?
    /// Lifetime it is restored to when recycled.
    public var maxLife: Int?

    /// Pinned in place: unaffected by forces and never moved by the boundary.
    public var isFixed: Bool
    /// Exempt from world gravity and damping, so orbital energy is not bled away.
    public var ignoresGravity: Bool

    /// Where it returns to when recycled. `nil` means it simply expires.
    public var originX: Double?
    public var originY: Double?
    /// How far into the screen that place is, for a field with depth. Nought is the middle.
    public var originZ: Double = 0

    /// Held to its origin by a spring. Only the lattice preset sets this.
    public var latticeBound: Bool
    /// Which strand of the helix preset it belongs to: `1` or `-1`.
    public var helixStrand: Double?

    public var kind: ParticleKind
    public var trail: TrailBuffer

    public init(
        id: Int,
        x: Double,
        y: Double,
        velocityX: Double = 0,
        velocityY: Double = 0,
        radius: Double = 2,
        mass: Double = 1,
        charge: Double = 0,
        color: PackedColor = PackedColor(r: 255, g: 255, b: 255),
        lifespan: Int? = nil,
        maxLife: Int? = nil,
        isFixed: Bool = false,
        ignoresGravity: Bool = false,
        originX: Double? = nil,
        originY: Double? = nil,
        latticeBound: Bool = false,
        helixStrand: Double? = nil,
        kind: ParticleKind = .standard
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.radius = radius
        // Zero mass would divide by zero in every force that respects it.
        self.mass = mass == 0 ? 1 : mass
        self.charge = charge
        self.color = color
        self.lifespan = lifespan
        self.maxLife = maxLife
        self.isFixed = isFixed
        self.ignoresGravity = ignoresGravity
        self.originX = originX
        self.originY = originY
        self.latticeBound = latticeBound
        self.helixStrand = helixStrand
        self.kind = kind
        self.trail = TrailBuffer()
    }

    /// Whether this particle has expired and should be removed or recycled.
    @inlinable
    public var hasExpired: Bool {
        if let lifespan { return lifespan <= 0 }
        return false
    }

    /// Whether it can be returned to a starting point instead of being deleted.
    @inlinable
    public var isRecyclable: Bool {
        originX != nil && originY != nil
    }

    /// Whether every stored value is a usable number.
    ///
    /// Checks for infinity as well as not-a-number. The web implementation tested only
    /// the latter, so an infinite coordinate or velocity was reported as healthy —
    /// and the repair that clamped excessive speed then turned it into a
    /// not-a-number, manufacturing the corruption it existed to remove.
    @inlinable
    public var isFinite: Bool {
        x.isFinite && y.isFinite && velocityX.isFinite && velocityY.isFinite && z.isFinite && velocityZ.isFinite
    }
}

/// A distance constraint between two particles, used for cloth, rope and blobs.
public struct Spring: Sendable, Hashable {
    /// Index of the first particle in the engine's list.
    public var a: Int
    /// Index of the second particle.
    public var b: Int
    /// The length it tries to hold.
    public var rest: Double
    /// Stiffness.
    public var k: Double

    public init(a: Int, b: Int, rest: Double, k: Double) {
        self.a = a
        self.b = b
        self.rest = rest
        self.k = k
    }
}
