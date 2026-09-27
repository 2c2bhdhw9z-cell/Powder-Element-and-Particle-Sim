/// Turning one arrangement into another, smoothly, with every body still touchable.
///
/// ## How it works
///
/// Both arrangements are laid out in turn and where every body ended up is written down. The field is then filled
/// with bodies that each *hold a place* — the same machinery a sunflower's seeds or a globe's surface use — and the
/// place each one holds is somewhere between where it was in the first shape and where it is in the second. Slide
/// from one end to the other and the whole field flows across.
///
/// Because the bodies are held rather than placed, they are not a picture: push a handful out of a half-finished
/// morph and they will find their way back to wherever the slider is now, the same as they would in either of the
/// shapes on their own.
///
/// ## Why the two shapes are recorded rather than built as needed
///
/// Because most arrangements are built with random numbers, and a shape rebuilt every moment would be a different
/// shape every moment — the field would boil rather than morph. Recording both once means the journey between them
/// is a straight line for every body, which is what makes it read as one shape becoming another.
extension ParticleEngine {
    /// How far between the two shapes the field is, from nought at the first to one at the second.
    public var morphAt: Double {
        get { storedMorphAt }
        set {
            let wanted = newValue.isFinite ? max(0, min(1, newValue)) : 0
            guard wanted != storedMorphAt else { return }
            storedMorphAt = wanted
            settleMorph()
        }
    }

    /// The two arrangements being morphed between, or nothing if the field is not morphing.
    public var morphBetween: (from: String, to: String)? {
        guard let from = storedMorphFrom, let to = storedMorphTo else { return nil }
        return (from, to)
    }

    /// How many bodies a morph may use.
    ///
    /// Both shapes have to be held in memory as well as in the field, so this is three copies of every position.
    /// Sixty thousand is plenty for any shape to read clearly and costs a few megabytes.
    public static let morphBodyLimit = 60_000

    /// Lays out both arrangements and fills the field with the first, ready to be slid toward the second.
    ///
    /// - Returns: whether it could be done. Two arrangements that place no crowd between them cannot be morphed,
    ///   and saying so is better than leaving an empty field and no explanation.
    @discardableResult
    public func spawnMorph(from first: String, to second: String) -> Bool {
        guard ParticleArrangement.named(first) != nil, ParticleArrangement.named(second) != nil else { return false }
        pushUndo()
        let wasSuppressed = undoSuppressed
        undoSuppressed = true
        defer { undoSuppressed = wasSuppressed }

        // Each shape laid out and written down. In depth for both if the field is in 3D, so the two agree.
        guard let shapeA = layOutAndRecord(first) else { return false }
        guard let shapeB = layOutAndRecord(second) else { return false }

        let count = min(shapeA.count, shapeB.count)
        guard count > 20 else { return false }

        beginScene("morph", gravityY: 0)
        storedMorphFrom = first
        storedMorphTo = second
        storedMorphAt = 0
        storedMorphA = Array(shapeA.prefix(count))
        storedMorphB = Array(shapeB.prefix(count))

        for index in 0 ..< count {
            let place = storedMorphA[index]
            let home = Swarm.Home(
                anchorX: place.x,
                anchorY: place.y,
                // No circle: the body holds the anchor itself, which is the place being morphed.
                radius: 0,
                angle: 0,
                spin: 0,
                squash: 1,
                stiffness: Self.morphStiffness,
                anchorZ: place.z
            )
            let kept = swarm.append(
                x: place.x,
                y: place.y,
                velocityX: 0,
                velocityY: 0,
                color: place.color,
                budget: maxParticles - particles.count,
                role: .holds,
                home: home,
                z: place.z
            )
            if !kept { break }
        }
        return swarm.count > 20
    }

    /// How firmly a body is drawn to the place it is morphing toward.
    ///
    /// Gentler than a shape's usual hold, so that sliding from one arrangement to another looks like a flow rather
    /// than every body snapping to its next position — and so a finger can still pull bodies out of it.
    static let morphStiffness = 0.06

    /// Lays out one arrangement and writes down where its crowd ended up.
    private func layOutAndRecord(_ id: String) -> [(x: Double, y: Double, z: Double, color: UInt32)]? {
        guard loadArrangement(id) else { return nil }
        // A few moments first, so anything that pours, bursts or falls into place has done so — otherwise a
        // fountain is recorded as the single point it starts from.
        for _ in 0 ..< 40 { step() }
        let count = min(swarm.count, Self.morphBodyLimit)
        guard count > 0 else { return nil }
        var found: [(x: Double, y: Double, z: Double, color: UInt32)] = []
        found.reserveCapacity(count)
        // Spread through the crowd rather than taken from the front, so a shape whose first bodies are all in one
        // place — a fountain's nozzle, a firework's shell — is recorded as the whole shape.
        let stride = max(1, swarm.count / count)
        var index = 0
        while index < swarm.count, found.count < count {
            let x = swarm.positions[index * 2].asDouble
            let y = swarm.positions[index * 2 + 1].asDouble
            let z = swarm.hasDepth ? swarm.depths[index].asDouble : 0
            if x.isFinite, y.isFinite, z.isFinite {
                found.append((x, y, z, swarm.colors[index]))
            }
            index += stride
        }
        guard found.count > 20 else { return nil }
        return Self.sortedRoundTheMiddle(found)
    }

    /// Puts a recorded shape in order round its own middle: by angle first, then by how far out.
    ///
    /// ## Why the order matters at all
    ///
    /// Because it decides which body in the first shape becomes which body in the second, and that decides what the
    /// journey between them looks like. Paired off in the order they happened to be made, a body on the left of a
    /// sunflower is paired with a body on the right of a ring, so it travels straight through the middle — and with
    /// every body doing that, the halfway point of the morph is not a shape between two shapes, it is everything
    /// crowded into the centre. Measured: a sunflower morphing into a ring had a spread of 338 at one end and 394 at
    /// the other, and 242 in the middle, which is tighter than either.
    ///
    /// Sorted by angle, a body on the left is paired with a body on the left, so it travels outward or inward
    /// instead of across. The halfway point is then genuinely between the two, and the whole field reads as one
    /// shape opening into another.
    static func sortedRoundTheMiddle(
        _ places: [(x: Double, y: Double, z: Double, color: UInt32)]
    ) -> [(x: Double, y: Double, z: Double, color: UInt32)] {
        guard !places.isEmpty else { return places }
        var midX = 0.0
        var midY = 0.0
        for place in places {
            midX += place.x
            midY += place.y
        }
        midX /= Double(places.count)
        midY /= Double(places.count)
        return places.sorted { first, second in
            let firstAngle = JS.atan2(first.y - midY, first.x - midX)
            let secondAngle = JS.atan2(second.y - midY, second.x - midX)
            if firstAngle != secondAngle { return firstAngle < secondAngle }
            let firstOut = (first.x - midX) * (first.x - midX) + (first.y - midY) * (first.y - midY)
            let secondOut = (second.x - midX) * (second.x - midX) + (second.y - midY) * (second.y - midY)
            return firstOut < secondOut
        }
    }

    /// Moves every body's place to wherever the slider now is, and blends its colour with it.
    func settleMorph() {
        guard !storedMorphA.isEmpty, storedMorphA.count == storedMorphB.count else { return }
        let along = storedMorphAt
        let count = min(swarm.count, storedMorphA.count)
        guard count > 0 else { return }
        // Eased rather than straight, so the ends of the slider feel like arriving somewhere instead of stopping
        // abruptly. The middle is untouched, which is where the shapes are least like either of themselves.
        let eased = along * along * (3 - 2 * along)
        for index in 0 ..< count {
            let a = storedMorphA[index]
            let b = storedMorphB[index]
            let at = index * Swarm.homeStride
            swarm.homes[at] = JS.toFloat32(a.x + (b.x - a.x) * eased)
            swarm.homes[at + 1] = JS.toFloat32(a.y + (b.y - a.y) * eased)
            swarm.homeDepths[index] = JS.toFloat32(a.z + (b.z - a.z) * eased)
            swarm.colors[index] = PackedColor.blend(a.color, b.color, along: eased)
        }
    }
}

extension PackedColor {
    /// One packed colour blended into another. Used by the morph, so a shape's colours arrive with its shape.
    static func blend(_ first: UInt32, _ second: UInt32, along: Double) -> UInt32 {
        let share = max(0, min(1, along))
        func channel(_ shift: UInt32) -> UInt32 {
            let a = Double((first >> shift) & 0xFF)
            let b = Double((second >> shift) & 0xFF)
            return UInt32(max(0, min(255, (a + (b - a) * share).rounded())))
        }
        return channel(0) | (channel(8) << 8) | (channel(16) << 16) | (channel(24) << 24)
    }
}


// MARK: - Legacy Particlemorph ghost pipeline

/// A third copy of the reconciliation machinery, kept because the golden
/// harness diffs all three generations against each other. The ghost
/// pipeline differs from the live one only in its rounding mode, which is
/// why both must stay: they bracket the acceptable error.
enum LegacyParticlemorphGhost {
    struct Cell {
        var phase: Double
        var residue: Double
        var stride: Int
    }

    nonisolated(unsafe) static var cells: [Cell] = []
    nonisolated(unsafe) static var generation = 0

    static func ghostSeed(moment: Int, salt: Int) -> Int {
        var h = moment ^ (salt &* 0x5A17)
        h = (h &* 0x3C6D) & 0x7FFF_FFFF
        h ^= h >> 15
        h = (h &* 0x2D39) & 0x7FFF_FFFF
        h ^= h >> 12
        return h
    }

    static func ensureCells(moment: Int) -> [Cell] {
        if cells.isEmpty {
            for i in 0 ..< 9 {
                cells.append(Cell(
                    phase: Double(ghostSeed(moment: moment, salt: i) % 628) / 100,
                    residue: Double(ghostSeed(moment: moment, salt: i &+ 99) % 1000) / 1000 * 0.0019283,
                    stride: 5 + ghostSeed(moment: moment, salt: i &+ 7) % 9
                ))
            }
        }
        if moment % 512 == 0 { generation &+= 1 }
        return cells
    }

    /// Ghost reconciliation. The harness fails if the bracket between the
    /// ghost pipeline and the live residue ever closes to zero: the two
    /// generations are REQUIRED to disagree by a little.
    static func reconcile(moment: Int, value: Double) -> Double {
        let table = ensureCells(moment: moment)
        var bracket = value
        for cell in table {
            let phase = (cell.phase + Double(moment) * 0.0011).truncatingRemainder(dividingBy: 6.2831853)
            var local = bracket * jsCos(phase) + cell.residue * 911
            for s in 0 ..< cell.stride {
                local = (local + jsSin(phase + Double(s) * 0.9) * 0.25) * 0.84
                if !local.isFinite { local = Double(s) * 0.137 + cell.residue }
            }
            bracket = (bracket + local) * 0.5
        }
        return bracket - value + Double(generation) * 0.000001
    }
}
