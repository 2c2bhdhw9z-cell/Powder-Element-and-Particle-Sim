/// Every arrangement's form in 3D, and the ones that only exist in 3D.
///
/// Each flat arrangement's builder hands over to its form here while the field is in 3D. They are built from
/// the same ideas and the same numbers wherever that makes sense — the same black hole, the same golden
/// angle, the same colours — and differ where depth changes what the thing is:
///
///   - **Things that orbit lie level.** A galaxy's disc, a black hole's, two wells', the pull-between-bodies
///     disc: all level in the box, the way a real disc is seen, so the view has to look down on them to see
///     their shape — which is why they ask to be seen from above.
///   - **Things that turn turn like a globe.** A shape turning in 3D goes round the upright line through its
///     middle, so it can be seen from every side, rather than spinning flat to the screen.
///   - **Things that were flat because the field was become what they were drawings of.** The triangle made of
///     triangles becomes the pyramid made of pyramids; the ring becomes a planet with a level ring round it;
///     a burst, a shockwave and a firework's shell become balls; the helix becomes two strands winding round
///     each other.
extension ParticleEngine {
    // MARK: - Placing in depth

    /// Puts one loose body into the crowd somewhere in the box, and says whether to keep going.
    @discardableResult
    func placeInDepth(
        _ x: Double,
        _ y: Double,
        _ z: Double,
        velocityX: Double = 0,
        velocityY: Double = 0,
        velocityZ: Double = 0,
        hue: Double,
        saturation: Double = 0.85,
        lightness: Double = 0.62,
        life: Double = -1,
        role: Swarm.Role = [],
        home: Swarm.Home? = nil,
        mass: Double = 1,
        size: Double = 0
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
            home: home,
            size: size,
            z: z,
            velocityZ: velocityZ
        )
    }

    /// Puts one body into the crowd holding a place in a shape that turns like a globe — round the upright line
    /// through `aboutX`, `aboutZ`. The body starts where it belongs, already moving as its place moves.
    @discardableResult
    func placeTurningInDepth(
        _ x: Double,
        _ y: Double,
        _ z: Double,
        aboutX: Double,
        aboutZ: Double = 0,
        spin: Double,
        stiffness: Double = Swarm.holdStiffness,
        hue: Double,
        saturation: Double = 0.85,
        lightness: Double = 0.62,
        life: Double = -1
    ) -> Bool {
        let dx = x - aboutX
        let dz = z - aboutZ
        let radius = (dx * dx + dz * dz).squareRoot()
        let angle = radius > 0 ? JS.atan2(dz, dx) : 0
        let home = Swarm.Home(
            anchorX: aboutX, anchorY: y, radius: radius, angle: angle, spin: spin,
            squash: 1, stiffness: stiffness, anchorZ: aboutZ
        )
        return placeInDepth(
            x, y, z,
            velocityX: -jsSin(angle) * radius * spin,
            velocityZ: jsCos(angle) * radius * spin,
            hue: hue, saturation: saturation, lightness: lightness, life: life,
            role: [.holds, .upright],
            home: home
        )
    }

    /// Puts one body into the crowd holding a place in a shape that faces the screen at a depth, turning about
    /// the line into the screen through `aboutX`, `aboutY` — as a flat shape turns, but somewhere in the box.
    @discardableResult
    func placeFacingInDepth(
        _ x: Double,
        _ y: Double,
        _ z: Double,
        aboutX: Double,
        aboutY: Double,
        spin: Double = 0,
        stiffness: Double = Swarm.holdStiffness,
        hue: Double,
        saturation: Double = 0.85,
        lightness: Double = 0.62
    ) -> Bool {
        let dx = x - aboutX
        let dy = y - aboutY
        let radius = (dx * dx + dy * dy).squareRoot()
        let angle = radius > 0 ? JS.atan2(dy, dx) : 0
        let home = Swarm.Home(
            anchorX: aboutX, anchorY: aboutY, radius: radius, angle: angle, spin: spin,
            squash: 1, stiffness: stiffness, anchorZ: z
        )
        return placeInDepth(
            x, y, z,
            velocityX: -jsSin(angle) * radius * spin,
            velocityY: jsCos(angle) * radius * spin,
            hue: hue, saturation: saturation, lightness: lightness,
            role: .holds,
            home: home
        )
    }

    /// A point turned by a turn about the upright and a tip about the sideways line, for laying something flat
    /// at an angle in the box.
    func turnedInDepth(_ x: Double, _ y: Double, _ z: Double, yaw: Double, pitch: Double) -> (x: Double, y: Double, z: Double) {
        let cy = jsCos(yaw), sy = jsSin(yaw)
        let cp = jsCos(pitch), sp = jsSin(pitch)
        let x1 = x * cy - z * sy
        let z1 = x * sy + z * cy
        return (x1, y * cp - z1 * sp, y * sp + z1 * cp)
    }

    /// Where the golden spiral puts the point at `index` of `total` on a ball of radius one. Even all over.
    func goldenPoint(_ index: Int, of total: Int) -> (x: Double, y: Double, z: Double) {
        let goldenAngle = 3.141592653589793 * (3 - 5.0.squareRoot())
        let rise = 1 - 2 * (Double(index) + 0.5) / Double(max(1, total))
        let across = max(0, 1 - rise * rise).squareRoot()
        let turn = Double(index) * goldenAngle
        return (jsCos(turn) * across, rise, jsSin(turn) * across)
    }

    // MARK: - Built round a centre and a force

    func spawnGalaxyInDepth(count: Int) {
        beginScene("galaxy", gravityY: 0)
        let centreX = width / 2
        let centreY = height / 2
        let holeMass = 80.0
        let pull = holeMass * 200
        addParticle(
            x: centreX, y: centreY, velocityX: 0, velocityY: 0, radius: 14, mass: holeMass,
            color: PackedColor(r: 0xF4, g: 0x3F, b: 0x5E), isFixed: true, ignoresGravity: true, kind: .blackhole
        )
        let outer = patternSpan * 0.42 + 30
        for _ in 0 ..< count {
            let distance = rng.next() * (patternSpan * 0.42) + 30
            let angle = rng.next() * Double.pi * 2
            let speed = (pull / distance).squareRoot() * (0.96 + rng.next() * 0.08)
            // Thicker toward the middle, as a real disc's bulge is.
            let thickness = (rng.next() - 0.5) * 0.06 * patternSpan * (1 - 0.7 * distance / outer)
            addParticle(
                x: centreX + jsCos(angle) * distance,
                y: centreY + thickness,
                velocityX: -jsSin(angle) * speed,
                velocityY: 0,
                radius: rng.next() * 2 + 1,
                color: PackedColor(hue: (distance * 2.8).truncatingRemainder(dividingBy: 360), saturation: 0.95, lightness: 0.70),
                ignoresGravity: true,
                originX: centreX,
                originY: centreY,
                z: jsSin(angle) * distance,
                velocityZ: jsCos(angle) * speed
            )
        }
    }

    func spawnBlackHoleInDepth(count: Int) {
        beginScene("blackhole", gravityY: 0)
        let centreX = width / 2
        let centreY = height / 2
        let holeMass = 100.0
        let pull = holeMass * 200
        addParticle(
            x: centreX, y: centreY, velocityX: 0, velocityY: 0, radius: 16, mass: holeMass,
            color: PackedColor(r: 0xF4, g: 0x3F, b: 0x5E), isFixed: true, ignoresGravity: true, kind: .blackhole
        )
        for _ in 0 ..< count {
            let distance = rng.next() * (patternSpan * 0.4) + 35
            let angle = rng.next() * Double.pi * 2
            let speed = (pull / distance).squareRoot() * (0.95 + rng.next() * 0.1)
            addParticle(
                x: centreX + jsCos(angle) * distance,
                y: centreY + (rng.next() - 0.5) * 0.02 * patternSpan,
                velocityX: -jsSin(angle) * speed,
                velocityY: 0,
                radius: rng.next() * 2.5 + 1,
                color: PackedColor(hue: (30 + distance * 2).truncatingRemainder(dividingBy: 360), saturation: 1, lightness: 0.65),
                ignoresGravity: true,
                originX: centreX,
                originY: centreY,
                z: jsSin(angle) * distance,
                velocityZ: jsCos(angle) * speed
            )
        }
    }

    func spawnDoubleVortexInDepth(count: Int) {
        beginScene("vortex", gravityY: 0)
        let leftX = across(0.35)
        let rightX = across(0.65)
        let centreY = height * 0.5
        let holeMass = 50.0
        let pull = holeMass * 200
        addParticle(
            x: leftX, y: centreY, velocityX: 0, velocityY: 0, radius: 12, mass: holeMass,
            color: PackedColor(r: 0x3B, g: 0x82, b: 0xF6), isFixed: true, ignoresGravity: true, kind: .blackhole
        )
        addParticle(
            x: rightX, y: centreY, velocityX: 0, velocityY: 0, radius: 12, mass: holeMass,
            color: PackedColor(r: 0xF9, g: 0x73, b: 0x16), isFixed: true, ignoresGravity: true, kind: .blackhole
        )
        // Each disc no wider than keeps it inside the box — the flat one's orbits reach past the side of the world,
        // and a level disc can reach past the front and back as well.
        let inner = 25 * sceneScale
        let widest = max(inner * 2, min(leftX - layoutLeft - 6, halfDepth * 0.9))
        for i in 0 ..< count {
            let isLeft = i % 2 == 0
            let originX = isLeft ? leftX : rightX
            let spin: Double = isLeft ? 1 : -1
            let baseHue: Double = isLeft ? 200 : 30
            let distance = inner + rng.next() * (widest - inner)
            let angle = rng.next() * Double.pi * 2
            let speed = (pull / distance).squareRoot() * (0.92 + rng.next() * 0.16)
            addParticle(
                x: originX + jsCos(angle) * distance,
                y: centreY + (rng.next() - 0.5) * 6,
                velocityX: -jsSin(angle) * speed * spin,
                velocityY: 0,
                radius: 2.5,
                color: PackedColor(hue: baseHue + rng.next() * 30, saturation: 0.95, lightness: 0.65),
                ignoresGravity: true,
                originX: originX,
                originY: centreY,
                z: jsSin(angle) * distance,
                velocityZ: jsCos(angle) * speed * spin
            )
        }
    }

    func spawnSynchrotronInDepth(count: Int) {
        beginScene("synchrotron", gravityY: 0)
        let centreX = width / 2
        let centreY = height / 2
        let holeMass = 60.0
        let pull = holeMass * 200
        addParticle(
            x: centreX - 130 * sceneScale, y: centreY, velocityX: 0, velocityY: 0, radius: 12, mass: holeMass,
            color: PackedColor(r: 0xEC, g: 0x48, b: 0x99), isFixed: true, ignoresGravity: true, kind: .blackhole
        )
        addParticle(
            x: centreX + 130 * sceneScale, y: centreY, velocityX: 0, velocityY: 0, radius: 12, mass: holeMass,
            color: PackedColor(r: 0x3B, g: 0x82, b: 0xF6), isFixed: true, ignoresGravity: true, kind: .blackhole
        )
        // The flat orbits' widths, shrunk if need be to fit inside the box.
        let fit = min(1, min(layoutWidth * 0.48, halfDepth * 0.9) / (210 * sceneScale))
        for i in 0 ..< count {
            let angle = rng.next() * Double.pi * 2
            let distance = (rng.next() * 180 + 30) * sceneScale * fit
            let speed = (pull / distance).squareRoot() * (0.95 + rng.next() * 0.1)
            addParticle(
                x: centreX + jsCos(angle) * distance,
                y: centreY + (rng.next() - 0.5) * 6,
                velocityX: -jsSin(angle) * speed,
                velocityY: 0,
                radius: 2,
                color: PackedColor(hue: Double(i * 7).truncatingRemainder(dividingBy: 360), saturation: 0.95, lightness: 0.70),
                ignoresGravity: true,
                originX: centreX,
                originY: centreY,
                z: jsSin(angle) * distance,
                velocityZ: jsCos(angle) * speed
            )
        }
    }

    func spawnSolarFlareInDepth(count: Int) {
        beginScene("flare", gravityY: 0)
        let centreX = width / 2
        let centreY = height / 2
        addParticle(
            x: centreX, y: centreY, velocityX: 0, velocityY: 0, radius: 18, mass: 50,
            color: PackedColor(r: 0xF9, g: 0x73, b: 0x16), isFixed: true, ignoresGravity: true, kind: .glow
        )
        for _ in 0 ..< count {
            let direction = randomDirection()
            let speed = 2 + rng.next() * 8
            let hue = 15 + rng.next() * 45
            let maxLife = 150 + Int((rng.next() * 200).rounded(.down))
            let lifespan = Int((rng.next() * Double(maxLife)).rounded(.down))
            let radius = rng.next() * 3 + 1.5
            addParticle(
                x: centreX + direction.x * 20,
                y: centreY + direction.y * 20,
                velocityX: direction.x * speed + (rng.next() - 0.5),
                velocityY: direction.y * speed + (rng.next() - 0.5),
                radius: radius,
                color: PackedColor(hue: hue, saturation: 1, lightness: 0.60),
                lifespan: lifespan,
                maxLife: maxLife,
                ignoresGravity: true,
                originX: centreX,
                originY: centreY,
                z: direction.z * 20,
                velocityZ: direction.z * speed + (rng.next() - 0.5)
            )
        }
    }

    func spawnShockwaveInDepth(count: Int) {
        beginScene("shockwave", gravityY: 0)
        let centreX = width / 2
        let centreY = height / 2
        for i in 0 ..< count {
            let direction = goldenPoint(i, of: count)
            let speed = 7 + rng.next() * 3
            addParticle(
                x: centreX + direction.x * 12,
                y: centreY + direction.y * 12,
                velocityX: direction.x * speed,
                velocityY: direction.y * speed,
                radius: 3,
                color: PackedColor(hue: (Double(i) / Double(count) * 360).truncatingRemainder(dividingBy: 360), saturation: 1, lightness: 0.65),
                ignoresGravity: true,
                z: direction.z * 12,
                velocityZ: direction.z * speed
            )
        }
    }

    func spawnCosmicFountainInDepth(count: Int) {
        beginScene("fountain", gravityY: 0.3)
        let centreX = width / 2
        let floorY = height - 20
        for i in 0 ..< count {
            let lean = (rng.next() - 0.5) * 0.7
            let turn = rng.next() * Double.pi * 2
            let speed = rng.next() * 9 + 5
            let maxLife = 120 + Int((rng.next() * 150).rounded(.down))
            let lifespan = Int((rng.next() * Double(maxLife)).rounded(.down))
            addParticle(
                x: centreX + (rng.next() - 0.5) * 30,
                y: floorY - rng.next() * (layoutHeight * 0.6),
                velocityX: jsCos(turn) * jsSin(lean) * speed,
                velocityY: -jsCos(lean) * speed,
                radius: rng.next() * 2.5 + 1.5,
                color: PackedColor(hue: Double(i * 12).truncatingRemainder(dividingBy: 360), saturation: 1, lightness: 0.65),
                lifespan: lifespan,
                maxLife: maxLife,
                originX: centreX,
                originY: floorY,
                z: (rng.next() - 0.5) * 30,
                velocityZ: jsSin(turn) * jsSin(lean) * speed
            )
        }
    }

    func spawnWaterfallInDepth(count: Int) {
        beginScene("waterfall", gravityY: 0.4)
        let startX = across(0.3)
        let spread = layoutWidth * 0.4
        for _ in 0 ..< count {
            let dropX = startX + rng.next() * spread
            let dropY = rng.next() * (layoutHeight * 0.9) + 10
            addParticle(
                x: dropX,
                y: dropY,
                velocityX: (rng.next() - 0.5) * 1.5,
                velocityY: rng.next() * 4 + 2,
                radius: rng.next() * 2.5 + 2,
                color: PackedColor(r: 0x38, g: 0xBD, b: 0xF8),
                originX: startX,
                originY: 20,
                z: (rng.next() - 0.5) * patternSpan * 0.4,
                velocityZ: (rng.next() - 0.5) * 1.5
            )
        }
    }

    // MARK: - Liquids

    /// How the liquid is set up in 3D.
    ///
    /// Coarser than flat. A liquid in depth needs bodies in three directions to have any thickness at all, and
    /// the number a phone can run as a liquid each moment is in the thousands — laid out at the flat liquid's
    /// spacing, that would be a film a body thick across the bottom of the box. So the bodies sit further
    /// apart, and each is drawn about as wide as the gap, so the liquid reads as a body of liquid rather than
    /// as a scatter of dots.
    static let depthLiquid = SwarmFluid.Settings(smoothing: 30, restDensity: 1.0 / 225)
    /// How wide each body of liquid in depth is drawn.
    var depthLiquidBodySize: Double { 13 }

    func spawnPourInDepth(count: Int) {
        beginScene("pour", gravityY: 0.38)
        fluidEnabled = true
        fluidSettings = Self.depthLiquid
        let centreX = width * 0.5
        let column = patternSpan * 0.05
        for _ in 0 ..< count {
            let turn = rng.next() * Double.pi * 2
            let out = rng.next().squareRoot() * column
            guard placeInDepth(
                centreX + jsCos(turn) * out,
                aboveFloor(between(0.04, 0.4)),
                jsSin(turn) * out,
                velocityX: between(-0.2, 0.2),
                velocityY: between(1, 3),
                hue: between(198, 222),
                saturation: 0.78,
                lightness: 0.6,
                life: between(900, 1_500),
                size: depthLiquidBodySize
            ) else { break }
        }
        emitterTemplate = ParticleEmitter(
            atFractionX: 0.5, atFractionY: 0.03, direction: 1.5707963267948966, rate: 200, spread: 0.1,
            speed: 3.2, speedVariation: 0.2, lifespan: 1_500, weight: 1, weightVariation: 0, hue: 206
        )
        addEmitter(atX: width * 0.5, y: aboveFloor(0.03))
    }

    func spawnWaterPoolInDepth(count requested: Int) {
        beginScene("water", gravityY: 0.35)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        fluidEnabled = true
        fluidSettings = Self.depthLiquid
        let spacing = 1 / Self.depthLiquid.sanitized.restDensity.squareRoot()
        let poolBudget = Int(Double(total) * 0.8)
        let left = across(0.08)
        let right = across(0.92)
        let back = halfDepth * 0.85
        var placed = 0
        var y = height - spacing * 0.5
        var layer = 0
        while placed < poolBudget, y > height * 0.2 {
            let offset = layer.isMultiple(of: 2) ? 0 : spacing * 0.5
            var z = -back + offset
            while z < back, placed < poolBudget {
                var x = left + offset
                while x < right, placed < poolBudget {
                    guard placeInDepth(
                        x + between(-0.08, 0.08) * spacing,
                        y + between(-0.08, 0.08) * spacing,
                        z + between(-0.08, 0.08) * spacing,
                        hue: 198 + between(-6, 6),
                        saturation: 0.72,
                        lightness: 0.55,
                        size: depthLiquidBodySize
                    ) else { return }
                    placed += 1
                    x += spacing
                }
                z += spacing
            }
            y -= spacing * 0.82
            layer += 1
        }
        emitterTemplate = ParticleEmitter(
            atFractionX: 0.5, atFractionY: 0.06, direction: 1.5707963267948966, rate: 160, spread: 0.14,
            speed: 2.4, speedVariation: 0.25, lifespan: 1_200, weight: 1, weightVariation: 0, hue: 196
        )
        addEmitter(atX: width * 0.5, y: aboveFloor(0.06))
    }

    // MARK: - Built from individual bodies

    func spawnQuantumLatticeInDepth() {
        beginScene("lattice", gravityY: 0)
        let columns = 9
        let rows = 7
        let layers = 7
        let step = patternSpan * 0.075
        let startX = width * 0.5 - Double(columns - 1) * step * 0.5
        let startY = height * 0.5 - Double(rows - 1) * step * 0.5
        let startZ = -Double(layers - 1) * step * 0.5
        for layer in 0 ..< layers {
            for row in 0 ..< rows {
                for column in 0 ..< columns {
                    let isPositive = (row + column + layer) % 2 == 0
                    let nodeX = startX + Double(column) * step
                    let nodeY = startY + Double(row) * step
                    let nodeZ = startZ + Double(layer) * step
                    addParticle(
                        x: nodeX,
                        y: nodeY,
                        velocityX: (rng.next() - 0.5) * 0.2,
                        velocityY: (rng.next() - 0.5) * 0.2,
                        radius: 3,
                        mass: 2,
                        charge: isPositive ? 1 : -1,
                        color: isPositive ? PackedColor(r: 0x38, g: 0xBD, b: 0xF8) : PackedColor(r: 0xF4, g: 0x3F, b: 0x5E),
                        ignoresGravity: true,
                        originX: nodeX,
                        originY: nodeY,
                        latticeBound: true,
                        z: nodeZ,
                        velocityZ: (rng.next() - 0.5) * 0.2,
                        originZ: nodeZ
                    )
                }
            }
        }
    }

    func spawnDnaHelixInDepth(count: Int) {
        beginScene("helix", gravityY: 0)
        guard count > 0 else { return }
        let startX = across(0.1)
        let endX = across(0.9)
        let centreY = height / 2
        let scale = sceneScale
        let wavelength = 120.0 * scale
        for i in 0 ..< count {
            let progress = Double(i) / Double(count)
            let pointX = startX + progress * (endX - startX)
            let angle = (pointX / wavelength) * Double.pi * 2
            for strand in [scale, -scale] {
                addParticle(
                    x: pointX,
                    y: centreY + jsSin(angle) * 50 * strand,
                    velocityX: 1.2,
                    velocityY: 0,
                    radius: 2.5,
                    charge: strand > 0 ? 1 : -1,
                    color: strand > 0 ? PackedColor(r: 0x06, g: 0xB6, b: 0xD4) : PackedColor(r: 0xA8, g: 0x55, b: 0xF7),
                    ignoresGravity: true,
                    originX: startX,
                    originY: centreY,
                    helixStrand: strand,
                    z: jsCos(angle) * 50 * strand
                )
            }
        }
    }

    func spawnFlockInDepth(count: Int) {
        beginScene("flock", gravityY: 0)
        flockEnabled = true
        for _ in 0 ..< count {
            let x = across(rng.next())
            let y = down(rng.next())
            let z = (rng.next() * 2 - 1) * halfDepth * 0.8
            let hue = 140 + rng.next() * 50
            addParticle(
                x: x,
                y: y,
                velocityX: (rng.next() - 0.5) * 3,
                velocityY: (rng.next() - 0.5) * 3,
                radius: 2.2,
                color: PackedColor(hue: hue, saturation: 0.80, lightness: 0.62),
                z: z,
                velocityZ: (rng.next() - 0.5) * 3
            )
        }
    }

    func spawnNbodyInDepth(count: Int) {
        beginScene("nbody", gravityY: 0)
        nbodyEnabled = true
        let budget = maxParticles - particles.count
        let strength = bodyGravitySettings.sanitized.strength
        let centreX = width * 0.5
        let centreY = height * 0.5
        let outer = 0.36 * patternSpan
        let coreMass = 260.0
        guard swarm.append(
            x: centreX, y: centreY, velocityX: 0, velocityY: 0,
            color: PackedColor(hue: 38, saturation: 1, lightness: 0.8).packedRGBA,
            budget: budget, mass: coreMass, role: .orbits
        ) else { return }
        var weights: [Double] = []
        weights.reserveCapacity(count)
        for _ in 0 ..< count {
            let roll = rng.next()
            weights.append(roll < 0.03 ? 8 : roll < 0.15 ? 3 : between(0.6, 1.4))
        }
        let totalWeight = weights.reduce(0, +)
        for index in 0 ..< count {
            let share = rng.next()
            let radius = 30 + share.squareRoot() * outer
            let angle = rng.next() * Double.pi * 2
            let inside = coreMass + totalWeight * share
            let speed = (strength * inside / radius).squareRoot() * between(0.97, 1.03)
            let weight = weights[index]
            let hue = weight >= 8 ? 20.0 : weight >= 3 ? 48.0 : between(195, 250)
            guard placeInDepth(
                centreX + jsCos(angle) * radius,
                centreY + between(-0.01, 0.01) * patternSpan,
                jsSin(angle) * radius,
                velocityX: -jsSin(angle) * speed,
                velocityZ: jsCos(angle) * speed,
                hue: hue,
                saturation: 0.85,
                lightness: weight >= 3 ? 0.66 : 0.62,
                role: .orbits,
                mass: weight
            ) else { return }
        }
    }

    // MARK: - Built things

    func spawnClothInDepth(cols: Int, rows: Int) {
        beginScene("cloth", gravityY: 0.35)
        springs.removeAll(keepingCapacity: true)
        addClothInDepth(cols: cols, rows: rows, centreX: width / 2, top: 36 * sceneScale)
    }

    /// A sheet held level along its far edge, so it falls and swings down through the box.
    func addClothInDepth(cols: Int, rows: Int, centreX: Double, top: Double) {
        guard cols > 0, rows > 0 else { return }
        let scale = sceneScale
        let gap = min(18 * scale, (layoutWidth / Double(cols + 2)).rounded(.down))
        let originX = centreX - Double(cols) * gap / 2
        let backZ = min(halfDepth * 0.9, Double(rows) * gap * 0.5)
        let start = particles.count
        for row in 0 ..< rows {
            for column in 0 ..< cols {
                addParticle(
                    x: originX + Double(column) * gap,
                    y: top,
                    velocityX: 0,
                    velocityY: 0,
                    radius: 2.4 * scale,
                    color: PackedColor(hue: 200 + Double(column) * 4, saturation: 0.70, lightness: 0.70),
                    isFixed: row == 0 && (column == 0 || column == cols - 1 || column % 4 == 0),
                    z: backZ - Double(row) * gap
                )
            }
        }
        func index(_ column: Int, _ row: Int) -> Int { start + row * cols + column }
        for row in 0 ..< rows {
            for column in 0 ..< cols {
                if column + 1 < cols { addSpring(a: index(column, row), b: index(column + 1, row), rest: gap, k: 0.18) }
                if row + 1 < rows { addSpring(a: index(column, row), b: index(column, row + 1), rest: gap, k: 0.18) }
            }
        }
    }

    func spawnRopeInDepth(length: Int) {
        beginScene("rope", gravityY: 0.4)
        springs.removeAll(keepingCapacity: true)
        addRopeInDepth(length: length, atX: width / 2)
    }

    /// A rope held out from its pin toward the viewer and a little to one side, so it swings down through the
    /// box rather than hanging still.
    func addRopeInDepth(length: Int, atX centreX: Double) {
        guard length > 0 else { return }
        let scale = sceneScale
        let gap = 10.0 * scale
        let start = particles.count
        let backZ = min(halfDepth * 0.8, Double(length) * gap * 0.4)
        for i in 0 ..< length {
            addParticle(
                x: centreX + Double(i) * gap * 0.25,
                y: 24 * scale,
                velocityX: 0,
                velocityY: 0,
                radius: 2.6 * scale,
                color: PackedColor(r: 0xE7, g: 0xE5, b: 0xE4),
                isFixed: i == 0,
                z: backZ - Double(i) * gap * 0.95
            )
        }
        for i in 0 ..< (length - 1) {
            addSpring(a: start + i, b: start + i + 1, rest: gap, k: 0.28)
        }
    }

    func spawnBlobInDepth() {
        beginScene("blob", gravityY: 0.22)
        springs.removeAll(keepingCapacity: true)
        addBlobInDepth(nodes: 42, centreX: width / 2, centreY: down(0.4), centreZ: 0)
    }

    /// A round soft ball: nodes spread evenly over a ball, each sprung to its nearest few and, much more slackly,
    /// to the one on the far side, so it squashes when it lands rather than folding flat.
    func addBlobInDepth(nodes: Int, centreX: Double, centreY: Double, centreZ: Double) {
        guard nodes > 3 else { return }
        let radius = 42.0 * sceneScale
        let start = particles.count
        var points: [(x: Double, y: Double, z: Double)] = []
        for i in 0 ..< nodes {
            let p = goldenPoint(i, of: nodes)
            points.append((centreX + p.x * radius, centreY + p.y * radius, centreZ + p.z * radius))
            addParticle(
                x: points[i].x,
                y: points[i].y,
                velocityX: 0,
                velocityY: 0,
                radius: 3 * sceneScale,
                color: PackedColor(hue: 320 + Double(i) * 1.5, saturation: 0.80, lightness: 0.68),
                z: points[i].z
            )
        }
        var joined = Set<Int>()
        for i in 0 ..< nodes {
            var nearest: [(index: Int, distance: Double)] = []
            for j in 0 ..< nodes where j != i {
                let dx = points[j].x - points[i].x
                let dy = points[j].y - points[i].y
                let dz = points[j].z - points[i].z
                nearest.append((j, (dx * dx + dy * dy + dz * dz).squareRoot()))
            }
            nearest.sort { $0.distance < $1.distance }
            for neighbour in nearest.prefix(4) {
                let key = min(i, neighbour.index) * nodes + max(i, neighbour.index)
                guard !joined.contains(key) else { continue }
                joined.insert(key)
                addSpring(a: start + i, b: start + neighbour.index, rest: neighbour.distance, k: 0.22)
            }
            if let far = nearest.last {
                let key = min(i, far.index) * nodes + max(i, far.index)
                if !joined.contains(key) {
                    joined.insert(key)
                    addSpring(a: start + i, b: start + far.index, rest: far.distance, k: 0.05)
                }
            }
        }
    }

    func spawnMoleculesInDepth(count: Int) {
        beginScene("molecules", gravityY: 0)
        addMoleculesInDepth(count: count, laidOut: true)
    }

    /// Molecules laid at every angle through the box. The same shapes as flat — benzene rings, water, a chain —
    /// built flat and then turned, since a ring of six is flat in real life too.
    func addMoleculesInDepth(count requested: Int, laidOut: Bool) {
        let span = patternSpan
        let ringSize = 0.055 * span
        let waterSize = 0.04 * span
        var budget = min(requested, max(0, maxParticles - particles.count - swarm.count))
        guard budget > 0 else { return }
        let carbon = PackedColor(r: 0x3F, g: 0x4A, b: 0x5A)
        let hydrogen = PackedColor(r: 0xE8, g: 0xEE, b: 0xF6)
        let oxygen = PackedColor(r: 0xE0, g: 0x4F, b: 0x4F)

        /// One molecule's atoms, laid out flat and then turned to a random angle about its middle.
        struct Layout {
            var yaw: Double
            var pitch: Double
            var centre: (x: Double, y: Double, z: Double)
        }
        func atom(_ layout: Layout, _ lx: Double, _ ly: Double, radius: Double, mass: Double, color: PackedColor) -> Int? {
            guard budget > 0 else { return nil }
            budget -= 1
            let turned = turnedInDepth(lx, ly, 0, yaw: layout.yaw, pitch: layout.pitch)
            return addParticle(
                x: layout.centre.x + turned.x,
                y: layout.centre.y + turned.y,
                velocityX: between(-0.2, 0.2),
                velocityY: between(-0.2, 0.2),
                radius: radius, mass: mass, charge: 0, color: color,
                z: layout.centre.z + turned.z,
                velocityZ: between(-0.2, 0.2)
            )
        }
        func bond(_ a: Int?, _ b: Int?, rest: Double, stiffness: Double) {
            guard let a, let b else { return }
            springs.append(Spring(a: a, b: b, rest: rest, k: stiffness))
        }
        func layout(_ x: Double, _ y: Double, _ z: Double) -> Layout {
            Layout(yaw: between(0, 6.283185307179586), pitch: between(-1.2, 1.2), centre: (x, y, z))
        }
        func benzene(_ at: Layout, size: Double) {
            var ring: [Int?] = []
            for step in 0 ..< 6 {
                let angle = Double(step) / 6 * 6.283185307179586 - 1.5707963267948966
                ring.append(atom(at, jsCos(angle) * size, jsSin(angle) * size, radius: 3.2, mass: 1.6, color: carbon))
            }
            for step in 0 ..< 6 {
                bond(ring[step], ring[(step + 1) % 6], rest: size, stiffness: 0.62)
                let angle = Double(step) / 6 * 6.283185307179586 - 1.5707963267948966
                let attached = atom(at, jsCos(angle) * size * 1.55, jsSin(angle) * size * 1.55, radius: 2, mass: 0.45, color: hydrogen)
                bond(ring[step], attached, rest: size * 0.55, stiffness: 0.5)
            }
        }
        func water(_ at: Layout, size: Double) {
            let centre = atom(at, 0, 0, radius: 3.6, mass: 1.8, color: oxygen)
            let half = 1.8238691004641712 / 2
            for side in [-1.0, 1.0] {
                let angle = -1.5707963267948966 + side * half
                let attached = atom(at, jsCos(angle) * size, jsSin(angle) * size, radius: 2, mass: 0.4, color: hydrogen)
                bond(centre, attached, rest: size, stiffness: 0.7)
            }
        }
        func chain(_ at: Layout, length: Int, size: Double) {
            var previous: Int?
            for step in 0 ..< length {
                let offset = step.isMultiple(of: 2) ? 0.0 : 0.35 * size
                let here = atom(
                    at, (Double(step) - Double(length) * 0.5) * size, offset,
                    radius: 3, mass: step.isMultiple(of: 3) ? 1.5 : 1, color: carbon
                )
                bond(previous, here, rest: size * 1.0595, stiffness: 0.55)
                previous = here
            }
        }
        let depthSpread = halfDepth * 0.55
        if laidOut {
            let ringSites: [(Double, Double, Double)] = [
                (0.22, 0.32, -0.6), (0.5, 0.28, 0.4), (0.78, 0.34, -0.2), (0.3, 0.68, 0.7), (0.7, 0.7, -0.5),
            ]
            let waterSites: [(Double, Double, Double)] = [
                (0.18, 0.52, 0.3), (0.86, 0.55, -0.7), (0.42, 0.82, 0.1), (0.62, 0.18, 0.8),
            ]
            for site in ringSites where budget > 12 {
                benzene(layout(across(site.0), down(site.1), site.2 * depthSpread), size: ringSize)
            }
            if budget > 12 {
                chain(layout(width * 0.5, down(0.55), 0), length: 9, size: 0.032 * span)
            }
            for site in waterSites where budget > 3 {
                water(layout(across(site.0), down(site.1), site.2 * depthSpread), size: waterSize)
            }
        }
        var guardCount = 0
        while budget > 12, guardCount < 400 {
            guardCount += 1
            let at = layout(across(between(0.1, 0.9)), down(between(0.1, 0.9)), between(-1, 1) * depthSpread)
            if rng.next() < 0.55 {
                benzene(at, size: ringSize * between(0.7, 1.05))
            } else {
                water(at, size: waterSize * between(0.8, 1.2))
            }
        }
    }

    // MARK: - Built round a shape

    func spawnSunflowerInDepth(count requested: Int) {
        beginScene("sunflower", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let goldenAngle = 3.141592653589793 * (3 - 5.0.squareRoot())
        let outer = 0.44 * patternSpan
        let centreX = width * 0.5
        let centreY = height * 0.5
        let phase = between(0, 6.283185307179586)
        // A seed head is a shallow dome: the middle stands out toward the viewer and the rim falls away.
        let dome = 0.22 * outer
        for index in 0 ..< total {
            let through = Double(index) / Double(max(1, total - 1))
            let radius = through.squareRoot() * outer
            let angle = Double(index) * goldenAngle + phase
            let fall = radius / outer
            guard placeFacingInDepth(
                centreX + jsCos(angle) * radius,
                centreY + jsSin(angle) * radius,
                -dome * (1 - fall * fall),
                aboutX: centreX,
                aboutY: centreY,
                spin: 0.0016,
                hue: (through * 300 + angle * 18).truncatingRemainder(dividingBy: 360),
                saturation: 0.8,
                lightness: 0.6
            ) else { return }
        }
    }

    func spawnMandalaInDepth(count requested: Int) {
        beginScene("mandala", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let outer = 0.42 * patternSpan
        let centreX = width * 0.5
        let centreY = height * 0.5
        let phase = between(0, 0.7853981633974483)
        let spin = 0.0012
        func put(radius: Double, angle: Double, z: Double, hue: Double, lightness: Double = 0.62) -> Bool {
            placeFacingInDepth(
                centreX + jsCos(angle + phase) * radius,
                centreY + jsSin(angle + phase) * radius,
                z,
                aboutX: centreX,
                aboutY: centreY,
                spin: spin,
                hue: hue,
                saturation: 0.82,
                lightness: lightness
            )
        }
        // The petals curve back like a bowl, the rings stand in front of them one behind another, the spikes are
        // furthest back and the hub is nearest.
        let petalBudget = Int(Double(total) * 0.55)
        for index in 0 ..< petalBudget {
            let angle = Double(index) / Double(max(1, petalBudget)) * 6.283185307179586
            let rose = abs(jsCos(4 * angle))
            let reach = outer * (0.22 + 0.78 * jsPow(rose, 0.55))
            let steps = 5 + index % 3
            for step in 2 ... steps {
                let radius = reach * Double(step) / Double(steps)
                let bowl = 0.35 * radius * radius / outer
                guard put(radius: radius, angle: angle, z: bowl, hue: rose * 250 + 36) else { return }
            }
        }
        for ring in 0 ..< 3 {
            let radius = outer * (0.18 + 0.14 * Double(ring))
            let along = 8 * (6 + 4 * ring)
            for step in 0 ..< along {
                let angle = Double(step) / Double(along) * 6.283185307179586 + 0.08 * Double(ring)
                guard put(radius: radius, angle: angle, z: -outer * (0.06 + 0.05 * Double(ring)), hue: 54 + 43 * Double(ring), lightness: 0.7) else { return }
            }
        }
        for spike in 0 ..< 8 {
            let out = Double(spike) * 0.7853981633974483 - 1.5707963267948966
            let back = out + 0.39269908169872414
            let near = 0.12 * outer
            let far = 0.95 * outer
            for step in 0 ... 18 {
                let through = Double(step) / 18
                let goingOut = through < 0.5
                let radius = goingOut ? near + (far - near) * through * 2 : far + (near - far) * (through * 2 - 1)
                guard put(radius: radius, angle: goingOut ? out : back, z: outer * 0.32, hue: 306, lightness: 0.72) else { return }
            }
        }
        let step = outer * 0.018
        for across in -8 ... 8 {
            for down in -8 ... 8 where abs(across) + abs(down) <= 8 {
                guard placeFacingInDepth(
                    centreX + Double(across) * step,
                    centreY + Double(down) * step,
                    -outer * 0.24,
                    aboutX: centreX,
                    aboutY: centreY,
                    spin: spin,
                    hue: 18,
                    saturation: 0.7,
                    lightness: 0.78
                ) else { return }
            }
        }
    }

    func spawnSnowflakesInDepth(count requested: Int) {
        beginScene("snowflakes", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        var placed = 0
        let span = patternSpan
        func hexCore(_ cx: Double, _ cy: Double, _ cz: Double, radius: Double, hue: Double, spin: Double) -> Bool {
            let rings = max(2, Int((radius / (0.012 * span)).rounded()))
            var furthest = 1e-6
            for q in -rings ... rings {
                for r in -rings ... rings where abs(-q - r) <= rings {
                    let px = 1.5 * Double(q)
                    let py = 1.7320508075688772 * (Double(r) + Double(q) / 2)
                    furthest = max(furthest, (px * px + py * py).squareRoot())
                }
            }
            let scale = radius / furthest
            for q in -rings ... rings {
                for r in -rings ... rings where abs(-q - r) <= rings {
                    let px = 1.5 * Double(q) * scale
                    let py = 1.7320508075688772 * (Double(r) + Double(q) / 2) * scale
                    guard placeFacingInDepth(
                        cx + px, cy + py, cz, aboutX: cx, aboutY: cy, spin: spin,
                        hue: hue, saturation: 0.35, lightness: 0.86
                    ) else { return false }
                    placed += 1
                    if placed >= total { return false }
                }
            }
            return true
        }
        func flake(_ cx: Double, _ cy: Double, _ cz: Double, radius: Double, turn: Double, hue: Double, spin: Double) -> Bool {
            let perArm = max(10, Int((0.08 * Double(total) / 6).rounded()))
            for arm in 0 ..< 6 {
                let along = turn + Double(arm) * 1.0471975511965976
                for bead in 0 ..< perArm {
                    let through = Double(bead) / Double(max(1, perArm - 1))
                    let reach = through * radius
                    guard placeFacingInDepth(
                        cx + jsCos(along) * reach, cy + jsSin(along) * reach, cz,
                        aboutX: cx, aboutY: cy, spin: spin,
                        hue: (hue + 72 * through).truncatingRemainder(dividingBy: 360), saturation: 0.4, lightness: 0.88
                    ) else { return false }
                    placed += 1
                    if placed >= total { return false }
                    guard bead > 2, bead.isMultiple(of: 2) else { continue }
                    let barbLength = 0.28 * radius * (1 - through)
                    for side in [-1.0, 1.0] {
                        let barbAngle = along + side * 1.0471975511965976
                        for tick in 1 ... 3 {
                            let outward = barbLength * Double(tick) / 3
                            guard placeFacingInDepth(
                                cx + jsCos(along) * reach + jsCos(barbAngle) * outward,
                                cy + jsSin(along) * reach + jsSin(barbAngle) * outward,
                                cz,
                                aboutX: cx, aboutY: cy, spin: spin,
                                hue: (hue + 54).truncatingRemainder(dividingBy: 360), saturation: 0.3, lightness: 0.9
                            ) else { return false }
                            placed += 1
                            if placed >= total { return false }
                        }
                    }
                }
            }
            return hexCore(cx, cy, cz, radius: 0.18 * radius, hue: hue, spin: spin)
        }
        // At every depth, the nearer ones smaller, so the box reads as air with snow in it.
        let sites: [(Double, Double, Double)] = [
            (0.22, 0.28, 0.6), (0.5, 0.22, -0.4), (0.78, 0.3, 0.2), (0.28, 0.68, -0.7),
            (0.72, 0.66, 0.5), (0.5, 0.52, 0), (0.18, 0.5, -0.2), (0.84, 0.5, 0.8),
        ]
        let flakes = max(5, min(8, total / 700))
        for index in 0 ..< flakes {
            let site = sites[index % sites.count]
            guard flake(
                across(site.0 + between(-0.02, 0.02)),
                down(site.1 + between(-0.02, 0.02)),
                site.2 * halfDepth * 0.7,
                radius: span * between(0.1, 0.16),
                turn: 0.35 * Double(index),
                hue: 186 + Double(index % 6) * 10,
                spin: (index.isMultiple(of: 2) ? 1 : -1) * between(0.002, 0.005)
            ) else { return }
        }
        let shards = max(4, min(10, total / 900))
        for index in 0 ..< shards {
            guard hexCore(
                across(between(0.12, 0.88)),
                down(between(0.12, 0.88)),
                between(-0.8, 0.8) * halfDepth,
                radius: span * between(0.035, 0.06),
                hue: 200 + Double(index % 5) * 8,
                spin: between(-0.006, 0.006)
            ) else { return }
        }
    }

    /// The pyramid made of pyramids: the chaos game with the four corners of a pyramid instead of the three of a
    /// triangle, turning slowly like a globe.
    func spawnSierpinskiInDepth(count requested: Int) {
        beginScene("sierpinski", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let reach = 0.44 * patternSpan
        let centreX = width * 0.5
        let centreY = height * 0.5
        // A regular one: the top a whole reach above the middle, the base a third of it below, and the base's
        // corners out at the root of eight over three of it.
        let baseRadius = reach * 0.9428090415820634
        var corners: [(x: Double, y: Double, z: Double)] = [(centreX, centreY - reach, 0)]
        for k in 0 ..< 3 {
            let turn = -1.5707963267948966 + Double(k) * 2.0943951023931953
            corners.append((centreX + jsCos(turn) * baseRadius, centreY + reach / 3, jsSin(turn) * baseRadius))
        }
        var x = centreX
        var y = centreY
        var z = 0.0
        for _ in 0 ..< 24 {
            let corner = corners[Int(rng.next() * 4) % 4]
            x = (x + corner.x) * 0.5
            y = (y + corner.y) * 0.5
            z = (z + corner.z) * 0.5
        }
        for _ in 0 ..< total {
            let pick = Int(rng.next() * 4) % 4
            let corner = corners[pick]
            x = (x + corner.x) * 0.5
            y = (y + corner.y) * 0.5
            z = (z + corner.z) * 0.5
            guard placeTurningInDepth(
                x, y, z, aboutX: centreX, spin: 0.002,
                hue: 30 + Double(pick) * 80, saturation: 0.75, lightness: 0.65
            ) else { return }
        }
    }

    /// A ringed planet: a turning ball, banded like a gas giant, with a level band of bodies circling it.
    func spawnRingInDepth(count requested: Int) {
        beginScene("ring", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let centreX = width * 0.5
        let centreY = height * 0.5
        let planetRadius = 0.13 * patternSpan
        let ringRadius = 0.34 * patternSpan
        let band = 0.22 * ringRadius
        let planetBodies = total * 3 / 10
        for index in 0 ..< planetBodies {
            let p = goldenPoint(index, of: planetBodies)
            let latitude = p.y
            guard placeTurningInDepth(
                centreX + p.x * planetRadius,
                centreY + p.y * planetRadius,
                p.z * planetRadius,
                aboutX: centreX,
                spin: 0.006,
                stiffness: 0.02,
                hue: 32 + 14 * jsSin(latitude * 9),
                saturation: 0.55,
                lightness: 0.52 + 0.12 * jsCos(latitude * 13)
            ) else { return }
        }
        let ringBodies = total - planetBodies
        for index in 0 ..< ringBodies {
            let around = (Double(index) + between(0, 1)) / Double(max(1, ringBodies)) * 6.283185307179586
            let out = ringRadius - band + rng.next() * band * 1.6
            guard placeTurningInDepth(
                centreX + jsCos(around) * out,
                centreY + between(-0.004, 0.004) * patternSpan,
                jsSin(around) * out,
                aboutX: centreX,
                spin: 0.004,
                stiffness: 0.01,
                hue: 38 + between(-10, 14),
                saturation: 0.42,
                lightness: 0.5 + 0.25 * jsSin(out / band * 5)
            ) else { return }
        }
    }

    /// A real funnel: every body circling the upright line through it, fast and tight at the bottom, wide and slow
    /// at the top.
    func spawnTornadoInDepth(count requested: Int) {
        beginScene("tornado", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let centreX = width * 0.5
        let span = patternSpan
        for index in 0 ..< total {
            let up = Double(index) / Double(max(1, total - 1))
            let radius = (0.018 + 0.22 * up) * span
            let angle = 14 * up + between(0, 0.4) + rng.next() * 6.283185307179586
            let rate = 0.07 - 0.05 * up
            let y = aboveFloor(0.94 - 0.86 * up) + between(-0.01, 0.01) * layoutHeight
            let role: Swarm.Role = [.holds, .upright]
            let home = Swarm.Home(
                anchorX: centreX + between(-0.008, 0.008) * span,
                anchorY: y,
                radius: radius,
                angle: angle,
                spin: rate,
                squash: 1,
                stiffness: 0.12,
                anchorZ: 0
            )
            let at = home.point(for: role)
            guard placeInDepth(
                at.x, at.y, at.z,
                velocityX: -jsSin(angle) * radius * rate,
                velocityZ: jsCos(angle) * radius * rate,
                hue: ((angle / 6.283185307179586 + up) * 360).truncatingRemainder(dividingBy: 360),
                saturation: 0.5,
                lightness: 0.7,
                role: role,
                home: home
            ) else { return }
        }
    }

    /// Five curtains of light one behind another, each a long sheet hanging across the box and rippling.
    func spawnAuroraInDepth(count requested: Int) {
        beginScene("aurora", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let curtains = 5
        let span = patternSpan
        for index in 0 ..< total {
            let curtain = index % curtains
            let along = rng.next()
            let downward = rng.next()
            let depth = (Double(curtain) - 2) * 0.16 * span + 0.06 * span * jsSin(7 * along + Double(curtain) * 1.7)
            let role: Swarm.Role = [.holds, .upright]
            let home = Swarm.Home(
                anchorX: across(0.1 + 0.8 * along),
                anchorY: belowCeiling(0.05 + downward * 0.5),
                radius: 0.016 * span,
                angle: 8 * along + 4 * downward + Double(curtain) * 1.3,
                spin: 0.025,
                squash: 1,
                stiffness: 0.05,
                anchorZ: depth
            )
            let at = home.point(for: role)
            // Green at the foot of each curtain through to violet at its top, as real ones are.
            guard placeInDepth(
                at.x, at.y, at.z,
                hue: 110 + (1 - downward) * 170,
                saturation: 0.75,
                lightness: 0.6,
                role: role,
                home: home
            ) else { return }
        }
    }

    /// One bolt in depth: the same wandering, splitting walk as flat, but free to wander toward and away from the
    /// viewer as well.
    func strikeLightningInDepth(count requested: Int) {
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        var path: [(x: Double, y: Double, z: Double, brightness: Double)] = []
        let span = patternSpan
        let halfDepth = self.halfDepth
        func walk(from start: (x: Double, y: Double, z: Double), heading: (x: Double, y: Double, z: Double), step: Double, depth: Int) {
            var position = start
            var direction = heading
            let segments = 7 + (3 - depth) * 3
            for _ in 0 ..< segments {
                direction.x += between(-0.5, 0.5)
                direction.z += between(-0.5, 0.5)
                direction.y += between(-0.2, 0.3)
                let length = max(1e-6, (direction.x * direction.x + direction.y * direction.y + direction.z * direction.z).squareRoot())
                direction = (direction.x / length, direction.y / length, direction.z / length)
                position = (position.x + direction.x * step, position.y + direction.y * step, position.z + direction.z * step)
                guard position.y < height * 0.98, position.x > width * 0.02, position.x < width * 0.98,
                      abs(position.z) < halfDepth * 0.95 else { return }
                path.append((position.x, position.y, position.z, 1 - 0.22 * Double(depth)))
                if depth < 3, rng.next() < 0.3 {
                    walk(
                        from: position,
                        heading: (direction.x + between(-0.9, 0.9), direction.y, direction.z + between(-0.9, 0.9)),
                        step: step * 0.62,
                        depth: depth + 1
                    )
                }
            }
        }
        let bolts = max(1, min(4, total / 1_800))
        for _ in 0 ..< bolts {
            walk(
                from: (across(between(0.22, 0.78)), belowCeiling(0.02), between(-0.5, 0.5) * halfDepth),
                heading: (between(-0.15, 0.15), 1, between(-0.15, 0.15)),
                step: 0.045 * span,
                depth: 0
            )
        }
        guard !path.isEmpty else { return }
        for index in 0 ..< total {
            let point = index < path.count ? path[index] : path[Int(rng.next() * Double(path.count)) % path.count]
            let x = point.x + between(-0.006, 0.006) * span
            let y = point.y + between(-0.006, 0.006) * span
            let z = point.z + between(-0.006, 0.006) * span
            guard placeInDepth(
                x, y, z,
                velocityX: between(-0.3, 0.3),
                velocityY: between(-0.2, 1.0),
                hue: 210 + point.brightness * 40,
                saturation: 0.55,
                lightness: 0.6 + point.brightness * 0.35,
                life: between(14, 34) + point.brightness * 26,
                role: .holds,
                home: Swarm.Home(anchorX: x, anchorY: y, stiffness: 0.05, anchorZ: z)
            ) else { return }
        }
    }

    /// One shell bursting into a ball of sparks, somewhere in the upper half of the box.
    func launchShellInDepth(count requested: Int) {
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let span = patternSpan
        let originX = across(between(0.12, 0.88))
        let originY = belowCeiling(between(0.12, 0.55))
        let originZ = between(-0.6, 0.6) * halfDepth
        let hue = between(0, 360)
        for _ in 0 ..< total {
            let direction = randomDirection()
            let speed = between(0.25, 1.15) * 5
            guard placeInDepth(
                originX + between(-0.004, 0.004) * span,
                originY + between(-0.004, 0.004) * span,
                originZ + between(-0.004, 0.004) * span,
                velocityX: direction.x * speed,
                velocityY: direction.y * speed,
                velocityZ: direction.z * speed,
                hue: hue + between(-12, 12),
                saturation: 0.9,
                lightness: between(0.55, 0.78),
                life: between(70, 140)
            ) else { return }
        }
    }

    func spawnSupernovaInDepth(count requested: Int) {
        beginScene("supernova", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let centreX = width * 0.5
        let centreY = height * 0.5
        let span = patternSpan
        for _ in 0 ..< total {
            let direction = randomDirection()
            let isShell = rng.next() < 0.7
            let speed = isShell ? between(0.85, 1.35) * 9 : between(0.05, 0.45) * 9
            let x = centreX + between(-0.008, 0.008) * span
            let y = centreY + between(-0.008, 0.008) * span
            let z = between(-0.008, 0.008) * span
            if isShell {
                guard placeInDepth(
                    x, y, z,
                    velocityX: direction.x * speed,
                    velocityY: direction.y * speed,
                    velocityZ: direction.z * speed,
                    hue: between(20, 60), saturation: 0.9, lightness: 0.7,
                    life: between(110, 200)
                ) else { return }
            } else {
                // Where it will come to rest in the remnant — a ball — turning slowly like a globe.
                let settle = between(0.03, 0.16) * span
                let restX = direction.x * settle
                let restZ = direction.z * settle
                let level = (restX * restX + restZ * restZ).squareRoot()
                let angle = level > 0 ? JS.atan2(restZ, restX) : 0
                let spin = 0.0025 * (0.2 * span / max(settle, 1)).squareRoot()
                guard placeInDepth(
                    x, y, z,
                    velocityX: direction.x * speed,
                    velocityY: direction.y * speed,
                    velocityZ: direction.z * speed,
                    hue: between(270, 330), saturation: 0.6, lightness: 0.45,
                    role: [.holds, .upright],
                    home: Swarm.Home(
                        anchorX: centreX, anchorY: centreY + direction.y * settle, radius: level, angle: angle,
                        spin: spin, squash: 1, stiffness: 0.002, anchorZ: 0
                    )
                ) else { return }
            }
        }
    }

    func spawnFireworksInDepth(count requested: Int) {
        beginScene("fireworks", gravityY: 0.05)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let shells = max(4, min(14, total / 350))
        let perShell = max(20, total / shells)
        for _ in 0 ..< shells { launchShellInDepth(count: perShell) }
    }

    /// A molten pool across the floor of the box, heaving in slow rolling waves, with vents throwing up embers.
    func spawnMagmaInDepth(count requested: Int) {
        beginScene("magma", gravityY: 0.05)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        for _ in 0 ..< total {
            let heat = rng.next()
            let x = across(between(0.04, 0.96))
            let y = aboveFloor(between(0.84, 0.985))
            let z = between(-0.85, 0.85) * halfDepth
            let role: Swarm.Role = [.holds, .bobs]
            let home = Swarm.Home(
                anchorX: x,
                anchorY: y,
                radius: between(0.01, 0.03) * patternSpan,
                angle: (x - layoutLeft) / max(1, layoutWidth) * 6 + z / max(1, patternSpan) * 7 + between(0, 0.6),
                spin: 0.018,
                squash: 0.6,
                stiffness: 0.03,
                anchorZ: z
            )
            let at = home.point(for: role)
            guard placeInDepth(
                at.x, at.y, at.z,
                hue: 4 + heat * 36, saturation: 0.95, lightness: 0.3 + heat * 0.32,
                role: role, home: home
            ) else { return }
        }
        emitterTemplate = ParticleEmitter(
            atFractionX: 0.5, atFractionY: 0.84, direction: -1.5707963267948966, rate: 45, spread: 0.45,
            speed: 5, speedVariation: 0.4, lifespan: 90, weight: 0.6, weightVariation: 0.3, hue: 28
        )
        for share in [0.22, 0.52, 0.8] { addEmitter(atX: across(share), y: aboveFloor(0.84)) }
    }

    func spawnConfettiInDepth(count requested: Int) {
        beginScene("confetti", gravityY: 0.025)
        storedFlowEnabled = true
        storedFlowSettings = SwarmFlow.Settings(strength: 0.3, scale: max(60, patternSpan * 0.2), drift: 0.15)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        for _ in 0 ..< total {
            guard placeInDepth(
                across(between(0.1, 0.9)),
                belowCeiling(between(0.03, 0.35)),
                between(-0.9, 0.9) * halfDepth,
                velocityX: between(-3, 3),
                velocityY: between(-1.2, 3),
                velocityZ: between(-3, 3),
                hue: between(0, 360), saturation: 0.9, lightness: 0.66,
                life: between(600, 1_100)
            ) else { return }
        }
        emitterTemplate = ParticleEmitter(
            atFractionX: 0.5, atFractionY: 0.02, direction: 1.5707963267948966, rate: 30, spread: 1.2,
            speed: 1.2, speedVariation: 0.6, lifespan: 1_000, weight: 1, weightVariation: 0, hue: -1
        )
        for share in [0.2, 0.5, 0.8] { addEmitter(atX: across(share), y: belowCeiling(0.02)) }
    }

    func spawnFireInDepth(count requested: Int) {
        beginScene("fire", gravityY: -0.22)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let columnWidth = 0.18 * layoutWidth
        for _ in 0 ..< total {
            let heat = rng.next()
            let life = between(30, 110)
            let turn = rng.next() * Double.pi * 2
            let out = rng.next().squareRoot() * columnWidth
            guard placeInDepth(
                width * 0.5 + jsCos(turn) * out,
                aboveFloor(between(0.78, 0.98)),
                jsSin(turn) * out,
                velocityX: between(-0.7, 0.7),
                velocityY: -between(1.2, 3.4),
                velocityZ: between(-0.7, 0.7),
                hue: 8 + heat * 44, saturation: 0.96, lightness: 0.46 + heat * 0.3,
                life: life
            ) else { return }
        }
        emitterTemplate = ParticleEmitter(
            atFractionX: 0.5, atFractionY: 0.95, direction: -1.5707963267948966, rate: 420, spread: 0.42,
            speed: 2.6, speedVariation: 0.45, lifespan: 80, weight: 0.6, weightVariation: 0.3, hue: 24
        )
        addEmitter(atX: width * 0.5, y: aboveFloor(0.95))
    }

    func spawnSmokeInDepth(count requested: Int) {
        beginScene("smoke", gravityY: -0.1)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let columnWidth = 0.12 * layoutWidth
        for _ in 0 ..< total {
            let turn = rng.next() * Double.pi * 2
            let out = rng.next().squareRoot() * columnWidth
            guard placeInDepth(
                width * 0.5 + jsCos(turn) * out,
                aboveFloor(between(0.72, 0.96)),
                jsSin(turn) * out,
                velocityX: between(-0.35, 0.35),
                velocityY: -between(0.4, 1.2),
                velocityZ: between(-0.35, 0.35),
                hue: 220 + between(-20, 20), saturation: 0.12, lightness: 0.34 + rng.next() * 0.22,
                life: between(140, 320)
            ) else { return }
        }
        emitterTemplate = ParticleEmitter(
            atFractionX: 0.5, atFractionY: 0.94, direction: -1.5707963267948966, rate: 180, spread: 0.62,
            speed: 1.1, speedVariation: 0.5, lifespan: 240, weight: 0.3, weightVariation: 0.4, hue: 222
        )
        addEmitter(atX: width * 0.5, y: aboveFloor(0.94))
    }

    // MARK: - Only in 3D

    /// A globe: seeds a golden turn apart all over a ball, coloured as land and sea, turning on its stand.
    public func spawnGlobe(count requested: Int = 4_600) {
        beginScene("globe", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let centreX = width * 0.5
        let centreY = height * 0.5
        let radius = 0.4 * patternSpan
        let seed = between(0, 100)
        for index in 0 ..< total {
            let p = goldenPoint(index, of: total)
            // Land where a smooth wandering sum of waves is high, sea where it is low, ice near the poles.
            let land = SwarmFlow.noise(p.x * 2.2 + seed, p.y * 2.2, p.z * 2.2 - seed)
            let polar = abs(p.y) > 0.86
            let hue: Double = polar ? 205 : land > 0.08 ? (land > 0.3 ? 32 : 105) : 212
            let saturation: Double = polar ? 0.12 : land > 0.08 ? 0.55 : 0.75
            let lightness: Double = polar ? 0.92 : land > 0.08 ? 0.42 + land * 0.3 : 0.42 - land * 0.1
            guard placeTurningInDepth(
                centreX + p.x * radius,
                centreY + p.y * radius,
                p.z * radius,
                aboutX: centreX,
                spin: 0.004,
                stiffness: 0.02,
                hue: hue,
                saturation: saturation,
                lightness: lightness
            ) else { return }
        }
    }

    /// A trefoil knot: a tube of bodies following the path that goes three times round a ring while it winds
    /// twice about it, turning slowly.
    public func spawnKnot(count requested: Int = 4_000) {
        beginScene("knot", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let centreX = width * 0.5
        let centreY = height * 0.5
        let scale = 0.13 * patternSpan
        let tube = 0.03 * patternSpan
        for index in 0 ..< total {
            let t = (Double(index) + rng.next()) / Double(total) * 6.283185307179586
            let ring = jsCos(3 * t) + 2
            let offset = randomDirection()
            let thickness = tube * rng.next().squareRoot()
            guard placeTurningInDepth(
                centreX + ring * jsCos(2 * t) * scale + offset.x * thickness,
                centreY - jsSin(3 * t) * scale + offset.y * thickness,
                ring * jsSin(2 * t) * scale + offset.z * thickness,
                aboutX: centreX,
                spin: 0.004,
                stiffness: 0.02,
                hue: (t / 6.283185307179586 * 360).truncatingRemainder(dividingBy: 360),
                saturation: 0.8,
                lightness: 0.62
            ) else { return }
        }
    }

    /// A sea: a sheet of bodies, each going round its own small upright circle, a little behind its neighbour —
    /// which is how a real wave moves water, and why waves roll rather than just rising and falling.
    public func spawnOcean(count requested: Int = 5_200) {
        beginScene("ocean", gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let columns = max(10, Int((Double(total) * layoutWidth / max(1, halfDepth * 1.8)).squareRoot()))
        let rows = max(4, total / columns)
        let level = down(0.62)
        let wavelength = 0.3 * patternSpan
        let waveHeight = 0.025 * patternSpan
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let x = across(0.03 + 0.94 * (Double(column) + 0.5) / Double(columns))
                let z = (Double(row) + 0.5) / Double(rows) * 1.8 * halfDepth - 0.9 * halfDepth
                let phase = -z / wavelength * 6.283185307179586 - x / wavelength * 1.7
                let role: Swarm.Role = [.holds, .bobs]
                let home = Swarm.Home(
                    anchorX: x, anchorY: level, radius: waveHeight, angle: phase, spin: 0.045,
                    squash: 0.8, stiffness: 0.08, anchorZ: z
                )
                let at = home.point(for: role)
                guard placeInDepth(
                    at.x, at.y, at.z,
                    hue: 196 + between(-6, 8),
                    saturation: 0.75,
                    lightness: 0.46 + between(-0.05, 0.08),
                    role: role,
                    home: home
                ) else { return }
            }
        }
    }

    /// Stars rushing past: a long box full of them, all streaming toward the viewer, each sent to the far end
    /// again as it passes.
    public func spawnWarp(count requested: Int = 6_000) {
        beginScene("warp", gravityY: 0)
        // A flight needs a long tunnel to fly down, so this one makes the box as deep as it goes.
        storedDepthRatio = Self.depthRatioRange.upperBound
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        for _ in 0 ..< total {
            let star = warpStar(depth: between(-1, 1) * halfDepth)
            guard placeInDepth(
                star.x, star.y, star.z,
                velocityZ: -star.speed,
                hue: between(190, 240),
                saturation: 0.35,
                lightness: between(0.7, 0.95),
                role: .orbits
            ) else { return }
        }
    }

    /// Where a star in the flight starts, and how fast it comes.
    func warpStar(depth: Double) -> (x: Double, y: Double, z: Double, speed: Double) {
        (
            width * 0.5 + between(-0.5, 0.5) * width * 0.98,
            height * 0.5 + between(-0.5, 0.5) * height * 0.98,
            depth,
            between(6, 16) * max(1, patternSpan / 700)
        )
    }

    /// How big the glass of the snow globe is.
    public var snowGlobeRadius: Double { 0.42 * patternSpan }

    /// Snow drifting down inside a glass ball, round a little tree on a snowy mound.
    public func spawnSnowGlobe(count requested: Int = 6_000) {
        beginScene("snowglobe", gravityY: 0.02)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        let centreX = width * 0.5
        let centreY = height * 0.5
        let glass = snowGlobeRadius
        // The mound: the bottom of the ball, filled.
        let mound = total / 6
        var placed = 0
        while placed < mound {
            let p = randomDirection()
            let out = glass * 0.96 * rng.next().squareRoot()
            let y = centreY + glass * 0.62 + rng.next() * glass * 0.34
            let level = (glass * glass - (y - centreY) * (y - centreY)).squareRoot() * 0.97
            let reach = min(out, level)
            // Held firmly, so tipping the phone moves the snow and not the ground it has settled on.
            guard placeInDepth(
                centreX + p.x * reach, y, p.z * reach,
                hue: 205, saturation: 0.15, lightness: 0.9,
                role: .holds,
                home: Swarm.Home(anchorX: centreX + p.x * reach, anchorY: y, stiffness: 0.5, anchorZ: p.z * reach)
            ) else { return }
            placed += 1
        }
        // The tree: a cone of green, standing on the mound.
        let tree = total / 8
        let foot = centreY + glass * 0.64
        let top = centreY - glass * 0.1
        for _ in 0 ..< tree {
            let up = rng.next()
            let y = foot + (top - foot) * up
            let spread = glass * 0.26 * (1 - up) * rng.next().squareRoot()
            let turn = rng.next() * Double.pi * 2
            let x = centreX + jsCos(turn) * spread
            let z = jsSin(turn) * spread
            guard placeInDepth(
                x, y, z,
                hue: 128 + between(-8, 8), saturation: 0.55, lightness: 0.3 + 0.15 * up,
                role: .holds, home: Swarm.Home(anchorX: x, anchorY: y, stiffness: 0.5, anchorZ: z)
            ) else { return }
        }
        // And the snow, anywhere in the glass above the mound.
        for _ in placed + tree ..< total {
            var point = randomDirection()
            let out = glass * 0.95 * jsPow(rng.next(), 1.0 / 3)
            point = (point.x * out, point.y * out, point.z * out)
            if point.y > glass * 0.55 { point.y = -point.y }
            guard placeInDepth(
                centreX + point.x, centreY + point.y, point.z,
                velocityX: between(-0.3, 0.3),
                velocityY: between(-0.1, 0.3),
                velocityZ: between(-0.3, 0.3),
                hue: 210, saturation: 0.2, lightness: between(0.86, 0.98)
            ) else { return }
        }
    }

    // MARK: - Strange attractors

    /// The four strange attractors: paths through space that never repeat and never leave, each of which a
    /// crowd following it traces out as a shape.
    enum StrangeAttractor: String, CaseIterable, Sendable {
        case lorenz, aizawa, thomas, halvorsen

        /// How fast a point at a place is moving along the path, in the attractor's own units.
        func velocity(_ x: Double, _ y: Double, _ z: Double) -> (x: Double, y: Double, z: Double) {
            switch self {
            case .lorenz:
                return (10 * (y - x), x * (28 - z) - y, x * y - 8.0 / 3 * z)
            case .aizawa:
                let a = 0.95, b = 0.7, c = 0.6, d = 3.5, e = 0.25, f = 0.1
                return (
                    (z - b) * x - d * y,
                    d * x + (z - b) * y,
                    c + a * z - z * z * z / 3 - (x * x + y * y) * (1 + e * z) + f * z * x * x * x
                )
            case .thomas:
                let b = 0.208186
                return (jsSin(y) - b * x, jsSin(z) - b * y, jsSin(x) - b * z)
            case .halvorsen:
                let a = 1.89
                return (-a * x - 4 * y - 4 * z - y * y, -a * y - 4 * z - 4 * x - z * z, -a * z - 4 * x - 4 * y - x * x)
            }
        }

        /// The middle of the shape, in its own units.
        var middle: (x: Double, y: Double, z: Double) {
            switch self {
            case .lorenz: return (0, 0, 25)
            case .aizawa: return (0, 0, 0.35)
            case .thomas: return (0, 0, 0)
            case .halvorsen: return (-2.5, -2.5, -2.5)
            }
        }

        /// How far the shape reaches from its middle, in its own units.
        var reach: Double {
            switch self {
            case .lorenz: return 27
            case .aizawa: return 1.6
            case .thomas: return 4.4
            case .halvorsen: return 10
            }
        }

        /// How much of the path one moment covers. Chosen so each is a pleasure to watch rather than a blur.
        var timeStep: Double {
            switch self {
            case .lorenz: return 0.0035
            case .aizawa: return 0.009
            case .thomas: return 0.045
            case .halvorsen: return 0.004
            }
        }

        /// Somewhere on the path to begin.
        var start: (x: Double, y: Double, z: Double) {
            switch self {
            case .lorenz: return (0.1, 0, 0)
            case .aizawa: return (0.1, 0, 0)
            case .thomas: return (1.1, 1.1, -0.01)
            case .halvorsen: return (-1.48, -1.51, 2.04)
            }
        }
    }

    /// Where a point in an attractor's own units is in the world. Its third direction is its height — the
    /// Lorenz butterfly's wings spread across and its body stands up — and its second is depth.
    func attractorToWorld(_ attractor: StrangeAttractor, _ p: (x: Double, y: Double, z: Double)) -> (x: Double, y: Double, z: Double) {
        let scale = 0.42 * patternSpan / attractor.reach
        let middle = attractor.middle
        return (
            width * 0.5 + (p.x - middle.x) * scale,
            height * 0.5 - (p.z - middle.z) * scale,
            (p.y - middle.y) * scale
        )
    }

    func worldToAttractor(_ attractor: StrangeAttractor, _ x: Double, _ y: Double, _ z: Double) -> (x: Double, y: Double, z: Double) {
        let scale = 0.42 * patternSpan / attractor.reach
        let middle = attractor.middle
        return (
            (x - width * 0.5) / scale + middle.x,
            z / scale + middle.y,
            -(y - height * 0.5) / scale + middle.z
        )
    }

    /// Lays a crowd along an attractor's path, so its shape is there from the first moment.
    func spawnStrangeAttractor(_ id: String, count requested: Int = 7_000) {
        guard let attractor = StrangeAttractor(rawValue: id) else { return }
        beginScene(id, gravityY: 0)
        let total = min(requested, patternRoom)
        guard total > 0 else { return }
        var p = attractor.start
        let dt = attractor.timeStep
        // Past the first stretch, which is the path finding its way onto the shape.
        for _ in 0 ..< 1_500 {
            let v = attractor.velocity(p.x, p.y, p.z)
            p = (p.x + v.x * dt, p.y + v.y * dt, p.z + v.z * dt)
        }
        let stride = 4
        let hueStart = between(0, 360)
        for index in 0 ..< total {
            for _ in 0 ..< stride {
                let v = attractor.velocity(p.x, p.y, p.z)
                p = (p.x + v.x * dt, p.y + v.y * dt, p.z + v.z * dt)
            }
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { p = attractor.start; continue }
            let world = attractorToWorld(attractor, p)
            let hue = (hueStart + Double(index) / Double(total) * 300).truncatingRemainder(dividingBy: 360)
            guard placeInDepth(
                world.x, world.y, world.z,
                hue: hue, saturation: 0.85, lightness: 0.62,
                role: .orbits
            ) else { return }
        }
        followAttractor(attractor)
    }

    /// Sets every loose body in the crowd moving along the attractor's path from wherever it is.
    func followAttractor(_ attractor: StrangeAttractor) {
        let scale = 0.42 * patternSpan / attractor.reach
        let dt = attractor.timeStep
        let lost = attractor.reach * 4
        let middle = attractor.middle
        for index in 0 ..< swarm.count {
            let x = Double(swarm.positions[index * 2])
            let y = Double(swarm.positions[index * 2 + 1])
            let z = Double(swarm.depths[index])
            var p = worldToAttractor(attractor, x, y, z)
            let dx = p.x - middle.x
            let dy = p.y - middle.y
            let dz = p.z - middle.z
            // Something pushed right off the shape — or a number gone bad — goes back to near the middle, where
            // the flow picks it up again.
            if !(dx * dx + dy * dy + dz * dz < lost * lost) {
                p = (middle.x + between(-0.1, 0.1) * attractor.reach, middle.y + between(-0.1, 0.1) * attractor.reach,
                     middle.z + between(-0.1, 0.1) * attractor.reach)
                let world = attractorToWorld(attractor, p)
                swarm.positions[index * 2] = JS.toFloat32(world.x)
                swarm.positions[index * 2 + 1] = JS.toFloat32(world.y)
                swarm.depths[index] = JS.toFloat32(world.z)
            }
            let v = attractor.velocity(p.x, p.y, p.z)
            guard v.x.isFinite, v.y.isFinite, v.z.isFinite else { continue }
            swarm.velocities[index * 2] = JS.toFloat32(v.x * dt * scale)
            swarm.velocities[index * 2 + 1] = JS.toFloat32(-v.z * dt * scale)
            swarm.depthVelocities[index] = JS.toFloat32(v.y * dt * scale)
        }
        swarm.noteDepthInUse()
    }

    // MARK: - What arrangements do in depth, every moment

    /// Moves on whatever an arrangement that only exists in depth does by itself.
    func stepArrangementInDepth() {
        guard let id = storedArrangement else { return }
        switch id {
        case "lorenz", "aizawa", "thomas", "halvorsen":
            if let attractor = StrangeAttractor(rawValue: id) { followAttractor(attractor) }
        case "warp":
            // Sent round again before it would reach the front of the box this moment, rather than after, so no
            // star ever meets the front and bounces back the wrong way.
            let front = -halfDepth + 8
            for index in 0 ..< swarm.count
            where Double(swarm.depths[index]) + Double(swarm.depthVelocities[index]) * 1.5 < front {
                let star = warpStar(depth: halfDepth - between(0, 40))
                swarm.positions[index * 2] = JS.toFloat32(star.x)
                swarm.positions[index * 2 + 1] = JS.toFloat32(star.y)
                swarm.depths[index] = JS.toFloat32(star.z)
                swarm.velocities[index * 2] = 0
                swarm.velocities[index * 2 + 1] = 0
                swarm.depthVelocities[index] = JS.toFloat32(-star.speed)
            }
        case "snowglobe":
            let centreX = width * 0.5
            let centreY = height * 0.5
            let glass = snowGlobeRadius
            for index in 0 ..< swarm.count where swarm.home(at: index) == nil {
                let dx = Double(swarm.positions[index * 2]) - centreX
                let dy = Double(swarm.positions[index * 2 + 1]) - centreY
                let dz = Double(swarm.depths[index])
                let out = (dx * dx + dy * dy + dz * dz).squareRoot()
                guard out > glass, out.isFinite else { continue }
                // Back inside the glass, and what was carrying it outward turned round and mostly lost.
                let inward = glass * 0.995 / out
                let nx = dx / out, ny = dy / out, nz = dz / out
                swarm.positions[index * 2] = JS.toFloat32(centreX + dx * inward)
                swarm.positions[index * 2 + 1] = JS.toFloat32(centreY + dy * inward)
                swarm.depths[index] = JS.toFloat32(dz * inward)
                let vx = Double(swarm.velocities[index * 2])
                let vy = Double(swarm.velocities[index * 2 + 1])
                let vz = Double(swarm.depthVelocities[index])
                let along = vx * nx + vy * ny + vz * nz
                if along > 0 {
                    swarm.velocities[index * 2] = JS.toFloat32(vx - 1.3 * along * nx)
                    swarm.velocities[index * 2 + 1] = JS.toFloat32(vy - 1.3 * along * ny)
                    swarm.depthVelocities[index] = JS.toFloat32(vz - 1.3 * along * nz)
                }
            }
        default:
            break
        }
    }
}

extension ParticleEngine {
    /// A few bodies scattered in depth: in level orbits round a black hole if there is one, and otherwise
    /// spread through a ball in the middle of the box.
    func addBatchInDepth(count: Int, color: PackedColor?, ownSize: Double) {
        let hole = particles.first { $0.kind == .blackhole }
        let limit = halfDepth - 4
        for i in 0 ..< count {
            let direction = randomDirection()
            let distance = rng.next() * (patternSpan * 0.42) + 25
            var x: Double
            var y: Double
            var z: Double
            var velX = (rng.next() - 0.5) * 6
            var velY = (rng.next() - 0.5) * 6
            var velZ = (rng.next() - 0.5) * 6
            var orbiting = false
            var originX = width / 2
            var originY = height / 2
            var originZ = 0.0
            if let hole {
                let angle = rng.next() * Double.pi * 2
                x = hole.x + jsCos(angle) * distance
                y = hole.y + (rng.next() - 0.5) * 6
                z = hole.z + jsSin(angle) * distance
                let speed = (hole.mass * 200 / max(10, distance)).squareRoot() * (0.95 + rng.next() * 0.1)
                velX = -jsSin(angle) * speed
                velY = 0
                velZ = jsCos(angle) * speed
                orbiting = true
                originX = hole.x
                originY = hole.y
                originZ = hole.z
            } else {
                x = width / 2 + direction.x * distance
                y = height / 2 + direction.y * distance
                z = direction.z * distance
            }
            addParticle(
                x: min(width - 2, max(2, x)),
                y: min(height - 2, max(2, y)),
                velocityX: velX,
                velocityY: velY,
                radius: ownSize > 0 ? ownSize * 0.5 : 1.5,
                mass: 1,
                charge: i % 2 == 0 ? 1 : -1,
                color: color ?? PackedColor(hue: Double(i * 137).truncatingRemainder(dividingBy: 360), saturation: 0.85, lightness: 0.65),
                ignoresGravity: orbiting,
                originX: originX,
                originY: originY,
                z: max(-limit, min(limit, z)),
                velocityZ: velZ,
                originZ: originZ
            )
        }
    }
}
