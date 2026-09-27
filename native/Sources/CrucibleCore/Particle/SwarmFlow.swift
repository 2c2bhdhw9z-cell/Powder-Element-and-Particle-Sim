/// Wind with structure: a flowing field that pushes bodies along curling paths.
///
/// Gravity, a vortex and an attractor all pull toward or around a single place, so a field under any of
/// them reads as one thing happening. This is different in kind — it is a *pattern* of motion filling
/// the whole world, with eddies and channels and slow patches, so different parts of the field do
/// different things at once. It is what makes a crowd look like smoke, or a current, or weather.
///
/// ## Why it curls rather than merely varying
///
/// The obvious way to make wind is to pick a direction at each place from some smoothly varying
/// function. That does not look like a fluid, and the reason is worth stating: such a field has places
/// where more flows in than out. Bodies pile up there and thin out at the opposite kind of place, so
/// within a few seconds the crowd has collected into blobs and stopped moving, which reads as clumping
/// rather than as flow.
///
/// The fix is to take the *curl* of a varying quantity rather than the quantity itself. In two dimensions
/// that means going up the slope in one direction and down it in the other:
///
/// ```
/// flow = (∂ψ/∂y, -∂ψ/∂x)
/// ```
///
/// A field made this way has exactly as much flowing out of anywhere as flows in, everywhere, as a matter
/// of arithmetic rather than of tuning. Nothing can collect. That is what gives the endless churn.
///
/// ## What the reference implementation has
///
/// The same idea, and only on the graphics card — there is no version of it on the processor at all, so
/// any scene of its that uses cloth or a painted field silently loses the wind entirely. It also throws
/// away how *fast* the flow is going and keeps only the direction, twice over, so its wind blows at one
/// speed everywhere and the calm patches that make a flow look like a flow do not exist. This one keeps
/// the strength.
public final class SwarmFlow {
    public init() {}

    /// How the wind behaves.
    public struct Settings: Sendable, Hashable, Codable {
        /// How hard it pushes.
        public var strength: Double = 0.35
        /// How large the eddies are, in pixels.
        ///
        /// A hundred and forty, which on a phone-sized field gives four or five eddies across it — few
        /// enough to be seen as shapes rather than as noise, many enough that different parts of the
        /// field are plainly doing different things.
        public var scale: Double = 140
        /// How fast the pattern itself changes, in turns of the pattern per second.
        ///
        /// Not nought. A fixed pattern is a set of channels that the crowd finds and then follows
        /// forever, and after a few seconds nothing changes again. Letting it drift slowly is what keeps
        /// it alive.
        public var drift: Double = 0.08

        public init(strength: Double = 0.35, scale: Double = 140, drift: Double = 0.08) {
            self.strength = strength
            self.scale = scale
            self.drift = drift
        }

        public static let `default` = Settings()

        var sanitized: Settings {
            Settings(
                strength: Self.clamp(strength, 0, 8, fallback: 0.35),
                scale: Self.clamp(scale, 12, 2_000, fallback: 140),
                drift: Self.clamp(drift, 0, 4, fallback: 0.08)
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

    /// Pushes every body along the flow.
    ///
    /// Velocity only, like the other forces, so that the speed limit and the walls still get the last
    /// word.
    public func step(swarm: Swarm, settings: Settings, time: Double) {
        let bodies = swarm.count
        guard bodies > 0 else { return }
        let tuned = settings.sanitized
        guard tuned.strength > 0 else { return }

        let positions = swarm.positions
        let velocities = swarm.velocities
        let inverseScale = 1 / tuned.scale
        let when = time.isFinite ? time * tuned.drift : 0
        let strength = tuned.strength

        for index in 0 ..< bodies {
            let pair = index * 2
            let x = Double(positions[pair])
            let y = Double(positions[pair + 1])
            guard x.isFinite, y.isFinite else { continue }

            let flow = Self.curl(atX: x * inverseScale, y: y * inverseScale, time: when)
            let velX = Double(velocities[pair])
            let velY = Double(velocities[pair + 1])
            guard velX.isFinite, velY.isFinite else { continue }
            velocities[pair] = JS.toFloat32(velX + flow.x * strength)
            velocities[pair + 1] = JS.toFloat32(velY + flow.y * strength)
        }
    }

    /// How far apart two samples of the slope would be taken, if it were measured that way.
    ///
    /// Kept only because the test that checks nothing can pile up uses it: measuring that property needs a
    /// step, and using the same one the slope is defined at makes the cancellation exact as arithmetic
    /// rather than merely close.
    static let slopeStep = 0.01

    /// The direction and strength of the flow at a point.
    ///
    /// The slope is worked out exactly rather than by sampling either side of the point. The obvious way —
    /// four extra samples, two per axis — costs four times as much, and measured at twenty-five thousand
    /// bodies that was ten milliseconds a moment, most of a frame for the wind alone. The blending between
    /// grid corners is a known curve, so its slope is a known curve too; differentiating it on paper turns
    /// four samples into one.
    ///
    /// The order is what makes this a curl rather than a plain gradient: the sideways flow comes from how
    /// the quantity changes *vertically*, and the vertical flow from how it changes *sideways*, with one of
    /// them negated. Swapping the two axes and flipping a sign is the whole of it, and it is why nothing
    /// can pile up.
    static func curl(atX x: Double, y: Double, time: Double) -> (x: Double, y: Double) {
        let slope = gradient(atX: x, y: y, time: time)
        return (x: slope.y, y: -slope.x)
    }

    /// How fast the quantity changes in each direction, worked out exactly.
    ///
    /// Three octaves, each half the size and half the weight of the last. One octave alone gives eddies all
    /// of one size, which reads as a regular pattern; adding smaller ones on top is what makes it look like
    /// weather. The slope of a halved-size octave is twice as steep for the same weight, so the frequency
    /// appears in the sum where the value version would not have it.
    static func gradient(atX x: Double, y: Double, time: Double) -> (x: Double, y: Double) {
        var acrossTotal = 0.0
        var downTotal = 0.0
        var amplitude = 1.0
        var frequency = 1.0
        var weight = 0.0
        for _ in 0 ..< 3 {
            let slope = octaveGradient(x * frequency, y * frequency, time * frequency)
            acrossTotal += amplitude * slope.x * frequency
            downTotal += amplitude * slope.y * frequency
            weight += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        let scale = 1 / max(1e-9, weight)
        return (x: acrossTotal * scale, y: downTotal * scale)
    }

    /// A smoothly varying quantity, the same at the same place every time.
    ///
    /// Value noise: a fixed random number at each corner of a grid, blended smoothly between them. Not the
    /// more usual simplex kind — this is a couple of dozen lines instead of a couple of hundred, and what
    /// matters here is only that it varies smoothly and repeatably, which both do equally.
    ///
    /// Kept alongside the slope version for the tests, which check the quantity itself is smooth.
    static func noise(_ x: Double, _ y: Double, _ time: Double) -> Double {
        var total = 0.0
        var amplitude = 1.0
        var frequency = 1.0
        var weight = 0.0
        for _ in 0 ..< 3 {
            total += amplitude * octave(x * frequency, y * frequency, time * frequency)
            weight += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return total / max(1e-9, weight)
    }

    /// One octave of it.
    static func octave(_ x: Double, _ y: Double, _ time: Double) -> Double {
        // Time is folded in as a third dimension, sampled between two whole layers. Sliding the pattern
        // sideways instead would look like wind blowing the *wind*, which is not the same thing as the
        // pattern itself changing.
        let layer = time.rounded(.down)
        let betweenLayers = smoothed(time - layer)
        let near = plane(x, y, Int(layer))
        let far = plane(x, y, Int(layer) + 1)
        return near + (far - near) * betweenLayers
    }

    /// The slope of one octave, in both directions.
    static func octaveGradient(_ x: Double, _ y: Double, _ time: Double) -> (x: Double, y: Double) {
        let layer = time.rounded(.down)
        let betweenLayers = smoothed(time - layer)
        let near = planeGradient(x, y, Int(layer))
        let far = planeGradient(x, y, Int(layer) + 1)
        return (
            x: near.x + (far.x - near.x) * betweenLayers,
            y: near.y + (far.y - near.y) * betweenLayers
        )
    }

    /// One whole layer: blended between the four corners of the grid square the point falls in.
    static func plane(_ x: Double, _ y: Double, _ layer: Int) -> Double {
        let cellX = x.rounded(.down)
        let cellY = y.rounded(.down)
        let acrossCell = smoothed(x - cellX)
        let downCell = smoothed(y - cellY)

        // Clamped rather than converted, so a body holding an unusable number cannot crash the wind.
        let column = JS.clampedInt(cellX, -1_000_000, 1_000_000)
        let row = JS.clampedInt(cellY, -1_000_000, 1_000_000)
        let topLeft = corner(column, row, layer)
        let topRight = corner(column + 1, row, layer)
        let bottomLeft = corner(column, row + 1, layer)
        let bottomRight = corner(column + 1, row + 1, layer)

        let top = topLeft + (topRight - topLeft) * acrossCell
        let bottom = bottomLeft + (bottomRight - bottomLeft) * acrossCell
        return top + (bottom - top) * downCell
    }

    /// The slope of one layer, from the same four corners.
    ///
    /// The blend is `top + (bottom − top) × v` where `top` and `bottom` are themselves blends along the
    /// other axis. Differentiating that gives the vertical slope as `(bottom − top) × v′`, and the sideways
    /// slope as the difference of the two rows' own slopes blended by `v`, times `u′`. Nothing subtle —
    /// just the product rule applied twice.
    static func planeGradient(_ x: Double, _ y: Double, _ layer: Int) -> (x: Double, y: Double) {
        let cellX = x.rounded(.down)
        let cellY = y.rounded(.down)
        let acrossFraction = x - cellX
        let downFraction = y - cellY
        let acrossCell = smoothed(acrossFraction)
        let downCell = smoothed(downFraction)
        let acrossSlope = smoothedSlope(acrossFraction)
        let downSlope = smoothedSlope(downFraction)

        // Clamped rather than converted, so a body holding an unusable number cannot crash the wind.
        let column = JS.clampedInt(cellX, -1_000_000, 1_000_000)
        let row = JS.clampedInt(cellY, -1_000_000, 1_000_000)
        let topLeft = corner(column, row, layer)
        let topRight = corner(column + 1, row, layer)
        let bottomLeft = corner(column, row + 1, layer)
        let bottomRight = corner(column + 1, row + 1, layer)

        let top = topLeft + (topRight - topLeft) * acrossCell
        let bottom = bottomLeft + (bottomRight - bottomLeft) * acrossCell

        let topRun = topRight - topLeft
        let bottomRun = bottomRight - bottomLeft
        return (
            x: (topRun + (bottomRun - topRun) * downCell) * acrossSlope,
            y: (bottom - top) * downSlope
        )
    }

    /// The blending curve between grid corners.
    ///
    /// Not a straight line. A straight blend leaves a visible crease at every grid line, because the slope
    /// changes abruptly there — and since the flow *is* the slope, those creases show up as a square grid
    /// of sudden changes in direction. This curve has zero slope at both ends, so the creases disappear.
    @inline(__always)
    static func smoothed(_ t: Double) -> Double {
        let clamped = max(0, min(1, t))
        return clamped * clamped * clamped * (clamped * (clamped * 6 - 15) + 10)
    }

    /// How fast that curve is rising. Zero at both ends, which is the property that removes the creases.
    @inline(__always)
    static func smoothedSlope(_ t: Double) -> Double {
        let clamped = max(0, min(1, t))
        let oneMinus = 1 - clamped
        return 30 * clamped * clamped * oneMinus * oneMinus
    }

    /// The fixed random value at one corner of the grid.
    ///
    /// Mixed out of the three whole numbers naming that corner, so it is the same every time without
    /// anything being stored — which is what lets the wind fill an unbounded world.
    @inline(__always)
    static func corner(_ x: Int, _ y: Int, _ z: Int) -> Double {
        // Three odd multipliers to spread the three inputs apart, then the standard avalanche mix, which
        // scatters a change in any single bit across all of them.
        var h = UInt32(truncatingIfNeeded: x &* 0x1B87_3593)
        h ^= UInt32(truncatingIfNeeded: y &* 0x85EB_CA6B)
        h ^= UInt32(truncatingIfNeeded: z &* 0xC2B2_AE35)
        h ^= h >> 16
        h = h &* 0x7FEB_352D
        h ^= h >> 15
        h = h &* 0x846C_A68B
        h ^= h >> 16
        // Centred on nought rather than running from nought to one, so the flow has no overall drift in any
        // direction.
        return Double(h) / 2_147_483_648.0 - 1
    }
}

extension ParticleEngine {
    /// Whether the wind blows.
    public var flowEnabled: Bool {
        get { storedFlowEnabled }
        set { storedFlowEnabled = newValue }
    }

    /// How the wind behaves.
    public var flowSettings: SwarmFlow.Settings {
        get { storedFlowSettings }
        set { storedFlowSettings = newValue }
    }
}
