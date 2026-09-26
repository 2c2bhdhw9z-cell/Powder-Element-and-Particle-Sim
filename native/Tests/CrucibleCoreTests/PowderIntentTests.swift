import Testing

@testable import CrucibleCore

/// What the powder world is meant to do, where the reference's recorded behaviour was wrong.
///
/// Each of these replaces part of a comparison that was retired — see `PowderGoldenTests` — or covers a
/// fault that the comparison could not see because the reference shared it.
@Suite("Powder intent")
struct PowderIntentTests {
    @Test("A spark runs along a wire and flashes the water at the end to steam")
    func sparkReachesWater() {
        let engine = PowderEngine(width: 40, height: 32, seed: 1234)
        for x in 0 ..< 40 { engine.setElement(x, 31, Element.bedrock) }
        for x in 4 ... 30 { engine.setElement(x, 20, Element.metal) }
        for x in 32 ... 37 {
            for y in 24 ... 29 { engine.setElement(x, y, Element.water) }
        }
        engine.setElement(5, 19, Element.spark, temp: 1000, life: 12)
        var sawSteam = false
        for _ in 0 ..< 120 {
            engine.step()
            for i in 0 ..< engine.cellCount where engine.type[i] == Element.steam { sawSteam = true }
            if sawSteam { break }
        }
        #expect(sawSteam, "the charge never reached the water")
    }

    @Test("A blast leaves no momentum in empty air")
    func blastLeavesNoStrayMomentum() {
        let engine = PowderEngine(width: 80, height: 60, seed: 7)
        for x in 0 ..< 80 {
            for y in 40 ..< 60 { engine.setElement(x, y, Element.sand) }
        }
        engine.triggerExplosion(centerX: 40, centerY: 38, radius: 16)
        var stray = 0
        for i in 0 ..< engine.cellCount
        where engine.type[i] == Element.empty && (engine.velocityX[i] != 0 || engine.velocityY[i] != 0) {
            stray += 1
        }
        #expect(stray == 0, "\(stray) empty cells were left carrying the blast's momentum")
    }

    @Test("An absurd blast size from a custom material is held to something a world can contain")
    func hugeBlastIsBounded() {
        let engine = PowderEngine(width: 60, height: 40, seed: 2)
        engine.triggerExplosion(centerX: 30, centerY: 20, radius: 4_000_000_000)
        #expect(engine.cellCount == 60 * 40)
    }

    @Test("A fan more than one cell across turns all of itself in one stroke")
    func wholeFanTurns() {
        let engine = PowderEngine(width: 20, height: 20, seed: 3)
        engine.drawBrush(centerX: 10, centerY: 10, radius: 1, elementID: Element.fan, shape: .square, now: 0)
        engine.drawBrush(centerX: 10, centerY: 10, radius: 1, elementID: Element.fan, shape: .square, now: 1_000)
        var turned = 0
        for y in 9 ... 11 {
            for x in 9 ... 11 where engine.life[engine.index(x, y)] == 1 { turned += 1 }
        }
        #expect(turned == 9, "only \(turned) of the fan's nine cells turned")
    }

    @Test("A fingerprint of a world with absurd gravity does not crash")
    func fingerprintSurvivesAbsurdGravity() {
        let engine = PowderEngine(width: 10, height: 10, seed: 1)
        engine.gravityY = 1e300
        _ = engine.hashLite()
    }

    @Test("The health report copes with an infinite temperature")
    func inspectionSurvivesInfinity() {
        let engine = PowderEngine(width: 10, height: 10, seed: 1)
        engine.temperature[5] = .infinity
        let report = engine.inspect()
        #expect(report.unreadableTempCount == 1)
    }

    @Test("A deleted custom material left in the world is found and cleared")
    func deletedMaterialIsFound() {
        let registry = ElementRegistry()
        var custom = DefaultElements.all[Int(Element.sand)]
        custom.id = Element.customIDStart
        #expect(registry.register(custom))
        let engine = PowderEngine(width: 10, height: 10, registry: registry, seed: 1)
        engine.setElement(3, 3, Element.customIDStart)
        #expect(registry.deleteCustomElement(Element.customIDStart))
        #expect(engine.inspect().corruptTypeCount == 1)
        #expect(engine.flushStuckCells() == 1)
    }

    @Test("A save file asking for a gigantic world is refused")
    func giganticWorldRefused() {
        let engine = PowderEngine(width: 20, height: 20, seed: 1)
        #expect(!engine.apply(lite: PowderLiteState(w: 8_192, h: 8_192, t: "", gx: nil, gy: nil)))
        #expect(engine.width == 20)
    }

    @Test("A world from another size is redrawn to fit, not cropped")
    func resampleKeepsTheWholeWorld() {
        let engine = PowderEngine(width: 40, height: 20, seed: 1)
        engine.setElement(0, 0, Element.stone)
        engine.setElement(39, 19, Element.water)
        engine.resample(width: 80, height: 60)
        #expect(engine.width == 80 && engine.height == 60)
        #expect(engine.type[engine.index(0, 0)] == Element.stone)
        #expect(engine.type[engine.index(79, 59)] == Element.water)
    }
}
