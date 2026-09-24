/// The physical properties of one element, stripped of everything the simulation
/// does not need.
///
/// ## Why this exists separately from ``ElementDefinition``
///
/// The web implementation calls `registry.getElement(type)` from inside its
/// per-cell loop — a hash lookup returning an object carrying a name, a
/// description and a reactions array. That is fine in JavaScript, where it is
/// far from the dominant cost. In Swift it would be the dominant cost: handing
/// back a struct containing a `String` and an `Array` means reference-count
/// traffic on every cell of every frame, which is both slow and a barrier to
/// running the simulation across threads.
///
/// So the simulation reads this instead: plain numbers and enums, no references,
/// no allocation, nothing to retain or release. ``ElementDefinition`` remains the
/// model the picker, the encyclopedia and the element editor use.
///
/// ## Absent values without `Optional`
///
/// ``ignitionTemp`` and ``defaultTemp`` are genuinely absent for most elements,
/// but wrapping them in `Optional` would add a branch to a hot path. They use
/// not-a-number as the absent marker instead, which turns out to be exactly
/// right rather than merely compact: every comparison against not-a-number is
/// false, so `temperature >= ignitionTemp` naturally answers "no" for an element
/// that never self-ignites, with no check needed.
public struct ElementPhysics: Sendable, Hashable {
    /// Bulk behavior, which selects the movement rules.
    public var state: ElementState
    /// Whether sparks travel through it.
    public var isConductor: Bool
    /// Whether an element is actually registered at this identifier. Unregistered
    /// slots hold air's properties so the simulation stays well-behaved if a
    /// corrupt scene names an element that does not exist.
    public var isDefined: Bool

    /// What it leaves behind when it decays.
    public var decayIntoID: ElementID
    /// Lifetime in ticks before decaying. Zero means permanent.
    public var decayTicks: Int32

    /// Base color, already parsed.
    public var color: PackedColor
    /// Strength of the position-based grain, as a percentage. Zero renders flat.
    public var colorVariation: Double

    /// Relative heaviness, for buoyancy and displacement.
    public var density: Double
    /// Flow sluggishness. One is instant, ten is honey. Never zero.
    public var viscosity: Double
    /// Gravity multiplier. One is normal, zero suspended, negative rises.
    public var gravityFactor: Double

    /// Likelihood of catching fire near heat, zero to one hundred.
    public var flammability: Double
    /// How fast it is consumed once alight.
    public var burnRate: Double
    /// Resistance to acid, zero to one hundred.
    public var acidResistance: Double
    /// Rate heat moves through it, zero to one.
    public var heatConductivity: Double

    /// Temperature at which it ignites unaided. Not-a-number means never.
    public var ignitionTemp: Double
    /// Temperature it is placed at. Not-a-number means use the world's ambient.
    public var defaultTemp: Double

    /// Whether this element self-ignites at all.
    @inlinable
    public var canSelfIgnite: Bool { !ignitionTemp.isNaN }

    /// Whether this element is placed at the world's ambient temperature.
    @inlinable
    public var usesAmbientTemp: Bool { defaultTemp.isNaN }

    /// Builds the packed form from an authoring definition.
    public init(_ definition: ElementDefinition, isDefined: Bool = true) {
        self.state = definition.state
        self.isConductor = definition.isConductor
        self.isDefined = isDefined
        self.decayIntoID = definition.decayIntoID
        self.decayTicks = Int32(clamping: definition.decayTicks)
        self.color = definition.color
        self.colorVariation = definition.colorVariation
        self.density = definition.density
        self.viscosity = definition.viscosity
        self.gravityFactor = definition.gravityFactor
        self.flammability = definition.flammability
        self.burnRate = definition.burnRate
        self.acidResistance = definition.acidResistance
        self.heatConductivity = definition.heatConductivity
        self.ignitionTemp = definition.ignitionTemp ?? .nan
        self.defaultTemp = definition.defaultTemp ?? .nan
    }
}

/// Every element's physical properties, in one flat array indexed by identifier.
///
/// Lookup is an array index rather than a hash, and the array is dense over the
/// whole identifier range so no bounds are ever missing. Because the contents are
/// plain numbers, the whole table is a value type safe to hand to any thread —
/// which is what allows the powder grid to be simulated across cores while the
/// element picker stays editable on the main thread.
///
/// Properties are grouped per element rather than per property (one array of
/// element records, not sixteen arrays of numbers). That is the opposite of the
/// usual advice, and it is right here because of how the simulation reads: it
/// takes one cell's element identifier and then wants several of that element's
/// properties at once. Grouped this way, those properties share a cache line.
public struct ElementTable: Sendable, Hashable {
    /// One record per identifier, from zero through the last custom slot.
    public let records: [ElementPhysics]

    /// Builds a table from a set of definitions. Identifiers with no definition
    /// are filled with air's properties and marked undefined.
    public init(definitions: [ElementDefinition]) {
        let airDefinition =
            definitions.first { $0.id == Element.empty }
            ?? DefaultElements.all[Int(Element.empty)]
        let filler = ElementPhysics(airDefinition, isDefined: false)

        var records = [ElementPhysics](repeating: filler, count: Element.capacity)
        for definition in definitions where Int(definition.id) < Element.capacity {
            records[Int(definition.id)] = ElementPhysics(definition)
        }
        self.records = records
    }

    /// The properties of an element.
    ///
    /// Out-of-range identifiers resolve to air rather than trapping. A scene file
    /// is user data and may be damaged or hand-edited; a corrupt cell should make
    /// the simulation shrug, not crash the app.
    @inlinable
    public subscript(id: ElementID) -> ElementPhysics {
        let index = Int(id)
        return index < records.count ? records[index] : records[Int(Element.empty)]
    }
}
