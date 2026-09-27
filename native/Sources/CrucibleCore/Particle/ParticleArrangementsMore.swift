/// More arrangements: a galaxy crash, the solar system, a row of pendulums, an atom and a marbling tray.
///
/// A separate file from `ParticlePatterns` and `ParticleSpawners` for one reason: those two are checked
/// against the reference implementation body for body, and the comparisons recorded for them depend on the
/// exact order random numbers are drawn in. Nothing in this file is in those comparisons, so keeping it apart
/// means a new scene here can never disturb them.
///
/// Each one has a flat form here and a form in depth in `ParticleArrangementsMoreDepth.swift`, chosen by the
/// first line of each function — the same arrangement as every other scene in the field.
extension ParticleEngine {
    // MARK: - Shared groundwork

    /// Puts one body into the crowd, flat. The same thing `ParticlePatterns` does for its own scenes; repeated
    /// here because that one is private to the file the recorded comparisons depend on.
    @discardableResult
    func placeLoose(
        _ x: Double,
        _ y: Double,
        velocityX: Double = 0,
        velocityY: Double = 0,
        hue: Double,
        saturation: Double = 0.85,
        lightness: Double = 0.62,
        mass: Double = 1,
        life: Double = -1,
        size: Double = 0,
        role: Swarm.Role = []
    ) -> Bool {
        swarm.append(
            x: x,
            y: y,
            velocityX: velocityX,
            velocityY: velocityY,
            color: PackedColor(hue: hue, saturation: saturation, lightness: lightness).packedRGBA,
            budget: maxParticles - particles.count,
            mass: mass,
            life: life,
            role: role,
            size: size
        )
    }

    /// How fast something has to travel to hold a circle of this radius round a pull of this strength.
    ///
    /// The pull a black hole applies is its mass times two hundred divided by the distance squared, so the
    /// speed that balances it is the square root of that pull times the distance. One place rather than five,
    /// because a scene whose speeds are slightly wrong does not look slightly wrong — it looks broken, with
    /// everything either spiralling in or leaving.
    func orbitSpeed(pullMass: Double, atDistance distance: Double) -> Double {
        guard distance > 0.001 else { return 0 }
        return (pullMass * 200 / distance).squareRoot()
    }

    // MARK: - Galaxy crash

    /// Two galaxies passing close enough to tear each other apart.
    ///
    /// The spectacle is not the cores but what happens to the stars: the ones on the near side of each disc are
    /// pulled toward the other galaxy and left behind as a long tail, which is exactly what the photographs of
    /// colliding galaxies show. The two cores are given a sideways offset rather than being aimed at each other,
    /// because a head-on hit simply swallows both discs and the tails never form.
    public func spawnGalaxyCrash(count requested: Int = 2_600) {
        if storedDepthEnabled { return spawnGalaxyCrashInDepth(count: requested) }
        beginScene("crash", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        let span = patternSpan
        let coreMass = 58.0
        let apart = span * 0.3
        let centreX = width * 0.5
        let centreY = height * 0.5
        // Each core sits to one side and a little above or below, so they sweep past rather than meet.
        let offset = span * 0.1
        let closing = orbitSpeed(pullMass: coreMass, atDistance: apart) * 0.34

        let cores: [(x: Double, y: Double, vx: Double, vy: Double, hue: Double)] = [
            (centreX - apart * 0.5, centreY - offset, closing, 0, 206),
            (centreX + apart * 0.5, centreY + offset, -closing, 0, 344),
        ]
        var coreIndex: [Int] = []
        for core in cores {
            coreIndex.append(
                addParticle(
                    x: core.x, y: core.y, velocityX: core.vx, velocityY: core.vy,
                    radius: 11, mass: coreMass,
                    color: PackedColor(hue: core.hue, saturation: 0.8, lightness: 0.62),
                    // Not pinned: the whole point is that the two of them move.
                    isFixed: false, ignoresGravity: true, kind: .blackhole
                )
            )
        }
        _ = coreIndex

        let inner = span * 0.035
        let disc = span * 0.14
        for index in 0 ..< total {
            let which = index % 2
            let core = cores[which]
            let distance = inner + rng.next() * disc
            let angle = rng.next() * Double.pi * 2
            // Both discs turn the same way, so the pair reads as one event rather than two unrelated swirls.
            let speed = orbitSpeed(pullMass: coreMass, atDistance: distance) * (0.95 + rng.next() * 0.1)
            let x = core.x + jsCos(angle) * distance
            let y = core.y + jsSin(angle) * distance
            // Brighter toward the middle of each disc, as a real one is.
            let closeness = 1 - (distance - inner) / max(1, disc)
            if !placeLoose(
                x, y,
                velocityX: -jsSin(angle) * speed + core.vx,
                velocityY: jsCos(angle) * speed + core.vy,
                hue: core.hue + (rng.next() - 0.5) * 26,
                saturation: 0.7,
                lightness: 0.5 + closeness * 0.26,
                // Keeps its speed, as everything in orbit does — otherwise both discs simply sink into their
                // own cores and there is nothing left to tear out into a tail.
                role: .orbits
            ) { break }
        }
    }

    // MARK: - The solar system

    /// The Sun and the planets in order, each holding its own circle.
    ///
    /// ## Why the distances are squeezed
    ///
    /// Because the real ones cannot be drawn. Neptune is thirty times as far out as the Earth, so a picture
    /// that fits Neptune on the screen puts Mercury, Venus, Earth and Mars inside a few pixels of the Sun.
    /// The distances here are squeezed toward the middle — each one raised to a power a little over a half —
    /// which keeps every planet in its right *order* and far enough from its neighbours to see.
    ///
    /// The speeds are then worked out from the distance each planet is actually drawn at, not from its real
    /// year, so that every planet genuinely holds the circle it is drawn on. What survives is the thing worth
    /// seeing: the inner planets race, and the outer ones crawl.
    ///
    /// The Earth is given a little pull of its own so the Moon has something to go round.
    public func spawnSolarSystem() {
        if storedDepthEnabled { return spawnSolarSystemInDepth() }
        beginScene("solar", gravityY: 0)
        let centreX = width * 0.5
        let centreY = height * 0.5
        layOutSolarSystem(centreX: centreX, centreY: centreY, inDepth: false)
    }

    /// One planet, as the scene describes it.
    struct Planet {
        var name: String
        /// How far from the Sun, with the Earth as one. Here to be read and checked, not to be drawn with.
        var distance: Double
        /// Where to draw it: nought at the innermost ring the scene uses, one at the outermost.
        ///
        /// ## Why this is a number in a table rather than a sum
        ///
        /// Because the sum that produces it is a logarithm, and this engine carries its own sine, cosine and
        /// powers precisely so that every machine gets identical answers — there is no logarithm among them, and
        /// borrowing the system's would give a scene that came out very slightly differently on different
        /// hardware. So the logarithms are worked out once, here: each of these is the logarithm of one plus the
        /// planet's real distance, divided by the same for Neptune.
        ///
        /// A logarithm is the right squeeze because it gives every *doubling* of distance the same room. Raising
        /// the distances to a power instead — which is what this scene did first — left Venus, the Earth and
        /// Mars in a huddle twenty pixels wide while one planet had the outer half of the screen to itself.
        var place: Double
        /// How wide to draw it, before the scene's own scale.
        var radius: Double
        var hue: Double
    }

    /// The eight planets, in order out from the Sun.
    static let solarPlanets: [Planet] = [
        Planet(name: "Mercury", distance: 0.39, place: 0.0957, radius: 2.1, hue: 32),
        Planet(name: "Venus", distance: 0.72, place: 0.1576, radius: 3.2, hue: 44),
        Planet(name: "Earth", distance: 1, place: 0.2015, radius: 3.4, hue: 205),
        Planet(name: "Mars", distance: 1.52, place: 0.2686, radius: 2.6, hue: 14),
        Planet(name: "Jupiter", distance: 5.2, place: 0.5306, radius: 8.4, hue: 28),
        Planet(name: "Saturn", distance: 9.58, place: 0.6858, radius: 7.2, hue: 48),
        Planet(name: "Uranus", distance: 19.2, place: 0.874, radius: 5, hue: 176),
        Planet(name: "Neptune", distance: 30.1, place: 1, radius: 4.8, hue: 224),
    ]

    /// Where the asteroid belt begins and ends, on the same scale: between Mars and Jupiter, as it is.
    static let solarBelt = (inner: 0.329, outer: 0.431)

    /// Builds the Sun, the planets, the Moon and the asteroid belt, flat or in the box.
    func layOutSolarSystem(centreX: Double, centreY: Double, inDepth: Bool) {
        let span = patternSpan
        let scale = sceneScale
        let sunMass = 150.0
        let nearest = span * 0.05
        let furthest = span * 0.46

        addParticle(
            x: centreX, y: centreY, velocityX: 0, velocityY: 0,
            radius: 13 * scale, mass: sunMass,
            color: PackedColor(hue: 46, saturation: 0.95, lightness: 0.66),
            isFixed: true, ignoresGravity: true, kind: .blackhole
        )

        /// A place on the squeezed scale, in the world's pixels. See `Planet.place`.
        func drawn(_ place: Double) -> Double {
            nearest + place * (furthest - nearest)
        }

        // ## Why there is no Moon
        //
        // It was tried, and it could not be made honest. Nothing here pulls except the Sun — that is what lets
        // every planet hold an exact circle — so for the Moon to go round the Earth, the Earth has to pull too.
        // Give it enough pull to keep a moon against the Sun, and the same pull wrecks Venus and Mars every
        // time they pass, because the distances here are squeezed and its neighbours come far closer than they
        // ever really do. Give it less, and the Sun simply takes the Moon away and leaves a ninth planet. A
        // moon that is quietly stolen within a few seconds is worse than no moon, so the scene is the Sun, the
        // planets and the belt.
        var named: [ParticleLabel] = [ParticleLabel("Sun", body: 0)]
        for planet in Self.solarPlanets {
            // Each planet's name follows the planet, because a label on Jupiter has to stay on Jupiter while it
            // goes round. The index is where this body is about to be added.
            named.append(ParticleLabel(planet.name, body: particles.count))
            let distance = drawn(planet.place)
            // Spread round the Sun rather than lined up, so the picture is not a single spoke.
            let angle = Double(planet.name.count) * 0.9 + planet.distance * 0.7
            let speed = orbitSpeed(pullMass: sunMass, atDistance: distance)
            let x = centreX + jsCos(angle) * distance
            let y = inDepth ? centreY : centreY + jsSin(angle) * distance
            let z = inDepth ? jsSin(angle) * distance : 0
            let vx = -jsSin(angle) * speed
            let alongY = inDepth ? 0 : jsCos(angle) * speed
            let alongZ = inDepth ? jsCos(angle) * speed : 0
            addParticle(
                x: x, y: y, velocityX: vx, velocityY: alongY,
                radius: planet.radius * scale,
                mass: 1,
                color: PackedColor(hue: planet.hue, saturation: 0.78, lightness: 0.6),
                ignoresGravity: true,
                z: z, velocityZ: alongZ
            )
        }

        labels = named

        // The asteroid belt, between Mars and Jupiter, in the crowd because there are thousands of them.
        //
        // Given the role that keeps its speed, as everything in orbit is. Without it the field's air friction
        // takes a hundredth of every asteroid's speed each moment, and the whole belt spirals into the Sun
        // inside a few seconds — which is not a belt, and not what the sky does.
        let beltInner = drawn(Self.solarBelt.inner)
        let beltOuter = drawn(Self.solarBelt.outer)
        let belt = min(1_800, patternRoom)
        for _ in 0 ..< belt {
            let distance = beltInner + rng.next() * (beltOuter - beltInner)
            let angle = rng.next() * Double.pi * 2
            let speed = orbitSpeed(pullMass: sunMass, atDistance: distance)
            let x = centreX + jsCos(angle) * distance
            let y = inDepth ? centreY + (rng.next() - 0.5) * span * 0.01 : centreY + jsSin(angle) * distance
            let z = inDepth ? jsSin(angle) * distance : 0
            let keepGoing: Bool
            if inDepth {
                keepGoing = placeInDepth(
                    x, y, z,
                    velocityX: -jsSin(angle) * speed,
                    velocityZ: jsCos(angle) * speed,
                    hue: 34, saturation: 0.25, lightness: 0.55,
                    role: .orbits
                )
            } else {
                keepGoing = placeLoose(
                    x, y,
                    velocityX: -jsSin(angle) * speed,
                    velocityY: jsCos(angle) * speed,
                    hue: 34, saturation: 0.25, lightness: 0.55,
                    role: .orbits
                )
            }
            if !keepGoing { break }
        }
    }

    // MARK: - Pendulum wave

    /// A row of weights on strings, each string a little longer than the last.
    ///
    /// Every weight is let go from the same side at the same moment. A longer string swings more slowly, so
    /// they immediately fall out of step — and because each is a fixed amount slower than its neighbour, the
    /// row passes through a snake, then two snakes, then a scatter, and eventually lines itself back up. None
    /// of that is animated: it is what a row of pendulums does.
    public func spawnPendulumWave(count requested: Int = 18) {
        if storedDepthEnabled { return spawnPendulumWaveInDepth(count: requested) }
        beginScene("pendulums", gravityY: 0.42)
        springs.removeAll(keepingCapacity: true)
        settleForSwinging()
        let total = max(4, min(requested, 22))
        let scale = sceneScale
        let shortest = layoutHeight * Self.shortestPendulum
        let longest = layoutHeight * Self.longestPendulum
        let top = layoutTop + layoutHeight * 0.1
        let lean = pendulumLean(longest: longest)

        for index in 0 ..< total {
            let share = total > 1 ? Double(index) / Double(total - 1) : 0
            let length = shortest + share * (longest - shortest)
            buildPendulum(
                atX: across(Self.pendulumRow.lowerBound + Self.pendulumRow.span * share),
                top: top, length: length, scale: scale, share: share, z: 0, lean: lean
            )
        }
    }

    /// How long the strings are, as shares of the screen's height.
    ///
    /// Short enough that a weight held out to a visible angle stays on the screen, which is what decides them:
    /// the first version used strings most of the screen tall, and the only lean that then fitted across was
    /// three degrees — a row of weights that barely moved and never made a pattern.
    static let shortestPendulum = 0.18
    static let longestPendulum = 0.34

    /// Where the pins sit across the screen. Kept off both edges, because every weight swings out past its pin
    /// on each side and has to stay in the world at the ends of its travel as well as at the start.
    static let pendulumRow = (lowerBound: 0.24, span: 0.5)

    /// Keeps the drag low enough for a swing to last.
    ///
    /// The field's usual drag takes a hundredth of the speed off every moment, which is right for a crowd and
    /// wrong for a pendulum: it halves a swing in about a second and stills the row inside four, so the pattern
    /// this scene exists to show would be over before it appeared. Set here rather than left to the default,
    /// and it stays where the scene put it so the slider can still change it afterwards.
    func settleForSwinging() {
        sceneSets(damping: 0.9995)
    }

    /// How far to one side every weight is held before the row is let go, as a share of its own string.
    ///
    /// One number for the whole row, worked out from the longest string. It has to be the same for every weight
    /// — that is what "they all start together" means, and it is the thing that makes the pattern appear — and
    /// it has to be small enough that the longest string does not hold its weight outside the world, where the
    /// wall would shove it back before the row had begun.
    func pendulumLean(longest: Double) -> Double {
        // A fifth of the screen's width is the room a weight has either side of the row before it would reach
        // the wall, which is what caps the lean on a tall, narrow screen.
        min(0.3, layoutWidth * 0.2 / max(1, longest))
    }

    /// One weight on a string: a pinned top and a single weight hanging from it, held out to one side.
    ///
    /// ## Why the string is one length and not a chain of links
    ///
    /// The first version hung each weight on a chain of four. That is a better-looking string and a worse
    /// pendulum, because the three nodes above the weight sit close to a pin that cannot move — so a finger put
    /// among them, which is where they crowd together, could barely shift anything, and the tools appeared not
    /// to work on this scene at all. With one length of string every body in the row is a weight, free to swing,
    /// and a finger can drag any of them out and let the row start again from wherever it is left.
    func buildPendulum(atX x: Double, top: Double, length: Double, scale: Double, share: Double, z: Double, lean: Double) {
        let links = 1
        let gap = length / Double(links)
        let start = particles.count
        for link in 0 ... links {
            let along = Double(link) * gap
            addParticle(
                x: x + along * lean,
                y: top + along * (1 - lean * lean * 0.5),
                velocityX: 0, velocityY: 0,
                radius: link == links ? 5 * scale : 1.6 * scale,
                mass: link == links ? 3 : 1,
                color: link == links
                    ? PackedColor(hue: 190 + share * 150, saturation: 0.82, lightness: 0.62)
                    : PackedColor(r: 0x9C, g: 0xA3, b: 0xAF),
                isFixed: link == 0,
                z: z
            )
        }
        for link in 0 ..< links {
            // Stiff, because a string is not a spring: a slack one turns the whole row into a bounce rather
            // than a swing, and the timing that makes the snake appear is lost.
            addSpring(a: start + link, b: start + link + 1, rest: gap, k: 0.8)
        }
    }

    // MARK: - Marbling

    /// A tray of liquid with bands of colour laid across it, for combing into marbled paper.
    ///
    /// The liquid is the field's own, so the colours do not mix into mud: each body keeps the colour it was
    /// given and simply goes where the liquid takes it. Dragging a finger across the bands pulls them into the
    /// feathered pattern that marbled endpapers are made of, and the pattern stays because the liquid holds
    /// its shape once the finger stops.
    public func spawnMarbling() {
        if storedDepthEnabled { return spawnMarblingInDepth() }
        beginScene("marbling", gravityY: 0.3)
        fluidEnabled = true
        // The flat liquid's own settings and its own spacing, exactly as the pool and the pour use them. Laid
        // out any denser than the liquid wants to be, or with bodies drawn wider than the gap between them,
        // the pressure between neighbours starts far too high and the tray bursts on the first moment.
        fluidSettings = .default
        let spacing = (1 / max(1e-6, fluidSettings.sanitized.restDensity)).squareRoot()
        let left = across(0.08)
        let right = across(0.92)
        let bottom = aboveFloor(0.96)
        let top = aboveFloor(0.56)
        let bands = 7.0
        var placed = 0
        let room = min(6_000, patternRoom)

        var y = bottom
        var row = 0
        while y > top, placed < room {
            // The same honeycomb the pool is laid out in: odd rows offset by half a gap, rows a triangle's
            // height apart. Square rows leave the liquid with lines of weakness along them.
            let offset = row.isMultiple(of: 2) ? 0 : spacing * 0.5
            var x = left + offset
            while x < right, placed < room {
                let share = (x - left) / max(1, right - left)
                // Bands across the tray, each its own colour, with a sharp edge between neighbours so a comb
                // drawn through has something to feather.
                let band = (share * bands).rounded(.down)
                if !placeLoose(
                    x + between(-spacing * 0.08, spacing * 0.08),
                    y + between(-spacing * 0.08, spacing * 0.08),
                    hue: 8 + band * 47,
                    saturation: 0.8,
                    lightness: 0.56
                ) { return }
                placed += 1
                x += spacing
            }
            y -= spacing * 0.866_025_403_784_438_6
            row += 1
        }
    }
}


extension ParticleEngine {
    // MARK: - Jellyfish

    /// A see-through bell that swims by squeezing itself, with tentacles trailing behind it.
    ///
    /// ## Why this is not an animation
    ///
    /// Nothing here is told where to go. The bell is a ring of bodies held together by muscles — springs whose
    /// length swells and shrinks — and the muscles across the inside of the bell are set a little behind the ones
    /// round its rim. Squeezing pushes the water the bell is sitting in out behind it, and the bell goes the
    /// other way. Take the muscles away and it is a jellyfish-shaped bag that sinks; set them pulsing and it
    /// swims, because that is what squeezing a bell in a liquid does.
    ///
    /// The tentacles are plain springs and are dragged along by whatever the bell does, which is why they trail
    /// and curl rather than being drawn curling.
    public func spawnJellyfish(count requested: Int = 3) {
        if storedDepthEnabled { return spawnJellyfishInDepth(count: requested) }
        // Weightless, because a jellyfish in water is: it neither sinks nor rises, and everything it does is its
        // own doing. Left with even a little gravity the bells simply sank to the floor, which took them five
        // hundred pixels down while their swimming was worth twenty — so what you saw was falling, not swimming.
        beginScene("jellyfish", gravityY: 0)
        springs.removeAll(keepingCapacity: true)
        // In no hurry, and the drag is what stops each squeeze adding to the last until the bell tears apart.
        sceneSets(damping: 0.96)
        let total = max(1, min(requested, 6))
        for index in 0 ..< total {
            let share = total > 1 ? Double(index) / Double(total - 1) : 0.5
            addJellyfish(
                centreX: across(0.24 + 0.52 * share),
                centreY: down(0.24 + 0.34 * (index % 2 == 0 ? share : 1 - share)),
                centreZ: 0,
                size: sceneScale * (13 + 4 * (index % 2 == 0 ? 1 : 0)),
                hue: 188 + Double(index) * 34
            )
        }
        // Something to swim through. The bell's squeeze has to push against water, and without any there is
        // nothing to push against and nothing to be pushed the other way.
        addJellyfishWater()
    }

    /// One bell and its tentacles.
    func addJellyfish(centreX: Double, centreY: Double, centreZ: Double, size: Double, hue: Double) {
        let rim = 14
        let radius = size * 1.6
        let start = particles.count

        // The rim of the bell, as a ring.
        for index in 0 ..< rim {
            let angle = Double(index) / Double(rim) * 6.283185307179586
            // Squashed, so it is a bell rather than a ball: wider than it is tall, and open underneath.
            addParticle(
                x: centreX + jsCos(angle) * radius,
                y: centreY + jsSin(angle) * radius * 0.62,
                velocityX: 0, velocityY: 0,
                radius: max(1.5, size * 0.18),
                mass: 1,
                color: PackedColor(hue: hue, saturation: 0.62, lightness: 0.66),
                z: centreZ + (storedDepthEnabled ? jsSin(angle) * radius * 0.2 : 0)
            )
        }

        // The rim itself, holding the ring together. Plain springs: the bell keeps its shape.
        let rimGap = radius * 6.283185307179586 / Double(rim)
        for index in 0 ..< rim {
            addSpring(a: start + index, b: start + (index + 1) % rim, rest: rimGap, k: 0.3)
        }

        // The muscles, across the inside of the bell from one side to the other. Each one set a little behind
        // the last, so the squeeze travels round rather than the whole bell clenching at once — which would
        // shake it on the spot instead of moving it.
        //
        // Every one of them pushes the same way, up and away from the mouth, while it is squeezing: that is the
        // water leaving the bell. See `Spring.thrust` for what that stands in for and what it leaves out.
        let across = rim / 2
        for index in 0 ..< across {
            let opposite = (index + across) % rim
            var muscle = Spring(
                a: start + index,
                b: start + opposite,
                rest: radius * 1.7,
                k: 0.22,
                pulse: 0.3,
                beat: 84,
                phase: Double(index) / Double(across) * 0.35
            )
            muscle.pushes(strength: 2.6, x: 0, y: -1)
            springs.append(muscle)
        }

        // Tentacles: strands of plain springs hanging from every other body on the rim, dragged along by the
        // bell. Nothing tells them to curl.
        let links = 7
        for index in stride(from: 0, to: rim, by: 3) {
            let angle = Double(index) / Double(rim) * 6.283185307179586
            // Only from the lower half, which is where a bell's tentacles hang from.
            guard jsSin(angle) > -0.2 else { continue }
            var previous = start + index
            let fromX = centreX + jsCos(angle) * radius
            let fromY = centreY + jsSin(angle) * radius * 0.62
            let gap = size * 0.5
            for link in 1 ... links {
                let made = addParticle(
                    x: fromX + jsCos(angle) * gap * 0.3 * Double(link),
                    y: fromY + gap * Double(link),
                    velocityX: 0, velocityY: 0,
                    radius: max(1, size * 0.09),
                    mass: 0.5,
                    color: PackedColor(hue: hue + 14, saturation: 0.5, lightness: 0.72),
                    z: centreZ
                )
                addSpring(a: previous, b: made, rest: gap, k: 0.22)
                previous = made
            }
        }
    }

    /// The water a jellyfish swims in: a loose crowd filling the tank, light enough to be pushed aside.
    func addJellyfishWater() {
        fluidEnabled = true
        fluidSettings = .default
        let spacing = (1 / max(1e-6, fluidSettings.sanitized.restDensity)).squareRoot() * 1.6
        let room = min(3_600, patternRoom)
        var placed = 0
        var y = down(0.08)
        while y < aboveFloor(0.98), placed < room {
            var x = across(0.05)
            while x < across(0.95), placed < room {
                if !placeLoose(
                    x + between(-spacing * 0.2, spacing * 0.2),
                    y + between(-spacing * 0.2, spacing * 0.2),
                    hue: 202 + between(-8, 8),
                    saturation: 0.42,
                    lightness: 0.34
                ) { return }
                placed += 1
                x += spacing
            }
            y += spacing
        }
    }
}
