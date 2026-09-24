/// The fifty built-in elements, transcribed from the web implementation's
/// `DEFAULT_ELEMENTS` table.
///
/// This is a data port, so it is deliberately verbatim: the same identifiers, the
/// same colors, the same physical constants, the same descriptions, in the same
/// order. Any tuning the simulation depends on lives in these numbers, and
/// "improving" one here would change behavior the test suite is meant to pin
/// down.
///
/// Properties absent from the original entry are absent here too, and pick up the
/// defaults resolved in ``ElementDefinition``'s initializer.
public enum DefaultElements {
    public static let all: [ElementDefinition] = [
        ElementDefinition(
            id: Element.air, name: "Air", category: .gases, state: .gas,
            hex: "#0a0a0c",
            density: 0,
            gravityFactor: 0,
            info: "Empty space"
        ),
        ElementDefinition(
            id: Element.sand, name: "Sand", category: .solids, state: .solidMovable,
            hex: "#e5c158", colorVariation: 15,
            density: 15,
            gravityFactor: 1,
            info: "Basic falling powder grain."
        ),
        ElementDefinition(
            id: Element.water, name: "Water", category: .liquids, state: .liquid,
            hex: "#2a7ab8", colorVariation: 2,
            density: 10, viscosity: 1,
            heatConductivity: 0.8,
            gravityFactor: 1,
            info: "Liquid water. Extinguishes fire and grows plants."
        ),
        ElementDefinition(
            id: Element.wood, name: "Wood", category: .solids, state: .solidFixed,
            hex: "#8b5a2b", colorVariation: 12,
            density: 50,
            flammability: 40, burnRate: 2,
            gravityFactor: 0,
            info: "Flammable solid structure."
        ),
        ElementDefinition(
            id: Element.fire, name: "Fire", category: .energetic, state: .plasma,
            hex: "#f97316", colorVariation: 30,
            density: -1,
            defaultTemp: 600,
            decayTicks: 40, decayIntoID: Element.smoke,
            gravityFactor: -0.8,
            info: "Intense thermal plasma (600°C). Ignites flammables."
        ),
        ElementDefinition(
            id: Element.smoke, name: "Smoke", category: .gases, state: .gas,
            hex: "#64748b", colorVariation: 8,
            density: -2,
            defaultTemp: 150,
            decayTicks: 120, decayIntoID: Element.empty,
            gravityFactor: -0.5,
            info: "Rising gas byproduct of combustion."
        ),
        ElementDefinition(
            id: Element.lava, name: "Lava", category: .liquids, state: .liquid,
            hex: "#ff3700", colorVariation: 35,
            density: 25, viscosity: 5,
            heatConductivity: 0.9,
            defaultTemp: 1200,
            gravityFactor: 1,
            info: "Incandescent molten rock (1200°C). Oozes down slopes, ignites flammables, melts stone/sand, boils water."
        ),
        ElementDefinition(
            id: Element.stone, name: "Stone", category: .solids, state: .solidFixed,
            hex: "#71717a", colorVariation: 10,
            density: 60,
            acidResistance: 20, heatConductivity: 0.45,
            gravityFactor: 0,
            info: "Durable barrier rock."
        ),
        ElementDefinition(
            id: Element.acid, name: "Acid", category: .liquids, state: .liquid,
            hex: "#a3e635", colorVariation: 20,
            density: 12, viscosity: 1,
            gravityFactor: 1,
            info: "Corrosive green liquid that dissolves most elements."
        ),
        ElementDefinition(
            id: Element.oil, name: "Oil", category: .liquids, state: .liquid,
            hex: "#3f3f46", colorVariation: 8,
            // Lighter than water (10), which is what makes it float.
            density: 8, viscosity: 2,
            flammability: 90, burnRate: 5,
            gravityFactor: 1,
            info: "Highly flammable petroleum. Floats on water."
        ),
        ElementDefinition(
            id: Element.gunpowder, name: "Gunpowder", category: .energetic, state: .solidMovable,
            hex: "#334155", colorVariation: 10,
            density: 18,
            flammability: 100,
            gravityFactor: 1,
            info: "Explosive black powder grain. Detonates on fire/spark."
        ),
        ElementDefinition(
            id: Element.plant, name: "Plant", category: .biological, state: .solidFixed,
            hex: "#22c55e", colorVariation: 20,
            density: 30,
            flammability: 60,
            gravityFactor: 0,
            info: "Organic vegetation. Spreads when fed with water!"
        ),
        ElementDefinition(
            id: Element.glass, name: "Glass", category: .solids, state: .solidFixed,
            hex: "#93c5fd", colorVariation: 5,
            density: 40,
            acidResistance: 100,
            gravityFactor: 0,
            info: "Transparent acid-proof glass barrier."
        ),
        ElementDefinition(
            id: Element.ice, name: "Ice", category: .solids, state: .solidFixed,
            hex: "#7dd3fc", colorVariation: 12,
            density: 9,
            defaultTemp: -15,
            gravityFactor: 0,
            info: "Translucent icy frost (-15°C / 5°F). Freezes water, melts near heat/fire/laser into water."
        ),
        ElementDefinition(
            id: Element.steam, name: "Steam", category: .gases, state: .gas,
            hex: "#9aafbf", colorVariation: 2,
            density: -3,
            defaultTemp: 120,
            gravityFactor: -0.85,
            info: "Hot water vapor. Rises, then rains back when it cools."
        ),
        ElementDefinition(
            id: Element.c4, name: "C4 Explosive", category: .energetic, state: .solidFixed,
            hex: "#dc2626", colorVariation: 5,
            density: 50,
            flammability: 100,
            info: "Stable explosive block. Powerful shockwave when triggered."
        ),
        ElementDefinition(
            id: Element.spark, name: "Spark / Electricity", category: .energetic, state: .energy,
            hex: "#facc15", colorVariation: 30,
            density: 0,
            defaultTemp: 1000,
            decayTicks: 12, decayIntoID: Element.empty,
            isConductor: true,
            info: "Electrical arc. Seeks water and metal, then ignites fuel."
        ),
        ElementDefinition(
            id: Element.metal, name: "Metal / Wire", category: .energetic, state: .solidFixed,
            hex: "#94a3b8", colorVariation: 5,
            density: 80,
            acidResistance: 80, heatConductivity: 0.55,
            isConductor: true,
            info: "Conductive metal. Passes sparks across distances."
        ),
        ElementDefinition(
            id: Element.virus, name: "Virus", category: .biological, state: .solidMovable,
            hex: "#d946ef", colorVariation: 25,
            density: 14,
            gravityFactor: 1,
            info: "Infectious bio-agent. Converts neighboring solids into Virus!"
        ),
        ElementDefinition(
            id: Element.ant, name: "Ant", category: .biological, state: .solidMovable,
            hex: "#78350f", colorVariation: 10,
            density: 12,
            gravityFactor: 1,
            info: "Living insect. Crawls across surfaces and digs tunnels."
        ),
        ElementDefinition(
            id: Element.void, name: "Void", category: .special, state: .solidFixed,
            hex: "#18181b", colorVariation: 0,
            density: 999,
            gravityFactor: 0,
            info: "Black hole singularity. Consumes any particle touching it."
        ),
        ElementDefinition(
            id: Element.clone, name: "Clone / Duplicator", category: .special, state: .solidFixed,
            hex: "#06b6d4", colorVariation: 10,
            density: 999,
            info: "Magical copier. Duplicates whichever particle touches it."
        ),
        ElementDefinition(
            id: Element.portalA, name: "Portal A", category: .special, state: .solidFixed,
            hex: "#3b82f6", colorVariation: 15,
            density: 999,
            info: "Teleports particles to Portal B."
        ),
        ElementDefinition(
            id: Element.portalB, name: "Portal B", category: .special, state: .solidFixed,
            hex: "#f97316", colorVariation: 15,
            density: 999,
            info: "Exit destination for Portal A."
        ),
        ElementDefinition(
            id: Element.antiGravityPowder, name: "Anti-Gravity Powder", category: .special, state: .solidMovable,
            hex: "#ec4899", colorVariation: 20,
            density: 5,
            gravityFactor: -1,
            info: "Powder that falls UPWARDS against gravity."
        ),
        ElementDefinition(
            id: Element.wax, name: "Wax", category: .solids, state: .solidFixed,
            hex: "#fef08a", colorVariation: 8,
            density: 11,
            flammability: 80,
            info: "Meltable wax block. Melts into liquid wax near heat."
        ),
        ElementDefinition(
            id: Element.thermite, name: "Thermite", category: .energetic, state: .solidMovable,
            hex: "#b91c1c", colorVariation: 15,
            density: 30,
            flammability: 100,
            defaultTemp: 2200,
            info: "Ultra-hot incendiary compound (2200°C). Melts through steel and stone."
        ),
        ElementDefinition(
            id: Element.saltWater, name: "Salt Water", category: .liquids, state: .liquid,
            hex: "#1d6fa8", colorVariation: 3,
            // Denser than fresh water (10), so it settles underneath it.
            density: 11, viscosity: 1,
            isConductor: true,
            info: "Conductive ocean salt water. Sinks below fresh water."
        ),
        ElementDefinition(
            id: Element.nitro, name: "Nitro Liquid", category: .liquids, state: .liquid,
            hex: "#84cc16", colorVariation: 15,
            density: 13, viscosity: 1,
            flammability: 100,
            info: "Volatile explosive liquid. Detonates on impact or heat."
        ),
        ElementDefinition(
            id: Element.bedrock, name: "Bedrock", category: .solids, state: .solidFixed,
            hex: "#09090b", colorVariation: 0,
            density: 9999,
            acidResistance: 100,
            info: "Indestructible border material."
        ),
        ElementDefinition(
            id: Element.rubber, name: "Rubber", category: .solids, state: .solidFixed,
            hex: "#475569", colorVariation: 5,
            density: 20,
            acidResistance: 90,
            info: "Non-conductive insulator block."
        ),
        ElementDefinition(
            id: Element.oxygen, name: "Oxygen Gas", category: .gases, state: .gas,
            hex: "#a5f3fc", colorVariation: 10,
            density: -1,
            gravityFactor: -0.3,
            info: "Concentrated oxygen gas. Supercharges fire combustion."
        ),
        ElementDefinition(
            id: Element.plasma, name: "Plasma", category: .energetic, state: .plasma,
            hex: "#a855f7", colorVariation: 25,
            density: -4,
            defaultTemp: 3000,
            decayTicks: 30, decayIntoID: Element.empty,
            gravityFactor: -0.9,
            info: "Superheated ionized gas channel (3000°C)."
        ),
        ElementDefinition(
            id: Element.fuseWire, name: "Fuse Wire", category: .energetic, state: .solidFixed,
            hex: "#ca8a04", colorVariation: 10,
            density: 15,
            flammability: 100, burnRate: 1,
            info: "Slow-burning gunpowder fuse string."
        ),
        ElementDefinition(
            id: Element.honey, name: "Honey", category: .liquids, state: .liquid,
            hex: "#f59e0b", colorVariation: 10,
            density: 14, viscosity: 9,
            info: "Thick, viscous golden honey. Flows very slowly."
        ),
        ElementDefinition(
            id: Element.helium, name: "Helium Gas", category: .gases, state: .gas,
            hex: "#f472b6", colorVariation: 15,
            density: -5,
            gravityFactor: -1.2,
            info: "Ultra-light gas. Soars rapidly to the top of the grid."
        ),
        ElementDefinition(
            id: Element.laser, name: "Laser Beam", category: .energetic, state: .energy,
            hex: "#ff0033", colorVariation: 20,
            density: 0,
            defaultTemp: 1500,
            decayTicks: 15, decayIntoID: Element.empty,
            gravityFactor: 0,
            info: "High-energy focused laser beam (1500°C). Vaporizes liquids, melts ice/stone, and ignites explosives instantly."
        ),
        ElementDefinition(
            id: Element.salt, name: "Salt", category: .solids, state: .solidMovable,
            hex: "#e7e5e4", colorVariation: 8,
            density: 16,
            gravityFactor: 1,
            interactions: [
                // One of only four declarative rules in the whole registry:
                // salt meeting water becomes nothing, and turns the water salty.
                InteractionRule(
                    targetElementID: Element.water, chance: 0.45,
                    resultSelfID: Element.empty, resultTargetID: Element.saltWater
                ),
            ],
            info: "Halite grains. Dissolves in water into salt water."
        ),
        ElementDefinition(
            id: Element.snow, name: "Snow", category: .solids, state: .solidMovable,
            hex: "#f8fafc", colorVariation: 10,
            density: 6,
            defaultTemp: -10,
            gravityFactor: 1,
            interactions: [
                InteractionRule(targetElementID: Element.fire, chance: 1, resultSelfID: Element.water),
                InteractionRule(targetElementID: Element.lava, chance: 1, resultSelfID: Element.water),
            ],
            info: "Light powder. Melts to water near heat."
        ),
        ElementDefinition(
            id: Element.dirt, name: "Dirt", category: .solids, state: .solidMovable,
            hex: "#6b4f3a", colorVariation: 14,
            density: 17,
            gravityFactor: 1,
            info: "Soil. Seeds take root here when watered."
        ),
        ElementDefinition(
            id: Element.seed, name: "Seed", category: .biological, state: .solidMovable,
            hex: "#65a30d", colorVariation: 10,
            density: 13,
            flammability: 50,
            gravityFactor: 1,
            interactions: [
                InteractionRule(targetElementID: Element.dirt, chance: 0.25, resultSelfID: Element.plant),
            ],
            info: "Germinates into plant on wet dirt."
        ),
        ElementDefinition(
            id: Element.coal, name: "Coal", category: .solids, state: .solidFixed,
            hex: "#292524", colorVariation: 8,
            density: 45,
            flammability: 70, burnRate: 3,
            gravityFactor: 0,
            info: "Carbon fuel. Burns slowly, hot."
        ),
        ElementDefinition(
            id: Element.concrete, name: "Concrete", category: .solids, state: .solidFixed,
            hex: "#a8a29e", colorVariation: 6,
            density: 70,
            acidResistance: 60,
            gravityFactor: 0,
            info: "Poured barrier. Tougher than stone, weaker than bedrock."
        ),
        ElementDefinition(
            id: Element.hydrogen, name: "Hydrogen", category: .gases, state: .gas,
            hex: "#e0f2fe", colorVariation: 12,
            density: -6,
            flammability: 100,
            gravityFactor: -1.1,
            info: "Lightest gas. Detonates violently with fire."
        ),
        ElementDefinition(
            id: Element.mercury, name: "Mercury", category: .liquids, state: .liquid,
            hex: "#94a3b8", colorVariation: 6,
            density: 40, viscosity: 1,
            gravityFactor: 1,
            isConductor: true,
            info: "Dense conductive metal liquid. Sinks through water."
        ),
        ElementDefinition(
            id: Element.mud, name: "Mud", category: .liquids, state: .liquid,
            hex: "#57534e", colorVariation: 10,
            density: 16, viscosity: 6,
            gravityFactor: 1,
            info: "Wet soil. Forms when dirt meets water."
        ),
        ElementDefinition(
            id: Element.obsidian, name: "Obsidian", category: .solids, state: .solidFixed,
            hex: "#1c1917", colorVariation: 8,
            density: 70,
            acidResistance: 80, heatConductivity: 0.35,
            defaultTemp: 200,
            gravityFactor: 0,
            info: "Volcanic glass. Lava quenched by water. Does not remelt easily."
        ),
        ElementDefinition(
            id: Element.copper, name: "Copper", category: .energetic, state: .solidFixed,
            hex: "#b87333", colorVariation: 8,
            density: 70,
            acidResistance: 55, heatConductivity: 1,
            defaultTemp: 20,
            gravityFactor: 0,
            isConductor: true,
            info: "Heat pipe. Moves temperature without moving mass. Also carries spark."
        ),
        ElementDefinition(
            id: Element.fan, name: "Fan", category: .special, state: .solidFixed,
            hex: "#64748b", colorVariation: 4,
            density: 80,
            gravityFactor: 0,
            info: "Blows gas and light powder. Paint over a fan again to rotate it (right, down, left, up)."
        ),
        ElementDefinition(
            id: Element.wetMix, name: "Wet mix", category: .solids, state: .solidMovable,
            hex: "#78716c", colorVariation: 8,
            density: 22, viscosity: 8,
            decayTicks: 280, decayIntoID: Element.concrete,
            gravityFactor: 1,
            info: "Wet concrete. Pours, then cures into concrete."
        ),
    ]
}
