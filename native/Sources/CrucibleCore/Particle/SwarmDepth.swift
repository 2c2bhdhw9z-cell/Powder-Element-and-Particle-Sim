/// The crowd's forces that depend on what is near what, for a field with depth.
///
/// ## Why these needed their own versions
///
/// Everything here finds a body's neighbours first. On a flat field that is a grid of squares across and down
/// the screen, and the bodies in the squares round a body are its neighbours. In depth that is no longer
/// true: a square seen from the front is a long column running from the front of the box to the back, and
/// most of what is in it is nowhere near the body — it is merely drawn over it. Using the flat grid, the
/// liquid would count a body a whole box away as crowding it, the pull between bodies would treat a disc as
/// a heap, and bodies would collide with whatever happened to be drawn on top of them.
///
/// So these use a grid of cubes. There can be far too many cubes in a large box to give each its own slot, so
/// each cube is filed under a number worked out from where it is — a hash — in a table sized to the crowd
/// rather than to the box. Two cubes can share a number; the distance check that follows sorts that out, and
/// a cube's neighbours are gathered so that a shared number is never walked twice.
///
/// None of this runs on a flat field. The flat versions are untouched, so everything built before depth
/// existed, and every recorded comparison, moves exactly as it did.

// MARK: - Finding neighbours in depth

final class SwarmHash3D {
    /// How wide each cube is.
    private(set) var cellSize = 1.0
    private var mask = 0
    /// Where each numbered slot's bodies begin in ``order``; the next slot's beginning is where they end.
    private var start: [Int32] = []
    /// Every body, sorted by slot.
    private var order: [Int32] = []
    /// Which slot each body went into, while sorting. Minus one for a body with unusable numbers.
    private var slotOf: [Int32] = []

    /// The largest table: two million slots, which is eight megabytes of starts.
    private static let largestTable = 1 << 21

    /// Files every body under its cube.
    func build(positions: UnsafePointer<Float>, depths: UnsafePointer<Float>, count: Int, cellSize wanted: Double) {
        cellSize = wanted.isFinite ? max(0.5, wanted) : 1
        var table = 4_096
        while table < count * 2, table < Self.largestTable { table <<= 1 }
        mask = table - 1
        if start.count < table + 1 {
            start = [Int32](repeating: 0, count: table + 1)
        } else {
            start.withUnsafeMutableBufferPointer { buffer in
                buffer.baseAddress?.update(repeating: 0, count: table + 1)
            }
        }
        if order.count < count {
            order = [Int32](repeating: 0, count: count)
            slotOf = [Int32](repeating: 0, count: count)
        }
        let inverse = 1 / cellSize
        let mask = self.mask

        start.withUnsafeMutableBufferPointer { starts in
        order.withUnsafeMutableBufferPointer { sorted in
        slotOf.withUnsafeMutableBufferPointer { slots in
            for index in 0 ..< count {
                let x = Double(positions[index * 2])
                let y = Double(positions[index * 2 + 1])
                let z = Double(depths[index])
                guard x.isFinite, y.isFinite, z.isFinite else {
                    slots[index] = -1
                    continue
                }
                let slot = Self.slot(Self.cube(x, inverse), Self.cube(y, inverse), Self.cube(z, inverse), mask)
                slots[index] = Int32(slot)
                starts[slot + 1] += 1
            }
            for slot in 0 ..< (mask + 1) { starts[slot + 1] += starts[slot] }
            // Filled from the back of each slot's run, counting down, so the fill needs no second table.
            for index in stride(from: count - 1, through: 0, by: -1) {
                let slot = Int(slots[index])
                guard slot >= 0 else { continue }
                starts[slot + 1] -= 1
                sorted[Int(starts[slot + 1])] = Int32(index)
            }
            // Counting down left every slot's end where its beginning should be; shift them back.
            var slot = mask + 1
            while slot > 0 {
                starts[slot] = starts[slot - 1]
                slot -= 1
            }
            starts[0] = 0
        }
        }
        }
        // The last pass left the ends shifted one along; put the true ends back.
        rebuildEnds(count: count)
    }

    /// Puts each slot's end back after the fill, which is simplest done by recounting.
    private func rebuildEnds(count: Int) {
        let slots = mask + 1
        start.withUnsafeMutableBufferPointer { starts in
            slotOf.withUnsafeBufferPointer { owned in
                for slot in 0 ... slots { starts[slot] = 0 }
                for index in 0 ..< count {
                    let slot = Int(owned[index])
                    guard slot >= 0 else { continue }
                    starts[slot + 1] += 1
                }
                for slot in 0 ..< slots { starts[slot + 1] += starts[slot] }
            }
        }
        // And sort again into those runs, now that the starts are right.
        var fill = [Int32](start[0 ..< slots])
        order.withUnsafeMutableBufferPointer { sorted in
            slotOf.withUnsafeBufferPointer { owned in
                for index in 0 ..< count {
                    let slot = Int(owned[index])
                    guard slot >= 0 else { continue }
                    sorted[Int(fill[slot])] = Int32(index)
                    fill[slot] += 1
                }
            }
        }
    }

    @inline(__always)
    static func cube(_ value: Double, _ inverse: Double) -> Int {
        // Clamped well inside what a whole number can hold. Nothing legitimate is anywhere near it.
        Int(max(-1_000_000_000, min(1_000_000_000, (value * inverse).rounded(.down))))
    }

    @inline(__always)
    static func slot(_ cx: Int, _ cy: Int, _ cz: Int, _ mask: Int) -> Int {
        ((cx &* 73_856_093) ^ (cy &* 19_349_663) ^ (cz &* 83_492_791)) & mask
    }

    /// What a pass reads while walking neighbours.
    struct Storage {
        let start: UnsafePointer<Int32>
        let order: UnsafePointer<Int32>
        let mask: Int
        let inverse: Double

        /// The slots of the twenty-seven cubes round a place, each once, written into `slots`.
        /// - Returns: how many different slots there are.
        @inline(__always)
        func gather(x: Double, y: Double, z: Double, into slots: UnsafeMutablePointer<Int>) -> Int {
            let cx = SwarmHash3D.cube(x, inverse)
            let cy = SwarmHash3D.cube(y, inverse)
            let cz = SwarmHash3D.cube(z, inverse)
            var found = 0
            for oz in -1 ... 1 {
                for oy in -1 ... 1 {
                    for ox in -1 ... 1 {
                        let slot = SwarmHash3D.slot(cx + ox, cy + oy, cz + oz, mask)
                        var seen = false
                        var k = 0
                        while k < found {
                            if slots[k] == slot {
                                seen = true
                                break
                            }
                            k += 1
                        }
                        if !seen {
                            slots[found] = slot
                            found += 1
                        }
                    }
                }
            }
            return found
        }
    }

    func withStorage<Result>(_ body: (Storage) -> Result) -> Result {
        start.withUnsafeBufferPointer { starts in
            order.withUnsafeBufferPointer { sorted in
                body(Storage(
                    start: starts.baseAddress!,
                    order: sorted.baseAddress!,
                    mask: mask,
                    inverse: 1 / cellSize
                ))
            }
        }
    }
}

// MARK: - Bodies meeting one another

extension Swarm {
    /// Pushes overlapping bodies apart in a field with depth.
    ///
    /// The same rule as the flat pass — the same size of body, the same bounce and friction, shared by weight —
    /// with neighbours found among the cubes round a body rather than the squares, so two bodies meet only
    /// when they are really close, and not when one is merely drawn in front of the other.
    func resolveCollisionsInDepth(
        width: Double,
        height: Double,
        depth: Double,
        contact: ContactSettings,
        hash: SwarmHash3D,
        keepsInside: Bool = true
    ) {
        let bodies = count
        guard bodies > 1, width > 0, height > 0 else { return }
        let halfDepth = depth * 0.5
        let cell = Double(bodies > 120_000 ? 7 : bodies > 40_000 ? 5 : 4)
        let diameter = contact.size <= 0
            ? max(3.2, cell * 0.88)
            : max(1, min(contact.size, cell * 0.98))
        let diameterSquared = diameter * diameter
        hash.build(positions: positions, depths: depths, count: bodies, cellSize: max(cell, diameter))
        let stride = bodies > 250_000 ? 2 : 1

        withUnsafeTemporaryAllocation(of: Int.self, capacity: 27) { slotBuffer in
            guard let slots = slotBuffer.baseAddress else { return }
            hash.withStorage { cells in
                var i = 0
                while i < bodies {
                    let pair = i * 2
                    var posX = positions[pair].asDouble
                    var posY = positions[pair + 1].asDouble
                    var posZ = depths[i].asDouble
                    var velX = velocities[pair].asDouble
                    var velY = velocities[pair + 1].asDouble
                    var velZ = depthVelocities[i].asDouble
                    guard posX.isFinite, posY.isFinite, posZ.isFinite else {
                        i += stride
                        continue
                    }

                    let found = cells.gather(x: posX, y: posY, z: posZ, into: slots)
                    for s in 0 ..< found {
                        let slot = slots[s]
                        var at = Int(cells.start[slot])
                        let end = Int(cells.start[slot + 1])
                        var examined = 0
                        // Capped, as the flat pass is, so one very crowded cube cannot dominate the frame.
                        while at < end, examined < 8 {
                            let other = Int(cells.order[at])
                            at += 1
                            guard other != i else { continue }
                            let otherPair = other * 2
                            let dx = posX - positions[otherPair].asDouble
                            let dy = posY - positions[otherPair + 1].asDouble
                            let dz = posZ - depths[other].asDouble
                            let distanceSquared = dx * dx + dy * dy + dz * dz
                            guard distanceSquared < diameterSquared, distanceSquared > 0.0001 else { continue }
                            examined += 1
                            let distance = distanceSquared.squareRoot()
                            let normalX = dx / distance
                            let normalY = dy / distance
                            let normalZ = dz / distance
                            let overlap = diameter - distance
                            let ownMass = masses[i].asDouble
                            let otherMass = masses[other].asDouble
                            let totalMass = ownMass + otherMass
                            let ownShare = totalMass > 0 ? otherMass / totalMass : 0.5
                            posX += normalX * overlap * ownShare
                            posY += normalY * overlap * ownShare
                            posZ += normalZ * overlap * ownShare
                            let takenShare = totalMass > 0 ? 2 * otherMass / totalMass : 1

                            let otherVelX = velocities[otherPair].asDouble
                            let otherVelY = velocities[otherPair + 1].asDouble
                            let otherVelZ = depthVelocities[other].asDouble
                            let closing = (velX - otherVelX) * normalX + (velY - otherVelY) * normalY
                                + (velZ - otherVelZ) * normalZ
                            if closing < 0 {
                                velX -= normalX * closing * contact.bounciness * takenShare
                                velY -= normalY * closing * contact.bounciness * takenShare
                                velZ -= normalZ * closing * contact.bounciness * takenShare
                            }
                            let relativeX = velX - otherVelX
                            let relativeY = velY - otherVelY
                            let relativeZ = velZ - otherVelZ
                            let along = relativeX * normalX + relativeY * normalY + relativeZ * normalZ
                            velX -= (relativeX - normalX * along) * contact.friction * takenShare
                            velY -= (relativeY - normalY * along) * contact.friction * takenShare
                            velZ -= (relativeZ - normalZ * along) * contact.friction * takenShare
                        }
                    }

                    velX *= 0.996
                    velY *= 0.996
                    velZ *= 0.996

                    if keepsInside {
                    if posX < 1 {
                        posX = 1
                        velX *= -0.55
                    } else if posX > width - 1 {
                        posX = width - 1
                        velX *= -0.55
                    }
                    if posY < 1 {
                        posY = 1
                        velY *= -0.55
                    } else if posY > height - 1 {
                        posY = height - 1
                        velY *= -0.55
                    }
                    if posZ < -halfDepth + 1 {
                        posZ = -halfDepth + 1
                        velZ *= -0.55
                    } else if posZ > halfDepth - 1 {
                        posZ = halfDepth - 1
                        velZ *= -0.55
                    }
                    }

                    positions[pair] = JS.toFloat32(posX)
                    positions[pair + 1] = JS.toFloat32(posY)
                    depths[i] = JS.toFloat32(posZ)
                    velocities[pair] = JS.toFloat32(velX)
                    velocities[pair + 1] = JS.toFloat32(velY)
                    depthVelocities[i] = JS.toFloat32(velZ)
                    i += stride
                }
            }
        }
    }
}

// MARK: - The liquid, in depth

/// The liquid for a field with depth.
///
/// The flat liquid's rules — crowding becomes pressure, neighbours drag one another toward the same speed, and
/// a surface holds itself together — measured over a ball round each body rather than a disc. Two things
/// change with that, and both are worked out rather than guessed:
///
///   - **The weighting's scale.** The flat one adds up to one over a disc; this one adds up to one over a
///     ball, which makes it fifteen over two pi times the reach cubed, and the rate it falls off at
///     fifteen over pi times the reach to the fourth.
///   - **What "how crowded it wants to be" means.** The setting is bodies per square pixel, which says how far
///     apart the liquid likes its bodies. The same spacing in depth is that number to the power of one and a
///     half — so moving the spacing slider means the same thing flat and in 3D.
final class SwarmDepthFluid {
    private var density: [Float] = []
    private var pressure: [Float] = []
    private var pushX: [Float] = []
    private var pushY: [Float] = []
    private var pushZ: [Float] = []
    private let hash = SwarmHash3D()

    func step(swarm: Swarm, settings: SwarmFluid.Settings, width: Double, height: Double) {
        let bodies = swarm.count
        guard bodies > 1, width > 0, height > 0 else { return }
        let tuned = settings.sanitized
        let reach = tuned.smoothing
        let reachSquared = reach * reach
        let weightScale = 15 / (2 * 3.141592653589793 * reachSquared * reach)
        let slopeScale = 15 / (3.141592653589793 * reachSquared * reachSquared)
        let restDensity = max(1e-9, tuned.restDensity * tuned.restDensity.squareRoot())

        if density.count < bodies {
            let extra = bodies - density.count
            density.append(contentsOf: repeatElement(0, count: extra))
            pressure.append(contentsOf: repeatElement(0, count: extra))
            pushX.append(contentsOf: repeatElement(0, count: extra))
            pushY.append(contentsOf: repeatElement(0, count: extra))
            pushZ.append(contentsOf: repeatElement(0, count: extra))
        }

        let positions = swarm.positions
        let depths = swarm.depths
        let velocities = swarm.velocities
        let depthVelocities = swarm.depthVelocities
        let masses = swarm.masses
        hash.build(positions: positions, depths: depths, count: bodies, cellSize: reach)

        withUnsafeTemporaryAllocation(of: Int.self, capacity: 27) { slotBuffer in
        guard let slots = slotBuffer.baseAddress else { return }
        hash.withStorage { cells in
        density.withUnsafeMutableBufferPointer { densityBuffer in
        pressure.withUnsafeMutableBufferPointer { pressureBuffer in
            // How crowded each body is.
            for index in 0 ..< bodies {
                let x = Double(positions[index * 2])
                let y = Double(positions[index * 2 + 1])
                let z = Double(depths[index])
                guard x.isFinite, y.isFinite, z.isFinite else {
                    densityBuffer[index] = Float(restDensity)
                    pressureBuffer[index] = 0
                    continue
                }
                var crowding = weightScale * Double(masses[index])
                let found = cells.gather(x: x, y: y, z: z, into: slots)
                for s in 0 ..< found {
                    var at = Int(cells.start[slots[s]])
                    let end = Int(cells.start[slots[s] + 1])
                    while at < end {
                        let other = Int(cells.order[at])
                        at += 1
                        guard other != index else { continue }
                        let dx = Double(positions[other * 2]) - x
                        let dy = Double(positions[other * 2 + 1]) - y
                        let dz = Double(depths[other]) - z
                        let distanceSquared = dx * dx + dy * dy + dz * dz
                        guard distanceSquared < reachSquared else { continue }
                        let falloff = 1 - distanceSquared.squareRoot() / reach
                        crowding += weightScale * falloff * falloff * Double(masses[other])
                    }
                }
                densityBuffer[index] = Float(crowding)
                pressureBuffer[index] = Float(max(0, tuned.stiffness * (crowding - restDensity)))
            }

            // What that pushes each body to do.
            pushX.withUnsafeMutableBufferPointer { outX in
            pushY.withUnsafeMutableBufferPointer { outY in
            pushZ.withUnsafeMutableBufferPointer { outZ in
                for index in 0 ..< bodies {
                    outX[index] = 0
                    outY[index] = 0
                    outZ[index] = 0
                    let x = Double(positions[index * 2])
                    let y = Double(positions[index * 2 + 1])
                    let z = Double(depths[index])
                    guard x.isFinite, y.isFinite, z.isFinite else { continue }
                    let own = max(1e-12, Double(densityBuffer[index]))
                    let ownPressure = Double(pressureBuffer[index])
                    let velX = Double(velocities[index * 2])
                    let velY = Double(velocities[index * 2 + 1])
                    let velZ = Double(depthVelocities[index])
                    guard velX.isFinite, velY.isFinite, velZ.isFinite else { continue }
                    let surface = max(0, 1 - own / restDensity)

                    var pushX = 0.0
                    var pushY = 0.0
                    var pushZ = 0.0
                    let found = cells.gather(x: x, y: y, z: z, into: slots)
                    for s in 0 ..< found {
                        var at = Int(cells.start[slots[s]])
                        let end = Int(cells.start[slots[s] + 1])
                        while at < end {
                            let other = Int(cells.order[at])
                            at += 1
                            guard other != index else { continue }
                            let dx = Double(positions[other * 2]) - x
                            let dy = Double(positions[other * 2 + 1]) - y
                            let dz = Double(depths[other]) - z
                            let distanceSquared = dx * dx + dy * dy + dz * dz
                            guard distanceSquared < reachSquared, distanceSquared > 1e-12 else { continue }
                            let distance = distanceSquared.squareRoot()
                            let falloff = 1 - distance / reach
                            let otherDensity = max(1e-12, Double(densityBuffer[other]))
                            let otherPressure = Double(pressureBuffer[other])
                            let awayX = -dx / distance
                            let awayY = -dy / distance
                            let awayZ = -dz / distance

                            let share = ownPressure / (own * own) + otherPressure / (otherDensity * otherDensity)
                            let strength = share * slopeScale * falloff
                            pushX += awayX * strength
                            pushY += awayY * strength
                            pushZ += awayZ * strength

                            if tuned.viscosity > 0 {
                                let relativeX = Double(velocities[other * 2]) - velX
                                let relativeY = Double(velocities[other * 2 + 1]) - velY
                                let relativeZ = Double(depthVelocities[other]) - velZ
                                if relativeX.isFinite, relativeY.isFinite, relativeZ.isFinite {
                                    let weight = tuned.viscosity * weightScale * falloff * falloff / otherDensity
                                    pushX += relativeX * weight
                                    pushY += relativeY * weight
                                    pushZ += relativeZ * weight
                                }
                            }
                            if tuned.cohesion > 0, surface > 0 {
                                let weight = tuned.cohesion * surface * falloff * falloff * weightScale
                                pushX -= awayX * weight / own
                                pushY -= awayY * weight / own
                                pushZ -= awayZ * weight / own
                            }
                        }
                    }

                    guard pushX.isFinite, pushY.isFinite, pushZ.isFinite else { continue }
                    let asked = (pushX * pushX + pushY * pushY + pushZ * pushZ).squareRoot()
                    let scale = asked > SwarmFluid.pushLimit ? SwarmFluid.pushLimit / asked : 1
                    outX[index] = Float(pushX * scale)
                    outY[index] = Float(pushY * scale)
                    outZ[index] = Float(pushZ * scale)
                }

                // Only now applied, for the reason the flat liquid gives: the drag reads a neighbour's speed.
                for index in 0 ..< bodies {
                    let velX = Double(velocities[index * 2])
                    let velY = Double(velocities[index * 2 + 1])
                    let velZ = Double(depthVelocities[index])
                    guard velX.isFinite, velY.isFinite, velZ.isFinite else { continue }
                    velocities[index * 2] = JS.toFloat32(velX + Double(outX[index]))
                    velocities[index * 2 + 1] = JS.toFloat32(velY + Double(outY[index]))
                    depthVelocities[index] = JS.toFloat32(velZ + Double(outZ[index]))
                }
            }
            }
            }
        }
        }
        }
        }
        swarm.noteDepthInUse()
    }
}

// MARK: - The pull between bodies, in depth

/// Every body pulling on every other, in a field with depth.
///
/// The flat version's method in three directions: small crowds exactly, pair by pair; large ones with the
/// box divided into lumps, each body feeling the lumps beside it one body at a time and everything further as
/// a single weight at the lump's centre. The far pull is worked out once per occupied lump rather than once
/// per body, and only for lumps that hold anything, which is what keeps a disc or a cluster — where most of
/// the box is empty — affordable.
final class SwarmDepthGravity {
    static let columns = 10
    static let rows = 14
    static let layers = 10

    private var cellMass: [Double] = []
    private var cellX: [Double] = []
    private var cellY: [Double] = []
    private var cellZ: [Double] = []
    private var farX: [Double] = []
    private var farY: [Double] = []
    private var farZ: [Double] = []
    private var cellStart: [Int32] = []
    private var order: [Int32] = []
    private var bodyCell: [Int32] = []
    private var occupied: [Int32] = []

    func step(swarm: Swarm, settings: SwarmGravity.Settings, width: Double, height: Double, depth: Double) {
        let bodies = swarm.count
        guard bodies > 1, width > 0, height > 0, depth > 0 else { return }
        let tuned = settings.sanitized
        guard tuned.strength > 0 else { return }
        if bodies < SwarmGravity.exactBelow {
            stepExactly(swarm: swarm, settings: tuned)
        } else {
            stepApproximately(swarm: swarm, settings: tuned, width: width, height: height, depth: depth)
        }
        swarm.noteDepthInUse()
    }

    @inline(__always)
    private func apply(_ pullX: Double, _ pullY: Double, _ pullZ: Double, to swarm: Swarm, at index: Int) {
        guard pullX.isFinite, pullY.isFinite, pullZ.isFinite else { return }
        let velX = Double(swarm.velocities[index * 2])
        let velY = Double(swarm.velocities[index * 2 + 1])
        let velZ = Double(swarm.depthVelocities[index])
        guard velX.isFinite, velY.isFinite, velZ.isFinite else { return }
        swarm.velocities[index * 2] = JS.toFloat32(velX + pullX)
        swarm.velocities[index * 2 + 1] = JS.toFloat32(velY + pullY)
        swarm.depthVelocities[index] = JS.toFloat32(velZ + pullZ)
    }

    private func stepExactly(swarm: Swarm, settings: SwarmGravity.Settings) {
        let bodies = swarm.count
        let positions = swarm.positions
        let depths = swarm.depths
        let masses = swarm.masses
        let softeningSquared = settings.softening * settings.softening
        for index in 0 ..< bodies {
            let x = Double(positions[index * 2])
            let y = Double(positions[index * 2 + 1])
            let z = Double(depths[index])
            guard x.isFinite, y.isFinite, z.isFinite else { continue }
            var pullX = 0.0
            var pullY = 0.0
            var pullZ = 0.0
            for other in 0 ..< bodies where other != index {
                let dx = Double(positions[other * 2]) - x
                let dy = Double(positions[other * 2 + 1]) - y
                let dz = Double(depths[other]) - z
                guard dx.isFinite, dy.isFinite, dz.isFinite else { continue }
                let distanceSquared = dx * dx + dy * dy + dz * dz + softeningSquared
                let scale = settings.strength * Double(masses[other]) / (distanceSquared * distanceSquared.squareRoot())
                pullX += dx * scale
                pullY += dy * scale
                pullZ += dz * scale
            }
            apply(pullX, pullY, pullZ, to: swarm, at: index)
        }
    }

    private func stepApproximately(
        swarm: Swarm,
        settings: SwarmGravity.Settings,
        width: Double,
        height: Double,
        depth: Double
    ) {
        let bodies = swarm.count
        let columns = Self.columns
        let rows = Self.rows
        let layers = Self.layers
        let cells = columns * rows * layers
        let cellWidth = width / Double(columns)
        let cellHeight = height / Double(rows)
        let cellDepth = depth / Double(layers)
        let halfDepth = depth * 0.5
        let softeningSquared = settings.softening * settings.softening
        let strength = settings.strength

        if cellMass.count < cells {
            cellMass = [Double](repeating: 0, count: cells)
            cellX = cellMass
            cellY = cellMass
            cellZ = cellMass
            farX = cellMass
            farY = cellMass
            farZ = cellMass
            cellStart = [Int32](repeating: 0, count: cells + 1)
        }
        if order.count < bodies {
            order = [Int32](repeating: 0, count: bodies)
            bodyCell = [Int32](repeating: 0, count: bodies)
        }
        let positions = swarm.positions
        let depths = swarm.depths
        let masses = swarm.masses

        @inline(__always) func cellIndex(_ x: Double, _ y: Double, _ z: Double) -> (Int, Int, Int) {
            (
                JS.clampedInt(x / cellWidth, 0, columns - 1),
                JS.clampedInt(y / cellHeight, 0, rows - 1),
                JS.clampedInt((z + halfDepth) / cellDepth, 0, layers - 1)
            )
        }

        for cell in 0 ..< cells {
            cellMass[cell] = 0
            cellX[cell] = 0
            cellY[cell] = 0
            cellZ[cell] = 0
            cellStart[cell] = 0
        }
        cellStart[cells] = 0

        for index in 0 ..< bodies {
            let x = Double(positions[index * 2])
            let y = Double(positions[index * 2 + 1])
            let z = Double(depths[index])
            guard x.isFinite, y.isFinite, z.isFinite else {
                bodyCell[index] = -1
                continue
            }
            let (column, row, layer) = cellIndex(x, y, z)
            let cell = (layer * rows + row) * columns + column
            bodyCell[index] = Int32(cell)
            let weight = Double(masses[index])
            cellMass[cell] += weight
            cellX[cell] += x * weight
            cellY[cell] += y * weight
            cellZ[cell] += z * weight
            cellStart[cell + 1] += 1
        }
        occupied.removeAll(keepingCapacity: true)
        for cell in 0 ..< cells where cellMass[cell] > 0 {
            cellX[cell] /= cellMass[cell]
            cellY[cell] /= cellMass[cell]
            cellZ[cell] /= cellMass[cell]
            occupied.append(Int32(cell))
        }
        for cell in 0 ..< cells { cellStart[cell + 1] += cellStart[cell] }
        var fill = [Int32](cellStart[0 ..< cells])
        for index in 0 ..< bodies where bodyCell[index] >= 0 {
            let cell = Int(bodyCell[index])
            order[Int(fill[cell])] = Int32(index)
            fill[cell] += 1
        }

        // What each occupied lump feels from every distant one.
        for entry in occupied {
            let cell = Int(entry)
            let column = cell % columns
            let row = (cell / columns) % rows
            let layer = cell / (columns * rows)
            var pullX = 0.0
            var pullY = 0.0
            var pullZ = 0.0
            for otherEntry in occupied {
                let other = Int(otherEntry)
                let otherColumn = other % columns
                let otherRow = (other / columns) % rows
                let otherLayer = other / (columns * rows)
                if abs(otherColumn - column) <= 1, abs(otherRow - row) <= 1, abs(otherLayer - layer) <= 1 {
                    continue
                }
                let dx = cellX[other] - cellX[cell]
                let dy = cellY[other] - cellY[cell]
                let dz = cellZ[other] - cellZ[cell]
                let distanceSquared = dx * dx + dy * dy + dz * dz + softeningSquared
                let scale = strength * cellMass[other] / (distanceSquared * distanceSquared.squareRoot())
                pullX += dx * scale
                pullY += dy * scale
                pullZ += dz * scale
            }
            farX[cell] = pullX
            farY[cell] = pullY
            farZ[cell] = pullZ
        }

        // And each body: its lump's distant pull, and everything in the lumps round it one at a time.
        for index in 0 ..< bodies {
            let own = Int(bodyCell[index])
            guard own >= 0 else { continue }
            let x = Double(positions[index * 2])
            let y = Double(positions[index * 2 + 1])
            let z = Double(depths[index])
            let column = own % columns
            let row = (own / columns) % rows
            let layer = own / (columns * rows)
            var pullX = farX[own]
            var pullY = farY[own]
            var pullZ = farZ[own]
            for nearLayer in max(0, layer - 1) ... min(layers - 1, layer + 1) {
                for nearRow in max(0, row - 1) ... min(rows - 1, row + 1) {
                    for nearColumn in max(0, column - 1) ... min(columns - 1, column + 1) {
                        let cell = (nearLayer * rows + nearRow) * columns + nearColumn
                        var at = Int(cellStart[cell])
                        let end = Int(cellStart[cell + 1])
                        while at < end {
                            let other = Int(order[at])
                            at += 1
                            guard other != index else { continue }
                            let dx = Double(positions[other * 2]) - x
                            let dy = Double(positions[other * 2 + 1]) - y
                            let dz = Double(depths[other]) - z
                            let distanceSquared = dx * dx + dy * dy + dz * dz + softeningSquared
                            let scale = strength * Double(masses[other])
                                / (distanceSquared * distanceSquared.squareRoot())
                            pullX += dx * scale
                            pullY += dy * scale
                            pullZ += dz * scale
                        }
                    }
                }
            }
            apply(pullX, pullY, pullZ, to: swarm, at: index)
        }
    }
}

// MARK: - The wind, in depth

extension SwarmFlow {
    /// The wind in a field with depth.
    ///
    /// The flat wind across and down, exactly as it blows on a flat field, and a third part into and out of the
    /// screen taken from the same kind of swirling field turned on its side — so the crowd is carried round in
    /// depth as well as across, rather than blowing about on sheets that never mix.
    public func stepInDepth(swarm: Swarm, settings: Settings, time: Double) {
        let bodies = swarm.count
        guard bodies > 0 else { return }
        let tuned = settings.sanitized
        guard tuned.strength > 0 else { return }
        let positions = swarm.positions
        let depths = swarm.depths
        let velocities = swarm.velocities
        let depthVelocities = swarm.depthVelocities
        let inverseScale = 1 / tuned.scale
        let when = time.isFinite ? time * tuned.drift : 0
        let strength = tuned.strength
        for index in 0 ..< bodies {
            let x = Double(positions[index * 2])
            let y = Double(positions[index * 2 + 1])
            let z = Double(depths[index])
            guard x.isFinite, y.isFinite, z.isFinite else { continue }
            let across = Self.curl(atX: x * inverseScale + z * inverseScale * 0.5, y: y * inverseScale, time: when)
            let inward = Self.curl(atX: z * inverseScale + 17.3, y: x * inverseScale - 5.1, time: when)
            let velX = Double(velocities[index * 2])
            let velY = Double(velocities[index * 2 + 1])
            let velZ = Double(depthVelocities[index])
            guard velX.isFinite, velY.isFinite, velZ.isFinite else { continue }
            velocities[index * 2] = JS.toFloat32(velX + across.x * strength)
            velocities[index * 2 + 1] = JS.toFloat32(velY + across.y * strength)
            depthVelocities[index] = JS.toFloat32(velZ + inward.x * strength)
        }
        swarm.noteDepthInUse()
    }
}
