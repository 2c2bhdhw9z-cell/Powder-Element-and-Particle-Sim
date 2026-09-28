// Little people who live in the powder world.
//
// ## Why they are not made of cells
//
// Everything else in this world is a cell: a material, a temperature, a lifetime. A cell has no direction, no goal and
// no memory, which is exactly why the world is cheap to run — half a million of them a moment.
//
// A person needs all three. They are facing a way, they are trying to get somewhere, and they remember they are on
// fire. Building that out of cells would mean giving every cell in the grid somewhere to keep it, which is a hundred
// thousand times as much memory as there are people, and it would put a decision about walking into the middle of a
// loop that runs over sand.
//
// So they are a short list beside the grid, and they read the grid to decide what to do. Twenty people is twenty
// decisions a moment, against a quarter of a million cells — free, in practice.
//
// ## What they actually do
//
// Walk, and turn round at a wall. Climb a single step up, because a world made of falling sand is full of single steps
// and a person who stopped at each would never go anywhere. Fall, and land. Notice heat nearby and run from it, which
// is the behaviour that makes them read as alive rather than as a toy — a person walking calmly towards lava is a
// sprite, and a person turning and running is somebody.
//
// Then burn, drown, or be buried, and go. They are not invincible, and a world where the people cannot be hurt is a
// world where nothing that happens to them matters.
//
// ## Why they are in the engine rather than the app
//
// Because "does a person climb a one-cell step and turn at a two-cell wall" is a question with a right answer, and the
// only place that answer can be checked is here. The app's job is to show them and to let a finger pick one up.

/// One little person.
public struct PowderPerson: Sendable, Hashable, Codable, Identifiable {
    /// What they are doing.
    public enum Doing: String, Sendable, Hashable, Codable {
        case walking
        case falling
        case climbing
        /// In somebody's hand.
        case held
        /// Underwater and holding their breath.
        case swimming
    }

    /// Their own number, so a person can be picked up and still be the same person afterwards.
    public var id: Int
    /// Where their feet are, in cells. Fractional, so they move at less than a cell a moment.
    public var x: Double
    public var y: Double
    /// How fast they are falling.
    public var fall: Double
    /// Which way they are facing: -1 for left, 1 for right.
    public var facing: Int
    public var doing: Doing
    /// Whether they have seen something to run from.
    ///
    /// Held apart from ``doing`` rather than being one of its cases, which is how it started out and was wrong: a person
    /// falling past a fire is frightened *and* falling, and making those alternatives meant somebody who saw the danger
    /// on the way down landed calm, having apparently forgotten. Posture and state of mind are two different questions
    /// about the same person.
    public var afraid: Bool
    /// How they are, from one down to nought. At nought they are gone.
    public var health: Double
    /// How hot they have got. Above their limit they start to burn.
    public var warmth: Double
    /// How long they have been underwater.
    public var breath: Double

    public init(
        id: Int,
        x: Double,
        y: Double,
        fall: Double = 0,
        facing: Int = 1,
        doing: Doing = .falling,
        afraid: Bool = false,
        health: Double = 1,
        warmth: Double = 20,
        breath: Double = PowderPeople.lungs
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.fall = fall
        self.facing = facing
        self.doing = doing
        self.afraid = afraid
        self.health = health
        self.warmth = warmth
        self.breath = breath
    }

    /// Whether they are frightened, which is what the colour shows.
    public var isAfraid: Bool { afraid }
}

/// Everyone in one world, including the next identity that will be given out.
///
/// Kept as one value so save, undo, rewind, resize and parallel worlds cannot restore the people but forget which
/// numbers have already been used. Old save files have no population field and therefore read as an empty one.
public struct PowderPopulation: Sendable, Hashable, Codable {
    public var people: [PowderPerson]
    public var nextID: Int

    public init(people: [PowderPerson] = [], nextID: Int = 0) {
        self.people = people
        self.nextID = nextID
    }
}

/// The numbers the people live by.
public enum PowderPeople {
    /// How tall a person is, in cells: feet, body, head.
    public static let height = 3
    /// How many there may be at once.
    ///
    /// Twenty rather than a thousand because the point is people you can tell apart and follow, and because each is a
    /// handful of grid reads a moment — cheap for twenty, and nobody would notice the difference at a thousand except
    /// that the world would be full of them.
    public static let most = 20
    /// How far a person walks each moment, in cells.
    public static let pace = 0.14
    /// How much faster they go when frightened.
    public static let panicPace = 0.34
    /// How many cells up a single step may be before it is a wall.
    public static let stepUp = 1
    /// How far they can see danger.
    public static let eyesight = 9
    /// How hot the air has to be before they start looking for a way out.
    public static let tooWarm = 70.0
    /// How hot before it begins to hurt.
    public static let burns = 120.0
    /// How long they can hold their breath, in moments.
    public static let lungs = 180.0
    /// How fast they fall, and how fast is too fast to land safely.
    public static let gravity = 0.06
    public static let terminalFall = 1.1
    public static let safeLanding = 0.75
    /// How much of their speed water leaves them each moment, and the fastest anybody sinks.
    ///
    /// Below what counts as a safe landing, so water is always a way down rather than only sometimes.
    public static let waterDrag = 0.82
    public static let waterFall = 0.4
}

extension PowderEngine {
    /// The people currently in the world.
    public var people: [PowderPerson] {
        storedPeople
    }

    /// Whether anybody lives here, so a world with nobody in it does no work for them at all.
    public var hasPeople: Bool { !storedPeople.isEmpty }

    /// Puts a person in the world, standing at a place.
    ///
    /// - Returns: their number, or nothing if the world is full of people or that is not a place.
    @discardableResult
    public func addPerson(atX x: Int, y: Int) -> Int? {
        guard storedPeople.count < PowderPeople.most, isValid(x, y) else { return nil }
        storedNextPersonID += 1
        // Facing is a stable fact of this person, not a draw from the world's physics random stream. Adding and then
        // removing somebody must not change where unrelated sand lands later.
        let facing = ((storedNextPersonID &+ x &* 31 &+ y &* 131) & 1) == 0 ? -1 : 1
        storedPeople.append(
            PowderPerson(
                id: storedNextPersonID,
                x: Double(x) + 0.5,
                y: Double(y),
                facing: facing
            )
        )
        return storedNextPersonID
    }

    /// Removes everybody, without reusing their old identities if more are added to this same world.
    public func clearPeople() {
        storedPeople.removeAll()
    }

    /// The complete population for save, history and exact world copying.
    public func capturePopulation() -> PowderPopulation {
        PowderPopulation(people: storedPeople, nextID: storedNextPersonID)
    }

    /// Replaces the population, making every value safe and visible before it can reach drawing or movement.
    ///
    /// A width/height may be supplied when a differently sized saved world is stretched onto this one. Held people are
    /// released for a save or history restore because there is no finger to carry them afterwards; an in-place resize
    /// keeps the held state while the same live touch continues.
    func adoptPopulation(
        _ population: PowderPopulation,
        releaseHeld: Bool = true,
        scalingFromWidth oldWidth: Int? = nil,
        height oldHeight: Int? = nil
    ) {
        guard width > 0, height > 0 else {
            storedPeople = []
            storedNextPersonID = max(0, min(1_000_000_000, population.nextID))
            return
        }
        var next = max(0, min(1_000_000_000, population.nextID))
        var used: Set<Int> = []
        var adopted: [PowderPerson] = []
        adopted.reserveCapacity(min(PowderPeople.most, population.people.count))
        for var person in population.people.prefix(PowderPeople.most) {
            if let oldWidth, let oldHeight, oldWidth > 0, oldHeight > 0 {
                person.x *= Double(width) / Double(oldWidth)
                let halfBody = Double(PowderPeople.height - 1) / 2
                let centre = person.y - halfBody
                person.y = (centre + 0.5) * Double(height) / Double(oldHeight) - 0.5 + halfBody
            }
            if person.id <= 0 || person.id > 1_000_000_000 || used.contains(person.id) {
                repeat { next += 1 } while used.contains(next)
                person.id = next
            }
            used.insert(person.id)
            next = max(next, person.id)
            let place = personPlaceInside(x: person.x, y: person.y)
            person.x = place.x
            person.y = place.y
            person.fall = person.fall.isFinite ? max(0, min(PowderPeople.terminalFall, person.fall)) : 0
            person.facing = person.facing < 0 ? -1 : 1
            if releaseHeld, person.doing == .held { person.doing = .falling }
            person.health = person.health.isFinite ? max(0, min(1, person.health)) : 1
            person.warmth = person.warmth.isFinite ? max(-10_000, min(10_000, person.warmth)) : ambientTemp
            person.breath = person.breath.isFinite ? max(0, min(PowderPeople.lungs, person.breath)) : PowderPeople.lungs
            adopted.append(person)
        }
        storedPeople = adopted
        storedNextPersonID = next
    }

    /// Keeps the live population visible after a crop/pad, or scales it with a resampled world.
    func peopleFollowResize(fromWidth oldWidth: Int, height oldHeight: Int, stretched: Bool) {
        let population = capturePopulation()
        adoptPopulation(
            population,
            releaseHeld: false,
            scalingFromWidth: stretched ? oldWidth : nil,
            height: stretched ? oldHeight : nil
        )
    }

    /// Turns each person's whole three-cell body over with the cells. Two turns return the exact vertical place.
    func flipPeopleUpsideDown() {
        for index in storedPeople.indices {
            storedPeople[index].y = Double(height + PowderPeople.height - 2) - storedPeople[index].y
        }
        adoptPopulation(capturePopulation(), releaseHeld: false)
    }

    private func personPlaceInside(x: Double, y: Double) -> (x: Double, y: Double) {
        let safeX = x.isFinite ? x : Double(width) / 2
        let safeY = y.isFinite ? y : Double(height - 1)
        let minFeet = Double(min(max(0, PowderPeople.height - 1), max(0, height - 1)))
        let maxFeet = Double(max(0, height - 1))
        return (
            max(0.5, min(max(0.5, Double(width) - 0.5), safeX)),
            max(minFeet, min(maxFeet, safeY))
        )
    }

    /// The person nearest a place, within a reach, if there is one.
    ///
    /// For picking one up: a finger is a blunt instrument and a person is one cell wide, so the nearest within a few
    /// cells is what somebody means rather than the one exactly under the fingertip.
    public func person(nearX x: Double, y: Double, within reach: Double) -> PowderPerson? {
        var best: PowderPerson?
        var closest = reach * reach
        for person in storedPeople {
            // Measured to the middle of them rather than their feet, so grabbing at a head works.
            let dy = person.y - Double(PowderPeople.height) / 2 - y
            let dx = person.x - x
            let distance = dx * dx + dy * dy
            if distance <= closest {
                closest = distance
                best = person
            }
        }
        return best
    }

    /// Picks somebody up. They stop walking and follow the hand.
    @discardableResult
    public func holdPerson(_ id: Int) -> Bool {
        guard let at = storedPeople.firstIndex(where: { $0.id == id }) else { return false }
        storedPeople[at].doing = .held
        storedPeople[at].fall = 0
        return true
    }

    /// Moves whoever is being held to a place, kept fully on the map even when a finger goes beyond an edge.
    public func carryHeldPeople(toX x: Double, y: Double) {
        let place = personPlaceInside(x: x, y: y)
        for at in storedPeople.indices where storedPeople[at].doing == .held {
            storedPeople[at].x = place.x
            storedPeople[at].y = place.y
        }
    }

    /// Lets go of everybody being held. They fall from wherever they are.
    public func dropHeldPeople() {
        for at in storedPeople.indices where storedPeople[at].doing == .held {
            let place = personPlaceInside(x: storedPeople[at].x, y: storedPeople[at].y)
            storedPeople[at].x = place.x
            storedPeople[at].y = place.y
            storedPeople[at].doing = .falling
            storedPeople[at].fall = 0
        }
    }

    /// Whether anybody is being carried.
    public var isCarryingSomebody: Bool {
        storedPeople.contains { $0.doing == .held }
    }

    // MARK: - Their moment

    /// Moves everybody on by one moment.
    ///
    /// Called from the world's own step, after the materials have moved: a person should be standing on where the sand
    /// has got to, not on where it was.
    func stepPeople() {
        guard !storedPeople.isEmpty else { return }
        var survivors: [PowderPerson] = []
        survivors.reserveCapacity(storedPeople.count)
        for var person in storedPeople {
            if person.doing != .held {
                feel(&person)
                guard person.health > 0 else {
                    // A puff of smoke where they were, so somebody watching sees what happened rather than a person
                    // simply ceasing to be there.
                    // Where they were, or in the water they drowned in: a puff rising out of a lake is how anybody
                    // watching sees that somebody went under. Never over something solid.
                    let x = Int(person.y.isFinite && person.x.isFinite ? person.x : -1)
                    let feet = Int(person.y.isFinite ? person.y : -1)
                    for y in stride(from: feet - 1, through: feet - PowderPeople.height, by: -1) where isValid(x, y) {
                        let here = typeAt(x, y)
                        if here == Element.empty || isLiquid(here) {
                            setElement(x, y, Element.smoke, temp: 120, life: 70)
                            break
                        }
                    }
                    continue
                }
                decide(&person)
                move(&person)
            }
            survivors.append(person)
        }
        storedPeople = survivors
    }

    /// What the world is doing to them.
    private func feel(_ person: inout PowderPerson) {
        let x = Int(person.x)
        var hottest = ambientTemp
        var inWater = false
        var buried = false
        // Over the three cells they occupy, because a fire at their feet and a fire at their head are the same problem
        // and only looking at one of them would let a person stand in a bonfire up to the waist.
        for step in 0 ..< PowderPeople.height {
            let y = Int(person.y) - step
            guard isValid(x, y) else { continue }
            let here = typeAt(x, y)
            hottest = max(hottest, Double(temperature[index(x, y)]))
            if here == Element.water || here == Element.saltWater { inWater = true }
            if here == Element.fire || here == Element.lava || here == Element.plasma || here == Element.acid {
                // Standing in the thing itself, rather than merely near it.
                person.health -= 0.06
            }
            let physics = elements[here]
            if physics.state == .solidFixed || physics.state == .solidMovable { buried = true }
        }

        // Warmth chases the air, so a person walks out of a hot room and cools down rather than being permanently
        // marked by having once been warm.
        person.warmth += (hottest - person.warmth) * 0.18
        if person.warmth > PowderPeople.burns {
            person.health -= (person.warmth - PowderPeople.burns) / 4_000
        }

        if inWater {
            person.breath -= 1
            if person.breath <= 0 { person.health -= 0.01 }
        } else {
            person.breath = min(PowderPeople.lungs, person.breath + 3)
        }

        // Buried in something solid: they cannot get out on their own. Slower than fire, so somebody who notices has
        // time to dig them out — which is the whole reason it is slow rather than instant.
        if buried, person.doing != .climbing { person.health -= 0.012 }
    }

    /// What they decide to do.
    private func decide(_ person: inout PowderPerson) {
        // Looking for trouble, both ways, and going the other way from whichever is nearer.
        var worstLeft = 0.0
        var worstRight = 0.0
        let feet = Int(person.y)
        let middle = feet - 1
        for reach in 1 ... PowderPeople.eyesight {
            let weight = Double(PowderPeople.eyesight - reach + 1)
            for side in [-1, 1] {
                let x = Int(person.x) + side * reach
                var danger = 0.0
                for y in [feet, middle] where isValid(x, y) {
                    let here = typeAt(x, y)
                    if here == Element.lava || here == Element.fire || here == Element.plasma {
                        danger = max(danger, weight)
                    } else if here == Element.acid {
                        danger = max(danger, weight * 0.8)
                    } else if Double(temperature[index(x, y)]) > PowderPeople.tooWarm {
                        danger = max(danger, weight * 0.5)
                    }
                }
                if side < 0 { worstLeft = max(worstLeft, danger) } else { worstRight = max(worstRight, danger) }
            }
        }

        let worst = max(worstLeft, worstRight)
        if worst > 0 {
            // Away from the worse side. Equal danger both ways means keep going rather than stand still dithering,
            // which is what a person cornered by fire on both sides actually looks like.
            if worstLeft != worstRight {
                person.facing = worstLeft > worstRight ? 1 : -1
            }
            person.afraid = true
        } else {
            person.afraid = false
        }
    }

    /// Where they get to.
    private func move(_ person: inout PowderPerson) {
        let feetY = Int(person.y)
        let below = feetY + 1

        // Off the bottom of the world.
        if feetY >= height {
            person.health = 0
            return
        }

        // Standing on something?
        let standing = isSolidFooting(Int(person.x), below)
        let inWater = isValid(Int(person.x), feetY) && isLiquid(typeAt(Int(person.x), feetY))

        if !standing {
            person.doing = inWater ? .swimming : .falling
            // People fall the way the world falls. With the world's pull turned down they fall more gently, and with no
            // pull downwards at all they hang where they are. Sideways and upward pulls are not followed: a person has
            // feet at one end and the whole of walking assumes the floor is below them.
            let pull = PowderPeople.gravity * (gravityY.isFinite ? max(0, min(2, gravityY)) : 1)
            if inWater {
                // Water takes speed *away*, rather than merely adding less. Slowing the pull alone was not enough and
                // is worth writing down: somebody who fell a long way before reaching the water was already going as
                // fast as anybody can, so a gentler pull changed nothing at all and they hit the bottom at full speed.
                // Water has to be drag, which is what makes a lake a way down and not just a slower sky.
                person.fall = min(PowderPeople.waterFall, person.fall * PowderPeople.waterDrag + pull)
            } else {
                person.fall = min(PowderPeople.terminalFall, person.fall + pull)
            }
            // Every row passed on the way down is checked, not only the one they end up above. A fall can cover more
            // than a cell in one moment, and checking only the end let people drop straight through a one-cell floor
            // about one time in ten, or land with their feet inside a thicker one.
            let column = Int(person.x)
            let target = person.y + person.fall
            let lastRow = Int(target) + 1
            if lastRow > below {
                for row in (below + 1) ... lastRow where isSolidFooting(column, row) {
                    person.y = Double(row - 1)
                    land(&person)
                    return
                }
            }
            person.y = target
            // Landed on the way down, rather than passing through the floor.
            if isSolidFooting(column, Int(person.y) + 1) {
                land(&person)
            }
            return
        }

        if person.fall > 0 { land(&person) }
        if person.doing == .falling || person.doing == .swimming { person.doing = .walking }

        let pace = person.afraid ? PowderPeople.panicPace : PowderPeople.pace
        let wantedX = person.x + Double(person.facing) * pace
        let aheadX = Int(wantedX + Double(person.facing) * 0.5)

        // Is the way ahead clear for the whole of them?
        if isWalkable(aheadX, feetY) {
            person.x = wantedX
            keepInside(&person)
            return
        }

        // A step up? A world of falling sand is nothing but single steps, and a person who stopped at each one would
        // never get anywhere.
        var climbed = false
        for up in 1 ... PowderPeople.stepUp {
            let stepY = feetY - up
            if isWalkable(aheadX, stepY), isSolidFooting(aheadX, stepY + 1) {
                // Onto the step, not still over the old column. Raised while their feet were still over where they
                // had been standing, they had nothing under them next moment, fell back, and tried again — one step
                // took about forty moments.
                person.x = Double(aheadX) + 0.5
                person.y = Double(stepY)
                person.doing = .climbing
                climbed = true
                break
            }
        }
        if climbed {
            keepInside(&person)
            return
        }

        // A wall. Turn round.
        person.facing = -person.facing
        if person.doing == .climbing { person.doing = .walking }
    }

    /// Landing, which hurts if it was a long way.
    private func land(_ person: inout PowderPerson) {
        if person.fall > PowderPeople.safeLanding {
            person.health -= (person.fall - PowderPeople.safeLanding) * 0.9
        }
        person.fall = 0
        person.y = Double(Int(person.y))
        if person.doing == .falling { person.doing = .walking }
    }

    /// Keeps them on the map, turning them round at the edges rather than letting them walk off.
    private func keepInside(_ person: inout PowderPerson) {
        if person.x < 0.5 {
            person.x = 0.5
            person.facing = 1
        } else if person.x > Double(width) - 0.5 {
            person.x = Double(width) - 0.5
            person.facing = -1
        }
    }

    /// Whether a cell is something to stand on.
    private func isSolidFooting(_ x: Int, _ y: Int) -> Bool {
        guard isValid(x, y) else { return y >= height }
        let physics = elements[typeAt(x, y)]
        return physics.state == .solidFixed || physics.state == .solidMovable
    }

    /// Whether a liquid.
    private func isLiquid(_ id: ElementID) -> Bool {
        elements[id].state == .liquid
    }

    /// Whether the whole of a person fits at a place with their feet there.
    private func isWalkable(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, x < width else { return false }
        for step in 0 ..< PowderPeople.height {
            let cell = y - step
            guard cell >= 0 else { continue }
            guard cell < height else { return false }
            let physics = elements[typeAt(x, cell)]
            // Liquids and gases can be walked through. Solids cannot, which is what makes a wall a wall.
            if physics.state == .solidFixed || physics.state == .solidMovable { return false }
        }
        return true
    }
}

// MARK: - Drawing them

extension PowderEngine {
    /// Paints the people over a finished picture of the world.
    ///
    /// Done here, in the one renderer, so they appear everywhere a world appears: on the screen, in a picture written
    /// to a file, on a television. A second drawing path in the app would mean people who are missing from every
    /// picture anybody shares.
    func drawPeople(into pixels: UnsafeMutablePointer<UInt32>, overlay: PowderOverlayMode) {
        guard !storedPeople.isEmpty else { return }
        for person in storedPeople {
            let x = Int(person.x)
            let feet = Int(person.y)
            guard x >= 0, x < width else { continue }

            // Frightened people go pale, hurt people go dark, and somebody being carried is brighter — three states
            // anybody can read at a glance on a moving screen without a word being written.
            let hurt = max(0, min(1, 1 - person.health))
            var red = 236
            var green = 224
            var blue = 208
            if person.isAfraid {
                red = 255
                green = 214
                blue = 120
            } else if person.doing == .held {
                red = 180
                green = 235
                blue = 255
            }
            red = Int(Double(red) * (1 - hurt * 0.65))
            green = Int(Double(green) * (1 - hurt * 0.75))
            blue = Int(Double(blue) * (1 - hurt * 0.75))
            // In the heat view they are drawn at their own warmth, like everything else in it, rather than in a colour
            // that would be the one thing in that picture not meaning what the picture means.
            let colour = overlay == .temperature
                ? Self.heatMap(person.warmth)
                : Self.pack(red, green, blue)

            for step in 0 ..< PowderPeople.height {
                let y = feet - step
                guard y >= 0, y < height else { continue }
                pixels[y * width + x] = colour
            }
            // Arms, one cell either side at the middle, which is what turns three stacked dots into a figure.
            let arms = feet - 1
            if arms >= 0, arms < height {
                if x - 1 >= 0 { pixels[arms * width + x - 1] = colour }
                if x + 1 < width { pixels[arms * width + x + 1] = colour }
            }
        }
    }
}
