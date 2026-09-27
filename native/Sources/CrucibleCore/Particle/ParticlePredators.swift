/// Foxes and rabbits: one kind hunts the other, both have young, and the numbers rise and fall.
///
/// ## What is going on
///
/// Rabbits wander, keep clear of any fox they can see, and have young — more slowly the more crowded the field is,
/// because there is only so much grass. Foxes wander until they see a rabbit, then chase it; a fox that catches one
/// eats it and is fed, and sometimes has a cub; a fox that goes too long without is gone.
///
/// Nothing sets the numbers. What happens is what always happens between a hunter and its food, and has been
/// measured in real hares and lynxes for two hundred years: rabbits flourish, so foxes flourish on them; the foxes
/// eat the rabbits down, and then starve; with few foxes about, the rabbits flourish again. The graph shows the two
/// numbers chasing each other round — the foxes' peaks always a little after the rabbits'.
///
/// ## Where it lives
///
/// On the individually interesting bodies, with which kind each is kept in its charge, as particle life does — and
/// with the charge force switched off for them, so the kinds are not flung apart as if electric. A fox's hunger is
/// its lifespan: it counts down every moment in the ordinary way, and eating sets it back to full. When it runs out,
/// the fox is removed by the same rule that removes anything whose life is over. A rabbit's lifespan is its old age.
public struct ParticleHerdCount: Sendable, Hashable {
    public var rabbits: Int
    public var foxes: Int

    public init(rabbits: Int, foxes: Int) {
        self.rabbits = rabbits
        self.foxes = foxes
    }
}

extension ParticleEngine {
    /// The charge a rabbit carries, to say what it is.
    public static let rabbitKind = 1.0
    /// The charge a fox carries.
    public static let foxKind = 2.0
    /// How many readings the graph keeps: a minute and a half of them.
    public static let herdHistoryLength = 360
    /// How often a reading is taken, in moments: four a second.
    public static let herdSampleEvery = 15
    /// The most rabbits the grass can feed. Near this, rabbits hardly breed at all.
    public static let rabbitCapacity = 700
    /// The most foxes at once, however well fed.
    public static let foxLimit = 120

    /// Whether the foxes are hunting.
    public var predatorsEnabled: Bool { storedPredatorsEnabled }

    /// How many of each there have been, oldest first, one reading every ``herdSampleEvery`` moments.
    public var herdHistory: [ParticleHerdCount] { storedHerdHistory }

    /// How many of each there are now.
    public var herdCount: ParticleHerdCount {
        var rabbits = 0
        var foxes = 0
        for body in particles {
            if body.charge == Self.rabbitKind { rabbits += 1 } else if body.charge == Self.foxKind { foxes += 1 }
        }
        return ParticleHerdCount(rabbits: rabbits, foxes: foxes)
    }

    // MARK: - The tuning, in one place

    /// How far a rabbit can see a fox, and a fox a rabbit, as shares of the screen.
    static let rabbitSight = 0.1
    static let foxSight = 0.17
    /// How hard each can run, in pixels a moment for every moment of effort.
    ///
    /// A fox sprints faster than a rabbit can run, so a chase that starts close ends in a catch; one that starts at
    /// the edge of what the fox can see often ends with the fox hungry and the rabbit gone.
    static let rabbitFlee = 0.32
    static let foxChase = 0.46
    static let wander = 0.09
    /// How long a fox can go without eating, and how long a rabbit lives, in moments.
    static let foxHunger = 600
    static let rabbitOldAge = 2_400
    /// How long a fox that has just eaten is too full to hunt.
    ///
    /// Without it one fox could clear a whole warren in a few seconds, and did: the foxes ate every rabbit in the
    /// field in their first boom and then all starved, and the graph was one spike and a flat line. A full fox
    /// wanders instead, which is what real ones do, and it is what lets the rabbits recover in time to feed the next
    /// generation.
    static let foxFull = 200
    /// How likely a fox is to die of something other than hunger in any one moment: about once in fifty seconds.
    /// Without an ordinary death, well-fed foxes lived for ever and filled the field.
    static let foxMortality = 1.0 / 3_000
    /// How likely a rabbit is to have young in any one moment, with the field empty.
    static let rabbitBreeding = 0.0028
    /// How likely a fox is to have a cub each time it eats.
    static let foxBreeding = 0.25

    /// Rabbits in a field, a few foxes among them, and the hunting switched on.
    public func spawnFoxesAndRabbits(rabbits: Int = 220, foxes: Int = 12) {
        beginScene("foxes", gravityY: 0)
        // A field, not a sky: nothing falls, and the drag is what makes running a thing that has to be kept up.
        sceneSets(damping: 0.9, maxSpeed: 4)
        storedPredatorsEnabled = true
        storedChargeIsKind = true
        storedHerdHistory = []
        storedHerdSampleAge = 0
        for _ in 0 ..< max(0, rabbits) {
            addRabbit(x: across(0.06 + rng.next() * 0.88), y: down(0.06 + rng.next() * 0.88), z: randomHerdDepth())
        }
        for _ in 0 ..< max(0, foxes) {
            addFox(x: across(0.1 + rng.next() * 0.8), y: down(0.1 + rng.next() * 0.8), z: randomHerdDepth())
        }
        recordHerd()
    }

    private func randomHerdDepth() -> Double {
        storedDepthEnabled ? (rng.next() - 0.5) * halfDepth * 1.6 : 0
    }

    @discardableResult
    private func addRabbit(x: Double, y: Double, z: Double) -> Int {
        let age = Self.rabbitOldAge
        return addParticle(
            x: x, y: y, velocityX: 0, velocityY: 0,
            radius: 2.4 * sceneScale, mass: 1, charge: Self.rabbitKind,
            color: PackedColor(hue: 38, saturation: 0.35, lightness: 0.82),
            // Not all the same age, so they do not all die of old age together.
            lifespan: age / 2 + Int(rng.next() * Double(age)), maxLife: age,
            z: z
        )
    }

    @discardableResult
    private func addFox(x: Double, y: Double, z: Double) -> Int {
        addParticle(
            x: x, y: y, velocityX: 0, velocityY: 0,
            radius: 3.6 * sceneScale, mass: 1, charge: Self.foxKind,
            color: PackedColor(hue: 20, saturation: 0.9, lightness: 0.55),
            lifespan: Self.foxHunger, maxLife: Self.foxHunger,
            z: z
        )
    }

    /// Adds a reading to the graph.
    private func recordHerd() {
        storedHerdHistory.append(herdCount)
        if storedHerdHistory.count > Self.herdHistoryLength {
            storedHerdHistory.removeFirst(storedHerdHistory.count - Self.herdHistoryLength)
        }
    }

    /// One moment of hunting, fleeing and breeding.
    func stepPredators() {
        guard storedPredatorsEnabled else { return }
        storedHerdSampleAge += 1
        if storedHerdSampleAge >= Self.herdSampleEvery {
            storedHerdSampleAge = 0
            recordHerd()
        }

        var rabbits: [Int] = []
        var foxes: [Int] = []
        for index in particles.indices where particles[index].isFinite && !particles[index].hasExpired {
            let kind = particles[index].charge
            if kind == Self.rabbitKind { rabbits.append(index) } else if kind == Self.foxKind { foxes.append(index) }
        }
        guard !rabbits.isEmpty || !foxes.isEmpty else { return }

        let span = patternSpan
        let rabbitSightSquared = (span * Self.rabbitSight) * (span * Self.rabbitSight)
        let foxSightSquared = (span * Self.foxSight) * (span * Self.foxSight)
        let inDepth = storedDepthEnabled
        var eaten = Set<Int>()
        var fedFoxes: [Int] = []
        var births: [(x: Double, y: Double, z: Double, fox: Bool)] = []

        func distanceSquared(_ a: Int, _ b: Int) -> (dx: Double, dy: Double, dz: Double, squared: Double) {
            let dx = particles[b].x - particles[a].x
            let dy = particles[b].y - particles[a].y
            let dz = inDepth ? particles[b].z - particles[a].z : 0
            return (dx, dy, dz, dx * dx + dy * dy + dz * dz)
        }

        func push(_ index: Int, _ dx: Double, _ dy: Double, _ dz: Double, _ strength: Double) {
            let length = (dx * dx + dy * dy + dz * dz).squareRoot()
            guard length > 1e-9 else { return }
            particles[index].velocityX += dx / length * strength
            particles[index].velocityY += dy / length * strength
            if inDepth { particles[index].velocityZ += dz / length * strength }
        }

        func wanderPush(_ index: Int) {
            let angle = rng.next() * 6.283185307179586
            let rise = inDepth ? (rng.next() - 0.5) : 0
            push(index, jsCos(angle), jsSin(angle), rise, Self.wander)
        }

        // The foxes first: whoever is caught this moment does not also get to run.
        var diedNaturally = Set<Int>()
        for fox in foxes {
            if rng.chance(Self.foxMortality) {
                diedNaturally.insert(particles[fox].id)
                continue
            }
            // Too full to hunt, so it wanders.
            if let hunger = particles[fox].lifespan, hunger > Self.foxHunger - Self.foxFull {
                wanderPush(fox)
                continue
            }
            var nearest = -1
            var nearestAway = foxSightSquared
            var toward = (dx: 0.0, dy: 0.0, dz: 0.0)
            for rabbit in rabbits where !eaten.contains(rabbit) {
                let d = distanceSquared(fox, rabbit)
                if d.squared < nearestAway {
                    nearestAway = d.squared
                    nearest = rabbit
                    toward = (d.dx, d.dy, d.dz)
                }
            }
            guard nearest >= 0 else {
                wanderPush(fox)
                continue
            }
            let catchDistance = particles[fox].radius + particles[nearest].radius + 1.5
            if nearestAway <= catchDistance * catchDistance {
                eaten.insert(nearest)
                fedFoxes.append(fox)
                if rng.chance(Self.foxBreeding) {
                    births.append((particles[fox].x, particles[fox].y, particles[fox].z, true))
                }
            } else {
                push(fox, toward.dx, toward.dy, toward.dz, Self.foxChase)
            }
        }
        for fox in fedFoxes { particles[fox].lifespan = Self.foxHunger }

        // Then the rabbits that are left.
        let grass = max(0, 1 - Double(rabbits.count) / Double(Self.rabbitCapacity))
        for rabbit in rabbits where !eaten.contains(rabbit) {
            var nearest = -1
            var nearestAway = rabbitSightSquared
            var away = (dx: 0.0, dy: 0.0, dz: 0.0)
            for fox in foxes {
                let d = distanceSquared(rabbit, fox)
                if d.squared < nearestAway {
                    nearestAway = d.squared
                    nearest = fox
                    away = (-d.dx, -d.dy, -d.dz)
                }
            }
            if nearest >= 0 {
                push(rabbit, away.dx, away.dy, away.dz, Self.rabbitFlee)
            } else {
                wanderPush(rabbit)
                // Young only when not running for its life.
                if rng.chance(Self.rabbitBreeding * grass) {
                    births.append((particles[rabbit].x, particles[rabbit].y, particles[rabbit].z, false))
                }
            }
        }

        if !eaten.isEmpty || !diedNaturally.isEmpty {
            let gone = Set(eaten.map { particles[$0].id }).union(diedNaturally)
            removeParticles { gone.contains($0.id) }
        }

        guard !births.isEmpty else { return }
        var foxesNow = foxes.count - diedNaturally.count
        var rabbitsNow = rabbits.count - eaten.count
        let nudge = 4 * sceneScale
        for birth in births {
            // Room in the field for another body at all, before anything else is asked.
            guard bodyCount < maxParticles else { break }
            let x = birth.x + (rng.next() - 0.5) * nudge
            let y = birth.y + (rng.next() - 0.5) * nudge
            let z = inDepth ? birth.z + (rng.next() - 0.5) * nudge : 0
            if birth.fox {
                guard foxesNow < Self.foxLimit else { continue }
                addFox(x: x, y: y, z: z)
                foxesNow += 1
            } else {
                guard rabbitsNow < Self.rabbitCapacity else { continue }
                addRabbit(x: x, y: y, z: z)
                rabbitsNow += 1
            }
        }
    }
}
