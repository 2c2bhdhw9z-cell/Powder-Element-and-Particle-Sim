/// What a finger does to a body: the pull, push, swirl, freeze or colour of whichever tool is in hand.
///
/// ## Why this is Built-Helion's brush
///
/// The owner's working reference is Built-Helion, where the tools did what they said on every particle. This
/// field had two brushes of its own instead, and neither was that:
///
///   - **The crowd's** pushed with a constant eight hundredths of a pixel a moment — too faint to see — and
///     had no swirl, freeze or paint at all. Most of the arrangements are made of the crowd, so on most of
///     them the tools did next to nothing.
///   - **The individual bodies'** fell away with the square of the distance, so on a phone's screen, where a
///     finger's width is dozens of the world's pixels, it had faded to almost nothing a short way out.
///
/// Helion's is one rule for everything: a circle a fixed share of the screen high, a push that fades evenly
/// from full at the finger to nothing at the circle's edge, and forces measured in screen heights per second
/// per second — so the same tool feels the same on a phone as on a laptop, and on every arrangement. Its
/// numbers are copied here as they are.
///
/// Three tools this field has and Helion does not are built from Helion's parts: the well is a pull with a
/// swirl in it, the hawk is Helion's short-range repulsor (a hawk scatters a flock), and hyper is a hard pull
/// that does not fade across the circle.
public enum ParticleBrush {
    /// Helion's default strength. The field's own strength setting multiplies it, so one means Helion's.
    public static let defaultStrength = 0.85

    // Helion's accelerations at full strength, in screen heights per second per second.
    static let pullRate = 24.0
    static let pushRate = 26.0
    static let swirlRate = 28.0
    static let scatterRate = 32.0
    // The three tools built from Helion's parts.
    static let wellPullRate = 46.0
    static let wellSwirlRate = 14.0
    static let rushRate = 40.0

    /// Helion's limit on how hard anything may be accelerated, per axis, in screen heights per second per second.
    static let accelerationLimit = 80.0

    /// Moments a second, squared. An acceleration per second per second becomes one per moment per moment by
    /// dividing by this, because the field steps sixty times a second.
    static let momentsSquared = 3_600.0

    /// Whether a tool acts on bodies at all, rather than on the world or not at all.
    public static func touchesBodies(_ mode: ParticleMouseMode) -> Bool {
        switch mode {
        case .attract, .repel, .vortex, .gravityWell, .freeze, .hawk, .hyperDrive, .painter:
            return true
        case .emitter, .current, .wall, .source:
            return false
        }
    }

    /// What the finger does to one body.
    public struct Effect: Sendable, Hashable {
        /// Whether the body is inside the finger's reach at all.
        public var inReach: Bool
        /// The change in velocity, in pixels a moment.
        public var velocityX: Double
        public var velocityY: Double
        /// Whether the body is stopped dead, which is what freezing does.
        public var stops: Bool

        public static let untouched = Effect(inReach: false, velocityX: 0, velocityY: 0, stops: false)
    }

    /// Works out what the finger does to a body at a place.
    ///
    /// - Parameters:
    ///   - reach: how far the finger reaches, in the world's pixels. Infinite means the whole field.
    ///   - strength: how hard, where ``defaultStrength`` is Helion's own.
    ///   - unit: how many of the world's pixels one screen height is. Every force is measured against it, which
    ///     is what makes a tool feel the same whatever the screen.
    @inline(__always)
    public static func effect(
        _ mode: ParticleMouseMode,
        atX x: Double,
        y: Double,
        fingerX: Double,
        fingerY: Double,
        reach: Double,
        strength: Double,
        unit: Double
    ) -> Effect {
        let dx = fingerX - x
        let dy = fingerY - y
        let distanceSquared = dx * dx + dy * dy
        let unlimited = !reach.isFinite
        guard distanceSquared.isFinite else { return .untouched }
        if !unlimited {
            guard reach > 0, distanceSquared < reach * reach else { return .untouched }
        }
        if mode == .freeze {
            return Effect(inReach: true, velocityX: 0, velocityY: 0, stops: true)
        }

        let distance = distanceSquared.squareRoot() + 1e-6
        // Full at the finger, nothing at the edge, evenly in between. With no edge, full everywhere.
        let fall = unlimited ? 1 : max(0, 1 - distance / reach)
        let share = strength * fall
        let towardX = dx / distance
        let towardY = dy / distance

        var ax = 0.0
        var ay = 0.0
        switch mode {
        case .attract:
            ax = towardX * share * pullRate
            ay = towardY * share * pullRate
        case .repel:
            ax = -towardX * share * pushRate
            ay = -towardY * share * pushRate
        case .vortex:
            ax = -towardY * share * swirlRate
            ay = towardX * share * swirlRate
        case .gravityWell:
            ax = towardX * share * wellPullRate - towardY * share * wellSwirlRate
            ay = towardY * share * wellPullRate + towardX * share * wellSwirlRate
        case .hawk:
            // Helion's repulsor: strongest right beside the finger and falling away with distance, which is
            // what makes it scatter rather than shove.
            let scale = max(1e-6, unit)
            let offsetX = dx / scale
            let offsetY = dy / scale
            let k = share * scatterRate / (offsetX * offsetX + offsetY * offsetY + 0.0004)
            ax = -offsetX * k
            ay = -offsetY * k
        case .hyperDrive:
            ax = towardX * strength * rushRate
            ay = towardY * strength * rushRate
        case .painter:
            return Effect(inReach: true, velocityX: 0, velocityY: 0, stops: false)
        case .freeze, .emitter, .current, .wall, .source:
            return .untouched
        }

        ax = max(-accelerationLimit, min(accelerationLimit, ax))
        ay = max(-accelerationLimit, min(accelerationLimit, ay))
        let toPixels = max(0, unit) / momentsSquared
        return Effect(inReach: true, velocityX: ax * toPixels, velocityY: ay * toPixels, stops: false)
    }

    /// The colour the paint tool gives a body.
    ///
    /// Cycling with time and along the crowd, so a stroke leaves a rainbow rather than one flat colour. Floored
    /// to a whole degree, as the reference does.
    public static func paintColor(now: Double, index: Int) -> PackedColor {
        let hue = (now / 10 + Double(index) * 5)
            .truncatingRemainder(dividingBy: 360)
            .rounded(.down)
        return PackedColor(hue: hue.isFinite ? hue : 0, saturation: 0.95, lightness: 0.65)
    }

    /// The colour hyper leaves behind.
    public static let rushColor = PackedColor(r: 0xF4, g: 0x3F, b: 0x5E)
}

extension Swarm {
    /// What the finger does to the crowd, for one moment.
    ///
    /// Velocities only, and colours for the two tools that paint. Bodies that hold a place in a shape feel it
    /// exactly as loose ones do; their shape is what pulls them back once the finger has gone, so a shape can
    /// be pushed through, pulled apart or swirled, and then mends.
    public func applyBrush(
        _ mode: ParticleMouseMode,
        fingerX: Double,
        fingerY: Double,
        reach: Double,
        strength: Double,
        unit: Double,
        now: Double
    ) {
        guard count > 0, ParticleBrush.touchesBodies(mode), fingerX.isFinite, fingerY.isFinite else { return }
        let rush = ParticleBrush.rushColor.packedRGBA
        for i in 0 ..< count {
            let pair = i * 2
            let x = Double(positions[pair])
            let y = Double(positions[pair + 1])
            guard x.isFinite, y.isFinite else { continue }
            let effect = ParticleBrush.effect(
                mode,
                atX: x,
                y: y,
                fingerX: fingerX,
                fingerY: fingerY,
                reach: reach,
                strength: strength,
                unit: unit
            )
            guard effect.inReach else { continue }
            if effect.stops {
                velocities[pair] = 0
                velocities[pair + 1] = 0
                continue
            }
            if mode == .painter {
                colors[i] = ParticleBrush.paintColor(now: now, index: i).packedRGBA
                continue
            }
            velocities[pair] = JS.toFloat32(Double(velocities[pair]) + effect.velocityX)
            velocities[pair + 1] = JS.toFloat32(Double(velocities[pair + 1]) + effect.velocityY)
            if mode == .hyperDrive { colors[i] = rush }
        }
    }
}
