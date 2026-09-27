import Testing

@testable import CrucibleCore

/// The materials this app has of its own, each checked for doing what its card says it does.
///
/// Written after the materials were already in the app and described to the owner as working — which they had not
/// been shown to do. These are the checks that should have come first.
@Suite("This app's own materials")
struct PowderOwnElementsTests {
    /// A small world with a bedrock floor.
    private func world(width: Int = 40, height: Int = 30) -> PowderEngine {
        let engine = PowderEngine(width: width, height: height, seed: 7)
        for x in 0 ..< width { engine.setElement(x, height - 1, Element.bedrock) }
        return engine
    }

    private func count(_ id: ElementID, in engine: PowderEngine) -> Int {
        var found = 0
        for index in 0 ..< engine.width * engine.height where engine.type[index] == id { found += 1 }
        return found
    }

    /// The highest row anything of this kind has reached, where nought is the top.
    private func highest(_ id: ElementID, in engine: PowderEngine) -> Int? {
        for y in 0 ..< engine.height {
            for x in 0 ..< engine.width where engine.type[y * engine.width + x] == id { return y }
        }
        return nil
    }

    @Test("They are built in, listed, and have cards of their own")
    func theyAreProperMaterials() {
        let registry = ElementRegistry()
        for element in DefaultElements.own {
            #expect(registry.isBuiltIn(element.id), "\(element.name) is not built in")
            #expect(registry.element(element.id).name == element.name)
            #expect(Encyclopedia.hasOwnCard(for: element.id), "\(element.name) has no card")
            #expect(Element.isKnown(element.id))
            // Heat has to be able to reach them, or anything that changes when hot never will.
            #expect(element.heatConductivity > 0.05, "\(element.name) cannot be heated at all")
            #expect(element.heatConductivity <= 1, "\(element.name) conducts heat impossibly well")
        }
        let listed = Set(registry.paletteElements.map(\.id))
        for element in DefaultElements.own {
            #expect(listed.contains(element.id), "\(element.name) is not offered in the palette")
        }
    }

    @Test("They survive being saved, and being sent to another phone")
    func theySurviveSaving() {
        let engine = world()
        engine.setElement(5, 20, Element.kernel)
        engine.setElement(6, 20, Element.belt)
        engine.setElement(7, 20, Element.magnet)
        let other = PowderEngine(width: 40, height: 30, seed: 1)
        #expect(other.apply(engine.captureState()))
        #expect(other.type[20 * 40 + 5] == Element.kernel, "a saved kernel came back as something else")
        #expect(other.type[20 * 40 + 6] == Element.belt)
        #expect(other.type[20 * 40 + 7] == Element.magnet)
        // And the health check does not mistake them for damage and repair them away.
        #expect(engine.inspect().corruptTypeCount == 0, "the health check thinks the new materials are damage")
    }

    @Test("A kernel on something hot pops, and the popcorn jumps and piles up")
    func kernelsPop() {
        // A pan: lava underneath, a metal plate over it, and the kernels on the plate. Straight onto lava is not
        // how popcorn is made, and lava sweeps whatever lands on it away.
        let engine = world()
        for x in 8 ... 31 { engine.setElement(x, 28, Element.lava) }
        for x in 8 ... 31 { engine.setElement(x, 27, Element.metal) }
        for x in 12 ... 27 { engine.setElement(x, 26, Element.kernel) }
        var mostPopcorn = 0
        var highestPopcorn = 30
        for _ in 0 ..< 900 {
            engine.step()
            mostPopcorn = max(mostPopcorn, count(Element.popcorn, in: engine))
            if let top = highest(Element.popcorn, in: engine) { highestPopcorn = min(highestPopcorn, top) }
        }
        #expect(mostPopcorn > 10, "only \(mostPopcorn) kernels ever popped")
        // It jumps: popcorn ends up above where the kernels were sitting.
        #expect(highestPopcorn < 24, "the popcorn never rose above row \(highestPopcorn)")
        // And a kernel that is already hot pops at once, keeping its heat rather than arriving cold.
        let hot = world()
        hot.setElement(10, 28, Element.kernel, temp: 260)
        hot.step()
        #expect(hot.type[28 * 40 + 10] == Element.popcorn, "a kernel at 260 degrees did not pop")
        #expect(hot.temperature[28 * 40 + 10] > 150, "the popcorn arrived cold")
    }

    @Test("Soap foams water, and foam floats and pops back to water")
    func soapFoams() {
        let engine = world()
        for x in 5 ... 34 {
            for y in 20 ... 28 { engine.setElement(x, y, Element.water) }
        }
        for x in 18 ... 21 { engine.setElement(x, 19, Element.soap) }
        var mostFoam = 0
        for _ in 0 ..< 300 {
            engine.step()
            mostFoam = max(mostFoam, count(Element.foam, in: engine))
        }
        #expect(mostFoam > 8, "soap in water made only \(mostFoam) cells of foam")

        // Foam left alone goes back to water.
        let alone = world()
        for x in 5 ... 15 { alone.setElement(x, 27, Element.foam) }
        for _ in 0 ..< 900 { alone.step() }
        #expect(count(Element.foam, in: alone) < 3, "foam never popped")
        #expect(count(Element.water, in: alone) > 5, "popped foam did not become water")
    }

    @Test("A sponge soaks up water, and gives it back when squashed")
    func spongesSoakAndDrip() {
        let engine = world()
        for x in 10 ... 20 { engine.setElement(x, 28, Element.sponge) }
        for x in 10 ... 20 { engine.setElement(x, 27, Element.water) }
        let waterBefore = count(Element.water, in: engine)
        for _ in 0 ..< 200 { engine.step() }
        #expect(count(Element.water, in: engine) < waterBefore, "the sponge soaked up nothing")
        #expect(count(Element.wetSponge, in: engine) > 0, "no sponge got wet")

        // Something heavy on a wet sponge squeezes water out of it.
        let squashed = world()
        squashed.setElement(20, 20, Element.wetSponge)
        squashed.setElement(20, 19, Element.stone)
        for x in 15 ... 25 { squashed.setElement(x, 21, Element.bedrock) }
        for _ in 0 ..< 200 { squashed.step() }
        #expect(count(Element.water, in: squashed) > 0, "a squashed wet sponge dripped nothing")
    }

    @Test("A belt carries what lands on it, and painting it again turns it round")
    func beltsCarry() {
        let engine = world()
        for x in 5 ... 34 { engine.setElement(x, 20, Element.belt) }
        engine.setElement(10, 19, Element.sand)
        // Long enough to move a few cells, short enough that the grain has not reached the end and fallen off.
        for _ in 0 ..< 15 { engine.step() }
        var sandAt: Int?
        for x in 0 ..< 40 where engine.type[19 * 40 + x] == Element.sand { sandAt = x }
        #expect((sandAt ?? 0) > 12, "the belt did not carry the sand along: it is at \(sandAt ?? -1)")
        #expect((sandAt ?? 99) < 20, "the belt flung the sand along at \(sandAt ?? -1) rather than carrying it")

        // Painted over, it runs the other way.
        let turned = world()
        for x in 5 ... 34 { turned.setElement(x, 20, Element.belt) }
        // One stroke over the whole belt, touching only belt — the same thing painting over it with a finger does.
        // One stroke rather than a stroke per cell, because turning is limited to once a third of a second so a
        // belt held under a finger does not flip back and forth.
        turned.drawBrush(
            centerX: 20, centerY: 20, radius: 15, elementID: Element.belt, shape: .square,
            targetElementID: Element.belt, now: 10_000
        )
        turned.setElement(25, 19, Element.sand)
        for _ in 0 ..< 15 { turned.step() }
        var turnedAt: Int?
        for x in 0 ..< 40 where turned.type[19 * 40 + x] == Element.sand { turnedAt = x }
        #expect((turnedAt ?? 40) < 23, "a repainted belt did not turn round: the sand is at \(turnedAt ?? -1)")
    }

    @Test("A magnet draws iron dust toward itself")
    func magnetsPullIron() {
        // A magnet on the floor with dust lying either side of it, which is how anybody would actually use one.
        let engine = world()
        engine.setElement(20, 28, Element.magnet)
        let dust = [(13, 28), (14, 28), (15, 28), (16, 28), (24, 28), (25, 28), (26, 28), (27, 28)]
        for (x, y) in dust { engine.setElement(x, y, Element.ironDust) }

        func distance(_ engine: PowderEngine) -> Double {
            var total = 0.0
            var found = 0
            for y in 0 ..< engine.height {
                for x in 0 ..< engine.width where engine.type[y * engine.width + x] == Element.ironDust {
                    total += Double(abs(x - 20) + abs(y - 28))
                    found += 1
                }
            }
            return found > 0 ? total / Double(found) : 0
        }
        let before = distance(engine)
        for _ in 0 ..< 200 { engine.step() }
        let after = distance(engine)
        #expect(after < before - 1.5, "the dust was not drawn in: \(before) steps away, then \(after)")
        #expect(count(Element.ironDust, in: engine) == dust.count, "dust was lost on the way")
    }
}
