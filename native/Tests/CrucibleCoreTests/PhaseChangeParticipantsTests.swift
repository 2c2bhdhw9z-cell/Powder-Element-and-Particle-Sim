import Testing

@testable import CrucibleCore

/// Guards the list of elements the phase-change stage is allowed to skip.
///
/// The tick now skips that stage entirely for elements ``PhaseChangeParticipants`` excludes.
/// That is a worthwhile saving and a standing invitation to a silent bug: someone adds a
/// phase change to an element years from now, does not know this list exists, and the change
/// simply never happens. No compiler error, no crash, no obvious symptom — just an element
/// that refuses to melt.
///
/// So the list is not trusted. These tests drive **every** element through a wide
/// temperature sweep and check by observation that the excluded ones genuinely do nothing,
/// which means the list cannot fall out of step with the code without a failure here.
@Suite("The phase-change stage can only be skipped where it does nothing")
struct PhaseChangeParticipantsTests {
    /// Temperatures spanning every threshold the stage tests, plus a little outside them.
    ///
    /// The thresholds in the chain are 0, 65, 100, 280, 320, 700, 1250 and 1450, so these
    /// step across all of them from both sides.
    private static let temperatures: [Double] = [
        -200, -60, -1, 0, 1, 20, 64, 65, 66, 99, 100, 101,
        279, 281, 319, 321, 699, 700, 701, 1249, 1251, 1449, 1451, 3000,
    ]

    /// Runs one element at one temperature and reports everything observable about the
    /// outcome.
    ///
    /// The neighbourhood is part of it: the water family asks whether anything hot is
    /// nearby, so each case is tried both in open space and surrounded by lava.
    ///
    /// The count of random draws is reported alongside the cell, because a stage can be
    /// wrong without changing anything visible — consuming a random number it should not
    /// have shifts every later decision in the world. That is the failure the golden
    /// comparison exists to catch, and it is checked here too.
    private static func observe(
        element: ElementID,
        temperature: Double,
        surroundedByLava: Bool
    ) -> (type: ElementID, temperature: Float, life: UInt16, velocityY: Int8, drew: Bool) {
        let engine = PowderEngine(width: 7, height: 7, seed: 777)
        if surroundedByLava {
            for y in 2 ... 4 {
                for x in 2 ... 4 where !(x == 3 && y == 3) {
                    engine.setElement(x, y, Element.lava, temp: 1200)
                }
            }
        }
        engine.setElement(3, 3, element, temp: temperature)

        let idx = engine.index(3, 3)
        let definition = engine.elements[element]
        // The generator's state advances on every draw and cannot return to a value it
        // has already held, so an unchanged state means nothing was drawn.
        let stateBefore = engine.rng.state

        _ = engine.updatePhase(x: 3, y: 3, idx: idx, definition: definition)

        return (
            engine.type[idx],
            engine.temperature[idx],
            engine.life[idx],
            engine.velocityY[idx],
            engine.rng.state != stateBefore
        )
    }

    /// The claim the optimisation rests on, checked against every element there is.
    @Test("An element the list excludes is untouched by the phase-change stage")
    func excludedElementsAreUntouched() {
        let table = ElementRegistry().table

        for rawID in 0 ... Int(Element.customIDEnd) {
            let element = ElementID(rawID)
            let physics = table[element]
            // Unregistered slots hold air's properties and cannot occur in a real grid.
            guard physics.isDefined, element != Element.empty else { continue }
            guard !physics.canChangePhase else { continue }

            for temperature in Self.temperatures {
                for surroundedByLava in [false, true] {
                    let result = Self.observe(
                        element: element,
                        temperature: temperature,
                        surroundedByLava: surroundedByLava
                    )
                    let context = "element \(rawID) at \(temperature)°C"
                        + (surroundedByLava ? " surrounded by lava" : "")

                    #expect(
                        result.type == element,
                        "\(context) became element \(result.type), so it does change phase and must be added to PhaseChangeParticipants.ids"
                    )
                    #expect(
                        !result.drew,
                        "\(context) consumed a random number, which shifts every later decision in the world even though the cell looks unchanged"
                    )
                }
            }
        }
    }

    /// The other direction: an element on the list had better actually use it, or the list
    /// has grown something stale that costs time for nothing.
    ///
    /// Not required for correctness — a needless entry is only wasteful — but a stale entry
    /// usually means the chain changed and nobody looked at the list, which is worth
    /// knowing about.
    @Test("Every element on the list changes at some temperature")
    func listedElementsEarnTheirPlace() {
        let table = ElementRegistry().table

        for element in PhaseChangeParticipants.ids.sorted() {
            let physics = table[element]
            guard physics.isDefined else { continue }

            var changedSomewhere = false
            for temperature in Self.temperatures {
                for surroundedByLava in [false, true] {
                    let result = Self.observe(
                        element: element,
                        temperature: temperature,
                        surroundedByLava: surroundedByLava
                    )
                    // Steam is the awkward one: it cools toward ambient every tick without
                    // necessarily becoming anything, so a temperature shift counts as the
                    // stage having done something.
                    if result.type != element || result.temperature != Float(temperature) {
                        changedSomewhere = true
                    }
                }
            }
            #expect(
                changedSomewhere,
                "element \(element) is listed as changing phase but never does, so the list has drifted from the code"
            )
        }
    }

    /// An element that self-ignites must be included whatever its identifier, which is how a
    /// user-authored element keeps working without being named in the list.
    @Test("A custom element with an ignition temperature is never skipped")
    func selfIgnitingCustomElementIsIncluded() {
        let registry = ElementRegistry()
        var custom = DefaultElements.all[Int(Element.wood)]
        custom.id = 60
        custom.name = "Tinder"
        custom.ignitionTemp = 300
        #expect(registry.register(custom))

        let physics = registry.table[60]
        #expect(physics.canChangePhase, "an element that self-ignites must not be skipped")

        // And it does in fact ignite, so the flag is not merely set but needed.
        let engine = PowderEngine(width: 5, height: 5, registry: registry, seed: 5)
        engine.setElement(2, 2, 60, temp: 500)
        engine.step()
        #expect(engine.typeAt(2, 2) == Element.fire)
    }

    /// And one that does not self-ignite, and is not otherwise listed, is skipped — the
    /// saving actually applies to custom elements rather than being quietly bypassed.
    @Test("A plain custom element is skipped")
    func plainCustomElementIsSkipped() {
        let registry = ElementRegistry()
        var custom = DefaultElements.all[Int(Element.stone)]
        custom.id = 61
        custom.name = "Slate"
        custom.ignitionTemp = nil
        #expect(registry.register(custom))

        #expect(!registry.table[61].canChangePhase)
    }
}
