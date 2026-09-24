// Explosions: a radial blast in three zones, ballistic embers, and a smoke plume.
//
// Ported from web/src/sim/powder/explosion.ts.
//
// This is the single largest consumer of random numbers in the simulation, and the
// order of those draws is preserved exactly. A draw that happens conditionally in
// the original happens conditionally here, and one that happens regardless happens
// regardless — including the two velocity draws that are taken before the code
// knows whether it will use them.

extension PowderEngine {
    /// Detonates at a point, remaking the surrounding cells and throwing them
    /// outward.
    ///
    /// - Parameters:
    ///   - radius: The blast core radius. The effect reaches twice this far.
    ///   - shockwaveForce: How hard material is thrown.
    ///   - maxHeat: Peak temperature at the centre, falling off with distance.
    public func triggerExplosion(
        centerX: Int,
        centerY: Int,
        radius: Int,
        shockwaveForce: Double = 22,
        maxHeat: Double = 3000
    ) {
        guard cellCount > 0 else { return }

        let radiusSquared = Double(radius * radius)
        let outerRadius = radius * 2
        let outerRadiusSquared = Double(outerRadius * outerRadius)

        // Zone 1: the blast itself. A zero radius still touches the centre cell,
        // matching the original; only a negative radius is rejected, and that
        // cannot be expressed as a range at all.
        if outerRadius >= 0 {
            for dy in -outerRadius ... outerRadius {
                for dx in -outerRadius ... outerRadius {
                    let x = centerX + dx
                    let y = centerY + dy
                    let distanceSquared = Double(dx * dx + dy * dy)
                    if distanceSquared > outerRadiusSquared || !isValid(x, y) { continue }

                    let idx = index(x, y)
                    let cellType = type[idx]

                    // Pressure spikes everywhere, even where nothing else happens —
                    // this is applied before the bedrock check, so a blast still
                    // pressurises against a bedrock wall.
                    pressure[idx] = JS.toFloat32(
                        pressure[idx].asDouble
                            + shockwaveForce * (1 - distanceSquared / (outerRadiusSquared + 1)) * 4
                    )

                    // Bedrock is completely blast-proof.
                    if cellType == Element.bedrock { continue }

                    // At the exact centre the distance is zero; a nominal value
                    // keeps the direction finite instead of dividing by zero.
                    let trueDistance = distanceSquared.squareRoot()
                    let distance = trueDistance == 0 ? 0.1 : trueDistance
                    let directionX = Double(dx) / distance
                    let directionY = Double(dy) / distance

                    let falloff = jsPow(max(0, 1 - distance / Double(outerRadius)), 0.8)
                    let force = falloff * shockwaveForce

                    // Both draws are taken unconditionally, before the zone is
                    // decided, exactly as in the original.
                    let velocityXValue = JS.round(directionX * force * (0.8 + rng.next() * 0.5))
                    let velocityYValue = JS.round(directionY * force * (0.8 + rng.next() * 0.5))

                    let heatPulse = JS.round(maxHeat * falloff)
                    temperature[idx] = JS.toFloat32(max(temperature[idx].asDouble, heatPulse))

                    if distanceSquared < radiusSquared * 0.25 {
                        // Crater core: everything is vaporised into plasma or flame.
                        //
                        // The original placed C4 explosive here while its comment
                        // said plasma, so every large blast seeded live charge at its
                        // own centre and explosions chained off their own debris.
                        setElement(
                            x, y,
                            rng.chance(0.7) ? Element.plasma : Element.fire,
                            temp: max(2800, heatPulse),
                            life: 35
                        )
                        velocityX[idx] = JS.toInt8(JS.round(velocityXValue * 1.5))
                        velocityY[idx] = JS.toInt8(JS.round(velocityYValue * 1.5))
                    } else if distanceSquared < radiusSquared * 0.85 {
                        // Fireball shell: material shatters, melts or catches.
                        if cellType != Element.empty {
                            switch cellType {
                            case Element.gunpowder, Element.nitro, Element.helium, Element.oil:
                                if rng.chance(0.8) {
                                    setElement(x, y, Element.fire, temp: 1800, life: 30)
                                }
                            case Element.water:
                                setElement(x, y, Element.steam, temp: 300, life: 60)
                            case Element.ice:
                                setElement(x, y, rng.chance(0.5) ? Element.water : Element.steam, temp: 150)
                            case Element.glass, Element.sand:
                                // Molten thermite or lava. The original's comment
                                // called 26 "sparks"; 26 is thermite, and hot
                                // incendiary debris is what was intended here.
                                setElement(x, y, rng.chance(0.6) ? Element.thermite : Element.lava, temp: 1200, life: 25)
                            case Element.wood:
                                setElement(x, y, rng.chance(0.7) ? Element.fire : Element.smoke, temp: 1400, life: 40)
                            default:
                                // Everything else breaks into burning debris, or
                                // merely smokes.
                                if rng.chance(0.6) {
                                    setElement(
                                        x, y,
                                        rng.chance(0.5) ? Element.fire : Element.thermite,
                                        temp: 1100,
                                        life: 30
                                    )
                                } else if rng.chance(0.4) {
                                    setElement(x, y, Element.smoke, temp: 300, life: 60)
                                }
                            }
                        } else if rng.chance(0.5) {
                            // Empty space fills with the expanding fireball.
                            setElement(x, y, rng.chance(0.6) ? Element.fire : Element.smoke, temp: 1200, life: 30)
                        }
                        velocityX[idx] = JS.toInt8(velocityXValue)
                        velocityY[idx] = JS.toInt8(velocityYValue)
                    } else {
                        // Outer shockwave: matter gets thrown, and anything flammable
                        // probably catches.
                        //
                        // Velocity is written only to cells that hold something. The
                        // original wrote it to empty air as well, where nothing ever
                        // damps it — the tick loop skips empty cells — and since
                        // swapping exchanges velocity, the next particle to drift
                        // into that cell inherited the stale shockwave and got
                        // launched long afterwards for no visible reason.
                        if cellType != Element.empty {
                            velocityX[idx] = JS.toInt8(JS.round(velocityXValue * 1.2))
                            velocityY[idx] = JS.toInt8(JS.round(velocityYValue * 1.2))

                            if elements[cellType].flammability > 0 && rng.chance(0.6) {
                                setElement(x, y, Element.fire, temp: 700, life: 30)
                            }
                        }
                    }
                }
            }
        }

        // Zone 2: embers thrown out in every direction.
        let emberCount = min(80, Int(Double(radius) * 1.8))
        for _ in 0 ..< max(0, emberCount) {
            // Both draws happen whether or not the ember lands on the grid.
            let angle = rng.next() * Double.pi * 2
            let speed = 8 + rng.next() * (shockwaveForce * 0.9)

            let emberX = Int(JS.round(Double(centerX) + jsCos(angle) * (Double(radius) * 0.4)))
            let emberY = Int(JS.round(Double(centerY) + jsSin(angle) * (Double(radius) * 0.4)))

            // Bedrock is blast-proof, and that has to hold here too. The radial blast
            // above skips it explicitly, but the ember phase used to overwrite it, so
            // flying debris could punch holes in a wall the explosion itself could
            // not touch.
            guard isValid(emberX, emberY), typeAt(emberX, emberY) != Element.bedrock else { continue }
            let emberIdx = index(emberX, emberY)
            let emberType = rng.chance(0.4) ? Element.thermite : Element.fire
            setElement(emberX, emberY, emberType, temp: 1600, life: 40 + rng.int(below: 30))
            velocityX[emberIdx] = JS.toInt8(JS.round(jsCos(angle) * speed))
            // Biased slightly upward, so debris arcs rather than skidding.
            velocityY[emberIdx] = JS.toInt8(JS.round(jsSin(angle) * speed - 2))
        }

        // Zone 3: a smoke plume, rising against gravity.
        //
        // The original hardcoded "up", so under inverted gravity it emitted the plume
        // into the ground while every other part of the engine respected gravity.
        let up = Double(-JS.signOrFallback(gravityY, fallback: 1))
        for _ in 0 ..< max(0, radius) {
            let smokeX = Int(JS.round(Double(centerX) + (rng.next() - 0.5) * Double(radius) * 1.2))
            let smokeY = Int(JS.round(Double(centerY) + up * (rng.next() * Double(radius) * 0.8)))
            guard isValid(smokeX, smokeY) else { continue }
            let smokeIdx = index(smokeX, smokeY)
            guard type[smokeIdx] == Element.empty else { continue }

            setElement(smokeX, smokeY, Element.smoke, temp: 250, life: 60 + rng.int(below: 40))
            velocityX[smokeIdx] = JS.toInt8(JS.round((rng.next() - 0.5) * 6))
            velocityY[smokeIdx] = JS.toInt8(JS.round(up * (4 + rng.next() * 6)))
        }

        // The app hears about this so it can shake the screen or make a noise. The
        // engine itself does neither.
        onBurst?(centerX, centerY, radius)
    }
}
