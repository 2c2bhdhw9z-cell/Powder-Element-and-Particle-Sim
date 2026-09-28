// Parallel worlds: two copies of the powder world from the same moment, one thing changed, run side by side.
//
// ## Why the copy has to be exact
//
// The whole point is that the one change is the *only* difference. So the copy is not a save and a load, which is
// deliberately lossy — undo forgets which way each grain was moving, and a saved file forgets the random numbers.
// A world copied that way and run beside its original comes apart within a second with nothing changed at all,
// because the physics draws thousands of random numbers a moment and the two would be drawing different ones.
// Everything is copied instead: every grid, every flag, every person, and the random numbers' own state. The checks
// run two untouched copies side by side for several seconds of a busy world and require them to stay identical to
// the last cell.
//
// ## What can be changed
//
// Things that change one rule of the world, and things that change almost nothing — one grain of sand, a different
// roll of the dice — which are the interesting ones: they show how much of what a world does is decided by chance,
// and how quickly two worlds that were the same stop being so.

extension PowderEngine {
    /// An exact copy of this world, at this moment, that will go on exactly as this one does until one of them is
    /// changed.
    public func twin() -> PowderEngine {
        let copy = PowderEngine(width: width, height: height, registry: registry)
        copy.becomeCopy(of: self)
        return copy
    }

    /// Makes this world exactly the same as another of the same size, down to the random numbers.
    ///
    /// - Returns: whether it could: not if the two are different sizes.
    @discardableResult
    public func becomeCopy(of other: PowderEngine) -> Bool {
        if other.width != width || other.height != height {
            resize(width: other.width, height: other.height)
            guard other.width == width, other.height == height else { return false }
        }
        let count = cellCount
        guard count > 0 else { return true }
        type.update(from: other.type, count: count)
        temperature.update(from: other.temperature, count: count)
        life.update(from: other.life, count: count)
        visited.update(from: other.visited, count: count)
        velocityX.update(from: other.velocityX, count: count)
        velocityY.update(from: other.velocityY, count: count)
        pressure.update(from: other.pressure, count: count)
        pressureNext.update(from: other.pressureNext, count: count)
        tint.update(from: other.tint, count: count)
        tintMayExist = other.tintMayExist

        gravityX = other.gravityX
        gravityY = other.gravityY
        ambientTemp = other.ambientTemp
        windX = other.windX
        pressureEnabled = other.pressureEnabled
        heatConductionEnabled = other.heatConductionEnabled
        frameCount = other.frameCount
        textureMode = other.textureMode
        jostleLeft = other.jostleLeft
        lastFanRotate = other.lastFanRotate
        // The tide's own setter forgets the surface, so the surface is copied after it.
        tide = other.tide
        tideSurface = other.tideSurface
        tideSurfaceAge = other.tideSurfaceAge
        storedPeople = other.storedPeople
        storedNextPersonID = other.storedNextPersonID
        storedNoticed = other.storedNoticed
        storedNoticedAny = other.storedNoticedAny
        storedNoticing = other.storedNoticing
        storedChainLength = other.storedChainLength
        storedLastBurstFrame = other.storedLastBurstFrame
        storedLongestChain = other.storedLongestChain
        portalBMayExist = other.portalBMayExist
        largestUnreportedBurst = other.largestUnreportedBurst
        rng = other.rng
        return true
    }

    /// How much of two worlds differs: the share of cells holding something different, nought to one.
    public static func difference(_ a: PowderEngine, _ b: PowderEngine) -> Double {
        guard a.width == b.width, a.height == b.height, a.cellCount > 0 else { return 1 }
        var differing = 0
        var filled = 0
        for index in 0 ..< a.cellCount {
            let one = a.type[index]
            let other = b.type[index]
            if one != Element.empty || other != Element.empty { filled += 1 }
            if one != other { differing += 1 }
        }
        // As a share of the cells that hold anything in either, so a small world in a big empty box is not called
        // almost identical merely because most of the box is air in both.
        return filled > 0 ? Double(differing) / Double(filled) : 0
    }
}

/// The one thing changed in the second of two parallel worlds.
public enum PowderParallelChange: String, CaseIterable, Sendable, Codable {
    case oneGrain
    case differentLuck
    case warmerRoom
    case colderRoom
    case upsideDown
    case wind
    case noHeatSpreading
    case noPressure

    public var title: String {
        switch self {
        case .oneGrain: "One grain of sand"
        case .differentLuck: "A different roll of the dice"
        case .warmerRoom: "A room 60° warmer"
        case .colderRoom: "A room 60° colder"
        case .upsideDown: "Gravity upside down"
        case .wind: "A steady wind"
        case .noHeatSpreading: "Heat does not spread"
        case .noPressure: "No air pressure"
        }
    }

    /// What it shows, in a sentence.
    public var about: String {
        switch self {
        case .oneGrain:
            "One grain of sand dropped in the middle of the second world and nothing else. Watch how long the two stay "
                + "the same."
        case .differentLuck:
            "The same world, the same rules, but the dice it rolls for which way each grain slides come up differently."
        case .warmerRoom: "The air the second world cools towards is sixty degrees warmer."
        case .colderRoom: "The air the second world cools towards is sixty degrees colder."
        case .upsideDown: "Everything in the second world falls up."
        case .wind: "A wind blowing to the right across the second world."
        case .noHeatSpreading: "In the second world heat stays where it is: nothing warms what is next to it."
        case .noPressure: "The second world has no air pressure, so explosions do not push."
        }
    }

    /// Makes the change in a world.
    public func apply(to engine: PowderEngine) {
        switch self {
        case .oneGrain:
            // Dropped from the top, in the middle, into the first empty place found going down.
            let x = engine.width / 2
            for y in 0 ..< engine.height where engine.typeAt(x, y) == Element.empty {
                engine.setElement(x, y, Element.sand)
                return
            }
        case .differentLuck:
            engine.rng = Mulberry32(seed: engine.rng.state &+ 0x9E37_79B9)
        case .warmerRoom:
            engine.ambientTemp += 60
        case .colderRoom:
            engine.ambientTemp -= 60
        case .upsideDown:
            // Not "weaker": in this world gravity is a direction and not a strength — a grain moves a cell a
            // moment whichever way is down — so a weaker gravity was offered once and changed nothing at all.
            engine.gravityY = -engine.gravityY
        case .wind:
            engine.setWind(0.6)
        case .noHeatSpreading:
            engine.heatConductionEnabled = false
        case .noPressure:
            engine.pressureEnabled = false
        }
    }

    /// Keeps the second world's settings the same as the first's — gravity as the phone tilts, the wind and the room
    /// as somebody changes them — apart from the one thing that is meant to differ. Called before every moment.
    public func keep(_ twin: PowderEngine, following first: PowderEngine) {
        twin.gravityX = first.gravityX
        twin.gravityY = self == .upsideDown ? -first.gravityY : first.gravityY
        switch self {
        case .warmerRoom: twin.ambientTemp = first.ambientTemp + 60
        case .colderRoom: twin.ambientTemp = first.ambientTemp - 60
        default: twin.ambientTemp = first.ambientTemp
        }
        if self == .wind { twin.setWind(0.6) } else if twin.windX != first.windX { twin.setWind(first.windX) }
        twin.heatConductionEnabled = self == .noHeatSpreading ? false : first.heatConductionEnabled
        twin.pressureEnabled = self == .noPressure ? false : first.pressureEnabled
    }

    /// Whether the change is to the world's gravity, which is then left alone rather than kept the same as the
    /// first world's when the phone is tilted.
    public var changesGravity: Bool { self == .upsideDown }
}
