// Mechanical movement: gravity, buoyancy, viscosity, momentum, beam propagation.
//
// Ported from web/src/sim/powder/movement.ts. The structure is kept
// deliberately parallel to the original — same order of tests, same order of
// random draws, same early exits — because in a cellular automaton those are the
// behavior. Reordering two equivalent-looking checks changes which cell wins a
// contested space, and a pile leans differently.

extension PowderEngine {
    /// Attempts to move a cell into a neighbouring position, either because that
    /// position is empty or because density says the two should trade places.
    ///
    /// - Returns: `true` if the cell moved.
    @usableFromInline
    func tryMoveOrSwap(
        fromIdx: Int,
        fromY: Int,
        toX: Int,
        toY: Int,
        selfDensity: Double
    ) -> Bool {
        guard isValid(toX, toY) else { return false }
        let toIdx = index(toX, toY)
        // Already moved this tick: leave it alone or things move twice per tick.
        if visited[toIdx] != 0 { return false }

        let targetType = type[toIdx]

        if targetType == Element.empty {
            swapCells(fromIdx, toIdx)
            return true
        }

        // Displacing something that is already there. Fixed solids and the
        // special rule-breakers are immovable, so only the rest are candidates.
        let target = elements[targetType]
        if target.state != .solidFixed && target.state != .special {
            let gravityDirection = JS.signOrFallback(gravityY, fallback: 1)
            let moveDirection = toY > fromY ? 1 : (toY < fromY ? -1 : 0)

            let sinkingWithGravity = moveDirection == gravityDirection && selfDensity > target.density
            let floatingAgainstGravity = moveDirection == -gravityDirection && selfDensity < target.density

            if sinkingWithGravity || floatingAgainstGravity {
                // Not every eligible swap happens, which is what stops density
                // sorting from looking mechanical. Rising things are pushier than
                // sinking ones.
                if rng.chance(selfDensity < 0 ? 0.95 : 0.78) {
                    swapCells(fromIdx, toIdx)
                    return true
                }
            }
        }

        return false
    }

    /// Moves a cell sideways into genuinely empty space. Used for liquids
    /// levelling out, where displacing a neighbour is not wanted.
    @usableFromInline
    func tryMoveEmpty(fromIdx: Int, toX: Int, toY: Int) -> Bool {
        guard isValid(toX, toY) else { return false }
        let toIdx = index(toX, toY)
        if visited[toIdx] != 0 { return false }
        if type[toIdx] != Element.empty { return false }
        swapCells(fromIdx, toIdx)
        return true
    }

    /// Runs one cell's movement for this tick.
    func updateMovement(x: Int, y: Int, idx: Int, definition: ElementPhysics) {
        // Structural material with no gravity never moves under its own weight.
        // Note this does not exclude fixed solids that *do* have a gravity factor:
        // those can still be thrown by an explosion through the momentum pass
        // below, which is how blast debris works.
        if definition.gravityFactor == 0 && definition.state == .solidFixed { return }

        if moveByMomentum(x: x, y: y, idx: idx) { return }

        // Which way is "down" for this element. A negative gravity factor flips
        // it, so anti-gravity powder falls upward. When the product is zero —
        // weightlessness — gases and plasma still drift up and everything else
        // settles down.
        let dirY = JS.signOrFallback(
            gravityY * definition.gravityFactor,
            fallback: definition.state == .gas || definition.state == .plasma ? -1 : 1
        )

        // Each mover reports whether the cell is finished for this tick — either
        // because it moved, or because it deliberately declined to. Both cases end
        // processing in the original, and that matters for the beam check below:
        // an element can match both a state rule and the beam rule, and must not
        // get two turns.
        switch definition.state {
        case .solidMovable:
            if moveGranularSolid(x: x, y: y, idx: idx, definition: definition, dirY: dirY) { return }
        case .liquid:
            if moveLiquid(x: x, y: y, idx: idx, definition: definition, dirY: dirY) { return }
        case .gas, .plasma:
            if moveGasOrPlasma(x: x, y: y, idx: idx, definition: definition, dirY: dirY) { return }
        case .solidFixed, .energy, .special:
            break
        }

        // Beams are checked separately rather than as another case, because an
        // element can match a state rule above and this one too.
        //
        // Dispatched on state alone. The original also tested whether the element's
        // *name* contained "Laser", which was redundant — the laser's state is already
        // energy — and a hazard, since custom elements are loaded from storage without
        // validation and anything a user named "Laser ..." silently inherited full beam
        // physics. Behaviour belongs to state, not to spelling.
        if definition.state == .energy {
            // A laser and a spark share a state and are not the same thing: one is a cutting beam
            // and the other is electricity creeping along a wire. They used to share this code,
            // and giving the laser the beam it needed gave sparks a twelve-cell reach and the
            // ability to set light to whatever they were next to — which broke electricity.
            //
            // Split by identifier, which is safe where a name check was not: the built-in ids are
            // fixed, so nothing a user invents can land on 36.
            if type[idx] == Element.laser {
                propagateLaser(x: x, y: y, idx: idx)
            } else {
                propagateBeam(x: x, y: y, idx: idx)
            }
        }
    }

    // MARK: - Momentum

    /// Carries a cell along its stored velocity, for explosion debris and other
    /// kinetic force.
    ///
    /// - Returns: `true` if the cell travelled, in which case it is done for this
    ///   tick and the normal gravity rules are skipped.
    private func moveByMomentum(x: Int, y: Int, idx: Int) -> Bool {
        let startVelocityX = velocityX[idx].asDouble
        let startVelocityY = velocityY[idx].asDouble
        if startVelocityX == 0 && startVelocityY == 0 { return false }

        let speed = JS.hypot(startVelocityX, startVelocityY)

        // Below the threshold the momentum is spent; drop it so the cell rejoins
        // ordinary gravity rather than creeping.
        guard speed > 0.3 else {
            velocityX[idx] = 0
            velocityY[idx] = 0
            return false
        }

        let normalX = startVelocityX / speed
        let normalY = startVelocityY / speed

        var positionX = Double(x)
        var positionY = Double(y)
        var currentIdx = idx
        var moved = false

        // Faster things cross more cells per tick, capped so a stray huge
        // velocity cannot stall the whole frame.
        let maxSteps = Int(min(JS.round(speed), 8))
        for _ in 0 ..< maxSteps {
            let nextX = Int(JS.round(positionX + normalX))
            let nextY = Int(JS.round(positionY + normalY))

            // The step was too small to reach another cell. Accumulate the
            // fractional position and try again.
            if nextX == Int(JS.round(positionX)) && nextY == Int(JS.round(positionY)) {
                positionX += normalX
                positionY += normalY
                continue
            }

            guard isValid(nextX, nextY) else {
                // Hit a wall: rebound, losing most of the energy.
                velocityX[currentIdx] = JS.toInt8(-velocityX[currentIdx].asDouble * 0.4)
                velocityY[currentIdx] = JS.toInt8(-velocityY[currentIdx].asDouble * 0.4)
                break
            }

            let targetIdx = index(nextX, nextY)
            let targetType = type[targetIdx]

            if targetType == Element.empty {
                swapCells(currentIdx, targetIdx)
                positionX = Double(nextX)
                positionY = Double(nextY)
                currentIdx = targetIdx
                moved = true
            } else if targetType == Element.bedrock {
                // Bedrock is unyielding: rebound harder than off a wall.
                velocityX[currentIdx] = JS.toInt8(-velocityX[currentIdx].asDouble * 0.3)
                velocityY[currentIdx] = JS.toInt8(-velocityY[currentIdx].asDouble * 0.3)
                break
            } else {
                // Struck another cell: pass some momentum on, keep a little.
                let target = elements[targetType]
                if target.state != .solidFixed {
                    velocityX[targetIdx] = JS.toInt8(velocityX[targetIdx].asDouble + startVelocityX * 0.6)
                    velocityY[targetIdx] = JS.toInt8(velocityY[targetIdx].asDouble + startVelocityY * 0.6)
                }
                velocityX[currentIdx] = JS.toInt8(velocityX[currentIdx].asDouble * 0.3)
                velocityY[currentIdx] = JS.toInt8(velocityY[currentIdx].asDouble * 0.3)
                break
            }
        }

        // Drag, applied whether or not the cell got anywhere.
        velocityX[currentIdx] = JS.toInt8(velocityX[currentIdx].asDouble * 0.85)
        velocityY[currentIdx] = JS.toInt8(velocityY[currentIdx].asDouble * 0.85)

        return moved
    }

    // MARK: - Granular solids

    /// Sand, gunpowder, salt, snow: fall straight down, otherwise slide off a
    /// shoulder.
    ///
    /// - Returns: `true` if the grain moved.
    private func moveGranularSolid(x: Int, y: Int, idx: Int, definition: ElementPhysics, dirY: Int) -> Bool {
        let belowY = y + dirY
        if tryMoveOrSwap(fromIdx: idx, fromY: y, toX: x, toY: belowY, selfDensity: definition.density) { return true }

        // Which shoulder is tried first is decided per cell per tick. A fixed
        // order would make every pile lean the same way.
        let firstIsLeft = rng.chance(0.5)
        let firstDX = firstIsLeft ? -1 : 1
        let secondDX = firstIsLeft ? 1 : -1

        if tryMoveOrSwap(fromIdx: idx, fromY: y, toX: x + firstDX, toY: belowY, selfDensity: definition.density) { return true }
        if tryMoveOrSwap(fromIdx: idx, fromY: y, toX: x + secondDX, toY: belowY, selfDensity: definition.density) { return true }
        return false
    }

    // MARK: - Liquids

    /// Water, lava, oil, acid, honey, mercury: fall, slide, then level out.
    ///
    /// - Returns: `true` if the cell is finished for this tick — either it moved,
    ///   or viscosity or cohesion decided it should stay where it is.
    private func moveLiquid(x: Int, y: Int, idx: Int, definition: ElementPhysics, dirY: Int) -> Bool {
        let belowY = y + dirY

        if tryMoveOrSwap(fromIdx: idx, fromY: y, toX: x, toY: belowY, selfDensity: definition.density) { return true }

        let firstIsLeft = rng.chance(0.5)
        let firstDX = firstIsLeft ? -1 : 1
        let secondDX = firstIsLeft ? 1 : -1

        if tryMoveOrSwap(fromIdx: idx, fromY: y, toX: x + firstDX, toY: belowY, selfDensity: definition.density) { return true }
        if tryMoveOrSwap(fromIdx: idx, fromY: y, toX: x + secondDX, toY: belowY, selfDensity: definition.density) { return true }

        // Sideways levelling. Thick liquids often simply do not, which is what
        // makes honey behave like honey.
        let viscosity = definition.viscosity
        if viscosity > 3 && rng.chance(0.35) { return true }

        // Cohesion: a cell surrounded by its own kind is in the middle of a body
        // of liquid and mostly stays put. Without this, a pool continuously
        // churns and looks like it is boiling.
        //
        // Checked as coordinates rather than as raw indices. The original computed
        // the index first and only range-checked it, so at the left wall the "left"
        // neighbour was the last cell of the row above — not adjacent at all — and
        // liquids behaved differently against the walls than anywhere else.
        var sameNeighbours = 0
        for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
            if isValid(nx, ny), type[index(nx, ny)] == definition.id {
                sameNeighbours += 1
            }
        }
        if sameNeighbours >= 3 && rng.chance(0.82) { return true }

        // Thin liquids occasionally reach two cells instead of one, which lets a
        // spill find its level without teleporting across the grid.
        let spread = viscosity <= 1 ? (rng.chance(0.35) ? 2 : 1) : 1
        let pressureHere = pressureEnabled ? pressure[idx].asDouble : 0
        let extra = pressureHere > 3 ? 1 : 0

        // Walk outward one cell at a time and stop a direction as soon as it is
        // blocked. The original tried distance two without having confirmed distance
        // one was passable, so liquid hopped straight through a one-cell-thick wall
        // and drained sealed tanks.
        func isClear(_ candidateX: Int) -> Bool {
            isValid(candidateX, y) && type[index(candidateX, y)] == Element.empty
        }
        var firstBlocked = false
        var secondBlocked = false
        for distance in 1 ... (spread + extra) {
            if !firstBlocked {
                if tryMoveEmpty(fromIdx: idx, toX: x + firstDX * distance, toY: y) { return true }
                if !isClear(x + firstDX * distance) { firstBlocked = true }
            }
            if !secondBlocked {
                if tryMoveEmpty(fromIdx: idx, toX: x + secondDX * distance, toY: y) { return true }
                if !isClear(x + secondDX * distance) { secondBlocked = true }
            }
            if firstBlocked && secondBlocked { break }
        }
        return false
    }

    // MARK: - Gases and plasma

    /// Smoke, steam, helium, fire: seek low pressure, then rise.
    ///
    /// - Returns: `true` if the cell moved.
    private func moveGasOrPlasma(x: Int, y: Int, idx: Int, definition: ElementPhysics, dirY: Int) -> Bool {
        if pressureEnabled {
            var bestX = x
            var bestY = y
            var bestPressure = pressure[idx].asDouble

            // Order matters: ties are kept by the first candidate examined.
            let candidates = [
                (x, y + dirY),
                (x - 1, y),
                (x + 1, y),
                (x, y - dirY),
            ]
            for (candidateX, candidateY) in candidates {
                guard isValid(candidateX, candidateY) else { continue }
                let candidateIdx = index(candidateX, candidateY)
                if visited[candidateIdx] != 0 { continue }
                let candidateType = type[candidateIdx]
                // Cannot push into something at least as heavy.
                if candidateType != Element.empty, elements[candidateType].density >= definition.density {
                    continue
                }
                if pressure[candidateIdx].asDouble < bestPressure {
                    bestPressure = pressure[candidateIdx].asDouble
                    bestX = candidateX
                    bestY = candidateY
                }
            }

            if bestX != x || bestY != y {
                if tryMoveOrSwap(fromIdx: idx, fromY: y, toX: bestX, toY: bestY, selfDensity: definition.density) {
                    return true
                }
            }
        }

        let moveY = y + dirY
        if tryMoveOrSwap(fromIdx: idx, fromY: y, toX: x, toY: moveY, selfDensity: definition.density) { return true }

        let firstIsLeft = rng.chance(0.5)
        let firstDX = firstIsLeft ? -1 : 1
        let secondDX = firstIsLeft ? 1 : -1

        if tryMoveOrSwap(fromIdx: idx, fromY: y, toX: x + firstDX, toY: moveY, selfDensity: definition.density) { return true }
        if tryMoveOrSwap(fromIdx: idx, fromY: y, toX: x + secondDX, toY: moveY, selfDensity: definition.density) { return true }
        if tryMoveOrSwap(fromIdx: idx, fromY: y, toX: x + firstDX, toY: y, selfDensity: definition.density) { return true }
        if tryMoveOrSwap(fromIdx: idx, fromY: y, toX: x + secondDX, toY: y, selfDensity: definition.density) { return true }
        return false
    }

    // MARK: - Beams

    /// Energy that is not a laser — a spark crossing a gap.
    ///
    /// Three cells, and it transforms the first thing it touches. Unchanged from the reference on
    /// purpose: this is the path electricity takes, and it is held to the web engine cell for cell
    /// by several golden scenarios.
    private func propagateBeam(x: Int, y: Int, idx: Int) {
        let stepDir = gravityY != 0 ? JS.signOrFallback(gravityY, fallback: 1) : 1

        for distance in 1 ... 3 {
            let targetY = y + distance * stepDir
            guard isValid(x, targetY) else { continue }

            let targetIdx = index(x, targetY)
            let targetType = type[targetIdx]

            if targetType == Element.empty {
                swapCells(idx, targetIdx)
                return
            }

            // Bedrock stops it dead. The reference did not break here, so the loop carried on to
            // the next distance and it reappeared on the far side of the wall.
            if targetType == Element.bedrock { break }

            // Energy passes through energy.
            if targetType != Element.laser {
                temperature[targetIdx] = JS.toFloat32(temperature[targetIdx].asDouble + 400)

                if targetType == Element.water || targetType == Element.ice {
                    setElement(x, targetY, Element.steam)
                } else if targetType == Element.sand || targetType == Element.stone {
                    setElement(x, targetY, Element.lava)
                } else {
                    setElement(x, targetY, Element.fire, temp: 150)
                }
                return
            }
        }
    }

    /// How far a laser travels in one moment.
    ///
    /// Twelve cells. It was three, and a laser is not a thing that creeps.
    static let beamSpeed = 12

    /// The laser: travels in a straight line and cuts whatever it meets.
    ///
    /// ## What was wrong with this
    ///
    /// A laser did not shoot. Painting one produced a red lump that sat exactly where it was
    /// put and did nothing, and three separate faults combined to cause it — all three
    /// inherited from the reference, which has the same problem.
    ///
    /// 1. **It looked three cells ahead, and passed through its own beam only within those
    ///    three.** A brush is wider than three cells, so every cell inside the lump found more
    ///    laser in front of it, ran out of look-ahead, and stayed put. Only the leading edge
    ///    could ever move.
    /// 2. **It burned only if it could not move, and returned either way.** So it never cleared
    ///    and advanced in the same moment, which is what cutting is.
    /// 3. **It stalled on its own damage.** Sand became lava, lava became fire, and fire is not
    ///    empty — so the beam sat against the hole it had just made.
    ///
    /// ## What it does now
    ///
    /// Looks the full twelve cells ahead. Passes through its own beam however thick it is, and
    /// through anything thin enough not to stop light — gas, plasma, the fire it just started.
    /// Burns the first solid thing in its path **and** advances into the furthest clear cell
    /// before it, in the same moment. Bedrock still absorbs it completely.
    ///
    /// The result is that a painted lump streams forward as a beam, cuts a channel through
    /// stone and sand, boils water on contact, and stops dead at bedrock.
    private func propagateLaser(x: Int, y: Int, idx: Int) {
        let stepDir = gravityY != 0 ? JS.signOrFallback(gravityY, fallback: 1) : 1

        // The furthest clear cell along the path, and the first solid thing past it.
        var reachable = 0
        var blockedIdx = -1
        var blockedType: ElementID = Element.empty
        var blockedY = 0

        for distance in 1 ... Self.beamSpeed {
            let targetY = y + distance * stepDir
            // The edge of the world ends the beam; there is nothing beyond it to travel into.
            guard isValid(x, targetY) else { break }

            let targetIdx = index(x, targetY)
            let targetType = type[targetIdx]

            if targetType == Element.empty {
                reachable = distance
                continue
            }
            // Bedrock stops a beam dead. The reference did not break here, so the loop carried
            // on to the next distance and the beam reappeared on the far side of the wall.
            if targetType == Element.bedrock { break }

            let target = elements[targetType]
            // Another beam, or a spark: light passes through light, however much of it there is.
            if target.state == .energy { continue }
            // Thin enough not to stop a beam — and this is what lets it cut, because the fire
            // and steam it leaves behind are exactly these.
            if target.state == .gas || target.state == .plasma {
                reachable = distance
                continue
            }

            blockedIdx = targetIdx
            blockedType = targetType
            blockedY = targetY
            break
        }

        // Burn what is in the way. Done before moving, and done whether or not it can move,
        // which together are what turn this from a lump into a cutting beam.
        if blockedIdx >= 0 {
            temperature[blockedIdx] = JS.toFloat32(temperature[blockedIdx].asDouble + 400)

            if blockedType == Element.water || blockedType == Element.ice {
                setElement(x, blockedY, Element.steam)
            } else if blockedType == Element.sand || blockedType == Element.stone {
                setElement(x, blockedY, Element.lava)
            } else {
                setElement(x, blockedY, Element.fire, temp: 150)
            }
        }

        if reachable > 0 {
            swapCells(idx, index(x, y + reachable * stepDir))
        }
    }
}
