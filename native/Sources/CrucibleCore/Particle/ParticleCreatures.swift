/// Creatures: bones, joints and muscles, built by hand, that have to stand up — and, if they are built well, walk.
///
/// ## What a creature is made of
///
/// Joints are bodies. A bone is a stiff spring between two joints; a muscle is a spring whose length swells and
/// shrinks on a beat, which the engine has been able to step since the jellyfish. Nothing else holds a creature up —
/// no hidden frame, no shape it is drawn back toward the way a jelly is. So a creature has to be *built* to stand: a
/// single stick falls over, a triangle stands, and a creature whose muscles all pull at once only shivers on the spot.
/// That is the point of it. It is a physics problem somebody solves with their hands.
///
/// ## What makes walking possible
///
/// Feet grip. A joint resting on the floor loses most of its sideways speed every moment, as a foot on real ground
/// does, and a joint lifted off it loses none. So a leg that swings forward through the air and pushes back while
/// planted moves the whole creature — and one that drags both feet together along the ground gets nowhere. Without
/// the grip the floor is ice (the rest of the field has no friction on its edges, which is right for a crowd and
/// wrong for a foot), and no arrangement of muscles walks on ice.
///
/// The grip belongs to creatures only. Every other body in the field meets the floor exactly as it always has, which
/// is also what keeps the comparisons with the reference untouched.
public struct ParticleCreature: Sendable, Hashable {
    /// The joints, by identifier, which survives other bodies being removed where a place in the list would not.
    public var ids: [Int]
    /// What it is called, for the tray.
    public var name: String
    /// Where its middle was when it came to life, to say how far it has walked.
    public var startX: Double
    /// How tall it was when it came to life, to say whether it is still standing.
    public var builtHeight: Double

    public init(ids: [Int], name: String, startX: Double, builtHeight: Double) {
        self.ids = ids
        self.name = String(name.prefix(40))
        self.startX = startX.isFinite ? startX : 0
        self.builtHeight = builtHeight.isFinite ? max(1, builtHeight) : 1
    }
}

/// How a creature is getting on.
public struct CreatureStatus: Sendable, Equatable {
    /// Whether it is still at least half as tall as it was built. Below that it has fallen over or folded up.
    public var isStanding: Bool
    /// How far its middle has moved sideways since it came to life, in the world's pixels. Positive is to the right.
    public var walked: Double
    /// How tall it is now, as a share of how tall it was built.
    public var heightShare: Double
    /// How many of its joints are left.
    public var joints: Int
}

/// A creature being drawn, before it is alive: joints where they were put, and what joins them.
///
/// Pure and small, so drawing one can be checked without a phone: every limb added snaps its ends to a joint already
/// there if one is close, so a figure drawn by finger joins up without the finger having to land exactly.
public struct CreaturePlan: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case bone
        case muscle
    }

    public struct Joint: Sendable, Equatable {
        public var x: Double
        public var y: Double
    }

    public struct Limb: Sendable, Equatable {
        public var a: Int
        public var b: Int
        public var kind: Kind
        /// Where in the beat a muscle is longest, nought to one. Muscles drawn one after another take turns.
        public var phase: Double
    }

    public private(set) var joints: [Joint] = []
    public private(set) var limbs: [Limb] = []

    /// How close to a joint a finger has to be to mean that joint, in the world's pixels.
    public static let snap = 16.0
    /// The shortest a limb may be. Anything shorter was a tap, not a stroke.
    public static let shortest = 8.0
    /// As many joints as are worth having in something built by finger.
    public static let mostJoints = 40

    public init() {}

    public var isEmpty: Bool { joints.isEmpty }

    /// The joint within reach of a place, if there is one: the nearest.
    public func joint(nearX x: Double, y: Double) -> Int? {
        var best: Int?
        var bestDistance = Self.snap * Self.snap
        for (index, joint) in joints.enumerated() {
            let dx = joint.x - x
            let dy = joint.y - y
            let distance = dx * dx + dy * dy
            if distance <= bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    /// A joint at a place, or the one already there.
    mutating func jointAt(x: Double, y: Double) -> Int? {
        if let existing = joint(nearX: x, y: y) { return existing }
        guard joints.count < Self.mostJoints, x.isFinite, y.isFinite else { return nil }
        joints.append(Joint(x: x, y: y))
        return joints.count - 1
    }

    /// Adds a limb from one place to another, making joints at either end unless there are joints there already.
    ///
    /// - Returns: whether a limb was added. Not for a stroke too short to be one, or one that doubles a limb already
    ///   there.
    @discardableResult
    public mutating func addLimb(fromX x0: Double, y y0: Double, toX x1: Double, y y1: Double, kind: Kind) -> Bool {
        let dx = x1 - x0
        let dy = y1 - y0
        guard (dx * dx + dy * dy).squareRoot() >= Self.shortest else { return false }
        let before = joints
        guard let a = jointAt(x: x0, y: y0), let b = jointAt(x: x1, y: y1), a != b else {
            joints = before
            return false
        }
        guard !limbs.contains(where: { ($0.a == a && $0.b == b) || ($0.a == b && $0.b == a) }) else {
            joints = before
            return false
        }
        let muscles = limbs.filter { $0.kind == .muscle }.count
        // Each muscle half a beat after the one before, so two pull in turn — the simplest gait there is.
        limbs.append(Limb(a: a, b: b, kind: kind, phase: kind == .muscle ? Double(muscles % 2) * 0.5 : 0))
        return true
    }

    /// Takes away the last limb drawn, and any joint left joined to nothing.
    public mutating func removeLast() {
        guard !limbs.isEmpty else {
            joints.removeAll()
            return
        }
        limbs.removeLast()
        var used = Set<Int>()
        for limb in limbs {
            used.insert(limb.a)
            used.insert(limb.b)
        }
        let keep = joints.indices.filter { used.contains($0) }
        var renumber: [Int: Int] = [:]
        for (new, old) in keep.enumerated() { renumber[old] = new }
        joints = keep.map { joints[$0] }
        limbs = limbs.map { Limb(a: renumber[$0.a] ?? 0, b: renumber[$0.b] ?? 0, kind: $0.kind, phase: $0.phase) }
    }

    /// Whether every joint is joined, through limbs, to every other.
    public var isInOnePiece: Bool {
        guard !joints.isEmpty else { return false }
        var reached: Set<Int> = [0]
        var waiting = [0]
        while let at = waiting.popLast() {
            for limb in limbs {
                let other = limb.a == at ? limb.b : limb.b == at ? limb.a : -1
                if other >= 0, !reached.contains(other) {
                    reached.insert(other)
                    waiting.append(other)
                }
            }
        }
        return reached.count == joints.count
    }

    /// What stops it being brought to life, in words, or nothing if it can be.
    public var problem: String? {
        if limbs.isEmpty { return "Draw a bone: drag from one place to another." }
        if !limbs.contains(where: { $0.kind == .bone }) { return "It needs at least one bone to be anything." }
        if !isInOnePiece { return "Some of it is not joined to the rest. Start a limb on a joint to join it on." }
        return nil
    }

    /// Stands a plan on the floor: its lowest joint moved down to a height, and it set across to a place.
    func placed(atX x: Double, floor: Double) -> CreaturePlan {
        guard let lowest = joints.map(\.y).max(), let left = joints.map(\.x).min(), let right = joints.map(\.x).max()
        else { return self }
        var moved = self
        let across = x - (left + right) / 2
        let down = floor - lowest
        moved.joints = joints.map { Joint(x: $0.x + across, y: $0.y + down) }
        return moved
    }

    /// Builds a plan from joints and limbs written out, for the creatures that come ready-made.
    init(joints: [(Double, Double)], limbs: [(Int, Int, Kind, Double)]) {
        self.joints = joints.map { Joint(x: $0.0, y: $0.1) }
        self.limbs = limbs.map { Limb(a: $0.0, b: $0.1, kind: $0.2, phase: $0.3) }
    }
}

/// Creatures that come ready-made, to see what is possible before building one.
///
/// Each was found rather than guessed: the walker is the one of a hundred and forty-four designs tried, varying the
/// legs, the muscles and their timing, that walked steadily one way for sixteen seconds without once falling over.
/// Most of the others fell over or shuffled on the spot, which is exactly what somebody building their own will find.
public enum ReadyCreature: String, CaseIterable, Sendable {
    case walker
    case table
    case tumbler

    public var name: String {
        switch self {
        case .walker: "Walker"
        case .table: "Table"
        case .tumbler: "Tumbler"
        }
    }

    /// What it shows.
    public var about: String {
        switch self {
        case .walker:
            "A braced box on two legs. Each leg is worked by two muscles pulling against each other, and the back leg "
                + "runs a quarter of a beat behind the front — which is all that decides which way it walks."
        case .table:
            "Four bones and a diagonal, and no muscles at all. It stands, and does nothing else: that is what balance is."
        case .tumbler:
            "The same box without its diagonal. A square of bones can fold flat, so the slightest lean and down it goes."
        }
    }

    /// The plan, in the world's pixels, with its lowest joints at nought.
    public var plan: CreaturePlan {
        switch self {
        case .walker:
            // The box: two top corners, two hips, and both diagonals. Then a foot under each hip on a bone, and two
            // muscles to each foot, one from the top corner above it and one from the far hip.
            CreaturePlan(
                joints: [(-35, -54), (35, -54), (-35, -36), (35, -36), (-35, 0), (35, 0)],
                limbs: [
                    (0, 1, .bone, 0), (2, 3, .bone, 0), (0, 2, .bone, 0), (1, 3, .bone, 0),
                    (0, 3, .bone, 0), (1, 2, .bone, 0),
                    (2, 4, .bone, 0), (3, 5, .bone, 0),
                    (0, 4, .muscle, 0.75), (1, 5, .muscle, 0),
                    (3, 4, .muscle, 0.25), (2, 5, .muscle, 0.5),
                ]
            )
        case .table:
            CreaturePlan(
                joints: [(-40, -44), (40, -44), (-40, 0), (40, 0)],
                limbs: [(0, 1, .bone, 0), (0, 2, .bone, 0), (1, 3, .bone, 0), (2, 3, .bone, 0), (0, 3, .bone, 0)]
            )
        case .tumbler:
            // Leaning a little, as anything built by hand does.
            CreaturePlan(
                joints: [(-14, -80), (26, -80), (-20, 0), (20, 0)],
                limbs: [(0, 1, .bone, 0), (0, 2, .bone, 0), (1, 3, .bone, 0), (2, 3, .bone, 0)]
            )
        }
    }
}

extension ParticleEngine {
    /// How many creatures there can be at once.
    public static let creatureLimit = 12
    /// How much of a foot's sideways speed is kept each moment it rests on the floor. The rest is the ground's grip.
    public static let creatureGrip = 0.25
    /// How stiff a bone is, on the engine's spring scale. About as stiff as a spring here can be without a joint with
    /// several bones shaking itself apart.
    public static let boneStiffness = 0.35
    /// How stiff a muscle is, and how far it swells and shrinks either way, as a share of its length.
    public static let muscleStiffness = 0.22
    public static let muscleSwell = 0.22
    /// How many moments one beat of a creature's muscles takes: a bit over a second.
    public static let creatureBeat = 72.0
    /// How big a joint is drawn.
    static let jointRadius = 3.0

    /// The creatures in the field.
    public var creatures: [ParticleCreature] { storedCreatures }

    /// Brings a plan to life standing on the floor, its middle at a place across the world.
    ///
    /// One undo point for the whole creature.
    ///
    /// - Returns: whether it came to life. Not if the plan has a problem, there are too many creatures already, or
    ///   there is no room for its joints.
    @discardableResult
    public func bringToLife(_ plan: CreaturePlan, named name: String, atX x: Double? = nil) -> Bool {
        guard plan.problem == nil, storedCreatures.count < Self.creatureLimit else { return false }
        guard bodyCount + plan.joints.count <= maxParticles else { return false }
        let middle = x ?? width / 2
        let standing = plan.placed(atX: max(60, min(width - 60, middle)), floor: height - Self.jointRadius - 0.5)
        return make(standing, named: name)
    }

    /// Brings a plan to life exactly where it was drawn — for one drawn on the world, which should come alive where
    /// it is and fall if it was drawn in the air.
    @discardableResult
    public func bringToLifeWhereDrawn(_ plan: CreaturePlan, named name: String) -> Bool {
        guard plan.problem == nil, storedCreatures.count < Self.creatureLimit else { return false }
        guard bodyCount + plan.joints.count <= maxParticles else { return false }
        return make(plan, named: name)
    }

    /// Puts a ready-made creature on the floor.
    @discardableResult
    public func addReadyCreature(_ kind: ReadyCreature, atX x: Double? = nil) -> Bool {
        bringToLife(kind.plan, named: kind.name, atX: x)
    }

    private func make(_ plan: CreaturePlan, named name: String) -> Bool {
        pushUndo()
        let hue = rng.next() * 360
        var ids: [Int] = []
        for joint in plan.joints {
            let id = addParticle(
                x: joint.x,
                y: joint.y,
                velocityX: 0,
                velocityY: 0,
                radius: Self.jointRadius,
                mass: 1,
                charge: 0,
                color: PackedColor(hue: hue, saturation: 0.6, lightness: 0.66)
            )
            ids.append(id)
        }
        // Adding a body can evict the oldest when the field is full, which renumbers everything; the joints are then
        // found again by identifier rather than trusted to be where they were put.
        var place: [Int: Int] = [:]
        for (index, body) in particles.enumerated() { place[body.id] = index }
        var added: [Spring] = []
        for limb in plan.limbs {
            guard let a = place[ids[limb.a]], let b = place[ids[limb.b]] else { continue }
            let dx = plan.joints[limb.b].x - plan.joints[limb.a].x
            let dy = plan.joints[limb.b].y - plan.joints[limb.a].y
            let length = (dx * dx + dy * dy).squareRoot()
            switch limb.kind {
            case .bone:
                added.append(Spring(a: a, b: b, rest: length, k: Self.boneStiffness))
            case .muscle:
                added.append(Spring(
                    a: a, b: b, rest: length, k: Self.muscleStiffness,
                    pulse: Self.muscleSwell, beat: Self.creatureBeat, phase: limb.phase
                ))
            }
        }
        springs.append(contentsOf: added)
        let xs = plan.joints.map(\.x)
        let ys = plan.joints.map(\.y)
        storedCreatures.append(ParticleCreature(
            ids: ids,
            name: name,
            startX: (xs.min()! + xs.max()!) / 2,
            builtHeight: (ys.max()! - ys.min()!)
        ))
        return true
    }

    /// Every creature's feet gripping the floor. After the bodies have moved and met the edges.
    func stepCreatures() {
        guard !storedCreatures.isEmpty, boundaryMode == .bounce else { return }
        var place: [Int: Int] = [:]
        for (index, body) in particles.enumerated() { place[body.id] = index }
        var survivors: [ParticleCreature] = []
        for creature in storedCreatures {
            let alive = creature.ids.filter { place[$0] != nil }
            guard alive.count >= 2 else { continue }
            var kept = creature
            kept.ids = alive
            survivors.append(kept)
            for id in alive {
                guard let index = place[id] else { continue }
                let body = particles[index]
                guard !body.isFixed, body.y >= height - body.radius - 0.75 else { continue }
                // Planted: most of the sideways speed goes into the ground, and a foot does not bounce.
                particles[index].velocityX = body.velocityX * Self.creatureGrip
                if particles[index].velocityY < 0 { particles[index].velocityY *= 0.2 }
            }
        }
        storedCreatures = survivors
    }

    /// How a creature is getting on, or nothing if there is no such creature.
    public func creatureStatus(_ index: Int) -> CreatureStatus? {
        guard storedCreatures.indices.contains(index) else { return nil }
        let creature = storedCreatures[index]
        var place: [Int: Int] = [:]
        for (at, body) in particles.enumerated() { place[body.id] = at }
        let bodies = creature.ids.compactMap { place[$0] }.map { particles[$0] }
        guard let left = bodies.map(\.x).min(), let right = bodies.map(\.x).max(),
              let top = bodies.map(\.y).min(), let bottom = bodies.map(\.y).max()
        else { return CreatureStatus(isStanding: false, walked: 0, heightShare: 0, joints: 0) }
        let share = (bottom - top) / creature.builtHeight
        return CreatureStatus(
            isStanding: share >= 0.5,
            walked: (left + right) / 2 - creature.startX,
            heightShare: share,
            joints: bodies.count
        )
    }

    /// Takes every creature out of the field, joints, bones and muscles.
    public func removeCreatures() {
        guard !storedCreatures.isEmpty else { return }
        pushUndo()
        let ids = Set(storedCreatures.flatMap(\.ids))
        storedCreatures = []
        _ = removeParticles { ids.contains($0.id) }
    }
}
