/// Making the swarm behave like a liquid.
///
/// The field has had a **Fluid** switch in its settings since it was ported. It is saved with a scene,
/// it is reset when the field is cleared, and nothing has ever read it. This is what it does.
///
/// ## What "like a liquid" means here
///
/// Each body works out how crowded it is, turns that into a pressure, and pushes away from wherever the
/// pressure is higher. Crowding is measured by adding up a weight for every nearby body — closer counts
/// for more — which spreads a handful of separate points into a continuous quantity. Two extra terms
/// make it read as water rather than as a gas: a drag between neighbours moving at different speeds,
/// which is what makes it thick, and a pull toward neighbours, which is what makes it bead up and hold a
/// surface instead of spreading out to a film one body deep.
///
/// ## The reference implementation's version is wrong, and this one is not
///
/// Worth stating precisely, because the numbers had to be re-derived rather than copied.
///
///   - **Its weighting does not add up to one.** Adding up that weight over the whole area it covers
///     comes to two thirds, not one, so every crowding figure it produces is two thirds of the truth.
///     That does not break it — it can be tuned around — but it does mean its rest-crowding setting is
///     an arbitrary number with no meaning. Here the weighting is normalised properly, and the
///     consequence is that crowding *is* mass per unit area: set the rest figure to one over the square
///     of the spacing you want and that is the spacing you get.
///   - **Its pressure is one-sided.** It divides by the neighbour's crowding only, so two bodies push on
///     each other by different amounts. Momentum is not conserved, and a fluid that invents momentum
///     drifts and heats up. Here the term is symmetric, so every push has an equal and opposite one.
///   - **What it calls a velocity correction is a second drag** with a different coefficient, added into
///     acceleration. It is not the thing it is named after. There is one drag term here, and it is
///     called one.
///
/// None of that is a claim that this is physically accurate. It is an approximation with invented
/// coefficients like every other real-time fluid; the difference is that the parts which have a right
/// answer have it.
///
/// ## Cost
///
/// Two passes over every body and all of its neighbours. That is the same shape of work as pushing
/// bodies apart, which costs about a millisecond per thousand — so this is not something to switch on at
/// a million bodies, and ``SwarmCost`` says so with measured numbers rather than leaving it to be
/// discovered.
public final class SwarmFluid {
    /// How crowded each body is. Mass per unit area.
    private var density: [Float] = []
    /// How hard each body is pushing outward.
    private var pressure: [Float] = []
    /// What the pass decided each body should do, before any of it is applied.
    ///
    /// Held apart from the velocities on purpose, and it is worth knowing why because getting it wrong
    /// does not look like a small error. The thickness term reads a neighbour's velocity; if the pass
    /// wrote its answers straight into the velocities as it went, body two would read body one's *new*
    /// velocity, body three would read body two's, and so on. Each body would amplify the one before it,
    /// and two hundred bodies in a row compounds that into numbers with twenty-six digits — which is
    /// exactly what happened the first time this was written, and what the tests caught.
    ///
    /// Keeping them apart also makes the pass independent of the order the bodies happen to be in, which
    /// is a property worth having on its own.
    private var pushX: [Float] = []
    private var pushY: [Float] = []
    private let grid = SwarmGrid()

    /// Whether the last pass found more bodies in one square than it could hold.
    ///
    /// Reported rather than hidden. Past the limit the crowding is under-counted, which makes the fluid
    /// read as thinner than it is — and a fluid that reads as thinner than it is does not gently lose
    /// accuracy, it stops holding itself apart and collapses.
    public private(set) var isOverCrowded = false

    public init() {}

    /// The settings the fluid needs, all in the same pixels and ticks the rest of the field uses.
    public struct Settings: Sendable, Hashable, Codable {
        /// How far a body looks for neighbours, in pixels.
        ///
        /// Twelve, which at the rest spacing below gives a body about eighteen neighbours. That number
        /// is the whole trade-off: too few and the crowding figure jumps about as individual bodies
        /// cross the boundary, which reads as the fluid boiling; too many and every body is comparing
        /// itself against hundreds of others twice a tick, which is what decides whether the fluid can
        /// be switched on at all. Eighteen is the usual figure for this kind of fluid and it is also
        /// about where the cost stops being reasonable.
        public var smoothing: Double = 12
        /// The crowding the fluid is happy at — mass per square pixel.
        ///
        /// Four hundredths, which is one body per twenty-five square pixels, or a spacing of five
        /// pixels. Because the weighting is properly normalised this number means exactly that, rather
        /// than being a figure arrived at by trial.
        public var restDensity: Double = 0.04
        /// How hard the fluid resists being squashed.
        public var stiffness: Double = 1.8
        /// How thick it is — the drag between neighbours moving at different speeds.
        public var viscosity: Double = 0.12
        /// How much it beads up rather than spreading out.
        public var cohesion: Double = 0.35

        public init(
            smoothing: Double = 12,
            restDensity: Double = 0.04,
            stiffness: Double = 1.8,
            viscosity: Double = 0.12,
            cohesion: Double = 0.35
        ) {
            self.smoothing = smoothing
            self.restDensity = restDensity
            self.stiffness = stiffness
            self.viscosity = viscosity
            self.cohesion = cohesion
        }

        public static let `default` = Settings()

        /// The settings with every number pulled into a range the pass can work in.
        var sanitized: Settings {
            Settings(
                smoothing: Self.clamp(smoothing, 4, 120, fallback: 12),
                restDensity: Self.clamp(restDensity, 0.0005, 1, fallback: 0.04),
                stiffness: Self.clamp(stiffness, 0, 20, fallback: 1.8),
                viscosity: Self.clamp(viscosity, 0, 1, fallback: 0.12),
                cohesion: Self.clamp(cohesion, 0, 2, fallback: 0.35)
            )
        }

        private static func clamp(
            _ value: Double,
            _ low: Double,
            _ high: Double,
            fallback: Double
        ) -> Double {
            guard value.isFinite else { return fallback }
            return max(low, min(high, value))
        }
    }

    /// Runs one step of the fluid over a swarm, changing velocities only.
    ///
    /// Velocities rather than positions, so that the rest of the tick — the speed limit, the walls, the
    /// finger — sees the fluid's contribution and can moderate it. A pass that moved bodies directly
    /// would be able to push them through a wall, and nothing afterwards would notice.
    public func step(
        swarm: Swarm,
        settings: Settings,
        width: Double,
        height: Double
    ) {
        let bodies = swarm.count
        guard bodies > 1, width > 0, height > 0 else {
            isOverCrowded = false
            return
        }

        let tuned = settings.sanitized
        let h = tuned.smoothing

        // The squares are made exactly as wide as a body can see, so the nine around it are enough. Any
        // narrower and a neighbour just outside the middle square's ring would be missed; any wider and
        // the pass examines bodies it then throws away.
        grid.build(
            positions: swarm.positions,
            count: bodies,
            width: width,
            height: height,
            cellSize: h
        )
        isOverCrowded = grid.overflowed

        // The grid may have widened its squares to keep their number manageable over a large world. When
        // it does, the nine squares no longer cover everything within reach and the fluid would be
        // measuring a smaller neighbourhood than it was asked for — so the reach follows the squares.
        let reach = min(h, grid.cellSize)
        let reachSquared = reach * reach

        // Weighting: `(1 - r/reach)` squared, scaled so that adding it up over the whole circle it
        // covers comes to exactly one. That integral works out to a sixth of pi times the radius
        // squared, so the scale is six over pi r squared. This is the constant the reference
        // implementation has as four rather than six.
        let weightScale = 6 / (3.141592653589793 * reachSquared)
        // And the rate at which the weighting falls off, for the push. The slope of the weighting is
        // twelve over pi r cubed times how far in from the edge the point is.
        let slopeScale = 12 / (3.141592653589793 * reachSquared * reach)

        // Taken once. Both passes walk it directly — see the note on `SwarmGrid.Storage` for why this
        // is not a "call me for each neighbour" method.
        guard let cells = grid.storage() else { return }

        if density.count < bodies {
            let extra = bodies - density.count
            density.append(contentsOf: repeatElement(0, count: extra))
            pressure.append(contentsOf: repeatElement(0, count: extra))
            pushX.append(contentsOf: repeatElement(0, count: extra))
            pushY.append(contentsOf: repeatElement(0, count: extra))
        }

        let positions = swarm.positions
        let velocities = swarm.velocities
        let masses = swarm.masses

        // MARK: How crowded each body is

        density.withUnsafeMutableBufferPointer { densityBuffer in
            pressure.withUnsafeMutableBufferPointer { pressureBuffer in
                let restDensity = max(1e-6, tuned.restDensity)
                for index in 0 ..< bodies {
                    let pair = index * 2
                    let x = Double(positions[pair])
                    let y = Double(positions[pair + 1])
                    guard x.isFinite, y.isFinite else {
                        densityBuffer[index] = Float(restDensity)
                        pressureBuffer[index] = 0
                        continue
                    }

                    // A body counts itself. At the closest possible distance the weighting is at its
                    // full value, so this is one whole unit of mass in the place the body actually is —
                    // leaving it out would make an isolated body read as having no crowding at all, and
                    // then dividing by that crowding would be dividing by nothing.
                    // A body counts its own weight, not one — crowding is mass per unit area, so a heavy
                    // body genuinely makes its surroundings denser.
                    var crowding = weightScale * Double(masses[index])
                    let (ownColumn, ownRow) = cells.cell(atX: x, y: y)
                    var scanRow = max(0, ownRow - 1)
                    let lastRow = min(cells.rows - 1, ownRow + 1)
                    let firstColumn = max(0, ownColumn - 1)
                    let lastColumn = min(cells.columns - 1, ownColumn + 1)
                    while scanRow <= lastRow {
                        let rowStart = scanRow * cells.columns
                        var scanColumn = firstColumn
                        while scanColumn <= lastColumn {
                            let cell = rowStart + scanColumn
                            let filled = Int(cells.counts[cell])
                            let base = cell * cells.stride
                            var slot = 0
                            while slot < filled {
                                let other = Int(cells.entries[base + slot])
                                slot += 1
                                guard other != index else { continue }
                                let otherPair = other * 2
                                let dx = Double(positions[otherPair]) - x
                                let dy = Double(positions[otherPair + 1]) - y
                                let distanceSquared = dx * dx + dy * dy
                                guard distanceSquared < reachSquared else { continue }
                                let falloff = 1 - distanceSquared.squareRoot() / reach
                                crowding += weightScale * falloff * falloff * Double(masses[other])
                            }
                            scanColumn += 1
                        }
                        scanRow += 1
                    }

                    densityBuffer[index] = Float(crowding)
                    // Never negative. A fluid that pulls itself together where it is thin is a fluid
                    // that collapses into clumps, which is the opposite of what the surface term below
                    // is carefully arranged to do.
                    pressureBuffer[index] = Float(max(0, tuned.stiffness * (crowding - restDensity)))
                }

                // MARK: What that pushes each body to do

                let viscosity = tuned.viscosity
                let cohesion = tuned.cohesion
                pushX.withUnsafeMutableBufferPointer { outX in
                pushY.withUnsafeMutableBufferPointer { outY in
                for index in 0 ..< bodies {
                    outX[index] = 0
                    outY[index] = 0
                    let pair = index * 2
                    let x = Double(positions[pair])
                    let y = Double(positions[pair + 1])
                    guard x.isFinite, y.isFinite else { continue }

                    let own = max(1e-6, Double(densityBuffer[index]))
                    let ownPressure = Double(pressureBuffer[index])
                    let velX = Double(velocities[pair])
                    let velY = Double(velocities[pair + 1])
                    guard velX.isFinite, velY.isFinite else { continue }

                    // How thin the fluid is here, from nought in the middle of it to one at a free
                    // surface. This is what lets the pull toward neighbours act only at the edges: in
                    // the body of the fluid it would just add to the pressure it is fighting, and the
                    // two would cancel into a slightly stiffer fluid rather than into a surface.
                    let surface = max(0, 1 - own / max(1e-6, tuned.restDensity))

                    var pushX = 0.0
                    var pushY = 0.0

                    let (ownColumn, ownRow) = cells.cell(atX: x, y: y)
                    var scanRow = max(0, ownRow - 1)
                    let lastRow = min(cells.rows - 1, ownRow + 1)
                    let firstColumn = max(0, ownColumn - 1)
                    let lastColumn = min(cells.columns - 1, ownColumn + 1)
                    while scanRow <= lastRow {
                        let rowStart = scanRow * cells.columns
                        var scanColumn = firstColumn
                        while scanColumn <= lastColumn {
                        let cell = rowStart + scanColumn
                        let filled = Int(cells.counts[cell])
                        let base = cell * cells.stride
                        var slot = 0
                        while slot < filled {
                        let other = Int(cells.entries[base + slot])
                        slot += 1
                        guard other != index else { continue }
                        let otherPair = other * 2
                        let dx = Double(positions[otherPair]) - x
                        let dy = Double(positions[otherPair + 1]) - y
                        let distanceSquared = dx * dx + dy * dy
                        guard distanceSquared < reachSquared, distanceSquared > 1e-12 else { continue }

                        let distance = distanceSquared.squareRoot()
                        let falloff = 1 - distance / reach
                        let otherDensity = max(1e-6, Double(densityBuffer[other]))
                        let otherPressure = Double(pressureBuffer[other])

                        // Away from the neighbour.
                        let awayX = -dx / distance
                        let awayY = -dy / distance

                        // The push apart. Each body's pressure is divided by the square of its *own*
                        // crowding, so the pair exchange equal and opposite amounts — which is what the
                        // reference implementation gets wrong by dividing both by the neighbour's.
                        let share = ownPressure / (own * own) + otherPressure / (otherDensity * otherDensity)
                        let strength = share * slopeScale * falloff
                        pushX += awayX * strength
                        pushY += awayY * strength

                        // The drag between them, which is what makes it thick. Toward the neighbour's
                        // velocity, in proportion to how much faster it is going.
                        //
                        // The weighting matters here more than anywhere else. A body's share of the
                        // area is one over its crowding, and the weighting adds up to one over the
                        // whole neighbourhood, so multiplying the two gives a total of about one —
                        // meaning a thickness of one would pull a body all the way to its neighbours'
                        // average speed in a single tick, and anything less is a fraction of the way.
                        //
                        // Leaving the weighting out was the first version of this, and the total came
                        // out about a hundred and seventy times too large: instead of damping toward
                        // the neighbours it overshot past them, every tick, and the test that asked
                        // whether thick fluid was calmer than thin found it seven times livelier.
                        if viscosity > 0 {
                            let relativeX = Double(velocities[otherPair]) - velX
                            let relativeY = Double(velocities[otherPair + 1]) - velY
                            if relativeX.isFinite, relativeY.isFinite {
                                let weight = viscosity * weightScale * falloff * falloff / otherDensity
                                pushX += relativeX * weight
                                pushY += relativeY * weight
                            }
                        }

                        // The pull together, which is what gives it a surface. Only at the surface —
                        // see above.
                        if cohesion > 0, surface > 0 {
                            let weight = cohesion * surface * falloff * falloff * weightScale
                            pushX -= awayX * weight / own
                            pushY -= awayY * weight / own
                        }
                        }
                        scanColumn += 1
                        }
                        scanRow += 1
                    }

                    guard pushX.isFinite, pushY.isFinite else { continue }

                    // Bounded. The pass is an approximation with invented coefficients, and a setting
                    // pushed to an extreme can ask for a change of velocity with no sensible size —
                    // which, stored as a single-precision number, becomes infinity, and infinity later
                    // meets the speed limit and turns into not-a-number, at which point the body is
                    // gone for good and nothing says why. A limit here means an extreme setting looks
                    // wrong rather than destroying the field.
                    let asked = (pushX * pushX + pushY * pushY).squareRoot()
                    if asked > Self.pushLimit {
                        let scale = Self.pushLimit / asked
                        outX[index] = Float(pushX * scale)
                        outY[index] = Float(pushY * scale)
                    } else {
                        outX[index] = Float(pushX)
                        outY[index] = Float(pushY)
                    }
                }

                // MARK: And only now, apply it
                //
                // Separated from working it out, because the thickness term reads a neighbour's
                // velocity — so changing velocities while still reading them would let each body
                // amplify the one before it. See the note on the buffers.
                for index in 0 ..< bodies {
                    let pair = index * 2
                    let velX = Double(velocities[pair])
                    let velY = Double(velocities[pair + 1])
                    guard velX.isFinite, velY.isFinite else { continue }
                    velocities[pair] = JS.toFloat32(velX + Double(outX[index]))
                    velocities[pair + 1] = JS.toFloat32(velY + Double(outY[index]))
                }
                }
                }
            }
        }
    }

    /// The most the fluid may change one body's velocity by in one tick.
    ///
    /// Sixty, which is twice the field's default speed limit — so the fluid can always overcome a body
    /// travelling at full speed, and can never ask for something with no sensible size.
    static let pushLimit = 60.0

    /// How crowded a body is, for tests and diagnostics.
    ///
    /// Mass per square pixel, so it can be compared directly against the rest figure — which is the
    /// whole practical benefit of normalising the weighting properly.
    public func crowding(at index: Int) -> Double {
        guard index >= 0, index < density.count else { return 0 }
        return Double(density[index])
    }
}
