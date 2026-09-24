/// An element's identifier.
///
/// Sixteen bits, matching the `Uint16Array` the web reference implementation uses
/// for its grid. Built-in elements occupy `0 ..< 50`; everything from 50 up is
/// available for user-authored custom elements.
public typealias ElementID = UInt16

/// The empty cell. Not "air the element" — genuinely nothing, and the value a
/// freshly allocated grid is full of.
public let emptyElementID: ElementID = 0

/// How an element behaves in bulk, which decides which movement rules apply to
/// it.
///
/// Raw values match the web reference implementation's strings so scenes and
/// custom elements stay readable and interchangeable between the two.
public enum ElementState: String, Sendable, Hashable, CaseIterable, Codable {
    /// Immovable structure: stone, bedrock, wire. Gravity never applies.
    case solidFixed = "solid_fixed"
    /// Granular solid: sand, salt, snow. Falls, piles, slides down slopes.
    case solidMovable = "solid_movable"
    /// Flows and levels out: water, oil, lava, mercury.
    case liquid
    /// Rises or drifts: steam, smoke, helium.
    case gas
    /// Extremely hot ionized matter.
    case plasma
    /// Not matter at all: sparks, laser beams. Travels rather than falls.
    case energy
    /// Rule-breakers with bespoke behavior: portals, cloners, the void.
    case special

    /// Whether the position-based color jitter applies to this state.
    ///
    /// Only granular and fixed solids are textured. Liquids, gases, plasma and
    /// energy must render flat — jittering them produced the "glittery water"
    /// bug recorded in the reference implementation's debug notes, because a
    /// liquid's cells move every frame and so the per-position jitter reshuffles
    /// constantly, making the whole body sparkle.
    @inlinable
    public var isTextured: Bool {
        self == .solidMovable || self == .solidFixed
    }
}

/// The palette grouping an element is filed under in the element picker.
public enum ElementCategory: String, Sendable, Hashable, CaseIterable, Codable {
    case solids = "Solids"
    case liquids = "Liquids"
    case gases = "Gases"
    case energetic = "Energetic"
    case biological = "Biological"
    case special = "Special"
    case custom = "Custom"
}

/// A declarative "when this touches that" rule.
///
/// The reference implementation defines this type and evaluates it generically,
/// but only four such rules actually exist in its registry — essentially all of
/// the real chemistry is hand-written control flow instead. The type is carried
/// over because it is the mechanism user-authored custom elements use to define
/// reactions without writing code.
public struct InteractionRule: Sendable, Hashable, Codable {
    /// The element this rule fires against.
    public var targetElementID: ElementID
    /// Probability per tick, from zero to one.
    public var chance: Double
    /// What this cell becomes. `nil` leaves it unchanged.
    public var resultSelfID: ElementID?
    /// What the neighbouring cell becomes. `nil` leaves it unchanged.
    public var resultTargetID: ElementID?
    /// An extra element placed in nearby free space, if there is any.
    public var spawnElementID: ElementID?
    /// Heat released (positive) or absorbed (negative), in degrees Celsius.
    public var tempChange: Double
    /// Radius of an explosion triggered by the reaction. Zero means none.
    public var explosionRadius: Int

    public init(
        targetElementID: ElementID,
        chance: Double,
        resultSelfID: ElementID? = nil,
        resultTargetID: ElementID? = nil,
        spawnElementID: ElementID? = nil,
        tempChange: Double = 0,
        explosionRadius: Int = 0
    ) {
        self.targetElementID = targetElementID
        self.chance = chance
        self.resultSelfID = resultSelfID
        self.resultTargetID = resultTargetID
        self.spawnElementID = spawnElementID
        self.tempChange = tempChange
        self.explosionRadius = explosionRadius
    }
}

/// Everything the simulation knows about one kind of matter.
///
/// ## Optionals resolved into defaults
///
/// Most of these properties are optional in the web reference implementation and
/// get a fallback applied at each use site — `def.viscosity || 1`,
/// `def.decayTicks || 0`, `def.gravityFactor !== undefined ? … : 1`, and so on.
/// Scattering those fallbacks across the physics modules is both a performance
/// cost and a correctness hazard: miss one and an element silently behaves
/// differently in one subsystem than another.
///
/// Here the defaults are applied exactly once, in this initializer, and every
/// property the physics reads is non-optional. The two genuinely absent-able
/// values keep their optionality because "absent" means something specific that
/// no number could express:
///
/// - ``ignitionTemp`` — `nil` means *never self-ignites*, which is different
///   from igniting at zero degrees.
/// - ``defaultTemp`` — `nil` means *start at whatever the world's ambient
///   temperature currently is*, which is a runtime value, not a constant.
///
/// ## Why `Double` and not `Float`
///
/// Every number in JavaScript is a double. Using `Float` here would make the
/// native physics disagree with the reference implementation's test suite in the
/// last decimal places, and those disagreements compound over thousands of
/// ticks. Fidelity to the oracle outranks the memory saving.
public struct ElementDefinition: Sendable, Hashable {
    /// Stable identifier. Also the value stored in the grid.
    public var id: ElementID
    /// Display name, as shown in the picker.
    public var name: String
    /// Palette grouping.
    public var category: ElementCategory
    /// Bulk behavior, which selects the movement rules.
    public var state: ElementState

    /// Base color, pre-parsed from hex at load time.
    public var color: PackedColor
    /// Strength of the position-based color jitter that gives solids a grain,
    /// as a percentage. Zero means render flat.
    public var colorVariation: Double

    /// Relative heaviness, used for buoyancy and displacement. Air is around 1,
    /// water 10, sand 15, metal 50.
    public var density: Double
    /// Flow sluggishness for liquids. One is instant; ten is honey.
    ///
    /// Normalized to at least a small positive value at construction, because
    /// the reference implementation reads it as `def.viscosity || 1` — a stored
    /// zero would there become one, and dividing by it here must never happen.
    public var viscosity: Double
    /// Likelihood of catching fire near heat, from zero to one hundred.
    public var flammability: Double
    /// How quickly it is consumed once alight.
    public var burnRate: Double
    /// Resistance to acid, from zero to one hundred.
    public var acidResistance: Double
    /// Rate heat moves through it, from zero to one.
    public var heatConductivity: Double
    /// Temperature at which it ignites unaided. `nil` means it never does.
    public var ignitionTemp: Double?
    /// Temperature it is placed at. `nil` means the world's ambient temperature.
    public var defaultTemp: Double?

    /// Lifetime in ticks before it decays. Zero means it is permanent.
    public var decayTicks: Int
    /// What it leaves behind when it decays. Zero is the empty cell.
    public var decayIntoID: ElementID

    /// Gravity multiplier. One is normal, zero is suspended, negative rises.
    public var gravityFactor: Double
    /// Whether sparks travel through it.
    public var isConductor: Bool

    /// Declarative reactions, used mainly by custom elements.
    public var interactions: [InteractionRule]
    /// Encyclopedia blurb.
    public var info: String

    public init(
        id: ElementID,
        name: String,
        category: ElementCategory,
        state: ElementState,
        color: PackedColor,
        colorVariation: Double = 0,
        density: Double,
        viscosity: Double = 1,
        flammability: Double = 0,
        burnRate: Double = 0,
        acidResistance: Double = 0,
        heatConductivity: Double = 0,
        ignitionTemp: Double? = nil,
        defaultTemp: Double? = nil,
        decayTicks: Int = 0,
        decayIntoID: ElementID = emptyElementID,
        gravityFactor: Double = 1,
        isConductor: Bool = false,
        interactions: [InteractionRule] = [],
        info: String = ""
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.state = state
        self.color = color
        self.colorVariation = colorVariation
        self.density = density
        // Mirrors `def.viscosity || 1`: zero is not a meaningful flow rate.
        self.viscosity = viscosity == 0 ? 1 : viscosity
        self.flammability = flammability
        self.burnRate = burnRate
        self.acidResistance = acidResistance
        self.heatConductivity = heatConductivity
        self.ignitionTemp = ignitionTemp
        self.defaultTemp = defaultTemp
        self.decayTicks = decayTicks
        self.decayIntoID = decayIntoID
        self.gravityFactor = gravityFactor
        self.isConductor = isConductor
        self.interactions = interactions
        self.info = info
    }

    /// Convenience for the registry's literal table, where colors are written as
    /// hex exactly as they appear in the reference implementation.
    ///
    /// An unparseable color is a programming error in a compiled-in table, so it
    /// fails loudly rather than silently substituting something wrong.
    public init(
        id: ElementID,
        name: String,
        category: ElementCategory,
        state: ElementState,
        hex: String,
        colorVariation: Double = 0,
        density: Double,
        viscosity: Double = 1,
        flammability: Double = 0,
        burnRate: Double = 0,
        acidResistance: Double = 0,
        heatConductivity: Double = 0,
        ignitionTemp: Double? = nil,
        defaultTemp: Double? = nil,
        decayTicks: Int = 0,
        decayIntoID: ElementID = emptyElementID,
        gravityFactor: Double = 1,
        isConductor: Bool = false,
        interactions: [InteractionRule] = [],
        info: String = ""
    ) {
        guard let parsed = PackedColor(hex: hex) else {
            preconditionFailure("Element \(id) (\(name)) has an invalid color literal: \(hex)")
        }
        self.init(
            id: id,
            name: name,
            category: category,
            state: state,
            color: parsed,
            colorVariation: colorVariation,
            density: density,
            viscosity: viscosity,
            flammability: flammability,
            burnRate: burnRate,
            acidResistance: acidResistance,
            heatConductivity: heatConductivity,
            ignitionTemp: ignitionTemp,
            defaultTemp: defaultTemp,
            decayTicks: decayTicks,
            decayIntoID: decayIntoID,
            gravityFactor: gravityFactor,
            isConductor: isConductor,
            interactions: interactions,
            info: info
        )
    }

    /// Whether this element occupies space that movement rules must respect.
    @inlinable
    public var isEmpty: Bool { id == emptyElementID }
}
