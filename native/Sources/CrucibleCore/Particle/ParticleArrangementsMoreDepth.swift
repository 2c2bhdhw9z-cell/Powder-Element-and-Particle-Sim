/// The forms in depth of the arrangements in `ParticleArrangementsMore.swift`, plus the atom, which only
/// exists in depth.
///
/// The rule followed here is the one the rest of the field follows: a thing that was flat because the field was
/// becomes the thing it was a drawing of. Two colliding discs lie level in the box so the tails sweep through
/// it; the solar system becomes a level plane you can look down on; the row of pendulums runs away from you
/// into the box, so the snake travels into the distance rather than across the glass; the marbling tray becomes
/// a real tray, seen from above.
extension ParticleEngine {
    // MARK: - Galaxy crash

    func spawnGalaxyCrashInDepth(count requested: Int) {
        beginScene("crash", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }

        let span = patternSpan
        let coreMass = 58.0
        let apart = span * 0.3
        let centreX = width * 0.5
        let centreY = height * 0.5
        let closing = orbitSpeed(pullMass: coreMass, atDistance: apart) * 0.34
        // One core nearer the front of the box and one nearer the back, so the pass happens in depth and can be
        // seen for what it is when the view is turned.
        let reach = min(halfDepth * 0.5, span * 0.1)

        let cores: [(x: Double, y: Double, z: Double, vx: Double, vy: Double, hue: Double, tip: Double)] = [
            (centreX - apart * 0.5, centreY - span * 0.06, -reach, closing, 0, 206, 0.32),
            (centreX + apart * 0.5, centreY + span * 0.06, reach, -closing, 0, 344, -0.5),
        ]
        for core in cores {
            addParticle(
                x: core.x, y: core.y, velocityX: core.vx, velocityY: core.vy,
                radius: 11, mass: coreMass,
                color: PackedColor(hue: core.hue, saturation: 0.8, lightness: 0.62),
                isFixed: false, ignoresGravity: true, kind: .blackhole,
                z: core.z
            )
        }

        let inner = span * 0.035
        let disc = span * 0.14
        for index in 0 ..< total {
            let core = cores[index % 2]
            let distance = inner + rng.next() * disc
            let angle = rng.next() * Double.pi * 2
            let speed = orbitSpeed(pullMass: coreMass, atDistance: distance) * (0.95 + rng.next() * 0.1)
            // A disc lying level, then tipped — each galaxy at its own angle, which is what makes a crash look
            // like two separate things meeting rather than one shape folding.
            let flat = (x: jsCos(angle) * distance, y: (rng.next() - 0.5) * distance * 0.1, z: jsSin(angle) * distance)
            let spun = (x: -jsSin(angle) * speed, y: 0.0, z: jsCos(angle) * speed)
            let place = turnedInDepth(flat.x, flat.y, flat.z, yaw: 0, pitch: core.tip)
            let along = turnedInDepth(spun.x, spun.y, spun.z, yaw: 0, pitch: core.tip)
            let closeness = 1 - (distance - inner) / max(1, disc)
            if !placeInDepth(
                core.x + place.x,
                core.y + place.y,
                max(-halfDepth + 2, min(halfDepth - 2, core.z + place.z)),
                velocityX: along.x + core.vx,
                velocityY: along.y + core.vy,
                velocityZ: along.z,
                hue: core.hue + (rng.next() - 0.5) * 26,
                saturation: 0.7,
                lightness: 0.5 + closeness * 0.26,
                role: .orbits
            ) { break }
        }
    }

    // MARK: - The solar system

    func spawnSolarSystemInDepth() {
        beginScene("solar", gravityY: 0)
        layOutSolarSystem(centreX: width * 0.5, centreY: height * 0.5, inDepth: true)
    }

    // MARK: - Pendulum wave

    /// The row runs into the box rather than across the screen, so the snake travels away from the viewer.
    func spawnPendulumWaveInDepth(count requested: Int) {
        beginScene("pendulums", gravityY: 0.42)
        springs.removeAll(keepingCapacity: true)
        settleForSwinging()
        let total = max(4, min(requested, 22))
        let scale = sceneScale
        let shortest = layoutHeight * Self.shortestPendulum
        let longest = layoutHeight * Self.longestPendulum
        let top = layoutTop + layoutHeight * 0.1
        let reach = halfDepth * 0.78
        let lean = pendulumLean(longest: longest)

        for index in 0 ..< total {
            let share = total > 1 ? Double(index) / Double(total - 1) : 0
            let length = shortest + share * (longest - shortest)
            // A slight fan across as well as back, so the nearest weight does not hide every one behind it.
            let x = across(0.34 + 0.32 * share)
            let z = -reach + 2 * reach * share
            buildPendulum(atX: x, top: top, length: length, scale: scale, share: share, z: z, lean: lean)
        }
    }

    // MARK: - Marbling

    /// A real tray: a level sheet of liquid a little way down the box, best looked at from above.
    func spawnMarblingInDepth() {
        beginScene("marbling", gravityY: 0.3)
        fluidEnabled = true
        fluidSettings = Self.depthLiquid
        let spacing = 1 / Self.depthLiquid.sanitized.restDensity.squareRoot()
        let left = layoutLeft + layoutWidth * 0.1
        let right = layoutLeft + layoutWidth * 0.9
        let front = -halfDepth * 0.8
        let back = halfDepth * 0.8
        let surface = aboveFloor(0.55)
        let bands = 7.0

        var z = front
        while z < back {
            var x = left
            while x < right {
                let share = (x - left) / max(1, right - left)
                let band = (share * bands).rounded(.down)
                if !placeInDepth(
                    x + (rng.next() - 0.5) * spacing * 0.3,
                    surface + (rng.next() - 0.5) * spacing * 0.3,
                    z,
                    hue: 8 + band * 47,
                    saturation: 0.8,
                    lightness: 0.56,
                    size: depthLiquidBodySize
                ) { return }
                x += spacing
            }
            z += spacing
        }
    }

    // MARK: - The atom

    /// The shapes an electron is actually found in, drawn as clouds of bodies.
    ///
    /// Not the rings of the schoolbook diagram, which are wrong: an electron does not follow a path. What it has
    /// is a region it is likely to be in, and those regions have real shapes — a ball for the innermost, and
    /// three dumbbells at right angles to each other for the next. Each cloud is denser where the electron is
    /// more likely to be, which is what these are pictures of.
    ///
    /// The whole thing turns slowly about its upright, so every lobe comes round to be seen.
    public func spawnAtom(count requested: Int = 5_200) {
        beginScene("atom", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let centreX = width * 0.5
        let centreY = height * 0.5
        let radius = min(0.34 * patternSpan, halfDepth * 0.82)
        let spin = 0.0045

        // The nucleus: a tight knot of protons and neutrons, bright at the middle of everything.
        let nucleus = max(40, total / 26)
        for index in 0 ..< nucleus {
            let point = goldenPoint(index, of: nucleus)
            let pull = radius * 0.055 * jsPow(rng.next(), 1.0 / 3)
            if !placeTurningInDepth(
                centreX + point.x * pull,
                centreY + point.y * pull,
                point.z * pull,
                aboutX: centreX,
                spin: spin,
                hue: index % 2 == 0 ? 8 : 268,
                saturation: 0.75,
                lightness: 0.66
            ) { return }
        }

        // The innermost cloud: a ball, thickest a little way out from the middle rather than at it.
        let shell = (total - nucleus) / 4
        for index in 0 ..< shell {
            let point = goldenPoint(index, of: shell)
            // Two draws added together bunch the distance toward the middle of the range, which is the shape
            // this cloud actually has.
            let spread = (rng.next() + rng.next()) * 0.5
            let pull = radius * (0.2 + spread * 0.34)
            if !placeTurningInDepth(
                centreX + point.x * pull,
                centreY + point.y * pull,
                point.z * pull,
                aboutX: centreX,
                spin: spin,
                hue: 196,
                saturation: 0.7,
                lightness: 0.4 + (1 - spread) * 0.3
            ) { return }
        }

        // The clouds, named where each one sits, since none of them is a body to hang a name on.
        labels = [
            ParticleLabel("Nucleus", x: centreX, y: centreY - radius * 0.1, z: 0),
            ParticleLabel("Inner shell", x: centreX, y: centreY - radius * 0.62, z: 0),
            ParticleLabel("Lobes", x: centreX + radius * 0.8, y: centreY, z: 0),
        ]

        // Three dumbbells, one along each direction. A lobe is fat where it points and pinched at the middle,
        // which is what squaring the lean along its own direction gives.
        let lobe = (total - nucleus - shell) / 3
        let axes: [(x: Double, y: Double, z: Double, hue: Double)] = [
            (1, 0, 0, 44),
            (0, 1, 0, 318),
            (0, 0, 1, 142),
        ]
        for axis in axes {
            for index in 0 ..< lobe {
                let point = goldenPoint(index, of: lobe)
                let lean = point.x * axis.x + point.y * axis.y + point.z * axis.z
                // Thrown away rather than squashed inward: keeping every point and scaling it would fill the
                // pinch in the middle, and the pinch is the whole shape.
                let thickness = lean * lean
                if rng.next() > thickness { continue }
                let pull = radius * (0.34 + rng.next() * 0.6)
                if !placeTurningInDepth(
                    centreX + point.x * pull,
                    centreY + point.y * pull,
                    point.z * pull,
                    aboutX: centreX,
                    spin: spin,
                    hue: axis.hue,
                    saturation: 0.78,
                    lightness: 0.4 + thickness * 0.26
                ) { return }
            }
        }
    }
}


extension ParticleEngine {
    // MARK: - Jellyfish

    /// Bells swimming through the box, spread through its depth so they pass in front of and behind each other.
    func spawnJellyfishInDepth(count requested: Int) {
        beginScene("jellyfish", gravityY: 0)
        springs.removeAll(keepingCapacity: true)
        sceneSets(damping: 0.96)
        let total = max(1, min(requested, 6))
        for index in 0 ..< total {
            let share = total > 1 ? Double(index) / Double(total - 1) : 0.5
            addJellyfish(
                centreX: across(0.26 + 0.48 * share),
                centreY: down(0.24 + 0.34 * (index % 2 == 0 ? share : 1 - share)),
                centreZ: (share - 0.5) * halfDepth * 1.3,
                size: sceneScale * (13 + 4 * (index % 2 == 0 ? 1 : 0)),
                hue: 188 + Double(index) * 34
            )
        }
        addJellyfishWaterInDepth()
    }

    /// The water, filling the box rather than a sheet of it.
    func addJellyfishWaterInDepth() {
        fluidEnabled = true
        fluidSettings = Self.depthLiquid
        let spacing = (1 / max(1e-6, Self.depthLiquid.sanitized.restDensity)).squareRoot() * 1.5
        let room = min(9_000, patternRoom)
        var placed = 0
        var z = -halfDepth * 0.9
        while z < halfDepth * 0.9, placed < room {
            var y = down(0.08)
            while y < aboveFloor(0.98), placed < room {
                var x = across(0.06)
                while x < across(0.94), placed < room {
                    if !placeInDepth(
                        x + between(-spacing * 0.2, spacing * 0.2),
                        y + between(-spacing * 0.2, spacing * 0.2),
                        z + between(-spacing * 0.2, spacing * 0.2),
                        hue: 202 + between(-8, 8),
                        saturation: 0.42,
                        lightness: 0.34,
                        size: depthLiquidBodySize
                    ) { return }
                    placed += 1
                    x += spacing
                }
                y += spacing
            }
            z += spacing
        }
    }
}
