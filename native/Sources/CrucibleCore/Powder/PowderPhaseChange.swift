// Boiling, freezing, melting, condensing, vitrifying.
//
// Ported from web/src/sim/powder/phase-change.ts.

/// Which elements ``PowderEngine/updatePhase(x:y:idx:definition:)`` can actually do
/// something to.
///
/// Walking the phase-change chain costs about fifteen nanoseconds for a cell it will
/// decline to touch, which measurement showed to be a third of what an inert cell such as
/// stone costs to visit at all. Forty of the fifty built-in elements have no phase change,
/// so most of that is waste.
///
/// ## The trap this deliberately avoids
///
/// A hand-kept list that must agree with a long chain of `if` statements somewhere else is
/// exactly the kind of thing that rots: add a phase change later, forget the list, and the
/// change silently never happens. There is no compiler error for that and no obvious
/// symptom.
///
/// Two things guard against it. The list lives in this file, directly above the chain it
/// has to agree with, rather than in the element table it feeds. And
/// `PhaseChangeParticipantsTests` checks the agreement by brute force — it drives every
/// element through a wide temperature sweep, beside lava and away from it, and fails if any
/// element the list excludes turns out to change anyway. Adding a phase change without
/// updating the list breaks that test loudly.
enum PhaseChangeParticipants {
    /// The elements named in the chain below.
    ///
    /// Kept in the order they appear there, so the two can be read side by side.
    static let ids: Set<ElementID> = [
        Element.water,      // boils, and freezes
        Element.saltWater,  // boils
        Element.steam,      // cools toward ambient, and rains
        Element.ice,        // melts
        Element.snow,       // melts
        Element.lava,       // vitrifies
        Element.obsidian,   // re-melts
        Element.stone,      // melts
        Element.sand,       // fuses to glass
        Element.wax,        // softens to honey
    ]

    /// Whether the phase-change stage needs to run for an element at all.
    ///
    /// Anything with an ignition temperature qualifies whatever its identifier, which is
    /// how a user-authored element that self-ignites keeps working without being listed.
    static func includes(id: ElementID, ignitionTemp: Double) -> Bool {
        // Not-a-number means the element never self-ignites, and every comparison against
        // it is false — so this reads as "has an ignition temperature at all".
        if !ignitionTemp.isNaN { return true }
        return ids.contains(id)
    }
}

extension PowderEngine {
    /// Whether a particular element sits within `radius` cells, excluding the
    /// centre.
    func hasTypeNear(x: Int, y: Int, elementID: ElementID, radius: Int) -> Bool {
        for dy in -radius ... radius {
            for dx in -radius ... radius {
                if dx == 0 && dy == 0 { continue }
                let nx = x + dx
                let ny = y + dy
                guard isValid(nx, ny) else { continue }
                if type[index(nx, ny)] == elementID { return true }
            }
        }
        return false
    }

    /// Whether anything hot enough to drive a phase change sits within `radius`
    /// cells.
    ///
    /// Fire, lava and plasma always count. Obsidian and stone count only while
    /// they are still glowing, which is what lets a lava flow that has crusted
    /// over keep boiling the water around it.
    func hasHotNear(x: Int, y: Int, radius: Int) -> Bool {
        for dy in -radius ... radius {
            for dx in -radius ... radius {
                if dx == 0 && dy == 0 { continue }
                let nx = x + dx
                let ny = y + dy
                guard isValid(nx, ny) else { continue }
                let neighbourIdx = index(nx, ny)
                let neighbourType = type[neighbourIdx]
                if neighbourType == Element.lava || neighbourType == Element.fire
                    || neighbourType == Element.plasma
                {
                    return true
                }
                if neighbourType == Element.obsidian || neighbourType == Element.stone,
                   temperature[neighbourIdx].asDouble > 280
                {
                    return true
                }
            }
        }
        return false
    }

    /// Applies any phase change the cell's temperature calls for.
    ///
    /// - Returns: `true` if the cell became something else, in which case it does
    ///   not also move this tick.
    ///
    /// Every branch below is gated on the cell's element, and the only one with a side
    /// effect short of a transformation — steam drifting toward ambient — is gated too.
    /// Nothing here draws a random number except inside that steam branch. So for an
    /// element this function has no case for, calling it and not calling it are
    /// indistinguishable, which is what ``PhaseChangeParticipants`` exists to exploit.
    func updatePhase(x: Int, y: Int, idx: Int, definition: ElementPhysics) -> Bool {
        let cellType = definition.id
        let temp = temperature[idx].asDouble

        // Only the three water-family elements need to know about nearby heat, and
        // finding out costs a 3×3 scan, so the question is asked once and only
        // when it can matter.
        let nearLava: Bool
        if cellType == Element.water || cellType == Element.saltWater || cellType == Element.steam {
            nearLava = hasHotNear(x: x, y: y, radius: 1)
        } else {
            nearLava = false
        }

        // Water and salt water boil. Touching lava boils them regardless of their
        // own temperature, which is what makes lava meeting water dramatic rather
        // than gradual.
        if cellType == Element.water || cellType == Element.saltWater {
            if temp >= 100 || (nearLava && hasTypeNear(x: x, y: y, elementID: Element.lava, radius: 1)) {
                setElement(x, y, Element.steam, temp: max(120, temp), life: 90)
                velocityY[idx] = -2
                return true
            }
        }

        // Fresh water freezes.
        //
        // The engine's own documentation listed freezing as a phase change but nothing
        // implemented it: ice melted the instant it rose above zero, while a pond
        // chilled to minus fifty stayed liquid forever. Salt water deliberately does
        // not freeze here — salt lowers the freezing point, which is also why it is
        // the one that stays liquid in the cold.
        if cellType == Element.water && temp <= 0 {
            setElement(x, y, Element.ice, temp: min(-1, temp))
            return true
        }

        // Ice and snow melt above freezing.
        if cellType == Element.ice && temp > 0 {
            setElement(x, y, Element.water, temp: max(1, temp))
            return true
        }
        if cellType == Element.snow && temp > 0 {
            setElement(x, y, Element.water, temp: max(1, temp))
            return true
        }

        // Steam drifts toward ambient and eventually rains back down — but never
        // while lava is still beside it, or the rain would immediately re-boil and
        // the pair would oscillate forever.
        if cellType == Element.steam {
            let cooling = temperature[idx].asDouble
            temperature[idx] = JS.toFloat32(cooling + (ambientTemp - cooling) * 0.012)
            if !nearLava && temperature[idx].asDouble < 85 && rng.chance(0.045) {
                setElement(x, y, Element.water, temp: max(20, temperature[idx].asDouble))
                velocityY[idx] = 1
                return true
            }
        }

        // Lava below the vitrification threshold becomes volcanic glass.
        if cellType == Element.lava && temp < 700 {
            setElement(x, y, Element.obsidian, temp: max(180, temp))
            return true
        }

        // Obsidian only goes back to lava under extreme heat, which is what stops
        // a cooled flow from endlessly re-melting.
        if cellType == Element.obsidian && temp > 1450 {
            setElement(x, y, Element.lava, temp: temp)
            return true
        }

        if cellType == Element.stone && temp > 1250 {
            setElement(x, y, Element.lava, temp: temp)
            return true
        }

        if cellType == Element.sand && temp > 1450 {
            setElement(x, y, Element.glass, temp: temp)
            return true
        }

        if cellType == Element.wax && temp > 65 {
            setElement(x, y, Element.honey, temp: temp)
            return true
        }

        // Spontaneous ignition once a material passes its own ignition point.
        //
        // `ignitionTemp` is declared and documented on an element but the original
        // never read it, so nothing in the world could catch fire from heat alone —
        // only by touching a flame. Sealing wood in a box and heating it to 1000°C did
        // nothing at all. No built-in element sets the property today, so this changes
        // no existing behaviour; it makes the property mean something for any element
        // that does set it.
        //
        // The comparison relies on the absent value being not-a-number, which is false
        // against every comparison, so an element that never self-ignites needs no
        // check of its own.
        if temp >= definition.ignitionTemp {
            setElement(x, y, Element.fire, temp: max(400, temp))
            return true
        }

        return false
    }

    /// Resolves lava meeting water: the water flashes to steam and the lava loses
    /// real heat.
    ///
    /// The amount of heat carried away is a fixed floor plus a share of how much
    /// hotter the lava was than the water it just boiled. That proportional term is
    /// the important part — with a fixed amount alone, a lava pocket under a thin
    /// cap of water stalls around 1100°C and oscillates indefinitely instead of
    /// ever crossing the 700°C threshold and setting. The share dominates while the
    /// lava is very hot and tapers off as it approaches the threshold.
    func quenchLava(lavaIdx: Int, waterIdx: Int) {
        let lavaTemp = temperature[lavaIdx].asDouble
        let waterTemp = temperature[waterIdx].asDouble

        // The water is converted in place rather than through setElement, because
        // it must keep its position in the scan and be marked as already handled.
        type[waterIdx] = Element.steam
        temperature[waterIdx] = JS.toFloat32(max(130, 80 + lavaTemp * 0.08))
        life[waterIdx] = 100
        // Thrown clear of the lava with a sideways kick and a strong upward one.
        velocityX[waterIdx] = JS.toInt8(Double(rng.chance(0.5) ? -1 : 1) * (1 + Double(rng.int(below: 2))))
        velocityY[waterIdx] = JS.toInt8(-4 - Double(rng.int(below: 2)))
        visited[waterIdx] = 1

        let gap = max(0, lavaTemp - waterTemp)
        let cooled = lavaTemp - (55 + rng.next() * 25 + gap * 0.22)
        temperature[lavaIdx] = JS.toFloat32(cooled)

        if cooled < 700 {
            type[lavaIdx] = Element.obsidian
            temperature[lavaIdx] = JS.toFloat32(max(180, cooled))
            life[lavaIdx] = 0
            velocityX[lavaIdx] = 0
            velocityY[lavaIdx] = 0
        }
        visited[lavaIdx] = 1
    }
}
