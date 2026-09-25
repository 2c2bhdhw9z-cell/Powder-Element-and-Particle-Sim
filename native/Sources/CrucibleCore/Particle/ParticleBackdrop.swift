/// What the field sits on, and how brightly it glows.
///
/// Two small things that between them change the character of the whole chamber more than any physics
/// setting does. The field has always been a scatter of points on flat near-black; a starfield behind
/// it and a bloom around it make the same arrangement of bodies read as a photograph of something
/// rather than as a chart.
///
/// Both are drawn by the graphics card, so what lives here is the choice and the numbers — which is the
/// part that can be saved, restored and tested.

/// What is drawn behind the field.
public enum ParticleBackdrop: String, Sendable, Hashable, CaseIterable, Codable {
    /// Nothing. Flat near-black, which is what the field has always had.
    case none
    /// Stars, twinkling, in three sizes.
    case starfield
    /// A cool top and a warm bottom, clear through the middle.
    case gradient
    /// Two soft clouds of colour, drifting.
    case nebula

    /// A name for the interface.
    public var displayName: String {
        switch self {
        case .none: return "None"
        case .starfield: return "Stars"
        case .gradient: return "Gradient"
        case .nebula: return "Nebula"
        }
    }

    /// The number the shader switches on.
    ///
    /// Written out rather than taken from the order of the cases, so adding one cannot silently
    /// renumber the rest.
    public var shaderIdentifier: Int32 {
        switch self {
        case .none: return 0
        case .starfield: return 1
        case .gradient: return 2
        case .nebula: return 3
        }
    }

    /// Whether this one changes from frame to frame.
    ///
    /// Stars twinkle and clouds drift; a gradient does not. Nothing depends on this yet, but a
    /// backdrop that does not move is one the drawing could skip redrawing — and the distinction is
    /// cheaper to record now than to work out later.
    public var moves: Bool {
        switch self {
        case .none, .gradient: return false
        case .starfield, .nebula: return true
        }
    }
}

/// How the glow behaves.
public struct ParticleGlow: Sendable, Hashable, Codable {
    /// How bright the glow is when added back over the field. Nought switches it off entirely.
    ///
    /// Off by default. A glow suits some scenes and ruins others — a lattice or a cloth wants crisp
    /// edges — so it is offered rather than assumed.
    public var strength: Double = 0
    /// How far the glow spreads, in pixels of the half-size picture it is built in.
    ///
    /// Held apart from the strength deliberately. The reference implementation ties the two together,
    /// so asking for a brighter glow there also gives a wider one — which is why turning it up reads as
    /// a haze settling over everything rather than as the bright things getting brighter.
    public var spread: Double = 2.2
    /// How bright something has to be before it glows at all.
    ///
    /// Without this every dim body glows faintly, and the sum of that is a uniform wash that lifts the
    /// black and flattens the picture.
    public var threshold: Double = 0.32

    public init(strength: Double = 0, spread: Double = 2.2, threshold: Double = 0.32) {
        self.strength = strength
        self.spread = spread
        self.threshold = threshold
    }

    public static let `default` = ParticleGlow()

    /// The settings with every number pulled into a usable range.
    public var sanitized: ParticleGlow {
        ParticleGlow(
            strength: Self.clamp(strength, 0, 4, fallback: 0),
            spread: Self.clamp(spread, 0.2, 12, fallback: 2.2),
            threshold: Self.clamp(threshold, 0, 1, fallback: 0.32)
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

extension ParticleEngine {
    /// What is drawn behind the field.
    public var backdrop: ParticleBackdrop {
        get { storedBackdrop }
        set { storedBackdrop = newValue }
    }

    /// How brightly the field glows.
    public var glow: ParticleGlow {
        get { storedGlow }
        set { storedGlow = newValue }
    }

    /// How brightly the backdrop is drawn.
    ///
    /// Separate from the choice of backdrop so a starfield can be turned down to a hint without being
    /// swapped for a different one — which is what somebody usually wants when a backdrop is competing
    /// with the field rather than sitting behind it.
    public var backdropStrength: Double {
        get { storedBackdropStrength }
        set { storedBackdropStrength = newValue.isFinite ? max(0, min(2, newValue)) : 1 }
    }
}
