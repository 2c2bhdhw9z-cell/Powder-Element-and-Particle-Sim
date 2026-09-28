import Testing

@testable import CrucibleCore

/// Little people who live in the powder world.
///
/// Every one of these is a claim about behaviour that reading the code cannot settle: does somebody climb a one-cell
/// step and turn at a two-cell wall; do they notice lava and run the other way; does water break a fall. Those are the
/// difference between a person and a sprite that slides along a floor, and they are all arithmetic, so they belong here
/// rather than in something anybody has to watch.
@Suite("Little people")
struct PowderPeopleTests {
    /// A world with a floor across the bottom and nothing else.
    private func room(_ width: Int = 60, _ height: Int = 30, floorAt floor: Int? = nil) -> PowderEngine {
        let engine = PowderEngine(width: width, height: height, seed: 41)
        let level = floor ?? height - 2
        for x in 0 ..< width { engine.setElement(x, level, Element.bedrock) }
        for x in 0 ..< width where level + 1 < height { engine.setElement(x, level + 1, Element.bedrock) }
        return engine
    }

    private func only(_ engine: PowderEngine) -> PowderPerson {
        engine.people[0]
    }

    // MARK: Being there at all

    @Test("Somebody can be put in the world, and there is a limit")
    func peopleCanBeAdded() {
        let engine = room()
        #expect(engine.hasPeople == false)
        #expect(engine.addPerson(atX: 10, y: 27) != nil)
        #expect(engine.hasPeople)
        #expect(engine.people.count == 1)

        for i in 0 ..< PowderPeople.most { _ = engine.addPerson(atX: 10 + i, y: 27) }
        #expect(engine.people.count == PowderPeople.most, "more people than the world allows")
        #expect(engine.addPerson(atX: 5, y: 27) == nil)
        #expect(engine.addPerson(atX: -5, y: 27) == nil)

        engine.clearPeople()
        #expect(engine.hasPeople == false)
    }

    @Test("Everybody has their own number, kept for good")
    func numbersAreTheirOwn() {
        let engine = room()
        let first = engine.addPerson(atX: 10, y: 27)
        let second = engine.addPerson(atX: 20, y: 27)
        #expect(first != second)
        #expect(engine.holdPerson(first!))
        for _ in 0 ..< 30 { engine.step() }
        #expect(engine.people.contains { $0.id == first }, "somebody lost their number while being carried")
        #expect(engine.holdPerson(9_999) == false)
    }

    @Test("A world with nobody in it does no work for them")
    func nobodyCostsNothing() {
        let engine = room()
        for _ in 0 ..< 20 { engine.step() }
        #expect(engine.hasPeople == false)
        #expect(engine.people.isEmpty)
    }

    // MARK: Walking

    @Test("They walk")
    func theyWalk() {
        let engine = room()
        _ = engine.addPerson(atX: 10, y: 27)
        let started = only(engine).x
        for _ in 0 ..< 40 { engine.step() }
        #expect(abs(only(engine).x - started) > 2, "nobody went anywhere")
        #expect(only(engine).health > 0.99, "walking along a floor hurt somebody")
    }

    @Test("They turn round at a wall rather than walking into it")
    func theyTurnAtAWall() {
        let engine = room()
        // A wall three cells tall, well beyond a step.
        for y in 24 ... 27 { engine.setElement(30, y, Element.bedrock) }
        _ = engine.addPerson(atX: 26, y: 27)
        // Facing the wall to start with, whichever way the coin came down.
        var people = engine.people
        people[0].facing = 1
        engine.setPeopleForTest(people)

        for _ in 0 ..< 80 { engine.step() }
        #expect(only(engine).x < 30, "somebody walked into a wall")
        #expect(only(engine).facing == -1, "somebody did not turn round at a wall")
    }

    @Test("They climb a single step up, because a world of falling sand is made of them")
    func theyClimbAStep() {
        // The room's floor has its top at 28, so somebody standing on it has their feet at 27. One cell higher from
        // there means filling 27 as well, and nothing above it.
        let engine = room()
        for x in 30 ..< 60 { engine.setElement(x, 27, Element.bedrock) }
        _ = engine.addPerson(atX: 26, y: 27)
        var people = engine.people
        people[0].facing = 1
        engine.setPeopleForTest(people)

        for _ in 0 ..< 200 { engine.step() }
        #expect(only(engine).x > 32, "somebody stopped at a single step instead of climbing it")
        #expect(only(engine).y < 27, "somebody got past the step without going up")
    }

    @Test("They do not walk off the edge of the world")
    func theyStayInside() {
        let engine = room(30, 20)
        _ = engine.addPerson(atX: 2, y: 17)
        var people = engine.people
        people[0].facing = -1
        engine.setPeopleForTest(people)
        for _ in 0 ..< 200 { engine.step() }
        #expect(engine.people.count == 1, "somebody walked out of the world")
        #expect(only(engine).x >= 0)
        #expect(only(engine).x <= 30)
    }

    // MARK: Falling

    @Test("They fall, and they land")
    func theyFallAndLand() {
        let engine = room(40, 40)
        _ = engine.addPerson(atX: 20, y: 4)
        #expect(only(engine).doing == .falling)
        for _ in 0 ..< 200 { engine.step() }
        let landed = only(engine)
        #expect(landed.y > 30, "somebody did not fall")
        #expect(landed.doing != .falling, "somebody never landed")
        #expect(landed.fall == 0)
    }

    @Test("A long drop hurts and a short one does not")
    func longDropsHurt() {
        let short = room(40, 40)
        _ = short.addPerson(atX: 20, y: 33)
        for _ in 0 ..< 120 { short.step() }
        #expect(short.people.first?.health ?? 0 > 0.98, "a step down hurt somebody")

        let long = room(40, 200)
        for x in 0 ..< 40 { long.setElement(x, 198, Element.bedrock) }
        _ = long.addPerson(atX: 20, y: 2)
        for _ in 0 ..< 600 { long.step() }
        let after = long.people.first
        #expect(after == nil || after!.health < 0.95, "falling two hundred cells did no harm at all")
    }

    @Test("Water breaks a fall")
    func waterBreaksAFall() {
        // The reason this matters: water being a way down safely is the difference between a tall world being explorable
        // and a tall world being a way to kill people.
        // Both sampled while still on the way down: after landing everybody's falling speed is nought, which would
        // make the two look identical for the wrong reason.
        let dry = room(40, 160)
        _ = dry.addPerson(atX: 20, y: 3)
        let wet = room(40, 160)
        for y in 20 ..< 158 { for x in 0 ..< 40 { wet.setElement(x, y, Element.water) } }
        _ = wet.addPerson(atX: 20, y: 3)

        for _ in 0 ..< 60 { dry.step(); wet.step() }
        let drySpeed = dry.people.first?.fall ?? 0
        let wetPerson = wet.people.first
        #expect(drySpeed > 0.5, "the dry fall was not fast, so this proves nothing")
        #expect((wetPerson?.fall ?? 99) < drySpeed, "water did not slow the fall")
        #expect(wetPerson?.doing == .swimming || wetPerson?.doing == .walking)
    }

    @Test("Falling into deep water is always survivable, however far the drop")
    func waterIsAlwaysAWayDown() {
        // The claim worth making, rather than 'water is a bit slower'. Somebody who fell a long way before reaching the
        // water is already going as fast as anybody can, so water has to take speed away rather than add less of it —
        // it did the latter at first, and a hundred-and-fifty-cell drop into a lake was fatal.
        let engine = room(40, 200)
        for y in 150 ..< 198 { for x in 0 ..< 40 { engine.setElement(x, y, Element.water) } }
        _ = engine.addPerson(atX: 20, y: 2)
        // Watched until they stop sinking, and no longer. Left there they eventually drown, which is right and is a
        // different question — the one here is only whether the impact hurt them.
        var health = 1.0
        for _ in 0 ..< 1_000 {
            engine.step()
            guard let person = engine.people.first else { break }
            health = person.health
            if person.fall == 0, person.y > 190 { break }
        }
        #expect(engine.people.first != nil, "a long drop into deep water killed somebody")
        #expect(health > 0.9, "a long drop into deep water hurt somebody on the way in")
    }

    // MARK: Danger

    @Test("They see lava and run the other way")
    func theyRunFromLava() {
        // The behaviour that makes them read as alive. A person walking calmly into lava is a sprite.
        let engine = room(80, 30)
        for x in 55 ..< 62 { engine.setElement(x, 27, Element.lava, temp: 1_200) }
        _ = engine.addPerson(atX: 50, y: 27)
        var people = engine.people
        people[0].facing = 1
        engine.setPeopleForTest(people)

        var turned = false
        var wasAfraid = false
        for _ in 0 ..< 60 {
            engine.step()
            guard let person = engine.people.first else { break }
            if person.isAfraid { wasAfraid = true }
            if person.facing == -1 { turned = true; break }
        }
        #expect(turned, "somebody walked towards lava without turning")
        #expect(wasAfraid, "somebody near lava was never frightened")
    }

    @Test("Frightened people move faster than calm ones")
    func fearIsFaster() {
        let calm = room(90, 30)
        _ = calm.addPerson(atX: 45, y: 27)
        let scared = room(90, 30)
        for x in 60 ..< 68 { scared.setElement(x, 27, Element.lava, temp: 1_200) }
        _ = scared.addPerson(atX: 50, y: 27)
        var people = scared.people
        people[0].facing = -1
        scared.setPeopleForTest(people)

        let calmFrom = calm.people[0].x
        let scaredFrom = scared.people[0].x
        for _ in 0 ..< 25 { calm.step(); scared.step() }
        let calmWent = abs((calm.people.first?.x ?? calmFrom) - calmFrom)
        let scaredWent = abs((scared.people.first?.x ?? scaredFrom) - scaredFrom)
        #expect(scaredWent > calmWent, "fear was no faster than a stroll")
    }

    @Test("Standing in fire hurts, and quickly")
    func fireHurts() {
        // Wide, because a fire one cell across is a fire somebody simply steps out of — and stepping out of it is the
        // right thing for them to do, so the check has to be about a fire they cannot escape.
        let engine = room(40, 30)
        _ = engine.addPerson(atX: 20, y: 27)
        for x in 0 ..< 40 {
            for y in 25 ... 27 { engine.setElement(x, y, Element.fire, temp: 900) }
        }
        for _ in 0 ..< 30 { engine.step() }
        let person = engine.people.first
        #expect(person == nil || person!.health < 0.6, "standing in a fire barely mattered")
    }

    @Test("Being buried is slow enough to be dug out of")
    func buryingIsSlow() {
        // Deliberately slow rather than instant: somebody who notices should have time to do something, and a world
        // where a landslide kills instantly is a world where the people are scenery.
        let engine = room(40, 30)
        _ = engine.addPerson(atX: 20, y: 27)
        for y in 25 ... 27 { engine.setElement(20, y, Element.sand) }
        for _ in 0 ..< 20 { engine.step() }
        let halfWay = engine.people.first
        #expect(halfWay != nil, "being buried killed somebody in a third of a second")
        #expect((halfWay?.health ?? 1) < 1, "being buried did nothing at all")
    }

    @Test("Somebody who dies leaves a puff of smoke where they were")
    func theyLeaveSomethingBehind() {
        // So that somebody watching sees what happened, rather than a person simply ceasing to exist.
        let engine = room(40, 30)
        _ = engine.addPerson(atX: 20, y: 27)
        var people = engine.people
        people[0].health = 0.02
        engine.setPeopleForTest(people)
        for y in 25 ... 27 { engine.setElement(20, y, Element.lava, temp: 1_500) }
        for _ in 0 ..< 10 { engine.step() }
        #expect(engine.people.isEmpty, "somebody survived being in lava at death's door")
    }

    @Test("They cool down again after being warm")
    func warmthFades() {
        // Warmth follows the air, so somebody who walks out of a hot room recovers rather than being marked for life.
        let engine = room(60, 30)
        _ = engine.addPerson(atX: 30, y: 27)
        var people = engine.people
        people[0].warmth = 90
        engine.setPeopleForTest(people)
        for _ in 0 ..< 80 { engine.step() }
        #expect((engine.people.first?.warmth ?? 99) < 40, "somebody stayed hot in a cold room")
    }

    @Test("Underwater they hold their breath, and then they cannot")
    func breathRunsOut() {
        let engine = room(40, 40)
        for y in 10 ..< 38 { for x in 0 ..< 40 { engine.setElement(x, y, Element.water) } }
        _ = engine.addPerson(atX: 20, y: 36)
        for _ in 0 ..< 60 { engine.step() }
        let earlier = engine.people.first
        #expect(earlier != nil)
        #expect((earlier?.breath ?? 0) < PowderPeople.lungs, "nobody was holding their breath underwater")
        #expect((earlier?.health ?? 0) > 0.9, "drowning started immediately rather than after a while")

        for _ in 0 ..< 400 { engine.step() }
        let later = engine.people.first
        #expect(later == nil || later!.health < 0.9, "somebody held their breath indefinitely")
    }

    // MARK: Being picked up

    @Test("Somebody can be picked up, carried and put down")
    func theyCanBeCarried() {
        let engine = room(60, 40)
        let id = engine.addPerson(atX: 20, y: 37)!
        for _ in 0 ..< 20 { engine.step() }

        #expect(engine.holdPerson(id))
        #expect(engine.isCarryingSomebody)
        engine.carryHeldPeople(toX: 45, y: 8)
        for _ in 0 ..< 10 { engine.step() }
        // While held they stay exactly where the hand is, rather than falling out of it.
        #expect(abs(only(engine).x - 45) < 0.01)
        #expect(abs(only(engine).y - 8) < 0.01)

        engine.dropHeldPeople()
        #expect(engine.isCarryingSomebody == false)
        for _ in 0 ..< 200 { engine.step() }
        let landed = engine.people.first
        #expect(landed == nil || landed!.y > 20, "somebody put down in mid-air did not fall")
    }

    @Test("The nearest person to a finger is the one picked up")
    func theNearestIsPickedUp() {
        // A finger is blunt and a person is one cell wide, so pointing near somebody has to be enough.
        let engine = room(80, 30)
        let left = engine.addPerson(atX: 20, y: 27)!
        let right = engine.addPerson(atX: 60, y: 27)!
        #expect(engine.person(nearX: 21, y: 26, within: 5)?.id == left)
        #expect(engine.person(nearX: 58, y: 26, within: 5)?.id == right)
        #expect(engine.person(nearX: 40, y: 26, within: 5) == nil, "somebody was grabbed from twenty cells away")
        // A grab at the head counts, not only at the feet.
        #expect(engine.person(nearX: 20.5, y: 25, within: 3)?.id == left)
    }

    // MARK: Being seen

    @Test("They are drawn, over the world rather than instead of it")
    func theyAreDrawn() {
        let engine = room(40, 30)
        let without = engine.renderToArray()
        _ = engine.addPerson(atX: 20, y: 27)
        let with = engine.renderToArray()
        #expect(with != without, "nobody appeared in the picture")

        var changed = 0
        for i in 0 ..< with.count where with[i] != without[i] { changed += 1 }
        // Three cells of body and two of arms. Not more: a person who painted half the screen would be a bug.
        #expect(changed >= 3 && changed <= 6, "a person took up \(changed) cells")
    }

    @Test("A frightened person looks different from a calm one")
    func fearShows() {
        // Three states anybody can read at a glance without a word being written: calm, frightened, hurt.
        let engine = room(40, 30)
        _ = engine.addPerson(atX: 20, y: 26)
        var people = engine.people
        people[0].doing = .walking
        engine.setPeopleForTest(people)
        let calm = engine.renderToArray()[25 * 40 + 20]

        people = engine.people
        people[0].afraid = true
        engine.setPeopleForTest(people)
        let afraid = engine.renderToArray()[25 * 40 + 20]

        people = engine.people
        people[0].afraid = false
        people[0].health = 0.2
        engine.setPeopleForTest(people)
        let hurt = engine.renderToArray()[25 * 40 + 20]

        #expect(calm != afraid, "a frightened person looked the same as a calm one")
        #expect(calm != hurt, "a badly hurt person looked the same as a well one")
        #expect(afraid != hurt)
    }

    @Test("In the heat view they are drawn at their own warmth")
    func theHeatViewShowsTheirWarmth() {
        // Otherwise they would be the one thing in that picture not meaning what the picture means.
        let engine = room(40, 30)
        _ = engine.addPerson(atX: 20, y: 26)
        var people = engine.people
        people[0].warmth = 900
        engine.setPeopleForTest(people)
        let hot = engine.renderToArray(overlay: .temperature)[25 * 40 + 20]

        people = engine.people
        people[0].warmth = 20
        engine.setPeopleForTest(people)
        let cool = engine.renderToArray(overlay: .temperature)[25 * 40 + 20]
        #expect(hot != cool, "somebody's warmth did not show in the heat view")
        #expect(hot & 0xFF > cool & 0xFF, "a hot person did not read as hot")
    }

    @Test("They appear in a picture written to a file too")
    func theyAreInPictures() throws {
        // One renderer, so they are in everything a world appears in — the screen, a file, a television. A second
        // drawing path in the app would mean people missing from every picture anybody shares.
        let engine = room(40, 30)
        let without = try #require(engine.pngBytes())
        _ = engine.addPerson(atX: 20, y: 27)
        let with = try #require(engine.pngBytes())
        #expect(with != without, "nobody was in the picture written to a file")
    }
}

extension PowderEngine {
    /// Replaces the people, for the checks that need somebody in a particular state.
    ///
    /// The engine gives no way to set a person's health or facing from outside, deliberately — those are the world's
    /// business. This is how a check puts somebody in the state being examined without that becoming a thing the app
    /// could do by accident.
    fileprivate func setPeopleForTest(_ people: [PowderPerson]) {
        storedPeople = people
    }
}
