// Lightning: seek water, ride conductors, then burn.
//
// Ported from web/src/sim/powder/electricity.ts.

/// Elements a spark treats as water and is drawn toward.
///
/// Oil used to be in this list, which meant a spark treated the most flammable
/// liquid in the game as if it were water and could never set it alight — the wet
/// branch runs before the ignition branch and returns. Removed, so lightning now
/// ignites oil as its description promises.
@inlinable
func isWet(_ elementID: ElementID) -> Bool {
    elementID == Element.water
        || elementID == Element.saltWater
        || elementID == Element.mercury
}

extension PowderEngine {
    /// How large the connected run of conductor — wire, copper or mercury — is,
    /// counting from a starting cell and giving up at eighty.
    ///
    /// Salt water conducts a strike but is deliberately not part of the load network.
    ///
    /// The size acts as electrical load: a long wire run gets hotter and is more
    /// likely to burn out than a short one.
    ///
    /// The cap is what keeps this affordable — without it, a screen-filling web of
    /// wire would be flood-filled from every spark, every tick. The traversal order
    /// is last-in-first-out, matching the original, which matters because the cap
    /// makes the *order* decide which cells get counted before it is reached.
    func conductorLoad(x: Int, y: Int) -> Int {
        var seen = Set<Int>()
        var stack = [index(x, y)]
        var found = 0

        // The cap is checked before popping, matching the original's loop
        // condition, so the traversal stops at exactly the same point.
        while found < 80, let i = stack.popLast() {
            if seen.contains(i) { continue }
            seen.insert(i)

            let cellType = type[i]
            guard cellType == Element.metal || cellType == Element.copper || cellType == Element.mercury
            else { continue }
            found += 1

            let cx = i % width
            let cy = i / width
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx
                let ny = cy + dy
                guard isValid(nx, ny) else { continue }
                stack.append(index(nx, ny))
            }
        }
        return found
    }

    /// Whether anything explosive sits within two cells, which turns an
    /// electrified wire into a detonator.
    func wireHasBoom(x: Int, y: Int) -> Bool {
        for dy in -2 ... 2 {
            for dx in -2 ... 2 {
                guard isValid(x + dx, y + dy) else { continue }
                switch type[index(x + dx, y + dy)] {
                case Element.c4, Element.gunpowder, Element.nitro, Element.hydrogen:
                    return true
                default:
                    break
                }
            }
        }
        return false
    }

    /// Steers a spark toward the most attractive thing nearby and resolves what
    /// happens when it arrives.
    ///
    /// Preference order is water, then flammable material, then conductor — which
    /// is why lightning in this world reliably finds a puddle.
    ///
    /// - Returns: `true` if the spark was consumed and should not also move.
    func steerSpark(x: Int, y: Int, idx: Int) -> Bool {
        // Look for a target within five cells and score by kind and closeness.
        var bestX = x
        var bestY = y
        // Starts at zero, not minus one. At minus one the first non-empty neighbour
        // scoring zero — inert stone, say — became the "target", which aimed the step
        // direction at a wall and left the spark unable to move while still believing
        // it had found something worth travelling to.
        var best = 0.0
        let searchRadius = 5

        for dy in -searchRadius ... searchRadius {
            for dx in -searchRadius ... searchRadius {
                if dx == 0 && dy == 0 { continue }
                let nx = x + dx
                let ny = y + dy
                guard isValid(nx, ny) else { continue }

                let neighbourType = type[index(nx, ny)]
                if neighbourType == Element.empty || neighbourType == Element.spark
                    || neighbourType == Element.bedrock
                {
                    continue
                }

                let distance = Double(abs(dx) + abs(dy))
                let neighbour = elements[neighbourType]

                // An else-chain, not independent tests: something wet is scored as
                // wet even when it also conducts, which is what keeps water the
                // first choice.
                var score = 0.0
                if isWet(neighbourType) {
                    score = 90 - distance * 8
                } else if neighbour.isConductor || neighbourType == Element.metal || neighbourType == Element.copper {
                    score = 55 - distance * 5
                } else if neighbour.flammability > 20 {
                    score = 70 - distance * 6
                }

                if score > best {
                    best = score
                    bestX = nx
                    bestY = ny
                }
            }
        }

        let stepX = bestX > x ? 1 : (bestX < x ? -1 : 0)
        let stepY = bestY > y ? 1 : (bestY < y ? -1 : 0)

        // Try the cells heading toward the target first, then every neighbour — each one once.
        //
        // The list used to repeat entries on the claim that the first one to resolve wins. That holds for water
        // and fuel, which stop the search, but not for wire, which carries on: with the target straight
        // across, the cell beside the spark appeared three times, so one wire cell was flooded three times,
        // could hop up to three sparks, and rolled to burn out three times — nearly a one-in-three chance
        // rather than the one-in-eight intended.
        let ordered: [(Int, Int)] = [
            (x + stepX, y + stepY),
            (x + stepX, y),
            (x, y + stepY),
            (x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1),
            (x + 1, y + 1), (x + 1, y - 1), (x - 1, y + 1), (x - 1, y - 1),
        ]
        var candidates: [(Int, Int)] = []
        candidates.reserveCapacity(ordered.count)
        for entry in ordered where !candidates.contains(where: { $0 == entry }) {
            candidates.append(entry)
        }

        for (nx, ny) in candidates {
            guard isValid(nx, ny), !(nx == x && ny == y) else { continue }
            let neighbourIdx = index(nx, ny)
            let neighbourType = type[neighbourIdx]
            let neighbour = elements[neighbourType]

            // Hitting water: flash it to steam and keep the spark alive so the
            // strike continues rather than stopping at the surface.
            if isWet(neighbourType) {
                temperature[neighbourIdx] = JS.toFloat32(max(temperature[neighbourIdx].asDouble, 140))
                if neighbourType == Element.water || neighbourType == Element.saltWater {
                    setElement(nx, ny, Element.steam, temp: 130, life: 70)
                    velocityY[neighbourIdx] = -2
                }
                // Stays hot, but its lifetime is left alone. The original re-stamped
                // the spark every tick, which made it immortal beside anything wet —
                // and beside mercury, which is never converted to steam, it also
                // seeded a brand-new spark every tick, forever.
                temperature[idx] = JS.toFloat32(1000)

                // Push a fresh spark one cell further along, so a strike forks
                // through a body of water instead of stopping dead.
                if isValid(nx + stepX, ny + stepY) {
                    let forwardIdx = index(nx + stepX, ny + stepY)
                    if type[forwardIdx] == Element.empty {
                        setElement(nx + stepX, ny + stepY, Element.spark, temp: 1000, life: 8)
                        visited[forwardIdx] = 1
                    }
                }
                return false
            }

            // Hitting fuel: ignite it, or detonate it if it is explosive. Wire and
            // copper are excluded even if flammable, so they are handled as
            // conductors below.
            if neighbour.flammability > 15 && neighbourType != Element.metal && neighbourType != Element.copper {
                switch neighbourType {
                case Element.gunpowder, Element.c4, Element.nitro, Element.hydrogen:
                    triggerExplosion(
                        centerX: nx,
                        centerY: ny,
                        radius: neighbourType == Element.c4 ? 18 : 14,
                        shockwaveForce: 18,
                        maxHeat: 2500
                    )
                default:
                    setElement(nx, ny, Element.fire, temp: 700, life: 28)
                }
                setElement(x, y, Element.fire, temp: 500, life: 8)
                return true
            }

            // Hitting wire: heat it in proportion to how much wire is attached,
            // then hop the charge onward.
            if neighbour.isConductor || neighbourType == Element.metal || neighbourType == Element.copper {
                let load = conductorLoad(x: nx, y: ny)
                temperature[neighbourIdx] = JS.toFloat32(
                    max(temperature[neighbourIdx].asDouble, 900 + Double(load) * 12)
                )

                // An overloaded run occasionally burns out.
                if load > 16 && rng.chance(0.12) {
                    setElement(nx, ny, Element.fire, temp: 800, life: 18)
                    setElement(x, y, Element.fire, temp: 500, life: 8)
                    return true
                }

                // Wire next to explosives is a detonator, and a longer run makes a
                // bigger bang.
                if wireHasBoom(x: nx, y: ny) {
                    triggerExplosion(
                        centerX: nx,
                        centerY: ny,
                        radius: 12 + min(10, load),
                        shockwaveForce: 16,
                        maxHeat: 2200
                    )
                    return true
                }

                for (hopX, hopY) in [
                    (nx + stepX, ny + stepY),
                    (nx + 1, ny), (nx - 1, ny), (nx, ny + 1), (nx, ny - 1),
                ] {
                    guard isValid(hopX, hopY), !(hopX == x && hopY == y) else { continue }
                    let hopIdx = index(hopX, hopY)
                    if type[hopIdx] == Element.empty {
                        setElement(hopX, hopY, Element.spark, temp: 1000, life: 8)
                        visited[hopIdx] = 1
                        break
                    }
                }
                // Note: no return. A conductor contact does not end the search, so
                // the spark can still resolve against a later candidate.
            }

            // Empty space, but only worth crossing if something was actually found
            // to head toward.
            if neighbourType == Element.empty && best > 0 {
                swapCells(idx, neighbourIdx)
                life[neighbourIdx] = max(life[neighbourIdx], 8)
                return true
            }
        }

        return false
    }
}
