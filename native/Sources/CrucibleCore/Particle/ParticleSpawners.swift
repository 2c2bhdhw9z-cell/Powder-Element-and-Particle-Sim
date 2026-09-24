// The scene presets.
//
// Ported from web/src/sim/particle/spawners.ts.
//
// The order of the random draws matters as much here as it does in the physics: a
// preset is only reproducible if it consumes the same numbers in the same sequence.
// Swift evaluates call arguments left to right and `addParticle` draws for any value
// it was not given, so each call below passes exactly the values the original passes,
// in the order the original's object literal lists them.

extension ParticleEngine {
    /// A ring of particles thrown outward from a point. Adds to the scene rather than
    /// replacing it.
    public func spawnBurst(count: Int = 100, x: Double? = nil, y: Double? = nil) {
        pushUndo()
        let centreX = x ?? width / 2
        let centreY = y ?? height / 2

        for i in 0 ..< count {
            let angle = rng.next() * Double.pi * 2
            let speed = rng.next() * 8 + 2
            addParticle(
                x: centreX,
                y: centreY,
                velocityX: jsCos(angle) * speed,
                velocityY: jsSin(angle) * speed,
                radius: rng.next() * 3 + 2,
                charge: i % 2 == 0 ? 1 : -1
            )
        }
    }

    /// A spiral disc orbiting a central black hole.
    public func spawnGalaxy(count: Int = 300) {
        clear()
        gravityX = 0
        gravityY = 0
        vortexForce = 0

        let centreX = width / 2
        let centreY = height / 2
        let holeMass = 80.0
        let gravitationalConstant = holeMass * 200

        addParticle(
            x: centreX, y: centreY, velocityX: 0, velocityY: 0,
            radius: 14, mass: holeMass,
            color: PackedColor(r: 0xF4, g: 0x3F, b: 0x5E),
            isFixed: true, ignoresGravity: true, kind: .blackhole
        )

        for _ in 0 ..< count {
            let distance = rng.next() * (min(width, height) * 0.42) + 30
            let angle = rng.next() * Double.pi * 2
            let orbitalSpeed = (gravitationalConstant / distance).squareRoot() * (0.96 + rng.next() * 0.08)

            addParticle(
                x: centreX + jsCos(angle) * distance,
                y: centreY + jsSin(angle) * distance,
                velocityX: -jsSin(angle) * orbitalSpeed,
                velocityY: jsCos(angle) * orbitalSpeed,
                radius: rng.next() * 2 + 1,
                color: PackedColor(hue: (distance * 2.8).truncatingRemainder(dividingBy: 360), saturation: 0.95, lightness: 0.70),
                ignoresGravity: true,
                originX: centreX,
                originY: centreY
            )
        }
    }

    /// Water falling from the top and recycled at the bottom.
    public func spawnWaterfall(count: Int = 250) {
        clear()
        gravityX = 0
        gravityY = 0.4

        let startX = width * 0.3
        let spread = width * 0.4

        for _ in 0 ..< count {
            let dropX = startX + rng.next() * spread
            let dropY = rng.next() * (height * 0.9) + 10
            addParticle(
                x: dropX,
                y: dropY,
                velocityX: (rng.next() - 0.5) * 1.5,
                velocityY: rng.next() * 4 + 2,
                radius: rng.next() * 2.5 + 2,
                color: PackedColor(r: 0x38, g: 0xBD, b: 0xF8),
                originX: startX,
                originY: 20
            )
        }
    }

    /// An expanding ring, evenly spaced in angle.
    public func spawnShockwave(count: Int = 300) {
        clear()
        gravityX = 0
        gravityY = 0

        let centreX = width / 2
        let centreY = height / 2
        for i in 0 ..< count {
            let angle = (Double(i) / Double(count)) * Double.pi * 2
            let speed = 7 + rng.next() * 3
            addParticle(
                x: centreX + jsCos(angle) * 12,
                y: centreY + jsSin(angle) * 12,
                velocityX: jsCos(angle) * speed,
                velocityY: jsSin(angle) * speed,
                radius: 3,
                color: PackedColor(
                    hue: ((Double(i) / Double(count)) * 360).truncatingRemainder(dividingBy: 360),
                    saturation: 1, lightness: 0.65
                ),
                ignoresGravity: true
            )
        }
    }

    /// A heavier black hole with a tighter accretion disc.
    public func spawnBlackHole(count: Int = 250) {
        clear()
        gravityX = 0
        gravityY = 0

        let centreX = width / 2
        let centreY = height / 2
        let holeMass = 100.0
        let gravitationalConstant = holeMass * 200

        addParticle(
            x: centreX, y: centreY, velocityX: 0, velocityY: 0,
            radius: 16, mass: holeMass,
            color: PackedColor(r: 0xF4, g: 0x3F, b: 0x5E),
            isFixed: true, ignoresGravity: true, kind: .blackhole
        )

        for _ in 0 ..< count {
            let distance = rng.next() * (min(width, height) * 0.4) + 35
            let angle = rng.next() * Double.pi * 2
            let orbitalSpeed = (gravitationalConstant / distance).squareRoot() * (0.95 + rng.next() * 0.1)

            addParticle(
                x: centreX + jsCos(angle) * distance,
                y: centreY + jsSin(angle) * distance,
                velocityX: -jsSin(angle) * orbitalSpeed,
                velocityY: jsCos(angle) * orbitalSpeed,
                radius: rng.next() * 2.5 + 1,
                color: PackedColor(hue: (30 + distance * 2).truncatingRemainder(dividingBy: 360), saturation: 1, lightness: 0.65),
                ignoresGravity: true,
                originX: centreX,
                originY: centreY
            )
        }
    }

    /// Two counter-rotating wells side by side.
    public func spawnDoubleVortex(count: Int = 300) {
        clear()
        gravityX = 0
        gravityY = 0

        let leftX = width * 0.35
        let rightX = width * 0.65
        let centreY = height * 0.5
        let holeMass = 50.0
        let gravitationalConstant = holeMass * 200

        addParticle(
            x: leftX, y: centreY, velocityX: 0, velocityY: 0, radius: 12, mass: holeMass,
            color: PackedColor(r: 0x3B, g: 0x82, b: 0xF6),
            isFixed: true, ignoresGravity: true, kind: .blackhole
        )
        addParticle(
            x: rightX, y: centreY, velocityX: 0, velocityY: 0, radius: 12, mass: holeMass,
            color: PackedColor(r: 0xF9, g: 0x73, b: 0x16),
            isFixed: true, ignoresGravity: true, kind: .blackhole
        )

        for i in 0 ..< count {
            let isLeft = i % 2 == 0
            let originX = isLeft ? leftX : rightX
            let spin: Double = isLeft ? 1 : -1
            let baseHue: Double = isLeft ? 200 : 30

            let distance = rng.next() * 130 + 25
            let angle = rng.next() * Double.pi * 2
            let orbitalSpeed = (gravitationalConstant / distance).squareRoot() * (0.92 + rng.next() * 0.16)

            addParticle(
                x: originX + jsCos(angle) * distance,
                y: centreY + jsSin(angle) * distance,
                velocityX: -jsSin(angle) * orbitalSpeed * spin,
                velocityY: jsCos(angle) * orbitalSpeed * spin,
                radius: 2.5,
                color: PackedColor(hue: baseHue + rng.next() * 30, saturation: 0.95, lightness: 0.65),
                ignoresGravity: true,
                originX: originX,
                originY: centreY
            )
        }
    }

    /// A central repulsor holding a shell of particles away from it.
    public func spawnRepulsor() {
        clear()
        gravityX = 0
        gravityY = 0

        let centreX = width / 2
        let centreY = height / 2

        addParticle(
            x: centreX, y: centreY, velocityX: 0, velocityY: 0, radius: 14, mass: 60,
            color: PackedColor(r: 0xA8, g: 0x55, b: 0xF7),
            isFixed: true, ignoresGravity: true, kind: .repulsor
        )

        for _ in 0 ..< 200 {
            let distance = rng.next() * 160 + 60
            let angle = rng.next() * Double.pi * 2
            addParticle(
                x: centreX + jsCos(angle) * distance,
                y: centreY + jsSin(angle) * distance,
                velocityX: (rng.next() - 0.5) * 2,
                velocityY: (rng.next() - 0.5) * 2,
                radius: 2.5,
                color: PackedColor(r: 0x10, g: 0xB9, b: 0x81),
                ignoresGravity: true,
                originX: centreX,
                originY: centreY
            )
        }
    }

    /// A glowing core throwing off short-lived flares.
    public func spawnSolarFlare(count: Int = 350) {
        clear()
        gravityX = 0
        gravityY = 0

        let centreX = width / 2
        let centreY = height / 2

        addParticle(
            x: centreX, y: centreY, velocityX: 0, velocityY: 0, radius: 18, mass: 50,
            color: PackedColor(r: 0xF9, g: 0x73, b: 0x16),
            isFixed: true, ignoresGravity: true, kind: .glow
        )

        for _ in 0 ..< count {
            let angle = rng.next() * Double.pi * 2
            let speed = 2 + rng.next() * 8
            let hue = 15 + rng.next() * 45
            let maxLife = 150 + Int((rng.next() * 200).rounded(.down))

            addParticle(
                x: centreX + jsCos(angle) * 20,
                y: centreY + jsSin(angle) * 20,
                velocityX: jsCos(angle) * speed + (rng.next() - 0.5),
                velocityY: jsSin(angle) * speed + (rng.next() - 0.5),
                radius: rng.next() * 3 + 1.5,
                color: PackedColor(hue: hue, saturation: 1, lightness: 0.60),
                lifespan: Int((rng.next() * Double(maxLife)).rounded(.down)),
                maxLife: maxLife,
                ignoresGravity: true,
                originX: centreX,
                originY: centreY
            )
        }
    }

    /// A charged grid, each node held to its own position by a spring.
    public func spawnQuantumLattice(rows: Int = 18, cols: Int = 24) {
        clear()
        gravityX = 0
        gravityY = 0

        guard rows > 0, cols > 0 else { return }
        let startX = width * 0.2
        let startY = height * 0.2
        let stepX = (width * 0.6) / Double(cols)
        let stepY = (height * 0.6) / Double(rows)

        for row in 0 ..< rows {
            for column in 0 ..< cols {
                let isPositive = (row + column) % 2 == 0
                let nodeX = startX + Double(column) * stepX
                let nodeY = startY + Double(row) * stepY
                addParticle(
                    x: nodeX,
                    y: nodeY,
                    velocityX: (rng.next() - 0.5) * 0.2,
                    velocityY: (rng.next() - 0.5) * 0.2,
                    radius: 3,
                    mass: 2,
                    charge: isPositive ? 1 : -1,
                    color: isPositive
                        ? PackedColor(r: 0x38, g: 0xBD, b: 0xF8)
                        : PackedColor(r: 0xF4, g: 0x3F, b: 0x5E),
                    ignoresGravity: true,
                    originX: nodeX,
                    originY: nodeY,
                    // Explicit, so the restoring force reaches this preset and nothing
                    // else. Inferring it from charge and origin also caught seven
                    // orbital presets and crushed them inward.
                    latticeBound: true
                )
            }
        }
    }

    /// Two counter-phase strands travelling left to right.
    public func spawnDnaHelix(count: Int = 280) {
        clear()
        gravityX = 0
        gravityY = 0

        guard count > 0 else { return }
        let startX = width * 0.1
        let endX = width * 0.9
        let centreY = height / 2
        let wavelength = 120.0

        for i in 0 ..< count {
            let progress = Double(i) / Double(count)
            let pointX = startX + progress * (endX - startX)
            let angle = (pointX / wavelength) * Double.pi * 2

            addParticle(
                x: pointX,
                y: centreY + jsSin(angle) * 50,
                velocityX: 1.2,
                velocityY: 0,
                radius: 2.5,
                charge: 1,
                color: PackedColor(r: 0x06, g: 0xB6, b: 0xD4),
                ignoresGravity: true,
                originX: startX,
                originY: centreY,
                // Explicit strand marker. Deciding this from the body's colour meant any
                // tool that repainted it dropped it out of the helix permanently.
                helixStrand: 1
            )

            addParticle(
                x: pointX,
                y: centreY - jsSin(angle) * 50,
                velocityX: 1.2,
                velocityY: 0,
                radius: 2.5,
                charge: -1,
                color: PackedColor(r: 0xA8, g: 0x55, b: 0xF7),
                ignoresGravity: true,
                originX: startX,
                originY: centreY,
                helixStrand: -1
            )
        }
    }

    /// A jet from the floor that falls back and is relaunched.
    public func spawnCosmicFountain(count: Int = 250) {
        clear()
        gravityX = 0
        gravityY = 0.3

        let centreX = width / 2
        let floorY = height - 20

        for i in 0 ..< count {
            let angle = -Double.pi / 2 + (rng.next() - 0.5) * 0.7
            let speed = rng.next() * 9 + 5
            let maxLife = 120 + Int((rng.next() * 150).rounded(.down))
            addParticle(
                x: centreX + (rng.next() - 0.5) * 30,
                y: floorY - rng.next() * (height * 0.6),
                velocityX: jsCos(angle) * speed,
                velocityY: jsSin(angle) * speed,
                radius: rng.next() * 2.5 + 1.5,
                color: PackedColor(hue: Double(i * 12).truncatingRemainder(dividingBy: 360), saturation: 1, lightness: 0.65),
                lifespan: Int((rng.next() * Double(maxLife)).rounded(.down)),
                maxLife: maxLife,
                originX: centreX,
                originY: floorY
            )
        }
    }

    /// Two wells far enough apart to fling particles between them.
    public func spawnSynchrotron(count: Int = 300) {
        clear()
        gravityX = 0
        gravityY = 0

        let centreX = width / 2
        let centreY = height / 2
        let holeMass = 60.0
        let gravitationalConstant = holeMass * 200

        addParticle(
            x: centreX - 130, y: centreY, velocityX: 0, velocityY: 0, radius: 12, mass: holeMass,
            color: PackedColor(r: 0xEC, g: 0x48, b: 0x99),
            isFixed: true, ignoresGravity: true, kind: .blackhole
        )
        addParticle(
            x: centreX + 130, y: centreY, velocityX: 0, velocityY: 0, radius: 12, mass: holeMass,
            color: PackedColor(r: 0x3B, g: 0x82, b: 0xF6),
            isFixed: true, ignoresGravity: true, kind: .blackhole
        )

        for i in 0 ..< count {
            let angle = rng.next() * Double.pi * 2
            let distance = rng.next() * 180 + 30
            let orbitalSpeed = (gravitationalConstant / distance).squareRoot() * (0.95 + rng.next() * 0.1)

            addParticle(
                x: centreX + jsCos(angle) * distance,
                y: centreY + jsSin(angle) * distance,
                velocityX: -jsSin(angle) * orbitalSpeed,
                velocityY: jsCos(angle) * orbitalSpeed,
                radius: 2,
                color: PackedColor(hue: Double(i * 7).truncatingRemainder(dividingBy: 360), saturation: 0.95, lightness: 0.70),
                ignoresGravity: true,
                originX: centreX,
                originY: centreY
            )
        }
    }

    /// A column of liquid poured from above.
    public func spawnPour(count: Int = 400) {
        clear()
        gravityY = 0.38
        fluidEnabled = true
        collisionsEnabled = true
        let centreX = width * 0.5
        for _ in 0 ..< count {
            addParticle(
                x: centreX + (rng.next() - 0.5) * 40,
                y: 20 + rng.next() * 40,
                velocityX: (rng.next() - 0.5) * 0.4,
                velocityY: 0.4 + rng.next(),
                radius: 2.4,
                color: PackedColor(hue: 200 + rng.next() * 30, saturation: 0.80, lightness: 0.65)
            )
        }
    }

    /// A scattered flock that finds its own formation.
    public func spawnFlock(count: Int = 220) {
        clear()
        gravityY = 0
        flockEnabled = true
        for _ in 0 ..< count {
            addParticle(
                x: rng.next() * width,
                y: rng.next() * height,
                velocityX: (rng.next() - 0.5) * 3,
                velocityY: (rng.next() - 0.5) * 3,
                radius: 2.2,
                color: PackedColor(hue: 140 + rng.next() * 50, saturation: 0.80, lightness: 0.62)
            )
        }
    }

    /// A rotating cloud of equal masses.
    public func spawnNbody(count: Int = 240) {
        clear()
        gravityY = 0
        nbodyEnabled = true
        let centreX = width / 2
        let centreY = height / 2
        for i in 0 ..< count {
            let angle = rng.next() * Double.pi * 2
            let distance = 30 + rng.next() * min(width, height) * 0.3
            addParticle(
                x: centreX + jsCos(angle) * distance,
                y: centreY + jsSin(angle) * distance,
                velocityX: -jsSin(angle) * 1.4,
                velocityY: jsCos(angle) * 1.4,
                radius: 2,
                mass: 1,
                color: PackedColor(hue: Double(i * 9).truncatingRemainder(dividingBy: 360), saturation: 0.90, lightness: 0.65)
            )
        }
    }

    /// A pinned sheet of sprung nodes.
    public func spawnCloth(cols: Int = 16, rows: Int = 12) {
        clear()
        gravityY = 0.35
        springs.removeAll(keepingCapacity: true)
        guard cols > 0, rows > 0 else { return }

        let gap = Double(min(18, Int((width / Double(cols + 2)).rounded(.down))))
        let originX = (width - Double(cols) * gap) / 2
        let originY = 36.0
        let start = particles.count

        for row in 0 ..< rows {
            for column in 0 ..< cols {
                addParticle(
                    x: originX + Double(column) * gap,
                    y: originY + Double(row) * gap,
                    velocityX: 0,
                    velocityY: 0,
                    radius: 2.4,
                    color: PackedColor(hue: 200 + Double(column) * 4, saturation: 0.70, lightness: 0.70),
                    // The top row is pinned at its corners and every fourth node.
                    isFixed: row == 0 && (column == 0 || column == cols - 1 || column % 4 == 0)
                )
            }
        }

        func index(_ column: Int, _ row: Int) -> Int { start + row * cols + column }
        for row in 0 ..< rows {
            for column in 0 ..< cols {
                if column + 1 < cols {
                    springs.append(Spring(a: index(column, row), b: index(column + 1, row), rest: gap, k: 0.18))
                }
                if row + 1 < rows {
                    springs.append(Spring(a: index(column, row), b: index(column, row + 1), rest: gap, k: 0.18))
                }
            }
        }
    }

    /// A chain hanging from a pinned top node.
    public func spawnRope(length: Int = 32) {
        clear()
        gravityY = 0.4
        springs.removeAll(keepingCapacity: true)
        guard length > 0 else { return }

        let centreX = width / 2
        let gap = 10.0
        let start = particles.count

        for i in 0 ..< length {
            addParticle(
                x: centreX,
                y: 24 + Double(i) * gap,
                velocityX: 0,
                velocityY: 0,
                radius: 2.6,
                color: PackedColor(r: 0xE7, g: 0xE5, b: 0xE4),
                isFixed: i == 0
            )
        }
        for i in 0 ..< (length - 1) {
            springs.append(Spring(a: start + i, b: start + i + 1, rest: gap, k: 0.28))
        }
    }

    /// A ring of nodes held in a blob by rim and cross springs.
    public func spawnBlob(nodes: Int = 24) {
        clear()
        gravityY = 0.22
        springs.removeAll(keepingCapacity: true)
        guard nodes > 1 else { return }

        let centreX = width / 2
        let centreY = height * 0.4
        let radius = 42.0
        let start = particles.count

        for i in 0 ..< nodes {
            let angle = (Double(i) / Double(nodes)) * Double.pi * 2
            addParticle(
                x: centreX + jsCos(angle) * radius,
                y: centreY + jsSin(angle) * radius,
                velocityX: 0,
                velocityY: 0,
                radius: 3,
                color: PackedColor(hue: 320 + Double(i) * 3, saturation: 0.80, lightness: 0.68)
            )
        }
        for i in 0 ..< nodes {
            // Around the rim, holding its shape.
            springs.append(Spring(
                a: start + i,
                b: start + ((i + 1) % nodes),
                rest: (2 * Double.pi * radius) / Double(nodes),
                k: 0.22
            ))
            // Across the middle, much slacker, so it squashes rather than folding.
            springs.append(Spring(
                a: start + i,
                b: start + ((i + nodes / 2) % nodes),
                rest: radius * 2,
                k: 0.05
            ))
        }
    }

    /// Drops a draggable gravity well into the current scene.
    public func placeWell(x: Double, y: Double) {
        addParticle(
            x: x, y: y, velocityX: 0, velocityY: 0, radius: 14, mass: 90,
            color: PackedColor(r: 0xFB, g: 0x71, b: 0x85),
            isFixed: true, ignoresGravity: true, kind: .blackhole
        )
    }

    /// Scatters a large number of bodies into the swarm, or into the object list when
    /// the count is small enough to be worth the extra per-body behaviour.
    public func spawnBatch(count: Int, color: PackedColor? = nil) {
        pushUndo()

        // Above this it goes to the swarm, which is the whole reason the swarm exists.
        if count >= 4000 {
            // The limit covers the whole field, so the objects already present come out
            // of it. The web version handed the swarm the full limit regardless, so the
            // two together could exceed what the user asked for.
            let budget = max(0, maxParticles - particles.count)
            swarm.spawn(
                count: count,
                width: width,
                height: height,
                color: color?.packedRGBA ?? 0,
                budget: budget,
                rng: &rng
            )
            return
        }

        let spaceLeft = maxParticles - particles.count - swarm.count
        let toSpawn = min(count, max(0, spaceLeft))
        guard toSpawn > 0 else { return }

        let centreX = width / 2
        let centreY = height / 2

        // Orbit an existing black hole if there is one, so a batch dropped into a
        // galaxy joins the disc instead of falling through it.
        var holeX = centreX
        var holeY = centreY
        var gravitationalConstant = 0.0
        if let hole = particles.first(where: { $0.kind == .blackhole }) {
            holeX = hole.x
            holeY = hole.y
            gravitationalConstant = hole.mass * 200
        }

        for i in 0 ..< toSpawn {
            let angle = rng.next() * Double.pi * 2
            let distance = rng.next() * (min(width, height) * 0.42) + 25
            let pointX = min(width - 2, max(2, holeX + jsCos(angle) * distance))
            let pointY = min(height - 2, max(2, holeY + jsSin(angle) * distance))

            var velocityX = (rng.next() - 0.5) * 6
            var velocityY = (rng.next() - 0.5) * 6
            var ignoresGravity = false

            if gravitationalConstant > 0 {
                let orbitalSpeed = (gravitationalConstant / max(10, distance)).squareRoot() * (0.95 + rng.next() * 0.1)
                velocityX = -jsSin(angle) * orbitalSpeed
                velocityY = jsCos(angle) * orbitalSpeed
                ignoresGravity = true
            }

            addParticle(
                x: pointX,
                y: pointY,
                velocityX: velocityX,
                velocityY: velocityY,
                radius: 1.5,
                mass: 1,
                charge: i % 2 == 0 ? 1 : -1,
                color: color ?? PackedColor(
                    hue: Double(i * 137).truncatingRemainder(dividingBy: 360),
                    saturation: 0.85, lightness: 0.65
                ),
                ignoresGravity: ignoresGravity,
                originX: holeX,
                originY: holeY
            )
        }
    }
}
