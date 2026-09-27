// Chemistry and per-element special behaviour.
//
// Ported from web/src/sim/powder/reactions.ts, the highest-fidelity-risk file in
// the whole project. The original is a long chain of independent `if` blocks
// keyed on raw element numbers, and it is not a table that could be converted
// mechanically — it is control flow, where the order of the blocks, which ones
// return early, and exactly when each random number is drawn all decide the
// outcome.
//
// Three rules were followed throughout:
//
//  1. **Named elements, never numbers.** The original says `if (type === 22)`. A
//     mistyped digit there compiles, runs, and quietly turns salt into
//     nitroglycerin. `Element.portalA` cannot be mistyped into something that
//     still compiles.
//  2. **Blocks stay in order and stay independent.** A cell can fall through
//     several of them in one tick. Merging them into a switch would look tidier
//     and would be wrong.
//  3. **Random draws happen at the same points.** Where the original
//     short-circuits and so sometimes does not draw, this does too.

extension PowderEngine {
    /// The four cells sharing an edge, in the order the original lists them for
    /// most reactions: below, left, right, above.
    ///
    /// The order is not cosmetic — most of these loops stop at the first match, so
    /// it decides which neighbour a reaction picks when several qualify. Checking
    /// below first is what makes things react downward by preference.
    @inline(__always)
    private func edgeNeighboursDownFirst(_ x: Int, _ y: Int) -> [(Int, Int)] {
        [(x, y + 1), (x - 1, y), (x + 1, y), (x, y - 1)]
    }

    /// The four edge neighbours, above first. Used by reactions that reach upward,
    /// such as plant growth.
    @inline(__always)
    private func edgeNeighboursUpFirst(_ x: Int, _ y: Int) -> [(Int, Int)] {
        [(x, y - 1), (x - 1, y), (x + 1, y), (x, y + 1)]
    }

    /// The four edge neighbours, vertical pair first: above, below, left, right.
    /// Used where the original reaches up and down before sideways.
    @inline(__always)
    private func edgeNeighboursVerticalFirst(_ x: Int, _ y: Int) -> [(Int, Int)] {
        [(x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y)]
    }

    /// All eight surrounding cells.
    @inline(__always)
    private func allNeighbours(_ x: Int, _ y: Int) -> [(Int, Int)] {
        [
            (x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y),
            (x - 1, y - 1), (x + 1, y - 1), (x - 1, y + 1), (x + 1, y + 1),
        ]
    }

    /// Runs one cell's chemistry.
    ///
    /// - Returns: `true` if the cell was consumed or transformed, in which case it
    ///   does not also move this tick.
    func updateReactions(
        x: Int,
        y: Int,
        idx: Int,
        definition: ElementPhysics,
        portalsB: [(Int, Int)]
    ) -> Bool {
        let cellType = definition.id

        // MARK: Heat sources — fire, lava, thermite, plasma, lasers

        // Dispatched on identifiers and state, never on the element's name. The
        // original also tested `name.contains("Laser")`, which let any custom element
        // named after a laser inherit these thermal effects.
        let isHeatSource = cellType == Element.fire
            || cellType == Element.lava
            || cellType == Element.thermite
            || cellType == Element.plasma
            || cellType == Element.laser
            || definition.state == .energy

        if isHeatSource {
            // Everything but lava stokes itself. Lava is excluded because it is a
            // thermal mass that should only ever lose heat — self-heating would
            // stop it from ever setting into obsidian.
            if cellType != Element.lava {
                temperature[idx] = JS.toFloat32(
                    min(3000, temperature[idx].asDouble + (cellType == Element.laser ? 80 : 20))
                )
            }

            for (nx, ny) in allNeighbours(x, y) {
                guard isValid(nx, ny) else { continue }
                let neighbourIdx = index(nx, ny)
                let neighbourType = type[neighbourIdx]
                if neighbourType == Element.empty { continue }

                let neighbour = elements[neighbourType]

                // Meeting water.
                if neighbourType == Element.water || neighbourType == Element.saltWater {
                    if cellType == Element.lava {
                        quenchLava(lavaIdx: idx, waterIdx: neighbourIdx)
                        // The lava may have set into obsidian, in which case this
                        // cell is finished.
                        if type[idx] != Element.lava { return true }
                        continue
                    } else if definition.state == .energy {
                        setElement(nx, ny, Element.steam, temp: max(120, temperature[neighbourIdx].asDouble))
                    } else if cellType == Element.fire {
                        // Fire loses: water puts it out and takes its place.
                        setElement(x, y, Element.steam, temp: 120)
                        return true
                    }
                }

                // Steam beside lava keeps pulling heat out of it, in proportion to
                // how much hotter the lava is. This is what finishes the job after
                // the water has already boiled away: without the proportional term a
                // lava blob that has skinned over stalls near 1100°C and never
                // crosses the 700°C threshold.
                if cellType == Element.lava && neighbourType == Element.steam {
                    temperature[idx] = JS.toFloat32(
                        temperature[idx].asDouble
                            - (55 + max(0, temperature[idx].asDouble - temperature[neighbourIdx].asDouble) * 0.18)
                    )
                    temperature[neighbourIdx] = JS.toFloat32(max(temperature[neighbourIdx].asDouble, 110))
                    if temperature[idx].asDouble < 700 {
                        setElement(x, y, Element.obsidian, temp: max(180, temperature[idx].asDouble))
                        return true
                    }
                }

                // Heat also bleeds out through an obsidian crust, which is how a
                // partly-set flow keeps cooling from the inside.
                if cellType == Element.lava && neighbourType == Element.obsidian {
                    let flow = (temperature[idx].asDouble - temperature[neighbourIdx].asDouble) * 0.28
                    temperature[idx] = JS.toFloat32(temperature[idx].asDouble - flow)
                    temperature[neighbourIdx] = JS.toFloat32(temperature[neighbourIdx].asDouble + flow)
                    if temperature[idx].asDouble < 700 {
                        setElement(x, y, Element.obsidian, temp: max(180, temperature[idx].asDouble))
                        return true
                    }
                }

                // Ice: a laser or thermite flashes it straight to steam, anything
                // else just melts it.
                if neighbourType == Element.ice {
                    if cellType == Element.laser || cellType == Element.thermite {
                        setElement(nx, ny, Element.steam, temp: 140)
                    } else {
                        setElement(nx, ny, Element.water, temp: 8)
                    }
                }

                // Lava and lasers work on sand and stone: sand occasionally fuses to
                // glass, and very hot lava can melt stone back into more lava.
                if cellType == Element.lava || cellType == Element.laser {
                    if neighbourType == Element.sand, rng.chance(0.08) {
                        setElement(nx, ny, Element.glass)
                    }
                    if neighbourType == Element.stone, temperature[idx].asDouble > 1100, rng.chance(0.02) {
                        setElement(nx, ny, Element.lava, temp: 1200)
                    }
                }

                // Ignition. The draw only happens for something that can burn at
                // all, and the more flammable it is the likelier it catches.
                if neighbour.flammability > 0 && rng.percentChance(neighbour.flammability) {
                    switch neighbourType {
                    case Element.gunpowder, Element.nitro, Element.oil, Element.hydrogen:
                        // Volatile things detonate instead of merely burning, each
                        // with its own yield.
                        //
                        // Oxygen and helium were listed here too, with their own blast
                        // radii, but neither carries a flammability value in the
                        // registry — so this branch could never be reached for them and
                        // those radii were dead constants. Removed rather than given
                        // invented flammability; helium is inert in any case.
                        let blastRadius: Int
                        switch neighbourType {
                        case Element.nitro: blastRadius = 26
                        case Element.hydrogen: blastRadius = 22
                        default: blastRadius = 16
                        }
                        triggerExplosion(
                            centerX: nx, centerY: ny,
                            radius: blastRadius, shockwaveForce: 22, maxHeat: 3000
                        )
                    default:
                        setElement(nx, ny, Element.fire, temp: 400)
                    }
                }
            }
        }

        // MARK: Hot obsidian still boils water

        // A crust that is still glowing keeps flashing water to steam, which drains
        // the last of the heat out of a flow that has already set.
        if cellType == Element.obsidian && temperature[idx].asDouble > 320 {
            for (nx, ny) in edgeNeighboursVerticalFirst(x, y) {
                guard isValid(nx, ny) else { continue }
                let neighbourIdx = index(nx, ny)
                let neighbourType = type[neighbourIdx]
                if neighbourType == Element.water || neighbourType == Element.saltWater {
                    setElement(nx, ny, Element.steam, temp: 130, life: 80)
                    velocityY[neighbourIdx] = -2
                    temperature[idx] = JS.toFloat32(temperature[idx].asDouble - 90)
                }
            }
        }

        // MARK: Electricity

        if cellType == Element.spark {
            if steerSpark(x: x, y: y, idx: idx) { return true }
        }

        // MARK: Acid

        if cellType == Element.acid {
            for (nx, ny) in edgeNeighboursDownFirst(x, y) {
                guard isValid(nx, ny) else { continue }
                let neighbourIdx = index(nx, ny)
                let neighbourType = type[neighbourIdx]

                // Glass and bedrock are immune, and acid does not eat acid.
                if neighbourType != Element.empty && neighbourType != Element.acid
                    && neighbourType != Element.glass && neighbourType != Element.bedrock
                {
                    let neighbour = elements[neighbourType]
                    // Resistance is a percentage chance of shrugging it off. The
                    // draw is skipped entirely for something with no resistance,
                    // which always dissolves.
                    if neighbour.acidResistance <= 0 || rng.next() * 100 > neighbour.acidResistance {
                        setElement(nx, ny, Element.smoke)
                        setElement(x, y, Element.empty)
                        return true
                    }
                }
            }
        }

        // MARK: Virus

        if cellType == Element.virus {
            for (nx, ny) in edgeNeighboursDownFirst(x, y) {
                guard isValid(nx, ny) else { continue }
                let neighbourType = type[index(nx, ny)]
                if neighbourType != Element.empty && neighbourType != Element.virus
                    && neighbourType != Element.bedrock && neighbourType != Element.glass
                {
                    if rng.chance(0.15) {
                        setElement(nx, ny, Element.virus)
                    }
                }
            }
        }

        // MARK: Ants

        if cellType == Element.ant {
            // One random direction per tick, which is what makes them wander rather
            // than march.
            let directions = [(1, 0), (-1, 0), (0, 1), (0, -1)]
            let direction = directions[rng.int(below: 4)]
            let nx = x + direction.0
            let ny = y + direction.1
            if isValid(nx, ny) {
                let neighbourIdx = index(nx, ny)
                let neighbourType = type[neighbourIdx]
                if neighbourType == Element.empty {
                    swapCells(idx, neighbourIdx)
                    return true
                }
                // Tunnelling: they slowly eat through wood, soil and plants.
                if neighbourType == Element.wood || neighbourType == Element.dirt || neighbourType == Element.plant {
                    if rng.chance(0.08) {
                        setElement(nx, ny, Element.empty)
                    }
                }
            }
        }

        // MARK: Wax

        if cellType == Element.wax {
            for (nx, ny) in edgeNeighboursVerticalFirst(x, y) {
                guard isValid(nx, ny) else { continue }
                let neighbourType = type[index(nx, ny)]
                if neighbourType == Element.fire || neighbourType == Element.lava || neighbourType == Element.thermite {
                    // Melts into honey, which is the engine's thick-liquid element.
                    setElement(x, y, Element.honey, temp: 80)
                    return true
                }
            }
        }

        // MARK: Dirt becomes mud

        if cellType == Element.dirt {
            for (nx, ny) in edgeNeighboursDownFirst(x, y) {
                guard isValid(nx, ny) else { continue }
                if type[index(nx, ny)] == Element.water, rng.chance(0.12) {
                    setElement(x, y, Element.mud)
                    setElement(nx, ny, Element.empty)
                    return true
                }
            }
        }

        // MARK: Ice spreads through cold water

        if cellType == Element.ice {
            for (nx, ny) in edgeNeighboursDownFirst(x, y) {
                guard isValid(nx, ny) else { continue }
                let neighbourIdx = index(nx, ny)
                if type[neighbourIdx] == Element.water,
                   temperature[neighbourIdx].asDouble < 8,
                   rng.chance(0.04)
                {
                    setElement(nx, ny, Element.ice, temp: -10)
                }
            }
        }

        // MARK: Plants drink

        if cellType == Element.plant {
            // Gated like every other growth and spread rule in the engine (seed
            // 0.25, virus 0.15, dirt 0.12, ant 0.08, ice 0.04). Ungated — as the
            // original was — a plant converted an adjacent water cell every single
            // tick, so a pond beside a plant filled effectively instantly instead of
            // creeping across it.
            for (nx, ny) in edgeNeighboursUpFirst(x, y) {
                guard isValid(nx, ny) else { continue }
                if type[index(nx, ny)] == Element.water, rng.chance(0.25) {
                    // The water is consumed and becomes new growth.
                    setElement(nx, ny, Element.plant)
                    break
                }
            }
        }

        // MARK: Void

        if cellType == Element.void {
            for (nx, ny) in allNeighbours(x, y) {
                guard isValid(nx, ny) else { continue }
                let neighbourIdx = index(nx, ny)
                if type[neighbourIdx] != Element.empty && type[neighbourIdx] != Element.void {
                    setElement(nx, ny, Element.empty)
                    // Leaves suction behind, so material is drawn in rather than
                    // merely deleted where it happens to touch.
                    pressure[neighbourIdx] = JS.toFloat32(-8)
                }
            }
        }

        // MARK: Fans

        if cellType == Element.fan {
            // The rotation is stored in the lifetime slot; painting over a fan
            // advances it.
            let rotation = Int(life[idx]) % 4
            let offsetX = rotation == 0 ? 1 : (rotation == 1 ? 0 : (rotation == 2 ? -1 : 0))
            let offsetY = rotation == 0 ? 0 : (rotation == 1 ? 1 : (rotation == 2 ? 0 : -1))

            // Blows four cells along its facing, stopping at bedrock or another fan.
            for reach in 1 ... 4 {
                let nx = x + offsetX * reach
                let ny = y + offsetY * reach
                guard isValid(nx, ny) else { break }
                let neighbourIdx = index(nx, ny)
                let neighbourType = type[neighbourIdx]
                if neighbourType == Element.bedrock || neighbourType == Element.fan { break }

                let neighbour = elements[neighbourType]
                if neighbourType == Element.empty {
                    // Empty space just gets pressurised, which is what draws gas
                    // along the stream.
                    pressure[neighbourIdx] = JS.toFloat32(pressure[neighbourIdx].asDouble + 1.4)
                    continue
                }

                if neighbour.state == .gas || neighbour.state == .plasma || neighbour.density < 16 {
                    velocityX[neighbourIdx] = JS.toInt8(
                        max(-20, min(20, velocityX[neighbourIdx].asDouble + Double(offsetX) * 5))
                    )
                    velocityY[neighbourIdx] = JS.toInt8(
                        max(-20, min(20, velocityY[neighbourIdx].asDouble + Double(offsetY) * 5))
                    )
                    pressure[neighbourIdx] = JS.toFloat32(pressure[neighbourIdx].asDouble + 2)

                    let aheadX = nx + offsetX
                    let aheadY = ny + offsetY
                    if isValid(aheadX, aheadY),
                       type[index(aheadX, aheadY)] == Element.empty,
                       rng.chance(0.45)
                    {
                        swapCells(neighbourIdx, index(aheadX, aheadY))
                    }
                } else {
                    // Too heavy to blow. The airflow stops at it, rather than carrying
                    // on and pressurising cells on the far side of a solid wall — the
                    // original matched neither branch for stone, metal, concrete or
                    // glass, so the loop simply continued straight through.
                    break
                }
            }
        }

        // MARK: Water erodes

        // Flowing water carves sand and soil and carries it downstream. Gated on a
        // low probability, so this is a slow sculpting effect rather than the water
        // instantly dissolving any bank it touches.
        if cellType == Element.water && rng.chance(0.06) {
            let gravityDirection = JS.signOrFallback(gravityY, fallback: 1)
            let spots = [
                (x, y + gravityDirection),
                (x - 1, y + gravityDirection),
                (x + 1, y + gravityDirection),
                (x - 1, y),
                (x + 1, y),
            ]
            for (nx, ny) in spots {
                guard isValid(nx, ny) else { continue }
                let neighbourIdx = index(nx, ny)
                let neighbourType = type[neighbourIdx]
                if neighbourType == Element.sand || neighbourType == Element.dirt {
                    let dumpX = x + (rng.chance(0.5) ? -1 : 1)
                    let dumpY = y + gravityDirection
                    if isValid(dumpX, dumpY), type[index(dumpX, dumpY)] == Element.empty {
                        swapCells(neighbourIdx, index(dumpX, dumpY))
                    } else if neighbourType == Element.dirt, rng.chance(0.35) {
                        setElement(nx, ny, Element.mud)
                    }
                    break
                }
            }
        }

        // MARK: Cloners

        if cellType == Element.clone {
            let neighbours = edgeNeighboursUpFirst(x, y)

            // Latches onto the first thing it finds touching it.
            var sourceID = Element.empty
            for (nx, ny) in neighbours {
                guard isValid(nx, ny) else { continue }
                let neighbourType = type[index(nx, ny)]
                if neighbourType != Element.empty && neighbourType != Element.clone {
                    sourceID = neighbourType
                    break
                }
            }

            if sourceID != Element.empty {
                for (nx, ny) in neighbours {
                    if isValid(nx, ny), type[index(nx, ny)] == Element.empty {
                        setElement(nx, ny, sourceID)
                        break
                    }
                }
            }
        }

        // MARK: Portals

        if cellType == Element.portalA && !portalsB.isEmpty {
            for (nx, ny) in edgeNeighboursUpFirst(x, y) {
                guard isValid(nx, ny) else { continue }
                let neighbourIdx = index(nx, ny)
                let passengerType = type[neighbourIdx]
                if passengerType != Element.empty && passengerType != Element.portalA
                    && passengerType != Element.portalB
                {
                    // With several exits, one is picked at random.
                    let destination = portalsB[rng.int(below: portalsB.count)]
                    let exits = [
                        (destination.0, destination.1 - 1),
                        (destination.0 + 1, destination.1),
                        (destination.0 - 1, destination.1),
                        (destination.0, destination.1 + 1),
                    ]
                    for (tx, ty) in exits {
                        if isValid(tx, ty), type[index(tx, ty)] == Element.empty {
                            setElement(tx, ty, passengerType)
                            setElement(nx, ny, Element.empty)
                            break
                        }
                    }
                }
            }
        }

        // MARK: Declarative rules

        // The mechanism user-authored elements use. Only four of these exist among
        // the built-ins, on salt, snow and seed.
        //
        if definition.hasInteractions {
            let neighbours = edgeNeighboursDownFirst(x, y)
            for rule in elements.interactions(for: cellType) {
                // Tested with a greater-than, so a probability of exactly 1 always
                // passes.
                if rng.next() > rule.chance { continue }

                for (nx, ny) in neighbours {
                    guard isValid(nx, ny) else { continue }
                    let neighbourIdx = index(nx, ny)
                    if type[neighbourIdx] == rule.targetElementID {
                        var acted = false

                        if let resultSelf = rule.resultSelfID {
                            setElement(x, y, resultSelf)
                            acted = true
                        }
                        if let resultTarget = rule.resultTargetID {
                            setElement(nx, ny, resultTarget)
                            acted = true
                        }

                        // Heat released or absorbed by the reaction. Declared on the
                        // rule type and documented, but the original never read it.
                        if rule.tempChange != 0 {
                            temperature[idx] = JS.toFloat32(temperature[idx].asDouble + rule.tempChange)
                            temperature[neighbourIdx] = JS.toFloat32(
                                temperature[neighbourIdx].asDouble + rule.tempChange
                            )
                            acted = true
                        }

                        // A third element produced into nearby free space. Also
                        // declared, documented, and previously ignored.
                        if let spawn = rule.spawnElementID {
                            for (spawnX, spawnY) in neighbours {
                                if isValid(spawnX, spawnY), type[index(spawnX, spawnY)] == Element.empty {
                                    setElement(spawnX, spawnY, spawn)
                                    acted = true
                                    break
                                }
                            }
                        }

                        if rule.explosionRadius > 0 {
                            triggerExplosion(centerX: x, centerY: y, radius: rule.explosionRadius)
                            acted = true
                        }

                        // Only counts as handled if something actually happened. A rule
                        // with no effects used to report success anyway, which skipped
                        // movement and left the particle hovering in mid-air.
                        if acted { return true }
                    }
                }
            }
        }

        return false
    }
}
