import Foundation
import Testing

@testable import CrucibleCore

/// Verifies the fifty built-in elements against the web reference
/// implementation's actual table, not against expectations typed out by hand.
///
/// This is the test that matters most for the element port. Fifty elements with a
/// dozen properties each is six hundred numbers, and a wrong one compiles, runs,
/// and silently changes how something behaves — sand that is one unit too light
/// floats on the wrong liquid, and nothing anywhere reports an error.
///
/// So the comparison is against `web-default-elements.json`, extracted straight
/// from the source of truth. It doubles as a test of the web-compatible
/// serialization layer, since the fixture is decoded with it.
@Suite("Built-in elements match the web reference table")
struct DefaultElementsTests {
    /// The web table, decoded through the web-compatible coding layer.
    static let reference: [ElementDefinition] = {
        guard let url = Bundle.module.url(
            forResource: "web-default-elements",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? Bundle.module.url(forResource: "web-default-elements", withExtension: "json") else {
            fatalError("Fixture web-default-elements.json is missing from the test bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ElementDefinition].self, from: data)
        } catch {
            fatalError("Could not decode the web element fixture: \(error)")
        }
    }()

    @Test("The fixture itself loaded, and describes fifty elements")
    func fixtureLoads() {
        #expect(Self.reference.count == 50)
        #expect(Self.reference.first?.id == Element.empty)
    }

    @Test("The port has the same number of elements, with the same identifiers in the same order")
    func identifiersMatch() {
        #expect(DefaultElements.all.count == Self.reference.count)
        #expect(DefaultElements.all.map(\.id) == Self.reference.map(\.id))
    }

    @Test("Every element matches the reference property for property")
    func everyPropertyMatches() {
        for (ported, reference) in zip(DefaultElements.all, Self.reference) {
            let label = "element \(reference.id) (\(reference.name))"

            #expect(ported.id == reference.id, "\(label): id")
            #expect(ported.name == reference.name, "\(label): name")
            #expect(ported.category == reference.category, "\(label): category")
            #expect(ported.state == reference.state, "\(label): state")
            #expect(ported.color == reference.color, "\(label): color")
            #expect(ported.colorVariation == reference.colorVariation, "\(label): colorVariation")
            #expect(ported.density == reference.density, "\(label): density")
            #expect(ported.viscosity == reference.viscosity, "\(label): viscosity")
            #expect(ported.flammability == reference.flammability, "\(label): flammability")
            #expect(ported.burnRate == reference.burnRate, "\(label): burnRate")
            #expect(ported.acidResistance == reference.acidResistance, "\(label): acidResistance")
            #expect(ported.heatConductivity == reference.heatConductivity, "\(label): heatConductivity")
            #expect(ported.ignitionTemp == reference.ignitionTemp, "\(label): ignitionTemp")
            #expect(ported.defaultTemp == reference.defaultTemp, "\(label): defaultTemp")
            #expect(ported.decayTicks == reference.decayTicks, "\(label): decayTicks")
            #expect(ported.decayIntoID == reference.decayIntoID, "\(label): decayIntoId")
            #expect(ported.gravityFactor == reference.gravityFactor, "\(label): gravityFactor")
            #expect(ported.isConductor == reference.isConductor, "\(label): isConductor")
            #expect(ported.interactions == reference.interactions, "\(label): interactions")
            #expect(ported.info == reference.info, "\(label): description")
        }
    }

    @Test("Whole definitions compare equal, catching any property added later")
    func wholeDefinitionsMatch() {
        // The property-by-property test above reports precisely what differs.
        // This one catches a property being added to the model but forgotten in
        // the comparison list.
        for (ported, reference) in zip(DefaultElements.all, Self.reference) {
            #expect(ported == reference, "element \(reference.id) (\(reference.name)) differs")
        }
    }

    @Test("Named identifiers point at the elements their names claim")
    func namedIdentifiersAreCorrect() {
        // The chemistry port will be written entirely in terms of these names, so
        // a wrong one here would be invisible and catastrophic.
        let expected: [(ElementID, String)] = [
            (Element.air, "Air"),
            (Element.sand, "Sand"),
            (Element.water, "Water"),
            (Element.wood, "Wood"),
            (Element.fire, "Fire"),
            (Element.smoke, "Smoke"),
            (Element.lava, "Lava"),
            (Element.stone, "Stone"),
            (Element.acid, "Acid"),
            (Element.oil, "Oil"),
            (Element.gunpowder, "Gunpowder"),
            (Element.plant, "Plant"),
            (Element.glass, "Glass"),
            (Element.ice, "Ice"),
            (Element.steam, "Steam"),
            (Element.c4, "C4 Explosive"),
            (Element.spark, "Spark / Electricity"),
            (Element.metal, "Metal / Wire"),
            (Element.virus, "Virus"),
            (Element.ant, "Ant"),
            (Element.void, "Void"),
            (Element.clone, "Clone / Duplicator"),
            (Element.portalA, "Portal A"),
            (Element.portalB, "Portal B"),
            (Element.antiGravityPowder, "Anti-Gravity Powder"),
            (Element.wax, "Wax"),
            (Element.thermite, "Thermite"),
            (Element.saltWater, "Salt Water"),
            (Element.nitro, "Nitro Liquid"),
            (Element.bedrock, "Bedrock"),
            (Element.rubber, "Rubber"),
            (Element.oxygen, "Oxygen Gas"),
            (Element.plasma, "Plasma"),
            (Element.fuseWire, "Fuse Wire"),
            (Element.honey, "Honey"),
            (Element.helium, "Helium Gas"),
            (Element.laser, "Laser Beam"),
            (Element.salt, "Salt"),
            (Element.snow, "Snow"),
            (Element.dirt, "Dirt"),
            (Element.seed, "Seed"),
            (Element.coal, "Coal"),
            (Element.concrete, "Concrete"),
            (Element.hydrogen, "Hydrogen"),
            (Element.mercury, "Mercury"),
            (Element.mud, "Mud"),
            (Element.obsidian, "Obsidian"),
            (Element.copper, "Copper"),
            (Element.fan, "Fan"),
            (Element.wetMix, "Wet mix"),
        ]
        #expect(expected.count == 50, "every built-in element needs a named identifier")

        let byID = Dictionary(uniqueKeysWithValues: Self.reference.map { ($0.id, $0.name) })
        for (id, name) in expected {
            #expect(byID[id] == name, "Element id \(id) is \(byID[id] ?? "missing"), not \(name)")
        }
    }

    @Test("Identifiers are unique, contiguous, and air is zero")
    func identifiersAreWellFormed() {
        let ids = DefaultElements.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate identifier")
        #expect(ids == Array(0 ..< 50).map(ElementID.init), "identifiers must be 0 through 49 in order")
        #expect(Element.builtInCount == 50)
        #expect(Element.customIDStart == 50, "custom elements start where built-ins end")
    }

    @Test("Only four declarative interaction rules exist, on salt, snow and seed")
    func declarativeRulesAreWhereExpected() {
        // Worth pinning down: the declarative reaction mechanism looks like the
        // main chemistry system but is barely used — the real chemistry is
        // hand-written control flow. If this count ever grows, the generic
        // evaluator has started carrying real weight and needs real test cover.
        let withRules = DefaultElements.all.filter { !$0.interactions.isEmpty }
        #expect(withRules.map(\.id) == [Element.salt, Element.snow, Element.seed])
        #expect(withRules.reduce(0) { $0 + $1.interactions.count } == 4)

        let salt = DefaultElements.all[Int(Element.salt)]
        #expect(salt.interactions == [
            InteractionRule(
                targetElementID: Element.water, chance: 0.45,
                resultSelfID: Element.empty, resultTargetID: Element.saltWater
            ),
        ])

        let snow = DefaultElements.all[Int(Element.snow)]
        #expect(snow.interactions == [
            InteractionRule(targetElementID: Element.fire, chance: 1, resultSelfID: Element.water),
            InteractionRule(targetElementID: Element.lava, chance: 1, resultSelfID: Element.water),
        ])

        let seed = DefaultElements.all[Int(Element.seed)]
        #expect(seed.interactions == [
            InteractionRule(targetElementID: Element.dirt, chance: 0.25, resultSelfID: Element.plant),
        ])
    }

    @Test("Density ordering that the physics depends on holds")
    func densityRelationshipsHold() {
        // These orderings are not incidental — they are what makes the described
        // behavior happen, and each is called out in an element's own description.
        let table = ElementTable(definitions: DefaultElements.all)
        #expect(
            table[Element.oil].density < table[Element.water].density,
            "oil must be lighter than water or it cannot float on it"
        )
        #expect(
            table[Element.saltWater].density > table[Element.water].density,
            "salt water must sink below fresh water"
        )
        #expect(
            table[Element.mercury].density > table[Element.water].density,
            "mercury must sink through water"
        )
        #expect(
            table[Element.ice].density < table[Element.water].density,
            "ice must be lighter than water"
        )
        #expect(
            table[Element.bedrock].density > table[Element.stone].density,
            "bedrock must outrank stone"
        )
        #expect(
            table[Element.concrete].density > table[Element.stone].density,
            "concrete is tougher than stone, weaker than bedrock"
        )
        #expect(table[Element.concrete].density < table[Element.bedrock].density)
    }

    @Test("Gases and flames have negative density so buoyancy lifts them")
    func risingThingsAreNegativelyDense() {
        let table = ElementTable(definitions: DefaultElements.all)
        for id in [Element.smoke, Element.steam, Element.helium, Element.hydrogen, Element.oxygen, Element.plasma, Element.fire] {
            #expect(table[id].density < 0, "element \(id) should have negative density")
            #expect(table[id].gravityFactor < 0, "element \(id) should have negative gravity")
        }
        // Helium and hydrogen are the two that should climb fastest.
        #expect(table[Element.hydrogen].density < table[Element.helium].density)
        #expect(table[Element.helium].density < table[Element.steam].density)
    }

    @Test("Decay chains terminate and never point at a missing element")
    func decayChainsAreValid() {
        let table = ElementTable(definitions: DefaultElements.all)
        for element in DefaultElements.all where element.decayTicks > 0 {
            #expect(
                Int(element.decayIntoID) < Element.capacity,
                "\(element.name) decays into an out-of-range identifier"
            )
            #expect(
                table[element.decayIntoID].isDefined,
                "\(element.name) decays into an element that does not exist"
            )
        }

        // Fire becomes smoke becomes nothing; wet mix cures into concrete.
        #expect(DefaultElements.all[Int(Element.fire)].decayIntoID == Element.smoke)
        #expect(DefaultElements.all[Int(Element.smoke)].decayIntoID == Element.empty)
        #expect(DefaultElements.all[Int(Element.wetMix)].decayIntoID == Element.concrete)

        // Follow every chain to its end and make sure none loops forever.
        for start in DefaultElements.all where start.decayTicks > 0 {
            var seen: Set<ElementID> = [start.id]
            var current = start.decayIntoID
            while table[current].decayTicks > 0 {
                #expect(seen.insert(current).inserted, "decay chain from \(start.name) loops at \(current)")
                if !seen.contains(current) { break }
                current = table[current].decayIntoID
            }
        }
    }

    @Test("Interaction rules only reference elements that exist")
    func interactionTargetsExist() {
        let table = ElementTable(definitions: DefaultElements.all)
        for element in DefaultElements.all {
            for rule in element.interactions {
                #expect(table[rule.targetElementID].isDefined, "\(element.name) targets a missing element")
                for produced in [rule.resultSelfID, rule.resultTargetID, rule.spawnElementID].compactMap({ $0 }) {
                    #expect(table[produced].isDefined, "\(element.name) produces a missing element \(produced)")
                }
                #expect(rule.chance > 0 && rule.chance <= 1, "\(element.name) has an unusable probability")
            }
        }
    }
}
