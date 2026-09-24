import Testing

@testable import CrucibleCore

/// The web reference implementation leaves most element properties optional and
/// applies a fallback at each place it reads them. Those fallbacks were collected
/// from its physics modules and are applied once here instead. These tests pin
/// each one down, because a wrong default is exactly the kind of bug that makes
/// an element behave subtly differently in one subsystem than another.
@Suite("ElementDefinition resolves the reference implementation's defaults")
struct ElementDefinitionTests {
    /// A minimal element that supplies only what has no sensible default.
    private func bare() -> ElementDefinition {
        ElementDefinition(
            id: 100,
            name: "Test",
            category: .custom,
            state: .solidMovable,
            hex: "#123456",
            density: 12
        )
    }

    @Test("Omitted numeric properties default to zero")
    func zeroDefaults() {
        // In JavaScript these are read through truthiness checks such as
        // `if (nDef.flammability && …)` or `!nDef.acidResistance`, so absent and
        // zero are already indistinguishable there.
        let element = bare()
        #expect(element.colorVariation == 0)
        #expect(element.flammability == 0)
        #expect(element.burnRate == 0)
        #expect(element.acidResistance == 0)
        #expect(element.heatConductivity == 0, "read as `def.heatConductivity ?? 0`")
        #expect(element.decayTicks == 0, "read as `def.decayTicks || 0`")
    }

    @Test("Omitted viscosity is one, and a stored zero is corrected to one")
    func viscosityDefault() {
        // The reference implementation reads `const viscosity = def.viscosity || 1`,
        // so a stored zero silently becomes one there. Normalising at
        // construction keeps that behavior while letting the physics divide by
        // viscosity without a zero check.
        #expect(bare().viscosity == 1)

        #expect(
            ElementDefinition(
                id: 101, name: "Zero", category: .custom, state: .liquid,
                hex: "#123456", density: 1, viscosity: 0
            ).viscosity == 1
        )

        #expect(
            ElementDefinition(
                id: 102, name: "Honey", category: .liquids, state: .liquid,
                hex: "#123456", density: 1, viscosity: 10
            ).viscosity == 10,
            "a real value passes through untouched"
        )
    }

    @Test("Omitted gravityFactor is one, but an explicit zero is respected")
    func gravityFactorDefault() {
        // This one is read as `def.gravityFactor !== undefined ? def.gravityFactor : 1`
        // — unlike the truthiness reads above, an explicit zero is meaningful
        // here and means "suspended in place". Collapsing it to one would make
        // anti-gravity and floating elements fall.
        #expect(bare().gravityFactor == 1)

        let suspended = ElementDefinition(
            id: 103, name: "Suspended", category: .special, state: .special,
            hex: "#123456", density: 1, gravityFactor: 0
        )
        #expect(suspended.gravityFactor == 0)

        let rising = ElementDefinition(
            id: 104, name: "Rising", category: .special, state: .solidMovable,
            hex: "#123456", density: 1, gravityFactor: -1
        )
        #expect(rising.gravityFactor == -1)
    }

    @Test("Omitted decay target is the empty cell")
    func decayTargetDefault() {
        #expect(bare().decayIntoID == emptyElementID, "read as `def.decayIntoId || EMPTY_ELEMENT_ID`")
        #expect(emptyElementID == 0)
    }

    @Test("Absence stays meaningful for ignition and placement temperature")
    func temperaturesStayOptional() {
        // These two cannot collapse to a number. `nil` ignition temperature means
        // "never self-ignites", which is not the same as igniting at zero
        // degrees; `nil` placement temperature means "use the world's current
        // ambient", which is a runtime value.
        let element = bare()
        #expect(element.ignitionTemp == nil)
        #expect(element.defaultTemp == nil)

        let ice = ElementDefinition(
            id: 105, name: "Ice", category: .solids, state: .solidFixed,
            hex: "#123456", density: 9, defaultTemp: -15
        )
        #expect(ice.defaultTemp == -15, "a placement temperature of below zero survives")
    }

    @Test("Conduction and reactions default to off and empty")
    func remainingDefaults() {
        let element = bare()
        #expect(element.isConductor == false)
        #expect(element.interactions.isEmpty)
        #expect(element.info == "")
    }

    @Test("Hex colors in the literal table are parsed at construction")
    func colorParsedFromHex() {
        #expect(bare().color == PackedColor(r: 0x12, g: 0x34, b: 0x56))
    }

    @Test("Only solids are textured, so liquids cannot glitter")
    func texturedStates() {
        // The reference implementation's debug notes record a bug where liquids
        // sparkled because the position-based color jitter was applied to them:
        // a liquid's cells move every frame, so a per-position jitter reshuffles
        // constantly. The rule is encoded on the state itself so no renderer can
        // forget it.
        #expect(ElementState.solidMovable.isTextured)
        #expect(ElementState.solidFixed.isTextured)
        #expect(!ElementState.liquid.isTextured)
        #expect(!ElementState.gas.isTextured)
        #expect(!ElementState.plasma.isTextured)
        #expect(!ElementState.energy.isTextured)
        #expect(!ElementState.special.isTextured)
    }

    @Test("State and category spellings match the web format exactly")
    func wireNamesMatchWebFormat() {
        // Scenes and custom elements are interchangeable with the reference
        // implementation only if these strings agree.
        #expect(ElementState.solidFixed.rawValue == "solid_fixed")
        #expect(ElementState.solidMovable.rawValue == "solid_movable")
        #expect(ElementState.liquid.rawValue == "liquid")
        #expect(ElementState.gas.rawValue == "gas")
        #expect(ElementState.plasma.rawValue == "plasma")
        #expect(ElementState.energy.rawValue == "energy")
        #expect(ElementState.special.rawValue == "special")

        #expect(ElementCategory.solids.rawValue == "Solids")
        #expect(ElementCategory.liquids.rawValue == "Liquids")
        #expect(ElementCategory.gases.rawValue == "Gases")
        #expect(ElementCategory.energetic.rawValue == "Energetic")
        #expect(ElementCategory.biological.rawValue == "Biological")
        #expect(ElementCategory.special.rawValue == "Special")
        #expect(ElementCategory.custom.rawValue == "Custom")
    }
}
