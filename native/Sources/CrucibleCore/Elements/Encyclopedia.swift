// GENERATED FILE — do not edit by hand.
//
// Written by scripts/generate-lore.mjs from
// Tests/CrucibleCoreTests/Fixtures/web-lore-golden.json, which is itself recorded from the
// reference implementation's encyclopedia.ts and periodic.ts.
//
// To change any of this text, change it in the web version, re-record the fixture, and run the
// generator again:
//
//     cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-lore
//     node scripts/generate-lore.mjs
//     cd native && swift test --filter Lore
//
// Generated rather than transcribed because it is several hundred short strings full of degree
// signs, typographic apostrophes and arrows, and a single mistyped melting point — or a card
// attached to the element next to the one it describes — would never misbehave and so would never
// be found. LoreTests holds this file to the fixture, so editing it here instead fails loudly.

/// What the encyclopedia says about one element.
///
/// Separate from `ElementDefinition` because it is prose for a reader rather than anything the
/// simulation consults: the melting point here is a phrase like "700°C solidify" or "never",
/// written to be understood, not the number the physics actually uses.
public struct ElementLore: Sendable, Hashable {
    /// How this element melts, as a phrase. Absent where the idea does not apply.
    public var melt: String?
    /// How it boils. Present on only a handful.
    public var boil: String?
    /// What it consumes or destroys.
    public var eats: String
    /// The one thing worth knowing about using it.
    public var note: String
}

/// The encyclopedia.
public enum Encyclopedia {
    /// The card for an element, or a general one for anything user-authored.
    ///
    /// A custom element has no card written for it, and inventing one would be worse than
    /// admitting there is none — so this points the reader at the properties they can actually
    /// see on the palette.
    public static func lore(for id: ElementID) -> ElementLore {
        cards[id] ?? fallback
    }

    /// Whether an element has a card of its own, as opposed to the general one.
    public static func hasOwnCard(for id: ElementID) -> Bool {
        cards[id] != nil
    }

    public static let fallback = ElementLore(
        melt: nil,
        boil: nil,
        eats: "See density and flammability on the palette.",
        note: "No extra card yet."
    )

    /// One card per built-in element.
    public static let cards: [ElementID: ElementLore] = [
        0: ElementLore(melt: nil, boil: nil, eats: "Nothing. Air. Pressure leaks into it.", note: "Empty cell."),  // Air
        1: ElementLore(melt: "1710°C", boil: nil, eats: "Nothing. Sinks in water, stacks, melts to glass beside lava.", note: "Silica grains. The default pile."),  // Sand
        2: ElementLore(melt: "0°C", boil: "100°C", eats: "Puts out fire. Boils on lava. Freezes beside ice. Carves sand.", note: "Seeks downhill. Lightning prefers it. Erodes dirt/sand."),  // Water
        3: ElementLore(melt: "—", boil: nil, eats: "Burns. Feeds fire and plants’ opposite.", note: "Fuel. High flammability."),  // Wood
        4: ElementLore(melt: "—", boil: nil, eats: "Wood, oil, plant, gunpowder, hydrogen, coal, wax.", note: "Dies to water and lack of fuel."),  // Fire
        5: ElementLore(melt: "—", boil: nil, eats: "Nothing. Rises. Follows fans.", note: "Combustion leftover."),  // Smoke
        6: ElementLore(melt: "700°C solidify", boil: "—", eats: "Water → steam + obsidian. Melts sand/stone when hot.", note: "Wins or loses by temperature, not by volume."),  // Lava
        7: ElementLore(melt: "~1200°C", boil: nil, eats: "Blocks most flow.", note: "Barrier rock."),  // Stone
        8: ElementLore(melt: "—", boil: nil, eats: "Most solids except glass and bedrock.", note: "Eats on contact."),  // Acid
        9: ElementLore(melt: "—", boil: "burns", eats: "Floats on water. Burns hard.", note: "Fuel layer."),  // Oil
        10: ElementLore(melt: "—", boil: nil, eats: "Detonates from fire, spark, laser.", note: "Keep it away from the rod."),  // Gunpowder
        11: ElementLore(melt: "—", boil: nil, eats: "Drinks water, burns.", note: "Grows toward moisture."),  // Plant
        12: ElementLore(melt: "~1400°C", boil: nil, eats: "Acid-proof. Brittle to laser/lava.", note: "Melted sand."),  // Glass
        13: ElementLore(melt: "0°C", boil: nil, eats: "Freezes nearby water.", note: "Dam material."),  // Ice
        14: ElementLore(melt: "—", boil: "condenses < 90°C", eats: "Nothing. Rises, then rains. Sealed rooms rupture.", note: "Steam. Lightning will still chase the wet left behind."),  // Steam
        15: ElementLore(melt: "—", boil: nil, eats: "Everything in a radius when sparked.", note: "Don’t wire this to copper."),  // C4 Explosive
        16: ElementLore(melt: "—", boil: nil, eats: "Seeks water and metal, then ignites fuel.", note: "Pathfinding arc. Not a decoration."),  // Spark / Electricity
        17: ElementLore(melt: "~1500°C", boil: nil, eats: "Carries spark and some heat.", note: "Wire. Use copper if you want a heat pipe."),  // Metal / Wire
        18: ElementLore(melt: "—", boil: nil, eats: "Converts neighboring solids.", note: "Keep it off the ant farm."),  // Virus
        19: ElementLore(melt: "—", boil: nil, eats: "Crawls dirt and sand, avoids water.", note: "Colony grain."),  // Ant
        20: ElementLore(melt: "never", boil: nil, eats: "Deletes anything that touches it. Sucks pressure.", note: "Vacuum well."),  // Void
        21: ElementLore(melt: "—", boil: nil, eats: "Copies the first neighbor it sees.", note: "Don’t clone C4 next to spark."),  // Clone / Duplicator
        22: ElementLore(melt: "—", boil: nil, eats: "Teleports matter to Portal B.", note: "Pair them."),  // Portal A
        23: ElementLore(melt: "—", boil: nil, eats: "Exit for Portal A.", note: "Pair them."),  // Portal B
        24: ElementLore(melt: "—", boil: nil, eats: "Falls up.", note: "Negative gravity sand."),  // Anti-Gravity Powder
        25: ElementLore(melt: "~60°C", boil: nil, eats: "Melts, then can burn.", note: "Candle logic."),  // Wax
        26: ElementLore(melt: "—", boil: nil, eats: "Burns through almost anything once lit.", note: "Thermite."),  // Thermite
        27: ElementLore(melt: "—", boil: "100°C", eats: "Better conductor than fresh water.", note: "Lightning loves this."),  // Salt Water
        28: ElementLore(melt: "—", boil: nil, eats: "Detonates. Shock + fire.", note: "Liquid boom."),  // Nitro Liquid
        29: ElementLore(melt: "never", boil: nil, eats: "Nothing. Immune.", note: "World edge."),  // Bedrock
        30: ElementLore(melt: "—", boil: nil, eats: "Bounces kinetic hits.", note: "Soft wall."),  // Rubber
        31: ElementLore(melt: "—", boil: nil, eats: "Feeds fire, boom with spark.", note: "Oxidizer."),  // Oxygen Gas
        32: ElementLore(melt: "—", boil: nil, eats: "Ignites and melts.", note: "Superheated gas."),  // Plasma
        33: ElementLore(melt: "—", boil: nil, eats: "Burns along its length, then spark.", note: "Timer."),  // Fuse Wire
        34: ElementLore(melt: "—", boil: nil, eats: "Slow pour. Burns if you try.", note: "Viscous."),  // Honey
        35: ElementLore(melt: "—", boil: nil, eats: "Rises. Can boom.", note: "Lighter than air."),  // Helium Gas
        36: ElementLore(melt: "—", boil: nil, eats: "Boils water, ignites fuel, melts sand.", note: "Beam."),  // Laser Beam
        37: ElementLore(melt: "801°C", boil: nil, eats: "Turns water into salt water.", note: "NaCl."),  // Salt
        38: ElementLore(melt: "0°C", boil: nil, eats: "Compacts toward ice.", note: "Light water."),  // Snow
        39: ElementLore(melt: "—", boil: nil, eats: "Drinks water → mud. Erodes.", note: "Soil."),  // Dirt
        40: ElementLore(melt: "—", boil: nil, eats: "Becomes plant with water.", note: "Start a farm."),  // Seed
        41: ElementLore(melt: "—", boil: nil, eats: "Burns long.", note: "Carbon."),  // Coal
        42: ElementLore(melt: "—", boil: nil, eats: "Cured wet mix. Barrier.", note: "The set stone."),  // Concrete
        43: ElementLore(melt: "—", boil: nil, eats: "Boom with spark or fire.", note: "Lightest fuel."),  // Hydrogen
        44: ElementLore(melt: "-39°C", boil: "357°C", eats: "Dense. Conducts. Sinks through water.", note: "Don’t drink it."),  // Mercury
        45: ElementLore(melt: "—", boil: nil, eats: "Dirt + water. Slow.", note: "Slurry."),  // Mud
        46: ElementLore(melt: "high", boil: nil, eats: "Won’t remelt easily.", note: "Quenched lava."),  // Obsidian
        47: ElementLore(melt: "1085°C", boil: nil, eats: "Moves heat, not mass. Conducts spark.", note: "Heat pipe. Line it from lava to ice."),  // Copper
        48: ElementLore(melt: "—", boil: nil, eats: "Pushes gas and light powder along gravity-right.", note: "Pressure without a blast."),  // Fan
        49: ElementLore(melt: "—", boil: nil, eats: "Pours, then becomes concrete.", note: "Wait. Don’t freeze it."),  // Wet mix
    ]
}

/// A real-world substance, and the lab material that stands in for it.
///
/// The drawer's whole premise is that the lab cannot simulate chemistry, so it maps something
/// recognisable onto the closest thing it can. Several entries map to the same material — iron,
/// silver, tin, tungsten, platinum, gold and aluminium are all simply "metal" — and that is
/// honest rather than lazy: the alternative is pretending to a distinction the physics does not
/// make.
public struct PeriodicEntry: Sendable, Hashable, Identifiable {
    /// Atomic number. Zero for a compound, which has none.
    public var atomicNumber: Int
    /// Chemical symbol, which for the compounds uses real subscript digits.
    public var symbol: String
    public var name: String
    /// The lab element this stands in for.
    public var mapsTo: ElementID
    /// Why that substitution, in a few words.
    public var why: String

    public var id: String { "\(atomicNumber)-\(symbol)" }

    /// Whether this is a compound rather than a single element.
    public var isCompound: Bool { atomicNumber == 0 }
}

/// The periodic drawer.
///
/// Not laid out as the real table. The reference presents it as two simple grids, and eighteen
/// scattered elements would leave an eighteen-column periodic layout almost entirely empty.
public enum PeriodicTable {
    /// The single elements, in order of atomic number.
    public static let elements: [PeriodicEntry] = [
        PeriodicEntry(atomicNumber: 1, symbol: "H", name: "Hydrogen", mapsTo: 43, why: "Light fuel. Spark it."),
        PeriodicEntry(atomicNumber: 2, symbol: "He", name: "Helium", mapsTo: 35, why: "Rises. Inert-ish boom."),
        PeriodicEntry(atomicNumber: 6, symbol: "C", name: "Carbon", mapsTo: 41, why: "Coal. Slow burn."),
        PeriodicEntry(atomicNumber: 8, symbol: "O", name: "Oxygen", mapsTo: 31, why: "Feeds fire."),
        PeriodicEntry(atomicNumber: 11, symbol: "Na", name: "Sodium", mapsTo: 37, why: "Closest: salt."),
        PeriodicEntry(atomicNumber: 13, symbol: "Al", name: "Aluminium", mapsTo: 17, why: "Metal / wire."),
        PeriodicEntry(atomicNumber: 14, symbol: "Si", name: "Silicon", mapsTo: 1, why: "Sand, then glass."),
        PeriodicEntry(atomicNumber: 16, symbol: "S", name: "Sulfur", mapsTo: 10, why: "Gunpowder stand-in."),
        PeriodicEntry(atomicNumber: 20, symbol: "Ca", name: "Calcium", mapsTo: 7, why: "Stone."),
        PeriodicEntry(atomicNumber: 26, symbol: "Fe", name: "Iron", mapsTo: 17, why: "Metal / wire."),
        PeriodicEntry(atomicNumber: 29, symbol: "Cu", name: "Copper", mapsTo: 47, why: "Heat pipe."),
        PeriodicEntry(atomicNumber: 47, symbol: "Ag", name: "Silver", mapsTo: 17, why: "Conductor."),
        PeriodicEntry(atomicNumber: 50, symbol: "Sn", name: "Tin", mapsTo: 17, why: "Soft metal."),
        PeriodicEntry(atomicNumber: 74, symbol: "W", name: "Tungsten", mapsTo: 17, why: "Hard metal."),
        PeriodicEntry(atomicNumber: 78, symbol: "Pt", name: "Platinum", mapsTo: 17, why: "Inert metal."),
        PeriodicEntry(atomicNumber: 79, symbol: "Au", name: "Gold", mapsTo: 17, why: "Dense metal."),
        PeriodicEntry(atomicNumber: 80, symbol: "Hg", name: "Mercury", mapsTo: 44, why: "Liquid metal."),
        PeriodicEntry(atomicNumber: 82, symbol: "Pb", name: "Lead", mapsTo: 44, why: "Heavy. Sinks."),
    ]

    /// The compounds, which have no atomic number.
    public static let compounds: [PeriodicEntry] = [
        PeriodicEntry(atomicNumber: 0, symbol: "H₂O", name: "Water", mapsTo: 2, why: "The liquid."),
        PeriodicEntry(atomicNumber: 0, symbol: "NaCl", name: "Salt", mapsTo: 37, why: "Makes water conductive."),
        PeriodicEntry(atomicNumber: 0, symbol: "SiO₂", name: "Silica", mapsTo: 12, why: "Glass."),
        PeriodicEntry(atomicNumber: 0, symbol: "H₂", name: "H gas", mapsTo: 43, why: "Same as hydrogen."),
        PeriodicEntry(atomicNumber: 0, symbol: "O₂", name: "O gas", mapsTo: 31, why: "Same as oxygen."),
        PeriodicEntry(atomicNumber: 0, symbol: "C₄", name: "C4", mapsTo: 15, why: "Don’t."),
    ]
}
