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

        // Beams are checked separately rather than as another case, because the
        // original tests the element's *name* as well as its state — so a
        // user-authored element called "Laser" something propagates like one even
        // if its state says otherwise.
        if definition.state == .energy || definition.id == Element.laser || definition.nameMentionsLaser {
            propagateBeam(x: x, y: y, idx: idx)
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
        // The neighbour offsets are computed without bounds checking and then
        // filtered by range, exactly as the original does. At the left and right
        // edges that means an index wraps onto the adjacent row, so a cell
        // against a wall sees a slightly different neighbourhood. That is
        // reproduced rather than corrected: it affects how liquids behave along
        // the walls, which is visible behavior the test suite pins down.
        var sameNeighbours = 0
        let neighbourIndices = [
            index(x - 1, y),
            index(x + 1, y),
            index(x, y - 1),
            index(x, y + 1),
        ]
        for neighbour in neighbourIndices {
            if neighbour >= 0, neighbour < cellCount, type[neighbour] == definition.id {
                sameNeighbours += 1
            }
        }
        if sameNeighbours >= 3 && rng.chance(0.82) { return true }

        // Thin liquids occasionally reach two cells instead of one, which lets a
        // spill find its level without teleporting across the grid.
        let spread = viscosity <= 1 ? (rng.chance(0.35) ? 2 : 1) : 1
        let pressureHere = pressureEnabled ? pressure[idx].asDouble : 0
        let extra = pressureHere > 3 ? 1 : 0

        for distance in 1 ... (spread + extra) {
            if tryMoveEmpty(fromIdx: idx, toX: x + firstDX * distance, toY: y) { return true }
            if tryMoveEmpty(fromIdx: idx, toX: x + secondDX * distance, toY: y) { return true }
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

    /// Sparks and laser beams: travel in a straight line and transform whatever
    /// they hit.
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

            // Bedrock stops a beam, and beams pass through each other.
            if targetType != Element.bedrock && targetType != Element.laser {
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
}
