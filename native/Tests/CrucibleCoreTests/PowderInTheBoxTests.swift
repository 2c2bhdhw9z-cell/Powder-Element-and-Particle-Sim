import Testing

@testable import CrucibleCore

/// The powder world shown through the box's camera.
@Suite("The powder world in the box")
struct PowderInTheBoxTests {
    private func castle() -> PowderEngine {
        let engine = PowderEngine(width: 80, height: 120, seed: 4)
        for x in 0 ..< 80 { engine.setElement(x, 119, Element.bedrock) }
        // A tower with a hollow middle, so there is something with a shape to look at.
        for y in 80 ..< 119 {
            for x in 30 ..< 50 where x < 34 || x > 45 { engine.setElement(x, y, Element.sand) }
        }
        return engine
    }

    private func box() -> ParticleEngine {
        let field = ParticleEngine(width: 400, height: 700, seed: 1)
        _ = field.setMaxParticles(200_000)
        _ = field.setDepthEnabled(true)
        return field
    }

    @Test("The world's shell is laid into the box, held in place, in the world's own colours")
    func itLaysTheWorldIn() {
        let powder = castle()
        let field = box()
        let laid = Hybrid.showPowderSlab(powder, in: field)
        #expect(laid > 100, "only \(laid) grains were laid in")
        #expect(laid == powder.surfaceCellCount(), "the slab is not the world's shell")
        #expect(field.swarm.count == laid)

        // Every grain is held where it was put, so the picture does not sag under gravity.
        for i in 0 ..< min(50, field.swarm.count) {
            #expect(field.swarm.home(at: i) != nil, "a grain of the slab was not held in place")
        }
        // Opaque, and coloured: a slab drawn in see-through black would be invisible.
        for i in 0 ..< min(50, field.swarm.count) {
            #expect(field.swarm.colors[i] >> 24 == 0xFF)
        }
        // It has depth: the slab is a slab rather than a sheet.
        #expect(field.swarm.hasDepth)
        var deepest = 0.0
        for i in 0 ..< field.swarm.count { deepest = max(deepest, abs(Double(field.swarm.depths[i]))) }
        #expect(deepest > 0)
    }

    @Test("It stays still and stays put while the field runs")
    func itHoldsItsShape() {
        let powder = castle()
        let field = box()
        Hybrid.showPowderSlab(powder, in: field)
        var before: [Float] = []
        for i in 0 ..< field.swarm.count * 2 { before.append(field.swarm.positions[i]) }

        field.gravityY = 0.4
        for _ in 0 ..< 200 { field.step() }

        var worst = 0.0
        for i in 0 ..< field.swarm.count {
            let dx = Double(field.swarm.positions[i * 2] - before[i * 2])
            let dy = Double(field.swarm.positions[i * 2 + 1] - before[i * 2 + 1])
            worst = max(worst, (dx * dx + dy * dy).squareRoot())
        }
        // A grain of the picture may be nudged, but the picture must not fall: the springs that hold it pull it back.
        #expect(worst < 6, "the slab sagged by \(worst) pixels")
        #expect(field.inspect().isHealthy)
    }

    @Test("Showing it does not touch the powder world at all")
    func theWorldIsUnchanged() {
        let powder = castle()
        let before = Array(UnsafeBufferPointer(start: powder.type, count: powder.cellCount))
        let moments = powder.frameCount
        let field = box()
        Hybrid.showPowderSlab(powder, in: field)
        #expect(Array(UnsafeBufferPointer(start: powder.type, count: powder.cellCount)) == before)
        #expect(powder.frameCount == moments)
        // And the powder world goes on falling exactly as it would have.
        powder.step()
        #expect(powder.frameCount == moments + 1)
    }

    @Test("Showing it again replaces it rather than piling up")
    func showingAgainReplaces() {
        let powder = castle()
        let field = box()
        let first = Hybrid.showPowderSlab(powder, in: field)
        let second = Hybrid.showPowderSlab(powder, in: field)
        #expect(first == second)
        #expect(field.swarm.count == second, "the second slab was laid on top of the first")

        // And the world changing changes what is shown.
        powder.drawBrush(centerX: 20, centerY: 60, radius: 6, elementID: Element.stone, shape: .circle)
        let third = Hybrid.showPowderSlab(powder, in: field)
        #expect(third > second)
    }

    @Test("An empty world shows nothing, and a ceiling too low is respected")
    func nothingAndLimits() {
        let field = box()
        #expect(Hybrid.showPowderSlab(PowderEngine(width: 40, height: 40, seed: 1), in: field) == 0)
        #expect(field.swarm.count == 0)

        // A world with far more shell than the box will carry: thinned, not cut short.
        let big = PowderEngine(width: 300, height: 400, seed: 2)
        for y in stride(from: 0, to: 400, by: 2) {
            for x in 0 ..< 300 { big.setElement(x, y, Element.sand) }
        }
        let small = ParticleEngine(width: 400, height: 700, seed: 1)
        _ = small.setMaxParticles(9_000)
        _ = small.setDepthEnabled(true)
        let laid = Hybrid.showPowderSlab(big, in: small)
        #expect(laid > 0 && laid <= 9_000, "\(laid) grains for a ceiling of nine thousand")
        // Spread over the whole world rather than one corner of it.
        var lowest = Double.infinity
        var highest = -Double.infinity
        for i in 0 ..< small.swarm.count {
            lowest = min(lowest, Double(small.swarm.positions[i * 2 + 1]))
            highest = max(highest, Double(small.swarm.positions[i * 2 + 1]))
        }
        #expect(highest - lowest > 200, "only a band of the world was shown")
    }
}
