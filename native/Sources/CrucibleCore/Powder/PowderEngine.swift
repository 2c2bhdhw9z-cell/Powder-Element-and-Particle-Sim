/// How solids are given a grain by the renderer.
public enum PowderTextureMode: String, Sendable, Hashable, CaseIterable, Codable {
    case diagonalMatrix = "diagonal_matrix"
    case naturalGrain = "natural_grain"
    case organicFlow = "organic_flow"
    case flat
}

/// The cellular-automata powder world.
///
/// One cell per grid position, each holding an element identifier plus the state
/// that element needs: temperature, remaining lifetime, momentum, pressure.
///
/// ## Storage
///
/// Eight parallel buffers, one per attribute, rather than one buffer of cell
/// structs. That matches the web implementation's typed arrays, and it is the
/// right shape here for the same reason: most passes over the grid read one or
/// two attributes of many cells (the movement scan reads types; heat diffusion
/// reads temperatures), so keeping each attribute contiguous means a cache line
/// fetched is a cache line used.
///
/// The buffers are allocated manually rather than held as Swift arrays. Eight
/// arrays would mean eight nested `withUnsafeMutableBufferPointer` closures
/// wrapped around every pass, and the physics needs to hand raw pointers to
/// worker threads later. The allocation is owned by this class and released in
/// `deinit`; all coordinate-taking entry points bounds-check before touching it.
///
/// ## Element widths are deliberate
///
/// Each buffer's element type matches the web implementation's typed array
/// exactly, and that is a fidelity requirement rather than a memory saving:
///
/// - `temperature` and the pressure fields are **single precision**, because the
///   web stores them in `Float32Array`. Every write rounds. Arithmetic happens at
///   double precision and narrows on store, exactly as JavaScript does. Holding
///   them at double precision instead would let values drift, and the chemistry
///   has hard thresholds — 700°C decides whether lava becomes obsidian — so drift
///   eventually flips real decisions.
/// - `velocityX` and `velocityY` are **signed bytes** that wrap on overflow,
///   because the web stores them in `Int8Array`. The momentum code multiplies by
///   fractions and stores back, genuinely leaving the range.
public final class PowderEngine {
    // MARK: - Dimensions

    public private(set) var width: Int
    public private(set) var height: Int
    /// Number of cells, `width * height`.
    public private(set) var cellCount: Int

    // MARK: - Grid buffers

    /// Which element occupies each cell. Zero is empty.
    public private(set) var type: UnsafeMutablePointer<ElementID>
    /// Cell temperature in degrees Celsius. Single precision, see the type note.
    public private(set) var temperature: UnsafeMutablePointer<Float>
    /// Ticks remaining before a decaying cell expires.
    public private(set) var life: UnsafeMutablePointer<UInt16>
    /// Set for cells that already moved this tick, so nothing moves twice.
    public private(set) var visited: UnsafeMutablePointer<UInt8>
    /// Horizontal momentum. Signed byte that wraps, see the type note.
    public private(set) var velocityX: UnsafeMutablePointer<Int8>
    /// Vertical momentum.
    public private(set) var velocityY: UnsafeMutablePointer<Int8>
    /// Pressure field.
    ///
    /// Settable within the module only, because the relaxation pass exchanges this
    /// with ``pressureNext`` rather than copying. See ``swapPressureBuffers()``.
    public internal(set) var pressure: UnsafeMutablePointer<Float>
    /// Scratch buffer the pressure relaxation writes into before swapping.
    public internal(set) var pressureNext: UnsafeMutablePointer<Float>

    // MARK: - Elements

    /// The editable element set. Custom elements are registered here.
    public let registry: ElementRegistry

    /// The packed element properties the physics reads.
    ///
    /// Refreshed from the registry at the start of every tick, so an element
    /// edited mid-session takes effect without the physics paying for a class
    /// property access per cell.
    public private(set) var elements: ElementTable

    // MARK: - World parameters

    /// Sideways gravity, set by device tilt.
    public var gravityX: Double = 0
    /// Vertical gravity: `1` is down, `-1` is up, `0` is weightless.
    public var gravityY: Double = 1
    /// The temperature cells return to, and the temperature they are placed at
    /// when their element does not specify one.
    public var ambientTemp: Double = 20
    /// Horizontal wind strength, clamped to `-5 ... 5` by ``setWind(_:)``.
    public var windX: Double = 0
    /// Whether the pressure field is simulated.
    public var pressureEnabled: Bool = true
    /// Whether heat spreads between cells.
    public var heatConductionEnabled: Bool = true
    /// Ticks elapsed. Also flips the horizontal scan direction each tick.
    public var frameCount: Int = 0
    /// How solids are grained by the renderer.
    public var textureMode: PowderTextureMode = .naturalGrain
    /// Remaining shake energy from a device jolt, decaying each tick.
    public var jostleLeft: Double = 0
    /// Tick of the last fan rotation, used to debounce repeated taps.
    public var lastFanRotate: Double = 0

    /// Whether an exit portal might be somewhere in the grid.
    ///
    /// The tick has to know where every exit portal is before anything moves, and
    /// finding them meant reading all several million cells on every single tick for
    /// something almost no world contains. This flag is what lets that pass be
    /// skipped, and it is exact rather than a guess:
    ///
    /// - Only sixteen places in the engine ever write a cell's element, and only two
    ///   of them can put an exit portal into the grid: deliberate placement through
    ///   ``setElement(_:_:_:temp:life:)``, and loading a world. Both set this. Nothing
    ///   decays into a portal and no reaction produces one, so a portal cannot appear
    ///   by accident.
    /// - Moving cells about cannot create one that was not already there, so the
    ///   per-tick physics needs no hook.
    /// - It is self-correcting downward: when the scan does run and finds nothing, the
    ///   flag is cleared again, so painting a portal and then erasing it returns the
    ///   world to the fast path instead of paying for the scan forever.
    ///
    /// A stale `true` costs one wasted pass and is harmless. A stale `false` would
    /// break teleportation, which is why every path that could introduce a portal sets
    /// it rather than trying to be clever.
    public internal(set) var portalBMayExist: Bool = false

    /// Called when an explosion goes off, so the app can shake the screen or play
    /// a sound. The engine itself does neither.
    public var onBurst: ((Int, Int, Int) -> Void)?
    /// The largest blast not yet reported. See ``takeLargestBurst()``.
    var largestUnreportedBurst = 0

    /// The random stream.
    ///
    /// Owned by the engine rather than read from a global, so a world plus a seed
    /// replays exactly — which is what makes the ported test suite meaningful and
    /// what any future lockstep multiplayer would need.
    public var rng: Mulberry32

    // MARK: - Lifetime

    /// Creates a world.
    ///
    /// Dimensions match the web implementation's defaults. A zero or negative
    /// dimension yields an empty world rather than a crash: the size is derived
    /// from a view's measured bounds at runtime, which can briefly be zero.
    public init(
        width: Int = 240,
        height: Int = 160,
        registry: ElementRegistry = ElementRegistry(),
        seed: UInt32? = nil
    ) {
        let safeWidth = max(0, width)
        let safeHeight = max(0, height)
        self.width = safeWidth
        self.height = safeHeight
        self.cellCount = safeWidth * safeHeight
        self.registry = registry
        self.elements = registry.table
        self.rng = seed.map(Mulberry32.init(seed:)) ?? Mulberry32()

        let capacity = max(1, safeWidth * safeHeight)
        self.type = Self.makeBuffer(capacity, ElementID(0))
        self.temperature = Self.makeBuffer(capacity, Float(0))
        self.life = Self.makeBuffer(capacity, UInt16(0))
        self.visited = Self.makeBuffer(capacity, UInt8(0))
        self.velocityX = Self.makeBuffer(capacity, Int8(0))
        self.velocityY = Self.makeBuffer(capacity, Int8(0))
        self.pressure = Self.makeBuffer(capacity, Float(0))
        self.pressureNext = Self.makeBuffer(capacity, Float(0))

        resetGrid()
    }

    deinit {
        let capacity = max(1, cellCount)
        Self.release(type, capacity)
        Self.release(temperature, capacity)
        Self.release(life, capacity)
        Self.release(visited, capacity)
        Self.release(velocityX, capacity)
        Self.release(velocityY, capacity)
        Self.release(pressure, capacity)
        Self.release(pressureNext, capacity)
    }

    private static func makeBuffer<T>(_ capacity: Int, _ value: T) -> UnsafeMutablePointer<T> {
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: capacity)
        buffer.initialize(repeating: value, count: capacity)
        return buffer
    }

    private static func release<T>(_ buffer: UnsafeMutablePointer<T>, _ capacity: Int) {
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
    }

    // MARK: - Geometry

    /// The buffer offset of a cell.
    ///
    /// Deliberately does **not** validate its arguments, matching the web
    /// implementation's `getIndex`. Some physics relies on that: the liquid
    /// cohesion check computes indices for all four neighbours including
    /// off-edge ones, then filters the results by range. Adding validation here
    /// would change which cells are considered neighbours at the grid edges, and
    /// so would change how liquids behave along the walls.
    @inlinable
    public func index(_ x: Int, _ y: Int) -> Int {
        y * width + x
    }

    /// Whether a coordinate is inside the grid.
    @inlinable
    public func isValid(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && x < width && y >= 0 && y < height
    }

    /// The element identifier at a coordinate, or bedrock outside the grid.
    @inlinable
    public func typeAt(_ x: Int, _ y: Int) -> ElementID {
        isValid(x, y) ? type[index(x, y)] : Element.bedrock
    }

    /// The physical properties at a coordinate.
    ///
    /// Outside the grid this reports bedrock, which is how the walls become
    /// solid without any special-casing in the movement rules — the same trick
    /// the web implementation's `getElementAt` uses.
    @inlinable
    public func physics(at x: Int, y: Int) -> ElementPhysics {
        elements[typeAt(x, y)]
    }

    // MARK: - Whole-grid operations

    /// Empties the world, returning every cell to nothing at ambient temperature.
    public func resetGrid() {
        guard cellCount > 0 else { return }
        type.update(repeating: Element.empty, count: cellCount)
        temperature.update(repeating: JS.toFloat32(ambientTemp), count: cellCount)
        life.update(repeating: 0, count: cellCount)
        visited.update(repeating: 0, count: cellCount)
        velocityX.update(repeating: 0, count: cellCount)
        velocityY.update(repeating: 0, count: cellCount)
        pressure.update(repeating: 0, count: cellCount)
        pressureNext.update(repeating: 0, count: cellCount)
        // An empty world contains no portals by definition. Callers that clear the grid
        // only to lay cells back down again — resizing, loading, undo — put the flag back
        // themselves afterwards.
        portalBMayExist = false
    }

    /// Changes the grid size, keeping whatever overlaps the new bounds.
    ///
    /// Momentum and pressure carry over with the cells; the pressure scratch
    /// buffer and the visited marks do not, since both are rebuilt every tick.
    /// Redraws the whole world at a different size, every part of it scaled to fit.
    ///
    /// Unlike ``resize(width:height:)``, which keeps the cells where they are and so crops or pads, this
    /// stretches the world onto the new grid, taking each new cell from the nearest old one. It is for a world
    /// that arrived at another size — from another phone, from the website, from a file saved at a different
    /// detail — which used to stay at its own size and be drawn stretched to fit the screen, every grain a
    /// rectangle rather than a square.
    ///
    /// Momentum is not carried, because a velocity measured in old cells means something different in new
    /// ones; everything simply continues from rest.
    public func resample(width newWidth: Int, height newHeight: Int) {
        guard Self.isValidSize(width: newWidth, height: newHeight) else { return }
        guard newWidth != width || newHeight != height, width > 0, height > 0 else { return }
        let oldWidth = width
        let oldHeight = height
        let oldCount = cellCount
        var oldType = [ElementID](repeating: 0, count: oldCount)
        var oldTemp = [Float](repeating: 0, count: oldCount)
        var oldLife = [UInt16](repeating: 0, count: oldCount)
        for i in 0 ..< oldCount {
            oldType[i] = type[i]
            oldTemp[i] = temperature[i]
            oldLife[i] = life[i]
        }
        resize(width: newWidth, height: newHeight)
        guard width == newWidth, height == newHeight else { return }
        resetGrid()
        for y in 0 ..< height {
            let fromY = min(oldHeight - 1, y * oldHeight / height)
            for x in 0 ..< width {
                let fromX = min(oldWidth - 1, x * oldWidth / width)
                let from = fromY * oldWidth + fromX
                let to = y * width + x
                type[to] = oldType[from]
                temperature[to] = oldTemp[from]
                life[to] = oldLife[from]
                if oldType[from] == Element.portalB { portalBMayExist = true }
            }
        }
    }

    public func resize(width newWidth: Int, height newHeight: Int) {
        // Refused outright if the size cannot be used, rather than clamped into
        // something nearby. Callers check afterwards whether the size they asked for is
        // the size they got — that is how loading a world and restoring an undo step both
        // avoid laying their cells down at a row length that was never adopted.
        guard Self.isValidSize(width: newWidth, height: newHeight) else { return }
        let safeWidth = newWidth
        let safeHeight = newHeight
        if safeWidth == width && safeHeight == height { return }

        let oldWidth = width
        let oldHeight = height
        let oldCapacity = max(1, cellCount)
        let oldType = type
        let oldTemp = temperature
        let oldLife = life
        let oldVelocityX = velocityX
        let oldVelocityY = velocityY
        let oldPressure = pressure
        // Carried across the clear below, because the cells come with it. If the portal
        // happened to fall outside the new bounds this is left needlessly true, which
        // costs one scan and then corrects itself.
        let hadPortal = portalBMayExist

        // Not carried over, so released immediately.
        Self.release(visited, oldCapacity)
        Self.release(pressureNext, oldCapacity)

        width = safeWidth
        height = safeHeight
        cellCount = safeWidth * safeHeight
        let capacity = max(1, cellCount)

        type = Self.makeBuffer(capacity, ElementID(0))
        temperature = Self.makeBuffer(capacity, Float(0))
        life = Self.makeBuffer(capacity, UInt16(0))
        visited = Self.makeBuffer(capacity, UInt8(0))
        velocityX = Self.makeBuffer(capacity, Int8(0))
        velocityY = Self.makeBuffer(capacity, Int8(0))
        pressure = Self.makeBuffer(capacity, Float(0))
        pressureNext = Self.makeBuffer(capacity, Float(0))

        resetGrid()

        let copyWidth = min(oldWidth, safeWidth)
        let copyHeight = min(oldHeight, safeHeight)
        for y in 0 ..< copyHeight {
            let oldRow = y * oldWidth
            let newRow = y * safeWidth
            for x in 0 ..< copyWidth {
                let from = oldRow + x
                let to = newRow + x
                type[to] = oldType[from]
                temperature[to] = oldTemp[from]
                life[to] = oldLife[from]
                velocityX[to] = oldVelocityX[from]
                velocityY[to] = oldVelocityY[from]
                pressure[to] = oldPressure[from]
            }
        }
        portalBMayExist = hadPortal

        Self.release(oldType, oldCapacity)
        Self.release(oldTemp, oldCapacity)
        Self.release(oldLife, oldCapacity)
        Self.release(oldVelocityX, oldCapacity)
        Self.release(oldVelocityY, oldCapacity)
        Self.release(oldPressure, oldCapacity)
    }

    /// How many cells are occupied.
    public var activeParticleCount: Int {
        var count = 0
        for i in 0 ..< cellCount where type[i] != Element.empty {
            count += 1
        }
        return count
    }

    // MARK: - Cell access

    /// Places an element in a cell, or does nothing if the coordinate is outside
    /// the grid.
    ///
    /// - Parameters:
    ///   - temp: Placement temperature. When omitted, the element's own placement
    ///     temperature is used, falling back to the world's ambient.
    ///   - life: Starting lifetime. When omitted, the element's decay time is
    ///     used — except for a fan, which keeps the lifetime it already had if a
    ///     fan is being painted over a fan. That counter is how a fan remembers
    ///     which way it points, so overwriting it would reset its direction on
    ///     every repaint.
    public func setElement(
        _ x: Int,
        _ y: Int,
        _ elementID: ElementID,
        temp: Double? = nil,
        life newLife: Int? = nil
    ) {
        guard isValid(x, y) else { return }
        let idx = index(x, y)
        let definition = elements[elementID]
        let previous = type[idx]

        type[idx] = elementID
        // Deliberate placement is one of only two ways a portal can enter the grid, so
        // this is where the tick learns it has to start looking for them again.
        if elementID == Element.portalB { portalBMayExist = true }

        if let temp {
            temperature[idx] = JS.toFloat32(temp)
        } else if !definition.usesAmbientTemp {
            temperature[idx] = JS.toFloat32(definition.defaultTemp)
        } else {
            temperature[idx] = JS.toFloat32(ambientTemp)
        }

        if let newLife {
            life[idx] = JS.toUInt16(Double(newLife))
        } else if elementID == Element.fan {
            if previous != Element.fan { life[idx] = 0 }
            // Otherwise the existing rotation counter is kept.
        } else {
            life[idx] = JS.toUInt16(Double(definition.decayTicks))
        }

        velocityX[idx] = 0
        velocityY[idx] = 0
    }

    /// Exchanges the contents of two cells and marks both as having moved.
    ///
    /// Marking both is what stops a cell from being processed again later in the
    /// same scan after it has already been displaced — without it, a falling
    /// grain the scan has not reached yet could be moved twice in one tick and
    /// fall at double speed.
    ///
    /// Pressure travels with the cell; the visited marks obviously do not.
    @inlinable
    public func swapCells(_ a: Int, _ b: Int) {
        let typeA = type[a]
        let tempA = temperature[a]
        let lifeA = life[a]
        let velocityXA = velocityX[a]
        let velocityYA = velocityY[a]
        let pressureA = pressure[a]

        type[a] = type[b]
        temperature[a] = temperature[b]
        life[a] = life[b]
        velocityX[a] = velocityX[b]
        velocityY[a] = velocityY[b]
        pressure[a] = pressure[b]

        type[b] = typeA
        temperature[b] = tempA
        life[b] = lifeA
        velocityX[b] = velocityXA
        velocityY[b] = velocityYA
        pressure[b] = pressureA

        visited[a] = 1
        visited[b] = 1
    }

    // MARK: - World controls

    /// Sets the wind, clamped to the range the physics is tuned for.
    public func setWind(_ value: Double) {
        windX = max(-5, min(5, value))
    }

    /// Makes the pressure scratch buffer the live one and vice versa.
    ///
    /// The pressure relaxation pass writes its results into the scratch buffer so
    /// that every cell sees the same generation of input rather than a mixture of
    /// old and new. Exchanging the two afterwards is free, where copying would
    /// cost a pass over the whole grid.
    func swapPressureBuffers() {
        let previous = pressure
        pressure = pressureNext
        pressureNext = previous
    }

    /// Adds shake energy, keeping whichever is larger so a gentle jolt cannot
    /// cancel a violent one already in progress.
    public func jostle(_ amount: Double) {
        jostleLeft = max(jostleLeft, amount)
    }

    /// A cheap fingerprint of the world, for spotting divergence between peers.
    ///
    /// Samples at most about four thousand cells and mixes them with the grid
    /// dimensions and gravity. All arithmetic wraps at 32 bits, matching the web
    /// implementation's `| 0` coercions.
    ///
    /// Vertical gravity is part of it. The original left it out, so two worlds
    /// differing only in gravity direction — an utterly different simulation —
    /// produced the same fingerprint, which is precisely the divergence this exists
    /// to catch.
    public func hashLite() -> Int32 {
        var hash = Int32(truncatingIfNeeded: width) &* 131
            &+ Int32(truncatingIfNeeded: height)
            // `| 0` in the reference: wrapped into range rather than converted. A plain conversion traps on
            // anything past nine quintillion, and gravity arrives here from other phones — one packet claiming
            // an absurd gravity used to crash whoever received it.
            &+ JS.toInt32(JS.round(gravityX * 10)) &* 17
            &+ JS.toInt32(JS.round(gravityY * 10)) &* 29
        guard cellCount > 0 else { return hash }
        let stride = max(1, cellCount / 4000)
        var i = 0
        while i < cellCount {
            // Mixes the value the compact format would actually send, not the raw cell.
            // The two disagreed for any id that does not fit in a byte, so the sender's
            // fingerprint described a world the receiver could not build: the "have we
            // drifted apart?" test stayed true forever, resending the whole grid every
            // tick while the two never converged.
            hash = hash &* 33 &+ Int32(PowderEngine.liteByte(type[i]))
            i += stride
        }
        return hash
    }

    // MARK: - The tick

    /// Advances the world one tick.
    ///
    /// The order is preserved from the web implementation exactly, because every
    /// stage sees the results of the ones before it:
    ///
    /// 1. Clear the visited marks.
    /// 2. Spread heat, and move it along copper — on alternate ticks.
    /// 3. Blow gases sideways — every third tick.
    /// 4. Rebuild the pressure field — on alternate ticks.
    /// 5. Apply any shake energy, then let it decay.
    /// 6. Find the portals, before anything has moved.
    /// 7. Walk every cell: decay, then phase change, then chemistry, then movement.
    ///
    /// Several stages deliberately run less often than every tick. That is not a
    /// shortcut bolted on for speed — the rates are part of the tuning. Heat
    /// diffusing on every tick would even out temperatures faster than material can
    /// move through them, and the thresholds the chemistry depends on would be
    /// reached at the wrong moments.
    ///
    /// Within the cell walk, the vertical direction matters because a falling grain
    /// must be moved before the grain above it, or a whole column collapses in a
    /// single tick instead of falling at a sane speed. The horizontal alternation
    /// matters because scanning one way every time makes piles lean — whichever side
    /// is scanned first gets first refusal on the empty space below.
    public func step() {
        frameCount += 1
        elements = registry.table

        guard cellCount > 0 else { return }
        visited.update(repeating: 0, count: cellCount)

        if heatConductionEnabled && frameCount % 2 == 0 {
            diffuseHeat()
            pipeHeat()
        }

        if windX != 0 && frameCount % 3 == 0 {
            applyWindDrift()
        }

        if pressureEnabled && frameCount % 2 == 0 {
            updatePressure()
        }

        if jostleLeft > 0 {
            applyJostle()
            // Decays fast, so a shake is a jolt rather than a sustained rumble.
            jostleLeft *= 0.72
            if jostleLeft < 0.15 { jostleLeft = 0 }
        }

        // Portals are located before anything moves, so a pair sees a consistent
        // snapshot of the world. Gathering them lazily would let a portal that has
        // already been stepped over teleport into a cell that no longer exists.
        //
        // Skipped entirely unless a portal might be present — see ``portalBMayExist``.
        // At one cell per screen pixel this pass alone reads over three million cells a
        // tick, for something a world almost never contains.
        var portalsB: [(Int, Int)] = []
        if portalBMayExist {
            for y in 0 ..< height {
                for x in 0 ..< width {
                    if type[index(x, y)] == Element.portalB {
                        portalsB.append((x, y))
                    }
                }
            }
            // Nothing found means nothing is there, and nothing can arrive without
            // announcing itself, so the scan can stop happening again.
            if portalsB.isEmpty { portalBMayExist = false }
        }

        // Bottom-up under normal gravity; top-down when it is inverted.
        let scanBottomUp = gravityY >= 0
        let startY = scanBottomUp ? height - 1 : 0
        let endY = scanBottomUp ? -1 : height
        let stepY = scanBottomUp ? -1 : 1

        var y = startY
        while y != endY {
            // Flip the horizontal direction per row and per tick, so no side is
            // consistently favoured.
            let scanLeftRight = (y + frameCount) % 2 == 0
            let startX = scanLeftRight ? 0 : width - 1
            let endX = scanLeftRight ? width : -1
            let stepX = scanLeftRight ? 1 : -1

            var x = startX
            while x != endX {
                let idx = index(x, y)
                if visited[idx] != 0 {
                    x += stepX
                    continue
                }

                let cellType = type[idx]
                if cellType == Element.empty {
                    x += stepX
                    continue
                }

                let definition = elements[cellType]

                // Decay: fire, smoke, sparks, plasma and curing concrete.
                if definition.decayTicks > 0 {
                    if life[idx] > 0 {
                        life[idx] -= 1
                    } else {
                        setElement(x, y, definition.decayIntoID)
                        x += stepX
                        continue
                    }
                }

                // A cell that changed phase or was consumed by a reaction does not
                // also move this tick.
                //
                // Skipped outright for the forty elements that have no phase change at
                // all. The stage is gated on the element in every one of its branches and
                // draws no random numbers outside them, so for those elements calling it
                // and not calling it cannot be told apart. See ``PhaseChangeParticipants``.
                if definition.canChangePhase, updatePhase(x: x, y: y, idx: idx, definition: definition) {
                    x += stepX
                    continue
                }

                if updateReactions(x: x, y: y, idx: idx, definition: definition, portalsB: portalsB) {
                    x += stepX
                    continue
                }

                updateMovement(x: x, y: y, idx: idx, definition: definition)

                x += stepX
            }

            y += stepY
        }
    }
}
