import Foundation
import Testing

@testable import CrucibleCore

/// An in-memory stand-in for the app's on-disk element store.
private final class MemoryStore: CustomElementStore {
    var saved: [ElementDefinition]
    var saveCount = 0

    init(initial: [ElementDefinition] = []) {
        self.saved = initial
    }

    func loadCustomElements() -> [ElementDefinition] { saved }

    func saveCustomElements(_ elements: [ElementDefinition]) {
        saved = elements
        saveCount += 1
    }
}

private func makeCustom(
    id: ElementID,
    name: String = "Testium",
    category: ElementCategory = .custom,
    state: ElementState = .solidMovable,
    hex: String = "#123456",
    density: Double = 20
) -> ElementDefinition {
    ElementDefinition(
        id: id, name: name, category: category, state: state,
        hex: hex, density: density
    )
}

/// The five behaviors the web implementation's `registry.test.ts` pins down,
/// translated, plus the cases its browser-only persistence path left untested.
@Suite("ElementRegistry")
struct ElementRegistryTests {
    @Test("Built-in identifiers are unique, start at air, and stay under one hundred")
    func builtInIdentifiersAreWellFormed() {
        let ids = DefaultElements.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(DefaultElements.all.first?.id == emptyElementID)
        #expect(ids.allSatisfy { $0 >= 0 })
        #expect(ids.max()! < 100)
    }

    @Test("Unknown identifiers fall back to the empty element")
    func unknownIdentifierFallsBack() {
        let registry = ElementRegistry()
        #expect(registry.element(999).id == emptyElementID)
        // Including identifiers past the end of storage entirely.
        #expect(registry.element(ElementID.max).id == emptyElementID)
    }

    @Test("Custom elements can be registered, resolved and deleted")
    func customElementLifecycle() {
        let registry = ElementRegistry()
        let custom = makeCustom(id: 50)

        #expect(registry.register(custom))
        #expect(registry.element(50).name == "Testium")
        #expect(!registry.isBuiltIn(50))
        #expect(registry.deleteCustomElement(50))
        #expect(registry.element(50).id == emptyElementID)
    }

    @Test("Custom identifiers outside the reserved range are refused")
    func outOfRangeCustomIdentifiersRefused() {
        let registry = ElementRegistry()

        // Below the reserved range: would shadow a built-in.
        #expect(!registry.register(makeCustom(id: 5, name: "Nope", density: 1)))
        #expect(registry.element(5).name == "Smoke", "the built-in must be untouched")

        // Above the reserved range.
        #expect(!registry.register(makeCustom(id: 100, name: "TooHigh")))
        #expect(!registry.register(makeCustom(id: 500, name: "WayTooHigh")))

        // The boundaries themselves are valid.
        #expect(registry.register(makeCustom(id: Element.customIDStart)))
        #expect(registry.register(makeCustom(id: Element.customIDEnd)))
    }

    @Test("The palette excludes the empty element, and category lookup filters correctly")
    func paletteAndCategoryLookup() {
        let registry = ElementRegistry()
        #expect(registry.paletteElements.allSatisfy { $0.id != emptyElementID })
        #expect(registry.paletteElements.count == DefaultElements.all.count - 1)

        let liquids = registry.elements(in: .liquids)
        #expect(!liquids.isEmpty)
        #expect(liquids.allSatisfy { $0.state == .liquid })

        // Air is categorised as a gas, so the gas category must still omit it.
        #expect(registry.elements(in: .gases).allSatisfy { $0.id != emptyElementID })
        #expect(registry.elements(in: .custom).isEmpty, "nothing custom exists in a fresh registry")
    }

    @Test("Listings come back ordered by identifier")
    func listingsAreOrdered() {
        let registry = ElementRegistry()
        #expect(registry.allElements.map(\.id) == registry.allElements.map(\.id).sorted())

        // Register out of order; ordering must still hold.
        registry.register(makeCustom(id: 70, name: "Seventy"))
        registry.register(makeCustom(id: 55, name: "FiftyFive"))
        let customIDs = registry.customElements.map(\.id)
        #expect(customIDs == [55, 70])
    }

    @Test("Built-in classification splits exactly at the custom range")
    func builtInClassification() {
        let registry = ElementRegistry()
        #expect(registry.isBuiltIn(0))
        #expect(registry.isBuiltIn(49))
        #expect(!registry.isBuiltIn(50))
        #expect(!registry.isBuiltIn(99))
    }

    @Test("Deleting refuses built-ins and empty slots")
    func deleteGuards() {
        let registry = ElementRegistry()
        #expect(!registry.deleteCustomElement(1), "sand is not deletable")
        #expect(registry.element(Element.sand).name == "Sand")
        #expect(!registry.deleteCustomElement(50), "nothing is registered at 50 yet")

        registry.register(makeCustom(id: 50))
        #expect(registry.deleteCustomElement(50))
        #expect(!registry.deleteCustomElement(50), "deleting twice reports the second as a no-op")
    }

    @Test("The next free identifier walks the range and reports exhaustion")
    func nextAvailableIdentifier() {
        let registry = ElementRegistry()
        #expect(registry.nextAvailableID == 50)

        registry.register(makeCustom(id: 50))
        #expect(registry.nextAvailableID == 51)

        // Fill every slot.
        for id in Element.customIDStart ... Element.customIDEnd {
            registry.register(makeCustom(id: id))
        }
        #expect(
            registry.nextAvailableID == nil,
            "a full registry must report no room rather than a sentinel number that could be used as an identifier"
        )

        // Freeing one in the middle offers exactly that slot back.
        registry.deleteCustomElement(73)
        #expect(registry.nextAvailableID == 73)
    }

    @Test("Resetting discards custom elements and restores every built-in")
    func resetToDefaults() {
        let registry = ElementRegistry()
        registry.register(makeCustom(id: 60))
        #expect(registry.element(60).id == 60)

        registry.resetToDefaults()
        #expect(registry.element(60).id == emptyElementID)
        #expect(registry.allElements.count == DefaultElements.all.count)
        #expect(registry.allElements == DefaultElements.all)
    }
}

@Suite("ElementRegistry persistence")
struct ElementRegistryPersistenceTests {
    @Test("Custom elements are restored from the store at startup")
    func customElementsRestored() {
        let store = MemoryStore(initial: [makeCustom(id: 51, name: "Restored")])
        let registry = ElementRegistry(store: store)
        #expect(registry.element(51).name == "Restored")
        #expect(registry.customElements.count == 1)
    }

    @Test("Registering and deleting write through to the store")
    func mutationsPersist() {
        let store = MemoryStore()
        let registry = ElementRegistry(store: store)

        registry.register(makeCustom(id: 50, name: "First"))
        #expect(store.saved.map(\.id) == [50])

        registry.register(makeCustom(id: 51, name: "Second"))
        #expect(store.saved.map(\.id) == [50, 51])

        registry.deleteCustomElement(50)
        #expect(store.saved.map(\.id) == [51])
    }

    @Test("Refused registrations do not touch the store")
    func refusedRegistrationsDoNotPersist() {
        let store = MemoryStore()
        let registry = ElementRegistry(store: store)
        _ = registry.register(makeCustom(id: 5))
        _ = registry.deleteCustomElement(5)
        #expect(store.saveCount == 0, "a rejected change must not cause a write")
    }

    @Test("Built-ins are never written to the store")
    func builtInsAreNotPersisted() {
        let store = MemoryStore()
        let registry = ElementRegistry(store: store)
        registry.register(makeCustom(id: 50))
        #expect(store.saved.allSatisfy { $0.id >= Element.customIDStart })
        #expect(store.saved.count == 1)
    }

    @Test("A stored element outside the reserved range is skipped, keeping the rest")
    func outOfRangeStoredElementsSkipped() {
        // A hand-edited or version-mismatched store should cost the user one
        // element, not all of them.
        let store = MemoryStore(initial: [
            makeCustom(id: 3, name: "ShadowsWood"),
            makeCustom(id: 52, name: "Good"),
            makeCustom(id: 200, name: "WayOutOfRange"),
        ])
        let registry = ElementRegistry(store: store)
        #expect(registry.element(Element.wood).name == "Wood", "the built-in survived")
        #expect(registry.element(52).name == "Good", "the valid one loaded")
        #expect(registry.customElements.map(\.id) == [52])
    }

    @Test("A registry with no store still works, it just forgets")
    func storeIsOptional() {
        let registry = ElementRegistry()
        #expect(registry.register(makeCustom(id: 50)))
        #expect(registry.element(50).id == 50)
    }
}

@Suite("ElementTable snapshot")
struct ElementTableTests {
    @Test("Registered elements appear in the table, deleted ones stop being defined")
    func tableTracksRegistry() {
        let registry = ElementRegistry()
        #expect(!registry.table[50].isDefined)

        registry.register(makeCustom(id: 50, state: .liquid, density: 42))
        #expect(registry.table[50].isDefined)
        #expect(registry.table[50].density == 42)
        #expect(registry.table[50].state == .liquid)

        registry.deleteCustomElement(50)
        #expect(!registry.table[50].isDefined)
    }

    @Test("Undefined slots behave like air rather than like garbage")
    func undefinedSlotsBehaveLikeAir() {
        let table = ElementTable(definitions: DefaultElements.all)
        let air = table[Element.air]
        let undefined = table[75]
        #expect(!undefined.isDefined)
        #expect(undefined.density == air.density)
        #expect(undefined.state == air.state)
        #expect(undefined.gravityFactor == air.gravityFactor)
    }

    @Test("Out-of-range lookups resolve to air instead of trapping")
    func outOfRangeLookupIsSafe() {
        // A damaged or hand-edited scene can name an element identifier that has
        // never existed. The simulation must shrug at that, not crash.
        let table = ElementTable(definitions: DefaultElements.all)
        #expect(table[ElementID.max].density == table[Element.air].density)
        #expect(table[9999].state == table[Element.air].state)
    }

    @Test("Absent temperatures are marked not-a-number, which answers comparisons correctly")
    func absentTemperaturesUseNotANumber() {
        let table = ElementTable(definitions: DefaultElements.all)

        let sand = table[Element.sand]
        #expect(sand.ignitionTemp.isNaN)
        #expect(!sand.canSelfIgnite)
        #expect(sand.defaultTemp.isNaN)
        #expect(sand.usesAmbientTemp)

        // The property that makes the sentinel work: a comparison against an
        // absent ignition point is false, so sand never ignites without anyone
        // writing a check for it.
        #expect(!(5000 >= sand.ignitionTemp), "comparing against an absent ignition point must not say yes")

        // Elements with a real placement temperature keep it.
        #expect(table[Element.lava].defaultTemp == 1200)
        #expect(!table[Element.lava].usesAmbientTemp)
        #expect(table[Element.ice].defaultTemp == -15)
        #expect(table[Element.fire].defaultTemp == 600)
        #expect(table[Element.thermite].defaultTemp == 2200)
        #expect(table[Element.plasma].defaultTemp == 3000)
    }

    @Test("Conductors are exactly the elements that should carry a spark")
    func conductorsAreCorrect() {
        let table = ElementTable(definitions: DefaultElements.all)
        let conductors = DefaultElements.all.filter { table[$0.id].isConductor }.map(\.id)
        #expect(
            conductors == [Element.spark, Element.metal, Element.saltWater, Element.mercury, Element.copper],
            "found \(conductors.map { DefaultElements.all[Int($0)].name })"
        )
        #expect(!table[Element.rubber].isConductor, "rubber is the insulator")
        #expect(!table[Element.water].isConductor, "fresh water conducts only via the wetness rules, not this flag")
    }

    @Test("The table is a value type, so a snapshot is unaffected by later edits")
    func snapshotIsIndependent() {
        // This is what lets the simulation run on another thread while the element
        // editor stays live on the main one.
        let registry = ElementRegistry()
        let before = registry.table
        registry.register(makeCustom(id: 50, density: 99))
        #expect(!before[50].isDefined, "the captured snapshot must not have changed")
        #expect(registry.table[50].isDefined)
    }
}

@Suite("Element serialization is interchangeable with the web format")
struct ElementCodableTests {
    @Test("Encoding uses the web implementation's key spellings")
    func keysMatchWebFormat() throws {
        let element = ElementDefinition(
            id: 50, name: "Testium", category: .custom, state: .solidMovable,
            hex: "#123456", density: 20,
            decayTicks: 10, decayIntoID: Element.smoke,
            info: "A test element"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(element), as: UTF8.self)

        #expect(json.contains(##""decayIntoId":5"##), "the web spells it decayIntoId, not decayIntoID")
        #expect(json.contains(##""description":"A test element""##), "the web calls it description")
        #expect(json.contains(##""color":"#123456""##), "color stays a hex string")
        #expect(json.contains(##""state":"solid_movable""##))
        #expect(json.contains(##""category":"Custom""##))
    }

    @Test("Defaults are omitted when encoding, so output stays compact")
    func defaultsOmitted() throws {
        let plain = ElementDefinition(
            id: 50, name: "Plain", category: .custom, state: .solidMovable,
            hex: "#000000", density: 1
        )
        let json = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        for omitted in ["viscosity", "flammability", "burnRate", "acidResistance",
                        "heatConductivity", "ignitionTemp", "defaultTemp", "decayTicks",
                        "decayIntoId", "gravityFactor", "isConductor", "interactions",
                        "description", "colorVariation"] {
            #expect(!json.contains(omitted), "\(omitted) was left at its default and should be omitted")
        }
    }

    @Test("Every built-in element survives a round-trip unchanged")
    func builtInsRoundTrip() throws {
        // Custom elements are stored this way, and scenes embed them, so a lossy
        // round-trip would corrupt someone's work.
        let data = try JSONEncoder().encode(DefaultElements.all)
        let restored = try JSONDecoder().decode([ElementDefinition].self, from: data)
        #expect(restored == DefaultElements.all)
    }

    @Test("Decoding fills in absent properties with the resolved defaults")
    func decodingAppliesDefaults() throws {
        let minimal = Data(##"""
        {"id":50,"name":"Bare","category":"Custom","state":"solid_movable","color":"#abcdef","density":7}
        """##.utf8)
        let element = try JSONDecoder().decode(ElementDefinition.self, from: minimal)
        #expect(element.viscosity == 1)
        #expect(element.gravityFactor == 1)
        #expect(element.decayTicks == 0)
        #expect(element.decayIntoID == emptyElementID)
        #expect(element.flammability == 0)
        #expect(element.isConductor == false)
        #expect(element.interactions.isEmpty)
        #expect(element.info == "")
        #expect(element.ignitionTemp == nil)
        #expect(element.defaultTemp == nil)
    }

    @Test("A stored viscosity of zero still normalises to one")
    func decodedZeroViscosityNormalises() throws {
        // The web reads viscosity as `def.viscosity || 1`, so a stored zero means
        // one there. Decoding must agree or a liquid's flow rate changes on
        // import.
        let data = Data(##"""
        {"id":50,"name":"Zero","category":"Custom","state":"liquid","color":"#abcdef","density":7,"viscosity":0}
        """##.utf8)
        #expect(try JSONDecoder().decode(ElementDefinition.self, from: data).viscosity == 1)
    }

    @Test("An explicit zero gravity factor survives decoding")
    func decodedZeroGravitySurvives() throws {
        let data = Data(##"""
        {"id":50,"name":"Float","category":"Custom","state":"special","color":"#abcdef","density":7,"gravityFactor":0}
        """##.utf8)
        #expect(try JSONDecoder().decode(ElementDefinition.self, from: data).gravityFactor == 0)
    }

    @Test("Interaction rules round-trip with the web key spellings")
    func interactionRulesRoundTrip() throws {
        let rule = InteractionRule(
            targetElementID: Element.water, chance: 0.45,
            resultSelfID: Element.empty, resultTargetID: Element.saltWater,
            spawnElementID: Element.steam, tempChange: -5, explosionRadius: 3
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(rule), as: UTF8.self)
        #expect(json.contains(##""targetElementId":2"##))
        #expect(json.contains(##""resultSelfId":0"##))
        #expect(json.contains(##""resultTargetId":27"##))
        #expect(json.contains(##""spawnElementId":14"##))
        #expect(try JSONDecoder().decode(InteractionRule.self, from: Data(json.utf8)) == rule)
    }

    @Test("An unrecognised state or category is reported rather than guessed at")
    func unknownEnumValuesThrow() {
        // The caller can then skip the one bad element and keep the others, which
        // is what the registry's loading path does.
        let data = Data(##"""
        {"id":50,"name":"Odd","category":"Custom","state":"quantum_foam","color":"#abcdef","density":7}
        """##.utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(ElementDefinition.self, from: data)
        }
    }
}
