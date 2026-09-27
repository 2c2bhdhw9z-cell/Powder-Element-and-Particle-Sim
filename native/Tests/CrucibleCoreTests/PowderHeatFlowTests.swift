import Testing

@testable import CrucibleCore

/// Heat moves from hot to cold, and nowhere else.
///
/// Written when a pan of popcorn kernels over lava was found sitting at sixty to ninety degrees below freezing.
/// Both the ordinary spreading of heat and the heat pipes handed heat out in equal shares, whatever each neighbour's
/// temperature — so a cell warming beside something hot drained the cold air and cold grains on its other sides just
/// as hard, and those went colder than anything in the world. Fixed in both engines; these hold the fix.
@Suite("Heat flows from hot to cold")
struct PowderHeatFlowTests {
    /// The coldest and hottest temperatures anywhere in the world, air included.
    private func range(_ engine: PowderEngine) -> (low: Double, high: Double) {
        var low = Double.infinity
        var high = -Double.infinity
        for i in 0 ..< engine.cellCount {
            let t = Double(engine.temperature[i])
            low = min(low, t)
            high = max(high, t)
        }
        return (low, high)
    }

    @Test("Nothing grows colder than the coldest thing or hotter than the hottest")
    func staysBetweenTheExtremes() {
        let engine = PowderEngine(width: 40, height: 30, seed: 3)
        // Stone and glass do nothing at these temperatures but conduct, so heat spreading is all that happens.
        for y in 10 ..< 20 {
            for x in 10 ..< 20 { engine.setElement(x, y, Element.stone, temp: 400) }
            for x in 20 ..< 30 { engine.setElement(x, y, Element.glass, temp: 20) }
        }
        for _ in 0 ..< 400 {
            engine.step()
            let now = range(engine)
            #expect(now.low > 19.99, "something cooled to \(now.low), below anything in the world")
            #expect(now.high < 400.01, "something heated to \(now.high), above anything in the world")
            if now.low <= 19.99 || now.high >= 400.01 { return }
        }
        // And heat did actually move.
        #expect(Double(engine.temperature[engine.index(20, 15)]) > 21, "the glass beside the stone never warmed")
    }

    @Test("A metal plate warms what sits on it, and never chills it")
    func plateWarmsWhatIsOnIt() {
        let engine = PowderEngine(width: 40, height: 30, seed: 3)
        for x in 5 ..< 35 {
            engine.setElement(x, 20, Element.stone, temp: 600)
            engine.setElement(x, 19, Element.metal, temp: 20)
            engine.setElement(x, 18, Element.glass, temp: 20)
        }
        var coldest = Double.infinity
        for _ in 0 ..< 300 {
            engine.step()
            for x in 5 ..< 35 { coldest = min(coldest, Double(engine.temperature[engine.index(x, 18)])) }
        }
        // The plate sits between something at six hundred and something at twenty. The old sharing drew heat out of
        // the cold glass whenever the plate was cooler than the average of the two.
        #expect(coldest > 19.99, "the glass on the plate cooled to \(coldest)")
        #expect(Double(engine.temperature[engine.index(20, 18)]) > 60, "the glass on the plate never warmed")
    }

    @Test("A pan of kernels over lava pops, instead of freezing first")
    func kernelsWarmFromTheStart() {
        let engine = PowderEngine(width: 40, height: 30, seed: 7)
        for x in 0 ..< 40 { engine.setElement(x, 29, Element.bedrock) }
        for x in 8 ... 31 { engine.setElement(x, 28, Element.lava) }
        for x in 8 ... 31 { engine.setElement(x, 27, Element.metal) }
        for x in 12 ... 27 { engine.setElement(x, 26, Element.kernel) }
        for _ in 0 ..< 20 {
            engine.step()
            for i in 0 ..< engine.cellCount where engine.type[i] == Element.kernel {
                #expect(engine.temperature[i] >= 19.99, "a kernel in a hot pan was at \(engine.temperature[i])")
            }
        }
    }
}
